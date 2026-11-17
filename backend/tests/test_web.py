import json
import os
import shutil
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request

import uvicorn

from helpers import DEVICES, TelnetSim, free_port, telnet_device, write_inventory
from cbt.config import Settings
from cbt.web import create_app


class WebTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sim = TelnetSim()
        cls.tmp = tempfile.mkdtemp()
        conf = os.path.join(cls.tmp, "conf")
        os.makedirs(conf)
        devs = [telnet_device(n, cls.sim.ports[n], m, sw) for n, _, m, sw, _ in DEVICES]
        devs.append(telnet_device("BAD-PASS-0001", cls.sim.ports["TKY-ENB-0001"], "AX-4000", "R5.2.1"))
        devs[-1]["password"] = "wrong"
        shutil.move(write_inventory(devs), os.path.join(conf, "lab.conf"))
        with open(os.path.join(conf, "broken.conf"), "w") as fh:
            fh.write("[X]\nhost = h\n")
        settings = Settings(conf_dir=conf, output_dir=os.path.join(cls.tmp, "output"),
                            log_dir=os.path.join(cls.tmp, "log"), web_dist=os.path.join(cls.tmp, "dist"), timeout=5)
        cls.port = free_port()
        cls.server = uvicorn.Server(uvicorn.Config(create_app(settings), port=cls.port, log_level="warning"))
        cls.thread = threading.Thread(target=cls.server.run, daemon=True)
        cls.thread.start()
        while not cls.server.started:
            time.sleep(0.05)

    @classmethod
    def tearDownClass(cls):
        cls.server.should_exit = True
        cls.thread.join()
        cls.sim.stop()
        shutil.rmtree(cls.tmp)

    def call(self, path, body=None):
        req = urllib.request.Request(f"http://127.0.0.1:{self.port}{path}",
                                     data=None if body is None else json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req) as r:
                data = r.read().decode()
                return r.status, json.loads(data) if r.headers.get_content_type() == "application/json" else data
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    def test_flow(self):
        status, invs = self.call("/api/inventories")
        self.assertEqual([i["name"] for i in invs], ["broken.conf", "lab.conf"])

        status, devs = self.call("/api/devices?inventory=lab.conf")
        self.assertEqual(status, 200)
        self.assertEqual(len(devs), 4)
        self.assertNotIn("password", devs[0])
        self.assertTrue(devs[0]["has_password"])
        self.assertEqual(devs[0]["collector"], "AX4000_R5")

        status, res = self.call("/api/collect", {"inventory": "lab.conf"})
        self.assertEqual(status, 200)
        by = {r["name"]: r for r in res["results"]}
        self.assertEqual((res["ok"], res["total"]), (3, 4))
        self.assertIn("login failed", by["BAD-PASS-0001"]["error"])

        # credentials typed in the UI override the inventory for that request only
        status, res = self.call("/api/collect", {"inventory": "lab.conf", "devices": ["BAD-PASS-0001"],
                                                 "password": "cbt-pass"})
        self.assertTrue(res["results"][0]["ok"], res)

        snap = by["TKY-ENB-0001"]["snapshot"]
        status, snaps = self.call("/api/configs/TKY-ENB-0001")
        self.assertEqual(snaps[0]["id"], snap)
        status, cfg = self.call(f"/api/configs/TKY-ENB-0001/{snap}")
        self.assertEqual([s["command"] for s in cfg["sections"]],
                         ["show version", "show running-config", "show cell status"])
        status, latest = self.call("/api/configs/TKY-ENB-0001/latest")
        self.assertEqual(latest["collected_at"], snap)
        status, raw = self.call("/api/configs/TKY-ENB-0001/latest/raw")
        self.assertTrue(raw.startswith("!! CBT collected TKY-ENB-0001"))
        status, log = self.call("/api/logs/TKY-ENB-0001")
        self.assertNotIn("cbt-pass", log)

        status, cmp_ = self.call("/api/compare", {"items": [{"device": "TKY-ENB-0001"}, {"device": "OSK-ENB-0102"},
                                                            {"device": "BAD-PASS-0001"}]})
        self.assertEqual(status, 200, cmp_)
        self.assertEqual(len(cmp_["diffs"]), 2)
        self.assertFalse(cmp_["diffs"][0]["identical"])
        # same simulator profile, hostname masked -> only the per-device generated values differ
        self.assertEqual(cmp_["matrix"]["show running-config"][cmp_["items"][0]["key"]], 0)

    def test_errors(self):
        self.assertEqual(self.call("/api/devices?inventory=broken.conf")[0], 400)
        self.assertEqual(self.call("/api/devices?inventory=nope.conf")[0], 404)
        self.assertEqual(self.call("/api/devices?inventory=..%2Fetc%2Fpasswd")[0], 400)
        self.assertEqual(self.call("/api/configs/..")[0], 400)
        self.assertEqual(self.call("/api/configs/NOPE/latest")[0], 404)
        self.assertEqual(self.call("/api/configs/TKY-ENB-0001/../../x")[0], 404)
        self.assertEqual(self.call("/api/compare", {"items": [{"device": "TKY-ENB-0001"}]})[0], 400)
        status, body = self.call("/api/collect", {"inventory": "lab.conf", "devices": ["NOPE"]})
        self.assertEqual((status, body["error"]), (404, "not in inventory: NOPE"))


if __name__ == "__main__":
    unittest.main()
