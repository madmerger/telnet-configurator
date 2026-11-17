"""Collected configurations on disk.

OUTDIR/<device>/<device>_<YYYYmmdd-HHMMSS>.cfg   one file per collection
OUTDIR/<device>/latest.cfg                       copy of the most recent one
A file starts with a "!! CBT collected ..." header, then one "!! ===== <command> =====" block per command.
"""
import os
import re
import shutil
from datetime import datetime

NAME_RE = re.compile(r"^[\w.-]+$")
HEADER_RE = re.compile(r"^!! CBT collected .*$")
SECTION_RE = re.compile(r"^!! ===== (.+) =====$")


def check_name(name):
    if not name or not NAME_RE.match(name) or name in (".", ".."):
        raise ValueError(f"invalid name: {name!r}")
    return name


def render(dev, sections, ts):
    header = f"!! CBT collected {dev['name']} ({dev['model']} {dev['sw']}) at {ts}\n"
    return header + "".join(f"!! ===== {cmd} =====\n{out}" for cmd, out in sections)


def save(outdir, dev, sections, ts=None):
    """Write a collection; returns the path of the timestamped file."""
    ts = ts or datetime.now().strftime("%Y%m%d-%H%M%S")
    name = check_name(dev["name"])
    d = os.path.join(outdir, name)
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, f"{name}_{ts}.cfg")
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(render(dev, sections, ts))
    os.replace(tmp, path)
    shutil.copyfile(path, os.path.join(d, "latest.cfg"))
    return path


def devices(outdir):
    if not os.path.isdir(outdir):
        return []
    return sorted(n for n in os.listdir(outdir) if NAME_RE.match(n) and os.path.isdir(os.path.join(outdir, n)))


def snapshots(outdir, device):
    """Timestamped collections of a device, newest first: [{"id", "ts", "lines", "size"}]."""
    d = os.path.join(outdir, check_name(device))
    if not os.path.isdir(d):
        return []
    pat = re.compile(rf"^{re.escape(device)}_(\d{{8}}-\d{{6}})\.cfg$")
    out = []
    for f in os.listdir(d):
        m = pat.match(f)
        if m:
            path = os.path.join(d, f)
            with open(path, encoding="utf-8", errors="replace") as fh:
                lines = sum(1 for _ in fh)
            out.append({"id": m.group(1), "ts": m.group(1), "lines": lines, "size": os.path.getsize(path)})
    return sorted(out, key=lambda s: s["id"], reverse=True)


def path_of(outdir, device, snapshot="latest"):
    check_name(device)
    if snapshot in (None, "", "latest"):
        return os.path.join(outdir, device, "latest.cfg")
    if not re.match(r"^\d{8}-\d{6}$", snapshot):
        raise ValueError(f"invalid snapshot: {snapshot!r}")
    return os.path.join(outdir, device, f"{device}_{snapshot}.cfg")


def read(outdir, device, snapshot="latest"):
    path = path_of(outdir, device, snapshot)
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def parse(text):
    """Split a collected file into its header line and [(command, output), ...]."""
    header, sections, cur = None, [], None
    for line in text.splitlines(keepends=True):
        stripped = line.rstrip("\n")
        if header is None and cur is None and HEADER_RE.match(stripped):
            header = stripped
            continue
        m = SECTION_RE.match(stripped)
        if m:
            cur = [m.group(1), ""]
            sections.append(cur)
            continue
        if cur is not None:
            cur[1] += line
    return header, [tuple(s) for s in sections]


def collected_at(header):
    m = re.search(r" at (\d{8}-\d{6})$", header or "")
    return m.group(1) if m else None
