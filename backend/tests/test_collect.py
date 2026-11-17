import os
import shutil
import tempfile
import unittest

from helpers import DEVICES, LAB_KEY, TelnetSim, expected_sections, port_open, telnet_device
from cbt import store
from cbt.service import collect_device


class CollectTestBase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.out, self.log = os.path.join(self.tmp, "output"), os.path.join(self.tmp, "log")
        self.addCleanup(shutil.rmtree, self.tmp)

    def assert_collected(self, dev, profile):
        r = collect_device(dev, self.out, self.log, timeout=10)
        self.assertTrue(r["ok"], r["error"])
        header, sections = store.parse(store.read(self.out, dev["name"], r["snapshot"]))
        self.assertTrue(header.startswith(f"!! CBT collected {dev['name']} ({dev['model']} {dev['sw']}) at "))
        self.assertEqual(dict(sections), expected_sections(profile, dev["name"]))
        self.assertEqual(store.read(self.out, dev["name"]), store.read(self.out, dev["name"], r["snapshot"]))
        return r


class TelnetCollectTest(CollectTestBase):
    @classmethod
    def setUpClass(cls):
        cls.sim = TelnetSim()

    @classmethod
    def tearDownClass(cls):
        cls.sim.stop()

    def dev(self, i, **over):
        name, _, model, sw, _ = DEVICES[i]
        d = telnet_device(name, self.sim.ports[name], model, sw)
        d.update(over)
        return d

    def test_all_models(self):
        for i, d in enumerate(DEVICES):
            with self.subTest(device=d[0]):
                self.assert_collected(self.dev(i), d[1])

    def test_session_log_masks_passwords(self):
        self.assert_collected(self.dev(0), DEVICES[0][1])
        with open(os.path.join(self.log, "TKY-ENB-0001.session.log")) as fh:
            log = fh.read()
        self.assertIn("hostname TKY-ENB-0001", log)
        self.assertNotIn("cbt-pass", log)
        self.assertNotIn("cbt-enable", log)

    def test_wrong_password(self):
        r = collect_device(self.dev(0, password="nope"), self.out, self.log, timeout=5)
        self.assertFalse(r["ok"])
        self.assertIn("login failed for cbtadmin", r["error"])
        self.assertEqual(store.snapshots(self.out, "TKY-ENB-0001"), [])

    def test_wrong_enable_password(self):
        r = collect_device(self.dev(1, enable_password="nope"), self.out, self.log, timeout=5)
        self.assertEqual(r["error"], "enable failed")

    def test_unknown_collector(self):
        r = collect_device(self.dev(0, sw="R9.0"), self.out, self.log)
        self.assertEqual(r["error"], "no collector for AX-4000:R9")

    def test_connection_refused(self):
        from helpers import free_port
        r = collect_device(self.dev(0, port=free_port()), self.out, self.log, timeout=3)
        self.assertIn("telnet connect to 127.0.0.1", r["error"])


@unittest.skipUnless(os.access(LAB_KEY, os.R_OK) and all(port_open(2200 + d[4]) for d in DEVICES),
                     "lab/ssh is not running (make lab-ssh-start)")
class SSHCollectTest(CollectTestBase):
    def dev(self, i, **over):
        name, _, model, sw, n = DEVICES[i]
        d = {"name": name, "protocol": "ssh", "host": "127.0.0.1", "port": 2200 + n, "model": model, "sw": sw,
             "user": os.environ.get("USER") or os.getlogin(), "auth": "publickey", "key_file": LAB_KEY,
             "known_hosts": os.path.join(self.tmp, "known_hosts"), "host_key_check": "accept-new",
             "enable_password": "cbt-enable"}
        d.update(over)
        return d

    def test_all_models_publickey(self):
        for i, d in enumerate(DEVICES):
            with self.subTest(device=d[0]):
                self.assert_collected(self.dev(i), d[1])

    def test_ssh_equals_telnet(self):
        sim = TelnetSim()
        self.addCleanup(sim.stop)
        for i, (name, _, model, sw, _) in enumerate(DEVICES):
            with self.subTest(device=name):
                a = collect_device(telnet_device(name, sim.ports[name], model, sw), self.out, self.log, timeout=10)
                t = store.parse(store.read(self.out, name))[1]
                b = collect_device(self.dev(i), self.out, self.log, timeout=10)
                s = store.parse(store.read(self.out, name))[1]
                self.assertTrue(a["ok"] and b["ok"])
                self.assertEqual(t, s)

    def test_unknown_host_key_rejected(self):
        r = collect_device(self.dev(0, host_key_check="yes"), self.out, self.log, timeout=5)
        self.assertFalse(r["ok"])
        self.assertIn("Host key verification failed", r["error"])

    def test_missing_key_file(self):
        r = collect_device(self.dev(0, key_file="/nonexistent"), self.out, self.log, timeout=5)
        self.assertEqual(r["error"], "ssh key file '/nonexistent' not found")


if __name__ == "__main__":
    unittest.main()
