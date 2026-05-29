import importlib.util
import pathlib
import unittest

MODULE_PATH = pathlib.Path(__file__).with_name("extract_baseline_metrics.py")
spec = importlib.util.spec_from_file_location("extract_baseline_metrics", MODULE_PATH)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class TestWritebackTelemetryParsing(unittest.TestCase):
    def test_extracts_normalized_writeback_fields(self):
        lines = [
            "D/vfs.lfs2_nand LFS2N_WRITEBACK_FLUSH flush_idx=1 reason=over_limit bytes=262144 stall_us=9424649",
            "D/vfs.lfs2_nand LFS2N_WRITEBACK_FLUSH flush_idx=2 reason=pressure bytes=131072 stall_us=123456",
            "D/vfs.lfs2_nand LFS2N_WRITEBACK_FLUSH flush_idx=3 reason=reserve_low bytes=126976 stall_us=222222",
            "D/vfs.lfs2_nand LFS2N_WRITEBACK_FLUSH flush_idx=3 reason=expand_fallback bytes=126976 stall_us=6178567",
            "D/vfs.lfs2_nand profile summary: meta_refresh=0 total=0 us, writeback_flush=4 bytes=647168 stall_us=15948894 reason_unknown=0 reason_over_limit=1 reason_expand_fallback=1 reason_pressure=1 reason_reserve_low=1 reason_cadence=0 reason_fflush=0 reason_fclose=0 reason_fread=0 reason_getc=0 reason_fseek=0 reason_ftell=0",
        ]
        metrics = mod.parse_metrics(lines)
        wb = metrics["writeback"]
        self.assertEqual(wb["trace_count"], 4)
        self.assertEqual(wb["trace_bytes"], 647168)
        self.assertEqual(wb["trace_total_stall_us"], 15948894)
        self.assertEqual(wb["trace_max_stall_us"], 9424649)
        self.assertEqual(wb["reason_counts"]["over_limit"], 1)
        self.assertEqual(wb["reason_counts"]["pressure"], 1)
        self.assertEqual(wb["reason_counts"]["reserve_low"], 1)
        self.assertEqual(wb["reason_counts"]["expand_fallback"], 1)
        self.assertEqual(wb["summary_count"], 4)
        self.assertEqual(wb["summary_bytes"], 647168)
        self.assertEqual(wb["summary_stall_us"], 15948894)
        self.assertEqual(wb["summary_reason_counts"]["reserve_low"], 1)
        self.assertEqual(wb["summary_reason_counts"]["pressure"], 1)

    def test_extracts_metadata_cadence_fields(self):
        lines = [
            "D/vfs.lfs2_nand profile summary: meta_refresh=2 total=900 us deferred=5 force=1, writeback_flush=1 bytes=4096 stall_us=200 reason_unknown=0 reason_over_limit=0 reason_expand_fallback=0 reason_pressure=0 reason_cadence=1 reason_fflush=0 reason_fclose=0 reason_fread=0 reason_getc=0 reason_fseek=0 reason_ftell=0, cache_guard=0 budget=131072 per_file_limit=65536 hard_cap=131072 peak_in_use=4096",
        ]
        metrics = mod.parse_metrics(lines)
        md = metrics["metadata_refresh"]
        wb = metrics["writeback"]
        self.assertEqual(md["meta_refresh_count"], 2)
        self.assertEqual(md["meta_refresh_total_us"], 900)
        self.assertEqual(md["meta_refresh_deferred_count"], 5)
        self.assertEqual(md["meta_refresh_force_count"], 1)
        self.assertEqual(wb["summary_reason_counts"]["reserve_low"], 0)

    def test_extracts_mount_metadata_recovery_events(self):
        lines = [
            "D/vfs.lfs2_nand lfs2_nand mount legacy layout recover",
            "D/vfs.lfs2_nand space metadata invalid, rebuilding",
            "D/vfs.lfs2_nand lfs2_nand mount load metadata failed, defer rebuild",
        ]
        metrics = mod.parse_metrics(lines)
        mr = metrics["mount_recovery"]
        self.assertEqual(mr["legacy_layout_recover_count"], 1)
        self.assertEqual(mr["metadata_rebuild_count"], 1)
        self.assertEqual(mr["metadata_defer_rebuild_count"], 1)

    def test_extracts_strategy_a_window_and_hold_metrics(self):
        lines = [
            "D/vfs.lfs2_nand LFS2N_WRITEBACK_WINDOW high=57344 low=32768 reserve=16384 free=8192",
            "D/vfs.lfs2_nand LFS2N_WRITEBACK_WINDOW high=57344 low=32768 reserve=16384 free=24576",
            "D/vfs.lfs2_nand profile summary: meta_refresh=0 total=0 us deferred=0 force=0, writeback_flush=2 bytes=65536 stall_us=200 reason_unknown=0 reason_over_limit=0 reason_expand_fallback=0 reason_pressure=0 reason_reserve_low=1 reason_cadence=0 reason_fflush=0 reason_fclose=1 reason_fread=0 reason_getc=0 reason_fseek=0 reason_ftell=0 pressure_hold=3 reserve_hold=2 reserve_urgent=1, cache_guard=0 budget=131072 per_file_limit=65536 hard_cap=131072 peak_in_use=65536",
        ]
        metrics = mod.parse_metrics(lines)
        wb = metrics["writeback"]
        win = wb["window"]
        self.assertEqual(win["count"], 2)
        self.assertEqual(win["free_min"], 8192)
        self.assertEqual(win["free_max"], 24576)
        self.assertEqual(win["last_free"], 24576)
        self.assertEqual(win["reserve_low_hits"], 1)
        self.assertEqual(wb["summary_pressure_hold_count"], 3)
        self.assertEqual(wb["summary_reserve_hold_count"], 2)
        self.assertEqual(wb["summary_reserve_urgent_count"], 1)

    def test_extracts_stage_overview_from_metadata_stage_logs(self):
        lines = [
            "D/vfs.lfs2_nand LFS2N_METADATA_STAGE stage=scan op=refresh attempt=0 cost_us=11 rc=0",
            "D/vfs.lfs2_nand LFS2N_METADATA_STAGE op=refresh stage=scan attempt=1 rc=-5 cost_us=13",
            "D/vfs.lfs2_nand LFS2N_META_REFRESH_STAGE stage=write op=refresh cost_us=21 rc=0 attempt=0",
            "D/vfs.lfs2_nand LFS2N_META_REFRESH_STAGE op=load stage=validate cost_us=8 rc=0",
        ]
        metrics = mod.parse_metrics(lines)
        stage_timing = metrics["metadata_refresh"]["stage_timing"]
        stage_overview = metrics["metadata_refresh"]["stage_overview"]
        by_op = stage_overview["by_op"]
        by_stage = stage_overview["by_stage"]
        self.assertEqual(stage_timing["refresh.scan"]["count"], 2)
        self.assertEqual(stage_timing["refresh.scan"]["fail_count"], 1)
        self.assertEqual(stage_timing["refresh.scan"]["last_attempt"], 1)
        self.assertEqual(stage_overview["total_stage_count"], 4)
        self.assertEqual(stage_overview["total_stage_us"], 53)
        self.assertEqual(stage_overview["max_stage_us"], 21)
        self.assertEqual(stage_overview["failed_stage_count"], 1)
        self.assertEqual(by_op["refresh"]["count"], 3)
        self.assertEqual(by_op["refresh"]["total_us"], 45)
        self.assertEqual(by_op["refresh"]["max_us"], 21)
        self.assertEqual(by_stage["scan"]["count"], 2)
        self.assertEqual(by_stage["scan"]["fail_count"], 1)
        self.assertEqual(by_stage["scan"]["max_us"], 13)

    def test_extracts_io_read_amplification_metrics(self):
        lines = [
            "D/little_flash LFS2N_IO_SUMMARY op=read calls=4 bytes=100 total_us=240 max_us=90",
            "D/little_flash LFS2N_IO_SUMMARY op=prog calls=2 bytes=80 total_us=20 max_us=11",
        ]
        metrics = mod.parse_metrics(lines)
        io_derived = metrics["io_derived"]
        self.assertEqual(io_derived["read_us_per_prog_byte"], 3.0)
        self.assertEqual(io_derived["read_bytes_per_prog_byte"], 1.25)
        self.assertEqual(io_derived["read_calls_per_prog_call"], 2.0)

    def test_extracts_legacy_device_metadata_stage_with_cont_done(self):
        lines = [
            "D/vfs.lfs2_nand space metadata scan attempt=0 cost=lu us",
            "D/vfs.lfs2_nand space metadata write attempt=0 cost=lu us",
            "D/vfs.lfs2_nand LFS2N_META_REFRESH_CONT op=dirty event=done attempt=0 slot=1 used=10 total=100 work_us=14945382",
        ]
        metrics = mod.parse_metrics(lines)
        metadata = metrics["metadata_refresh"]
        stage_overview = metadata["stage_overview"]
        by_stage = stage_overview["by_stage"]
        self.assertEqual(metadata["meta_refresh_count"], 1)
        self.assertEqual(metadata["meta_refresh_total_us"], 14945382)
        self.assertEqual(stage_overview["total_stage_count"], 2)
        self.assertEqual(stage_overview["total_stage_us"], 14945382)
        self.assertEqual(by_stage["scan"]["count"], 1)
        self.assertEqual(by_stage["write"]["count"], 1)

    def test_avoids_double_count_when_pure_and_legacy_write_wall_keys_both_exist(self):
        lines = [
            "I/user.LFS2N_BASELINE_MOUNT_MS 3000",
            "I/user.LFS2N_BASELINE_WRITE_WALL_MS 30000",
            "I/user.LFS2N_BASELINE_WRITE_PURE_WALL_MS 16000",
            "I/user.LFS2N_WRITE_MS 14000",
        ]
        metrics = mod.parse_metrics(lines)
        self.assertEqual(metrics["stage_latency_ms"]["LFS2N_BASELINE_WRITE_WALL_MS"], 30000)
        self.assertEqual(metrics["stage_latency_ms"]["LFS2N_BASELINE_WRITE_PURE_WALL_MS"], 16000)
        self.assertEqual(metrics["total_latency_ms"], 33000)


if __name__ == "__main__":
    unittest.main()
