"""Per model / software version collection settings and the common collection flow."""
import re
from dataclasses import dataclass, field

from .session import open_session


@dataclass(frozen=True)
class Collector:
    name: str
    prompt: str
    paging_cmd: str
    commands: tuple
    login_prompt: str = r"Username: ?$"
    password_prompt: str = r"Password: ?$"
    enable_cmd: str = None
    exit_cmd: str = "exit"
    description: str = field(default="", compare=False)

    def collect(self, dev, timeout=20, session_log=None):
        """Log in, prepare the CLI and run every command. Returns [(command, output), ...]."""
        s = open_session(
            protocol=dev.get("protocol", "telnet"),
            host=dev["host"],
            port=dev.get("port"),
            user=dev.get("user"),
            password=dev.get("password"),
            auth=dev.get("auth"),
            key_file=dev.get("key_file"),
            known_hosts=dev.get("known_hosts"),
            host_key_check=dev.get("host_key_check"),
            prompt=self.prompt,
            timeout=timeout,
            log=session_log,
        )
        try:
            # Over SSH, sshd has already authenticated the user and the CLI starts at the prompt.
            if dev.get("protocol", "telnet") != "ssh":
                s.login(dev.get("user"), dev.get("password"), self.login_prompt, self.password_prompt)
            if self.enable_cmd:
                s.enable(self.enable_cmd, dev.get("enable_password"))
            s.cmd(self.paging_cmd)
            sections = [(c, s.cmd(c)) for c in self.commands]
        finally:
            s.close(self.exit_cmd)
        return sections


AX4000_R5 = Collector(
    name="AX4000_R5",
    description="Hoshi Networks AX-4000 eNodeB, software R5.x",
    prompt=r"[\w.-]+[>#] ?$",
    enable_cmd="enable",
    paging_cmd="terminal length 0",
    commands=("show version", "show running-config", "show cell status"),
)

# R6 changed the prompt to HOST[R6]# and renamed the pager command.
AX4000_R6 = Collector(
    name="AX4000_R6",
    description="Hoshi Networks AX-4000 eNodeB, software R6.x",
    prompt=r"[\w.-]+\[R6\][>#] ?$",
    enable_cmd="enable",
    paging_cmd="terminal pager disable",
    commands=AX4000_R5.commands,
)

BG7_V200 = Collector(
    name="BG7_V200",
    description="Tsuki Systems BG-7 gNodeB, software V200",
    prompt=r"<[\w.-]+>$",
    login_prompt=r"login: ?$",
    paging_cmd="screen-length 0 temporary",
    commands=("display version", "display current-configuration", "display nr-cell all"),
    exit_cmd="quit",
)

# Which collector handles which model / software version.
HANDLERS = {
    "AX-4000:R5": AX4000_R5,
    "AX-4000:R6": AX4000_R6,
    "BG-7:V200": BG7_V200,
}


def handler_key(dev):
    m = re.match(r"^([A-Z]+\d+)", dev["sw"])
    return f"{dev['model']}:{m.group(1) if m else dev['sw']}"


def collector_for(dev):
    return HANDLERS.get(handler_key(dev))
