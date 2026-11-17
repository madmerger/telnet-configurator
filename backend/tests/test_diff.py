import unittest

import helpers  # noqa: F401  (sets sys.path)
from cbt import diff, store

A = store.render({"name": "TKY-1", "model": "AX", "sw": "R5"},
                 [("show version", "v1\nsame\n"), ("show running-config", "hostname TKY-1\na\nb\nc\n")], "20260101-000000")
B = store.render({"name": "OSK-2", "model": "AX", "sw": "R6"},
                 [("show version", "v2\nsame\n"), ("show running-config", "hostname OSK-2\na\nc\nd\n"),
                  ("show extra", "x\n")], "20260102-000000")


class DiffTest(unittest.TestCase):
    def test_parse(self):
        header, sections = store.parse(A)
        self.assertEqual(header, "!! CBT collected TKY-1 (AX R5) at 20260101-000000")
        self.assertEqual(store.collected_at(header), "20260101-000000")
        self.assertEqual([c for c, _ in sections], ["show version", "show running-config"])

    def test_side_by_side(self):
        rows = diff.side_by_side(["a", "b", "c"], ["a", "c", "d"])
        self.assertEqual([r["t"] for r in rows], ["eq", "del", "eq", "add"])
        self.assertEqual(rows[1], {"t": "del", "l": 2, "lt": "b", "r": None, "rt": None})
        self.assertEqual(rows[3], {"t": "add", "l": None, "lt": None, "r": 3, "rt": "d"})
        self.assertEqual([r["t"] for r in diff.side_by_side(["x"], ["y"])], ["chg"])

    def compare(self, mask):
        items = [{"key": "a", "device": "TKY-1", "text": A}, {"key": "b", "device": "OSK-2", "text": B}]
        return diff.compare(items, mask_hostname=mask)

    def test_compare_masks_hostname(self):
        r = self.compare(True)
        self.assertEqual(r["commands"], ["show version", "show running-config", "show extra"])
        secs = {s["command"]: s for s in r["diffs"][0]["sections"]}
        self.assertEqual(secs["show version"]["status"], "changed")
        self.assertEqual(secs["show running-config"]["rows"][0]["t"], "eq")
        self.assertEqual(secs["show running-config"]["rows"][0]["lt"], "hostname {HOSTNAME}")
        self.assertEqual(secs["show extra"]["status"], "only_target")
        self.assertEqual(r["matrix"]["show extra"], {"a": None, "b": 0})
        self.assertEqual(r["matrix"]["show version"], {"a": 0, "b": 1})

    def test_compare_without_mask(self):
        secs = {s["command"]: s for s in self.compare(False)["diffs"][0]["sections"]}
        self.assertEqual(secs["show running-config"]["rows"][0]["t"], "chg")

    def test_identical(self):
        items = [{"key": "a", "device": "TKY-1", "text": A}, {"key": "b", "device": "TKY-1", "text": A}]
        r = diff.compare(items)
        self.assertTrue(r["diffs"][0]["identical"])
        self.assertEqual((r["diffs"][0]["added"], r["diffs"][0]["removed"]), (0, 0))


if __name__ == "__main__":
    unittest.main()
