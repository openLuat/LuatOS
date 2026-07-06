import unittest

from verify_pgfs_nes_probe import parse_log_text, p95


class TestVerifyPgfsNesProbe(unittest.TestCase):
    def test_parse_log_extracts_tokens_and_hotspots(self):
        text = """
[2026-05-29 00:00:01.000][00000001.000] D/pgfs perf close path=a total=120
[2026-05-29 00:00:02.000][00000002.000] D/pgfs perf close path=b total=320
[2026-05-29 00:00:03.000][00000003.000] I/user.pgfs_nes_unzip ### PGFS_NES_UNZIP_METRIC ### unzip_ms=2000 reset_ms=150 entries=1
[2026-05-29 00:00:03.100][00000003.100] I/user.pgfs_nes_unzip ### PGFS_NES_UNZIP_PASS ###
"""
        parsed = parse_log_text(text)
        self.assertTrue(parsed["pass_seen"])
        self.assertFalse(parsed["fail_seen"])
        self.assertEqual(parsed["metric"]["unzip_ms"], 2000)
        self.assertEqual(parsed["metric"]["reset_ms"], 150)
        self.assertEqual(parsed["metric"]["entries"], 1)
        self.assertEqual(parsed["elapsed_s"], 3.1)
        self.assertEqual(parsed["close_totals_ms"], [120, 320])

    def test_p95(self):
        self.assertEqual(p95([]), 0)
        self.assertEqual(p95([1]), 1)
        self.assertEqual(p95([1, 2, 3, 4, 5]), 5)
        self.assertEqual(p95([10, 20, 30, 40, 50, 60, 70, 80, 90, 100]), 100)


if __name__ == "__main__":
    unittest.main()
