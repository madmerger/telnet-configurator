"""Collect one device: pick the collector, run it, store the result, keep the session log."""
import os
import time
from datetime import datetime

from . import store
from .collectors import collector_for, handler_key


def collect_device(dev, outdir, logdir, timeout=20):
    """-> {"name", "ok", "file", "snapshot", "lines", "error", "seconds"}; never raises for device errors."""
    started = time.monotonic()
    result = {"name": dev["name"], "ok": False, "file": None, "snapshot": None, "lines": 0, "error": None}
    try:
        store.check_name(dev["name"])
        collector = collector_for(dev)
        if collector is None:
            raise RuntimeError(f"no collector for {handler_key(dev)}")
        os.makedirs(logdir, exist_ok=True)
        sections = collector.collect(dev, timeout=timeout, session_log=os.path.join(logdir, f"{dev['name']}.session.log"))
        ts = datetime.now().strftime("%Y%m%d-%H%M%S")
        path = store.save(outdir, dev, sections, ts)
        with open(path, encoding="utf-8") as fh:
            result["lines"] = sum(1 for _ in fh)
        result.update(ok=True, file=path, snapshot=ts)
    except Exception as e:  # report per device, like the CLI's FAILED line
        result["error"] = str(e) or e.__class__.__name__
    result["seconds"] = round(time.monotonic() - started, 2)
    return result
