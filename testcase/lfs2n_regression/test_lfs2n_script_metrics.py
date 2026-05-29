import pathlib
import unittest


SCRIPT_PATH = (
    pathlib.Path(__file__).parent
    / "lfs2n_regression_basic"
    / "scripts"
    / "lfs2n_regression_test.lua"
)


class TestLfs2nScriptMetricEmission(unittest.TestCase):
    def test_has_fallback_log_for_pure_wall_metric(self):
        content = SCRIPT_PATH.read_text(encoding="utf-8")
        self.assertIn(
            'lfs2n_perf_log("LFS2N_METRIC", "LFS2N_BASELINE_WRITE_PURE_WALL_MS", wall_cost_ms)',
            content,
        )

    def test_perf_and_debug_logs_default_off(self):
        content = SCRIPT_PATH.read_text(encoding="utf-8")
        self.assertIn("local LFS2N_DEBUG_LOG_ENABLED = false", content)
        self.assertIn("local LFS2N_PERF_LOG_ENABLED = false", content)


if __name__ == "__main__":
    unittest.main()
