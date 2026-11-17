"""Compare collected configurations section by section (side-by-side rows for the UI)."""
import difflib

from .store import parse

HOSTNAME_TOKEN = "{HOSTNAME}"


def prepare(text, device=None, mask_hostname=False):
    """-> (header, {command: [lines]}) with the device's own hostname optionally masked."""
    header, sections = parse(text)
    out = {}
    for cmd, body in sections:
        if mask_hostname and device:
            body = body.replace(device, HOSTNAME_TOKEN)
        out[cmd] = body.splitlines()
    return header, out


def side_by_side(a, b):
    """Rows {"t": eq|chg|del|add, "l": left line no, "lt": left text, "r": ..., "rt": ...}; numbers are 1-based."""
    rows = []
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
        if op == "equal":
            rows += [{"t": "eq", "l": i + 1, "lt": a[i], "r": j + 1, "rt": b[j]} for i, j in zip(range(i1, i2), range(j1, j2))]
            continue
        n = max(i2 - i1, j2 - j1)
        for k in range(n):
            i, j = i1 + k, j1 + k
            left = i < i2
            right = j < j2
            t = "chg" if left and right else ("del" if left else "add")
            rows.append({
                "t": t,
                "l": i + 1 if left else None, "lt": a[i] if left else None,
                "r": j + 1 if right else None, "rt": b[j] if right else None,
            })
    return rows


def compare_pair(base, other):
    """base / other: {command: [lines]} -> list of per-section results."""
    order = list(base) + [c for c in other if c not in base]
    out = []
    for cmd in order:
        a, b = base.get(cmd), other.get(cmd)
        if a is None or b is None:
            rows = side_by_side(a or [], b or [])
            status = "only_target" if a is None else "only_base"
        else:
            rows = side_by_side(a, b)
            status = "equal" if all(r["t"] == "eq" for r in rows) else "changed"
        out.append({
            "command": cmd,
            "status": status,
            "added": sum(r["rt"] is not None and r["t"] != "eq" for r in rows),
            "removed": sum(r["lt"] is not None and r["t"] != "eq" for r in rows),
            "rows": rows,
        })
    return out


def compare(items, base_index=0, mask_hostname=True):
    """items: [{"key", "device", "text"}] -> base vs each other item, plus which items share each section verbatim."""
    prepared = [prepare(it["text"], it["device"], mask_hostname)[1] for it in items]
    commands = []
    for p in prepared:
        commands += [c for c in p if c not in commands]

    matrix = {}
    for cmd in commands:
        groups, row = [], {}
        for it, p in zip(items, prepared):
            if cmd not in p:
                row[it["key"]] = None
                continue
            body = p[cmd]
            if body not in groups:
                groups.append(body)
            row[it["key"]] = groups.index(body)
        matrix[cmd] = row

    base = prepared[base_index]
    diffs = []
    for idx, (it, p) in enumerate(zip(items, prepared)):
        if idx == base_index:
            continue
        sections = compare_pair(base, p)
        diffs.append({
            "key": it["key"],
            "identical": all(s["status"] == "equal" for s in sections),
            "added": sum(s["added"] for s in sections),
            "removed": sum(s["removed"] for s in sections),
            "sections": sections,
        })
    return {"base": items[base_index]["key"], "commands": commands, "matrix": matrix, "diffs": diffs}
