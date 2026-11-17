"""Web API for the CBT UI.

  GET  /api/inventories                       inventory files in conf/
  GET  /api/devices?inventory=NAME            devices of an inventory (no secrets) + latest collection
  POST /api/collect                           {inventory, devices: [...], password?, enable_password?}
  GET  /api/configs                           devices that have collected configurations
  GET  /api/configs/{device}                  collections of a device, newest first
  GET  /api/configs/{device}/{snapshot}       one collection (snapshot = YYYYmmdd-HHMMSS or latest)
  GET  /api/configs/{device}/{snapshot}/raw   the file as text/plain (download)
  GET  /api/logs/{device}                     last session log (passwords masked)
  POST /api/compare                           {items: [{device, snapshot}], base?, mask_hostname?}

The built React app (web/dist) is served at / when present.
"""
import os
import threading
from concurrent.futures import ThreadPoolExecutor

from starlette.applications import Starlette
from starlette.concurrency import run_in_threadpool
from starlette.exceptions import HTTPException
from starlette.requests import Request
from starlette.responses import JSONResponse, PlainTextResponse
from starlette.routing import Mount, Route
from starlette.staticfiles import StaticFiles

from . import diff, inventory, store
from .collectors import collector_for
from .config import Settings
from .service import collect_device

MAX_PARALLEL = 8


def create_app(settings=None):
    settings = settings or Settings.from_env()
    busy, busy_lock = set(), threading.Lock()

    def inventory_path(name):
        if not name:
            raise HTTPException(400, "inventory is required")
        try:
            store.check_name(name)
        except ValueError as e:
            raise HTTPException(400, str(e))
        path = os.path.join(settings.conf_dir, name)
        if not name.endswith(".conf") or not os.path.isfile(path):
            raise HTTPException(404, f"no inventory {name}")
        return path

    def load_inventory(name):
        try:
            return inventory.load(inventory_path(name))
        except inventory.InventoryError as e:
            raise HTTPException(400, str(e))

    def latest_info(device):
        snaps = store.snapshots(settings.output_dir, device)
        return {"snapshots": len(snaps), "latest": snaps[0]["id"] if snaps else None}

    async def inventories(request):
        names = sorted(f for f in os.listdir(settings.conf_dir) if f.endswith(".conf")) if os.path.isdir(settings.conf_dir) else []
        out = []
        for n in names:
            with open(os.path.join(settings.conf_dir, n), encoding="utf-8") as fh:
                first = [ln[1:].strip() for ln in fh.read().splitlines() if ln.startswith("#")][:1]
            out.append({"name": n, "description": first[0] if first else ""})
        return JSONResponse(out)

    async def devices(request):
        devs = load_inventory(request.query_params.get("inventory"))
        out = []
        for d in devs:
            c = collector_for(d)
            out.append({**inventory.public_view(d), "collector": c.name if c else None, **latest_info(d["name"])})
        return JSONResponse(out)

    async def collect(request):
        body = await _json(request)
        devs = load_inventory(body.get("inventory"))
        wanted = body.get("devices") or [d["name"] for d in devs]
        by_name = {d["name"]: d for d in devs}
        missing = [n for n in wanted if n not in by_name]
        if missing:
            raise HTTPException(404, f"not in inventory: {', '.join(missing)}")
        targets = []
        for name in wanted:
            dev = dict(by_name[name])
            # Credentials typed in the UI apply to this request only; they are never stored.
            for key in inventory.SECRET_KEYS:
                if body.get(key):
                    dev[key] = body[key]
            targets.append(dev)

        def run(dev):
            with busy_lock:
                if dev["name"] in busy:
                    return {"name": dev["name"], "ok": False, "error": "a collection of this device is already running"}
                busy.add(dev["name"])
            try:
                return collect_device(dev, settings.output_dir, settings.log_dir, settings.timeout)
            finally:
                with busy_lock:
                    busy.discard(dev["name"])

        def run_all():
            with ThreadPoolExecutor(max_workers=min(MAX_PARALLEL, len(targets) or 1)) as pool:
                return list(pool.map(run, targets))

        results = await run_in_threadpool(run_all)
        for r in results:
            r.pop("file", None)
        return JSONResponse({"results": results, "ok": sum(r["ok"] for r in results), "total": len(results)})

    async def configs(request):
        return JSONResponse([{"device": d, **latest_info(d)} for d in store.devices(settings.output_dir)])

    async def snapshots(request):
        device = _name(request.path_params["device"])
        return JSONResponse(store.snapshots(settings.output_dir, device))

    def read_snapshot(device, snapshot):
        try:
            return store.read(settings.output_dir, device, snapshot)
        except ValueError as e:
            raise HTTPException(400, str(e))
        except FileNotFoundError:
            raise HTTPException(404, f"no configuration {snapshot} for {device}")

    async def config(request):
        device, snapshot = _name(request.path_params["device"]), request.path_params["snapshot"]
        text = read_snapshot(device, snapshot)
        header, sections = store.parse(text)
        return JSONResponse({
            "device": device,
            "snapshot": snapshot,
            "collected_at": store.collected_at(header),
            "header": header,
            "lines": len(text.splitlines()),
            "sections": [{"command": c, "output": o, "lines": len(o.splitlines())} for c, o in sections],
        })

    async def config_raw(request):
        device, snapshot = _name(request.path_params["device"]), request.path_params["snapshot"]
        text = read_snapshot(device, snapshot)
        label = store.collected_at(store.parse(text)[0]) or snapshot
        return PlainTextResponse(text, headers={"Content-Disposition": f'attachment; filename="{device}_{label}.cfg"'})

    async def session_log(request):
        device = _name(request.path_params["device"])
        path = os.path.join(settings.log_dir, f"{device}.session.log")
        if not os.path.isfile(path):
            raise HTTPException(404, f"no session log for {device}")
        with open(path, encoding="utf-8", errors="replace") as fh:
            return PlainTextResponse(fh.read().replace("\r", ""))

    async def compare(request):
        body = await _json(request)
        req = body.get("items") or []
        if len(req) < 2:
            raise HTTPException(400, "choose at least two configurations to compare")
        items = []
        for it in req:
            device = _name(it.get("device"))
            snapshot = it.get("snapshot") or "latest"
            text = read_snapshot(device, snapshot)
            snap_id = store.collected_at(store.parse(text)[0]) or snapshot
            items.append({"key": f"{device}@{snap_id}", "device": device, "snapshot": snap_id, "text": text})
        base = body.get("base", 0)
        if not isinstance(base, int) or not 0 <= base < len(items):
            raise HTTPException(400, "base must be an index into items")
        result = diff.compare(items, base_index=base, mask_hostname=bool(body.get("mask_hostname", True)))
        result["items"] = [{"key": i["key"], "device": i["device"], "snapshot": i["snapshot"]} for i in items]
        return JSONResponse(result)

    async def http_error(request, exc):
        return JSONResponse({"error": exc.detail}, status_code=exc.status_code)

    routes = [
        Route("/api/inventories", inventories),
        Route("/api/devices", devices),
        Route("/api/collect", collect, methods=["POST"]),
        Route("/api/configs", configs),
        Route("/api/configs/{device}", snapshots),
        Route("/api/configs/{device}/{snapshot}", config),
        Route("/api/configs/{device}/{snapshot}/raw", config_raw),
        Route("/api/logs/{device}", session_log),
        Route("/api/compare", compare, methods=["POST"]),
    ]
    if os.path.isdir(settings.web_dist):
        routes.append(Mount("/", StaticFiles(directory=settings.web_dist, html=True)))
    return Starlette(routes=routes, exception_handlers={HTTPException: http_error})


def _name(value):
    try:
        return store.check_name(value)
    except ValueError as e:
        raise HTTPException(400, str(e))


async def _json(request: Request):
    try:
        body = await request.json()
    except ValueError:
        raise HTTPException(400, "request body must be JSON")
    if not isinstance(body, dict):
        raise HTTPException(400, "request body must be a JSON object")
    return body


app = create_app()
