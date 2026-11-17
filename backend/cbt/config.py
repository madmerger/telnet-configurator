import os
from dataclasses import dataclass

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


@dataclass
class Settings:
    conf_dir: str
    output_dir: str
    log_dir: str
    web_dist: str
    timeout: int = 20

    @classmethod
    def from_env(cls, env=None):
        env = os.environ if env is None else env
        root = os.path.abspath(env.get("CBT_ROOT", REPO_ROOT))
        return cls(
            conf_dir=os.path.abspath(env.get("CBT_CONF_DIR", os.path.join(root, "conf"))),
            output_dir=os.path.abspath(env.get("CBT_OUTPUT_DIR", os.path.join(root, "output"))),
            log_dir=os.path.abspath(env.get("CBT_LOG_DIR", os.path.join(root, "log"))),
            web_dist=os.path.abspath(env.get("CBT_WEB_DIST", os.path.join(root, "web", "dist"))),
            timeout=int(env.get("CBT_TIMEOUT", "20")),
        )
