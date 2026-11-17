"""Shared test helpers: run the Perl base-station simulator and ask it what a device should print."""
import json
import os
import socket
import subprocess
import sys
import tempfile
import time

BACKEND = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ROOT = os.path.dirname(BACKEND)
sys.path.insert(0, BACKEND)

# name, simulator profile, model, sw, lab port offset (22xx / 23xx / 24xx)
DEVICES = [
    ("TKY-ENB-0001", "ax4000-r5", "AX-4000", "R5.2.1", 1),
    ("OSK-ENB-0102", "ax4000-r6", "AX-4000", "R6.1.0", 2),
    ("NGY-GNB-0203", "bg7-v200", "BG-7", "V200R003C10", 3),
]
LAB_KEY = os.path.join(ROOT, "lab", ".state", "cbt_id_ed25519")
SECRET_ENV = ("CBT_PASSWORD", "CBT_ENABLE_PASSWORD", "CBT_SSH_KEY_FILE", "CBT_SSH_KNOWN_HOSTS", "CBT_SSH_HOST_KEY_CHECK")


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def port_open(port):
    try:
        socket.create_connection(("127.0.0.1", port), timeout=2).close()
        return True
    except OSError:
        return False


def wait_port(port, secs=5):
    deadline = time.monotonic() + secs
    while time.monotonic() < deadline:
        if port_open(port):
            return True
        time.sleep(0.1)
    return False


class TelnetSim:
    """sim/bs-sim.pl on free ports, one per device; .ports = {hostname: port}."""

    def __init__(self, devices=DEVICES):
        self.ports = {d[0]: free_port() for d in devices}
        args = []
        for name, profile, *_ in devices:
            args += ["--device", f"{profile}:{self.ports[name]}:{name}"]
        self.proc = subprocess.Popen(["perl", os.path.join(ROOT, "sim", "bs-sim.pl"), "--quiet", *args])
        for p in self.ports.values():
            if not wait_port(p):
                self.stop()
                raise RuntimeError(f"simulator did not start on port {p}")

    def stop(self):
        self.proc.terminate()
        self.proc.wait()


def expected_sections(profile, host):
    """{command: output} exactly as the simulated device prints it."""
    code = (
        "use BSSim::Profile; use JSON::PP;"
        "my ($n, $h) = @ARGV; my $p = BSSim::Profile->get($n);"
        "print JSON::PP->new->canonical->encode({ map { $_ => BSSim::Profile->render($p, $h, $_) } keys %{ $p->{commands} } });"
    )
    out = subprocess.check_output(["perl", "-I", os.path.join(ROOT, "sim", "lib"), "-e", code, profile, host])
    return json.loads(out)


def write_inventory(devices):
    fd, path = tempfile.mkstemp(suffix=".conf")
    with os.fdopen(fd, "w") as fh:
        for d in devices:
            fh.write(f"[{d['name']}]\n")
            fh.writelines(f"{k} = {v}\n" for k, v in sorted(d.items()) if k != "name")
            fh.write("\n")
    return path


def telnet_device(name, port, model, sw, **over):
    d = {"name": name, "host": "127.0.0.1", "port": port, "model": model, "sw": sw, "protocol": "telnet",
         "user": "cbtadmin", "password": "cbt-pass", "enable_password": "cbt-enable"}
    d.update(over)
    return d
