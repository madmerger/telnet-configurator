"""Command line: collect from an inventory (like bin/cbt-collect) or run the web server.

  python -m cbt collect -i ../conf/devices.local.conf [-d TKY-ENB-0001 ...]
  python -m cbt serve [--host 127.0.0.1] [--port 8000]
"""
import argparse
import os
import sys

from . import inventory
from .config import Settings
from .service import collect_device


def cmd_collect(args, settings):
    devices = inventory.load(args.inventory)
    if args.device:
        devices = [d for d in devices if d["name"] in set(args.device)]
        if not devices:
            sys.exit(f"no matching devices in {args.inventory}")
    failed = 0
    for dev in devices:
        print(f"{dev['name']:<14} {dev['model']:<8} {dev['sw']:<12} {dev['protocol']}://{dev['host']}:{dev['port']} ... ",
              end="", flush=True)
        r = collect_device(dev, args.outdir or settings.output_dir, args.logdir or settings.log_dir, args.timeout)
        if r["ok"]:
            print(f"OK ({r['lines']} lines) -> {r['file']}")
        else:
            failed += 1
            print(f"FAILED: {r['error']}")
    print(f"\n{len(devices) - failed}/{len(devices)} devices collected")
    return 1 if failed else 0


def cmd_serve(args, settings):
    import uvicorn
    uvicorn.run("cbt.web:app", host=args.host, port=args.port)
    return 0


def main(argv=None):
    settings = Settings.from_env()
    p = argparse.ArgumentParser(prog="python -m cbt")
    sub = p.add_subparsers(dest="command", required=True)
    c = sub.add_parser("collect", help="collect configurations from an inventory")
    c.add_argument("-i", "--inventory", default=os.path.join(settings.conf_dir, "devices.conf"))
    c.add_argument("-d", "--device", action="append")
    c.add_argument("-o", "--outdir")
    c.add_argument("--logdir")
    c.add_argument("--timeout", type=int, default=settings.timeout)
    s = sub.add_parser("serve", help="run the web API (and the built UI from web/dist)")
    s.add_argument("--host", default="127.0.0.1")
    s.add_argument("--port", type=int, default=8000)
    args = p.parse_args(argv)
    try:
        return {"collect": cmd_collect, "serve": cmd_serve}[args.command](args, settings)
    except inventory.InventoryError as e:
        sys.exit(str(e))


if __name__ == "__main__":
    sys.exit(main())
