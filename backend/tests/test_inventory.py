import os
import unittest

from helpers import write_inventory  # noqa: F401  (sets sys.path)
from cbt import inventory

BASE = {"name": "D1", "host": "127.0.0.1", "model": "AX-4000", "sw": "R5.2.1", "user": "cbtadmin"}


def load_one(env=None, **kw):
    path = write_inventory([{**BASE, **kw}])
    try:
        return inventory.load(path, env={"HOME": "/home/u", **(env or {})})[0]
    finally:
        os.unlink(path)


class InventoryTest(unittest.TestCase):
    def test_telnet_default(self):
        d = load_one(password="p")
        self.assertEqual(d["protocol"], "telnet")
        self.assertEqual(d["port"], 23)
        self.assertNotIn("auth", d)

    def test_ssh_defaults(self):
        d = load_one(protocol="SSH", password="p")
        self.assertEqual((d["protocol"], d["port"], d["auth"], d["host_key_check"]), ("ssh", 22, "password", "yes"))
        self.assertEqual(load_one(protocol="ssh", key_file="/k", port=2201)["auth"], "publickey")
        self.assertEqual(load_one(protocol="ssh", key_file="~/k")["key_file"], "/home/u/k")

    def test_secrets_from_environment(self):
        env = {"CBT_PASSWORD": "env-pass", "CBT_ENABLE_PASSWORD": "env-enable", "CBT_SSH_KEY_FILE": "/env/key",
               "MY_PASS": "ref-pass"}
        d = load_one(env, protocol="ssh", auth="password")
        self.assertEqual(d["password"], "env-pass")
        self.assertEqual(d["enable_password"], "env-enable")
        self.assertEqual(load_one(env, protocol="ssh", auth="publickey")["key_file"], "/env/key")
        self.assertEqual(load_one(env, password="${MY_PASS}")["password"], "ref-pass")
        self.assertEqual(load_one(env, password="${UNSET_CBT_VAR}")["password"], "env-pass")
        self.assertEqual(load_one(env, password="inline")["password"], "inline")

    def test_invalid_settings(self):
        cases = [
            ({"protocol": "rlogin"}, "unknown protocol 'rlogin'"),
            ({"protocol": "ssh", "auth": "kerberos"}, "unknown auth 'kerberos'"),
            ({"protocol": "ssh", "auth": "publickey"}, "needs 'key_file'"),
            ({"protocol": "ssh", "user": "${UNSET_CBT_VAR}"}, "ssh needs 'user'"),
            ({"protocol": "ssh", "host_key_check": "maybe"}, "host_key_check must be"),
            ({"port": "abc"}, "port must be a number"),
        ]
        for kw, msg in cases:
            with self.subTest(kw=kw), self.assertRaisesRegex(inventory.InventoryError, msg):
                load_one(**kw)

    def test_public_view_hides_secrets(self):
        v = inventory.public_view(load_one(password="p", enable_password="e"))
        self.assertNotIn("password", v)
        self.assertNotIn("enable_password", v)
        self.assertTrue(v["has_password"] and v["has_enable_password"])

    def test_repo_inventories_load(self):
        conf = os.path.join(os.path.dirname(__file__), "..", "..", "conf")
        env = {"USER": "u", "CBT_SSH_KEY_FILE": "/k", "CBT_PASSWORD": "p"}
        for f in sorted(os.listdir(conf)):
            with self.subTest(inventory=f):
                self.assertEqual(len(inventory.load(os.path.join(conf, f), env=env)), 3)


if __name__ == "__main__":
    unittest.main()
