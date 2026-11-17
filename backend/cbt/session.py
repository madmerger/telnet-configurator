"""Sessions to a base station: login, privileged mode, command execution.

TelnetSession speaks Telnet over a plain socket (refusing every option, like Net::Telnet).
SSHSession drives the system OpenSSH client (`ssh -tt`): sshd authenticates the user
(password via SSH_ASKPASS, or public key), so the device CLI starts at its prompt.
Both expose the same interface: login / enable / cmd / close.
"""
import os
import re
import select
import socket
import subprocess
import time

ASKPASS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "libexec", "cbt-askpass")

IAC, DONT, DO, WONT, WILL, SB, SE = 255, 254, 253, 252, 251, 250, 240


class SessionError(Exception):
    pass


def open_session(protocol="telnet", **kw):
    return SSHSession(**kw) if protocol == "ssh" else TelnetSession(**kw)


class _Session:
    def __init__(self, host, port, prompt, timeout=20, log=None, password=None, **kw):
        self.host, self.port = host, port
        self.prompt = re.compile(prompt)
        self.timeout = timeout
        self.buf = ""
        self.errmsg = ""
        self.eof = False
        self.secrets = [s for s in (password,) if s]
        self.logfh = open(log, "w", encoding="utf-8", errors="replace") if log else None
        self.opts = kw

    # waitfor(re_a, re_b, ...) -> (text before the match, matched text, index of the pattern)
    def waitfor(self, *patterns):
        patterns = [re.compile(p) if isinstance(p, str) else p for p in patterns]
        deadline = time.monotonic() + self.timeout
        while True:
            found = [(m.start(), i, m) for i, m in enumerate(p.search(self.buf) for p in patterns) if m]
            if found:
                _, i, m = min(found, key=lambda f: f[:2])  # earliest match in the stream wins
                pre, match = self.buf[: m.start()], m.group(0)
                self.buf = self.buf[m.end():]
                return pre, match, i
            left = deadline - time.monotonic()
            if left <= 0:
                self.errmsg = "timed out waiting for the device"
                return None
            if not self._read(left):
                return None

    def _close_log(self):
        if self.logfh:
            self.logfh.close()
            self.logfh = None

    def _log(self, data):
        if not self.logfh:
            return
        for s in self.secrets:
            data = data.replace(s, "********")
        self.logfh.write(data)
        self.logfh.flush()

    def _received(self, data):
        self._log(data)
        self.buf += data

    def _sendline(self, text):
        raise NotImplementedError

    def _read(self, wait):
        raise NotImplementedError

    def login(self, user, password, login_prompt, password_prompt):
        if self.waitfor(login_prompt) is None:
            raise SessionError(f"no login prompt: {self.errmsg}")
        self._sendline(user)
        if self.waitfor(password_prompt) is None:
            raise SessionError(f"no password prompt: {self.errmsg}")
        self._sendline(password or "")
        got = self.waitfor(self.prompt, r"% Authentication failed")
        if got is None or got[2] == 1:
            raise SessionError(f"login failed for {user}")

    def enable(self, cmd, password):
        if password:
            self.secrets.append(password)
        self._sendline(cmd)
        if self.waitfor(r"Password: ?$") is None:
            raise SessionError("no enable password prompt")
        self._sendline(password or "")
        got = self.waitfor(self.prompt, r"% Bad enable password")
        if got is None or got[2] == 1:
            raise SessionError("enable failed")

    def cmd(self, command):
        self._sendline(command)
        got = self.waitfor(self.prompt)
        if got is None:
            raise SessionError(f"command '{command}' failed: {self.errmsg}")
        out = got[0].replace("\r", "")
        # Devices that echo (pty, Telnet server echo) repeat what we typed.
        if out.startswith(command + "\n"):
            out = out[len(command) + 1:]
        elif out.startswith("\n"):
            out = out[1:]
        return out

    def close(self, exit_cmd="exit"):
        raise NotImplementedError

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()


class TelnetSession(_Session):
    def __init__(self, host, port=23, **kw):
        super().__init__(host, port or 23, **kw)
        self._pending = b""
        try:
            self.sock = socket.create_connection((host, self.port), timeout=self.timeout)
        except OSError as e:
            self._close_log()
            raise SessionError(f"telnet connect to {host}:{self.port} failed: {e.strerror or e}") from e
        self.sock.setblocking(False)

    def _sendline(self, text):
        data = (text + "\r\n").encode("utf-8").replace(b"\xff", b"\xff\xff")
        try:
            self._send_all(data)
        except OSError as e:
            raise SessionError(f"telnet write failed: {e}") from e

    def _send_all(self, data):
        while data:
            select.select([], [self.sock], [], self.timeout)
            n = self.sock.send(data)
            data = data[n:]

    def _read(self, wait):
        r, _, _ = select.select([self.sock], [], [], wait)
        if not r:
            return True
        try:
            data = self.sock.recv(65536)
        except BlockingIOError:
            return True
        except OSError as e:
            self.errmsg, self.eof = f"connection error: {e}", True
            return False
        if not data:
            self.errmsg, self.eof = "connection closed", True
            return False
        self._received(self._negotiate(data).decode("utf-8", errors="replace"))
        return True

    def _negotiate(self, data):
        """Strip Telnet commands from the stream, refusing every option the peer offers."""
        data = self._pending + data
        self._pending = b""
        out, replies, i = bytearray(), bytearray(), 0
        while i < len(data):
            b = data[i]
            if b != IAC:
                out.append(b)
                i += 1
                continue
            if i + 1 >= len(data):
                self._pending = data[i:]
                break
            cmd = data[i + 1]
            if cmd == IAC:
                out.append(IAC)
                i += 2
            elif cmd in (WILL, WONT, DO, DONT):
                if i + 2 >= len(data):
                    self._pending = data[i:]
                    break
                opt = data[i + 2]
                if cmd == WILL:
                    replies += bytes((IAC, DONT, opt))
                elif cmd == DO:
                    replies += bytes((IAC, WONT, opt))
                i += 3
            elif cmd == SB:
                end = data.find(bytes((IAC, SE)), i + 2)
                if end < 0:
                    self._pending = data[i:]
                    break
                i = end + 2
            else:
                i += 2
        if replies:
            try:
                self._send_all(bytes(replies))
            except OSError:
                pass
        return bytes(out)

    def close(self, exit_cmd="exit"):
        if getattr(self, "sock", None) is None:
            return
        try:
            if not self.eof:
                self._sendline(exit_cmd or "exit")
        except SessionError:
            pass
        self.sock.close()
        self.sock = None
        self._close_log()


class SSHSession(_Session):
    def __init__(self, host, port=22, user=None, auth="password", key_file=None, known_hosts=None,
                 host_key_check="yes", ssh="ssh", **kw):
        super().__init__(host, port or 22, **kw)
        self.user, self.auth = user, auth or "password"
        self.key_file, self.known_hosts = key_file, known_hosts
        self.host_key_check = host_key_check or "yes"
        self.stderr = ""
        self.proc = self.sock = self.errfh = None
        try:
            self._spawn(ssh, kw.get("password"))
            if self.waitfor(self.prompt) is None:
                raise SessionError(self._connect_error())
        except BaseException:
            self._shutdown(0)
            raise

    def login(self, *args, **kw):
        """sshd has already authenticated the user."""

    def _command(self, ssh):
        o = [ssh, "-tt", "-e", "none", "-x", "-a", "-p", str(self.port), "-l", self.user,
             "-o", f"ConnectTimeout={self.timeout}", "-o", "ClearAllForwardings=yes", "-o", "LogLevel=ERROR",
             "-o", f"StrictHostKeyChecking={self.host_key_check}"]
        if self.known_hosts:
            o += ["-o", f"UserKnownHostsFile={self.known_hosts}"]
        if self.auth == "publickey":
            if not self.key_file or not os.access(self.key_file, os.R_OK):
                raise SessionError(f"ssh key file '{self.key_file}' not found")
            o += ["-i", self.key_file, "-o", "IdentitiesOnly=yes", "-o", "PreferredAuthentications=publickey",
                  "-o", "BatchMode=yes"]
        else:
            if not self.secrets:
                raise SessionError(f"no password for {self.user}@{self.host}")
            o += ["-o", "PreferredAuthentications=password,keyboard-interactive", "-o", "PubkeyAuthentication=no",
                  "-o", "NumberOfPasswordPrompts=1", "-o", "BatchMode=no"]
        return o + ["--", self.host]

    def _spawn(self, ssh, password):
        cmd = self._command(ssh)
        env = dict(os.environ)
        if self.auth == "password":
            env.update(SSH_ASKPASS=ASKPASS, SSH_ASKPASS_REQUIRE="force", CBT_SSH_ASKPASS_SECRET=password)
            env.setdefault("DISPLAY", "none")
        else:
            env["SSH_ASKPASS_REQUIRE"] = "never"
            env.pop("CBT_SSH_ASKPASS_SECRET", None)
        mine, theirs = socket.socketpair()
        try:
            # New session: no controlling tty, so ssh must use SSH_ASKPASS and never prompt on a terminal.
            self.proc = subprocess.Popen(cmd, stdin=theirs, stdout=theirs, stderr=subprocess.PIPE, env=env,
                                         start_new_session=True, close_fds=True)
        except OSError as e:
            mine.close()
            raise SessionError(f"cannot run {ssh}: {e.strerror or e}") from e
        finally:
            theirs.close()
        self.sock = mine
        self.errfh = self.proc.stderr

    def _sendline(self, text):
        try:
            self.sock.sendall((text + "\n").encode("utf-8"))
        except OSError as e:
            raise SessionError(f"ssh write failed: {e}") from e

    def _read(self, wait):
        fds = [f for f in (self.sock, self.errfh) if f is not None]
        r, _, _ = select.select(fds, [], [], wait)
        for f in r:
            if f is self.errfh:
                data = os.read(f.fileno(), 65536)
                if data:
                    self.stderr += data.decode("utf-8", errors="replace")
                else:
                    self.errfh.close()
                    self.errfh = None
                continue
            try:
                data = self.sock.recv(65536)
            except OSError:
                data = b""
            if not data:
                self.errmsg, self.eof = "connection closed", True
                return False
            self._received(data.decode("utf-8", errors="replace"))
        return True

    def _connect_error(self):
        self._reap(5)
        while self.errfh is not None and self._read(1):
            pass
        err = "; ".join(line for line in self.stderr.replace("\r", "").split("\n") if line.strip())
        if "Permission denied" in err:
            return f"login failed for {self.user} (ssh: {err})"
        where = f"{self.user}@{self.host}:{self.port}"
        return f"ssh connect to {where} failed: {err or self.errmsg or 'no prompt'}"

    def close(self, exit_cmd="exit"):
        if self.proc is not None and self.sock is not None and not self.eof:
            try:
                self._sendline(exit_cmd or "exit")
                # Like the Telnet session: send the exit command, then hang up (some CLIs need two exits).
                self._read(0.5)
            except SessionError:
                pass
        self._shutdown(1)

    def _shutdown(self, secs):
        self._reap(secs)
        if self.errfh is not None:
            self.errfh.close()
            self.errfh = None
        self._close_log()

    def _reap(self, secs):
        if self.sock is not None:
            self.sock.close()
            self.sock = None
        if self.proc is None:
            return
        try:
            self.proc.wait(timeout=secs)
        except subprocess.TimeoutExpired:
            self.proc.terminate()
            self.proc.wait()
        self.proc = None
