import importlib.util
import pathlib
import unittest


MODULE_PATH = pathlib.Path(__file__).with_name("run_lfs2n_matrix.py")
spec = importlib.util.spec_from_file_location("run_lfs2n_matrix", MODULE_PATH)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class TestRunLfs2nMatrixSummary(unittest.TestCase):
    def test_prefers_pure_baseline_write_metric_when_present(self):
        result = {
            "case_id": "demo",
            "config": {},
            "metrics": {
                "stage_latency_ms": {
                    "LFS2N_BASELINE_WRITE_WALL_MS": 30000,
                    "LFS2N_BASELINE_WRITE_PURE_WALL_MS": 16000,
                }
            },
            "writeback_threshold": {},
            "timeout_occurrence": False,
            "run": {"returncode": 0, "elapsed_s": 1.0},
        }

        row = mod.to_summary_row(result)
        self.assertEqual(row["write_wall_ms"], 16000)

    def test_falls_back_to_legacy_baseline_write_metric(self):
        result = {
            "case_id": "demo",
            "config": {},
            "metrics": {
                "stage_latency_ms": {
                    "LFS2N_BASELINE_WRITE_WALL_MS": 17000,
                }
            },
            "writeback_threshold": {},
            "timeout_occurrence": False,
            "run": {"returncode": 0, "elapsed_s": 1.0},
        }

        row = mod.to_summary_row(result)
        self.assertEqual(row["write_wall_ms"], 17000)


if __name__ == "__main__":
    unittest.main()
