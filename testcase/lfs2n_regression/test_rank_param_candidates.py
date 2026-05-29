import importlib.util
import pathlib
import unittest

MODULE_PATH = pathlib.Path(__file__).with_name("rank_param_candidates.py")
spec = importlib.util.spec_from_file_location("rank_param_candidates", MODULE_PATH)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def _candidate(candidate_id, latency_ms, stall_total_us, stall_max_us, guard_count=0, over_limit=0, pressure=0, config_seen=1):
    return mod._normalize_candidate(
        candidate_id,
        {
            "total_latency_ms": latency_ms,
            "writeback": {
                "trace_total_stall_us": stall_total_us,
                "trace_max_stall_us": stall_max_us,
                "trace_count": 1,
                "reason_counts": {
                    "over_limit": over_limit,
                    "pressure": pressure,
                    "expand_fallback": 0,
                    "unknown": 0,
                },
            },
            "cache_pool": {
                "guard_count": guard_count,
                "guard_requested_bytes": 0,
                "hard_cap": 131072,
                "budget": 131072,
                "slots": 8,
                "chunk": 4096,
                "config_seen": config_seen,
            },
        },
        f"{candidate_id}.json",
    )


class TestRankParamCandidates(unittest.TestCase):
    def test_ranking_prefers_low_penalty(self):
        candidates = [
            _candidate("best", latency_ms=20000, stall_total_us=12000000, stall_max_us=2000000, guard_count=0, over_limit=0, pressure=2),
            _candidate("noisy", latency_ms=19000, stall_total_us=12000000, stall_max_us=2000000, guard_count=10, over_limit=5, pressure=5),
            _candidate("missing_telemetry", latency_ms=10000, stall_total_us=1000, stall_max_us=1000, config_seen=0),
        ]
        ranked = mod.rank_candidates(candidates)
        self.assertEqual(ranked[0]["candidate_id"], "best")
        self.assertEqual(ranked[-1]["candidate_id"], "missing_telemetry")
        self.assertLess(ranked[0]["ranking"]["penalty"], ranked[1]["ranking"]["penalty"])

    def test_build_recommendations_contains_both_presets(self):
        ranked = mod.rank_candidates([
            _candidate("top", latency_ms=18000, stall_total_us=10000000, stall_max_us=1800000),
            _candidate("second", latency_ms=19000, stall_total_us=11000000, stall_max_us=1900000),
        ])
        rec = mod.build_recommendations(ranked)
        self.assertIn("default_preset", rec)
        self.assertIn("aggressive_debug_preset", rec)
        self.assertEqual(rec["default_preset"]["from_candidate"], "top")
        self.assertEqual(rec["aggressive_debug_preset"]["from_candidate"], "top")


if __name__ == "__main__":
    unittest.main()
