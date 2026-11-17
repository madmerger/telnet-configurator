"""Device inventory (INI style, one [section] per device).

Values may reference environment variables as ${NAME}; an empty value counts as unset.

Connection keys (per device):
  protocol        telnet (default) | ssh
  port            default 23 (telnet) / 22 (ssh)
  auth            ssh only: password | publickey (default: publickey if key_file is set, else password)
  key_file        ssh private key                      (fallback: $CBT_SSH_KEY_FILE)
  known_hosts     ssh known_hosts file                 (fallback: $CBT_SSH_KNOWN_HOSTS, else ssh's default)
  host_key_check  yes (default) | accept-new | no      (fallback: $CBT_SSH_HOST_KEY_CHECK)
  password        login password                       (fallback: $CBT_PASSWORD)
  enable_password privileged mode password             (fallback: $CBT_ENABLE_PASSWORD)
"""
import os
import re

ENV_FALLBACK = {
    "password": "CBT_PASSWORD",
    "enable_password": "CBT_ENABLE_PASSWORD",
    "key_file": "CBT_SSH_KEY_FILE",
    "known_hosts": "CBT_SSH_KNOWN_HOSTS",
    "host_key_check": "CBT_SSH_HOST_KEY_CHECK",
}
DEFAULT_PORT = {"telnet": 23, "ssh": 22}
SECRET_KEYS = ("password", "enable_password")

_SECTION = re.compile(r"^\s*\[([^\]]+)\]\s*$")
_KEY_VALUE = re.compile(r"^\s*([\w.-]+)\s*=\s*(.*?)\s*$")
_ENV_REF = re.compile(r"\$\{(\w+)\}")


class InventoryError(ValueError):
    pass


def load(path, env=None):
    """Read an inventory file and return a list of device dicts with connection defaults applied."""
    env = os.environ if env is None else env
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError as e:
        raise InventoryError(f"cannot read inventory {path}: {e.strerror}") from e

    devices, cur = [], None
    for lineno, line in enumerate(lines, 1):
        if re.match(r"^\s*([#;]|$)", line):
            continue
        m = _SECTION.match(line)
        if m:
            cur = {"name": m.group(1)}
            devices.append(cur)
            continue
        m = _KEY_VALUE.match(line)
        if not m:
            raise InventoryError(f"{path}:{lineno}: expected key = value")
        if cur is None:
            raise InventoryError(f"{path}:{lineno}: key outside of a [device] section")
        cur[m.group(1)] = _ENV_REF.sub(lambda r: env.get(r.group(1), ""), m.group(2))

    for d in devices:
        for req in ("host", "model", "sw"):
            if req not in d:
                raise InventoryError(f"{path}: device [{d['name']}] is missing '{req}'")
        _connection_defaults(path, d, env)
    return devices


def _connection_defaults(path, d, env):
    for key, var in ENV_FALLBACK.items():
        if d.get(key) == "":
            del d[key]
        if key not in d and env.get(var):
            d[key] = env[var]
    where = f"{path}: device [{d['name']}]"
    d["protocol"] = (d.get("protocol") or "").lower() or "telnet"
    if d["protocol"] not in DEFAULT_PORT:
        raise InventoryError(f"{where}: unknown protocol '{d['protocol']}' (telnet or ssh)")
    port = d.get("port")
    try:
        d["port"] = int(port) if port not in (None, "") else DEFAULT_PORT[d["protocol"]]
    except ValueError:
        raise InventoryError(f"{where}: port must be a number") from None
    if d["protocol"] != "ssh":
        return

    if not d.get("user"):
        raise InventoryError(f"{where}: ssh needs 'user'")
    d["auth"] = (d.get("auth") or "").lower() or ("publickey" if "key_file" in d else "password")
    if d["auth"] not in ("password", "publickey"):
        raise InventoryError(f"{where}: unknown auth '{d['auth']}' (password or publickey)")
    if d["auth"] == "publickey" and "key_file" not in d:
        raise InventoryError(f"{where}: auth = publickey needs 'key_file' (or $CBT_SSH_KEY_FILE)")
    d["host_key_check"] = d.get("host_key_check", "yes").lower()
    if d["host_key_check"] not in ("yes", "accept-new", "no"):
        raise InventoryError(f"{where}: host_key_check must be yes, accept-new or no")
    home = env.get("HOME", "~")
    for key in ("key_file", "known_hosts"):
        if key in d:
            d[key] = re.sub(r"^~(?=/|$)", lambda _: home, d[key])


def public_view(device):
    """Device settings that are safe to show in the UI (no secrets, only whether they are set)."""
    view = {k: v for k, v in device.items() if k not in SECRET_KEYS}
    for k in SECRET_KEYS:
        view[f"has_{k}"] = bool(device.get(k))
    return view
