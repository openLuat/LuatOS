#!/usr/bin/env python3
import argparse
import json
import re
from pathlib import Path


IO_OPS = ("read", "prog", "erase", "sync")
WRITEBACK_REASON_KEYS = (
    "unknown",
    "over_limit",
    "expand_fallback",
    "pressure",
    "reserve_low",
    "cadence",
    "fflush",
    "fclose",
    "fread",
    "getc",
    "fseek",
    "ftell",
)

RE_STAGE_MS = re.compile(r"\b(LFS2N_[A-Z0-9_]*_MS)\b[^\d\-]*(-?\d+)")
RE_TRACE_WRITEBACK = re.compile(
    r"LFS2N_WRITEBACK_FLUSH\b.*?\breason=([a-z_]+)\b.*?\bbytes=(\d+)\b.*?\bstall_us=(\d+)"
)
RE_TRACE_CACHE = re.compile(r"LFS2_TRACE_CACHE_FLUSH\b.*?\bbytes=(\d+)\b.*?\bcost_us=(\d+)")
RE_WRITEBACK_WINDOW = re.compile(
    r"LFS2N_WRITEBACK_WINDOW\b.*?\bhigh=(\d+)\b.*?\blow=(\d+)\b.*?\breserve=(\d+)\b.*?\bfree=(\d+)\b"
)
RE_IO_SUMMARY = re.compile(
    r"LFS2N_IO_SUMMARY\b.*?\bop=(read|prog|erase|sync)\b.*?\bcalls=(\d+)\b.*?\bbytes=(\d+)\b.*?\btotal_us=(\d+)"
)
RE_PROFILE_SUMMARY = re.compile(
    r"profile summary:\s*meta_refresh=(\d+)\s+total=(\d+)\s+us(?:\s+deferred=(\d+)\s+force=(\d+))?,\s*writeback_flush=(\d+)\s+bytes=(\d+)\s+stall_us=(\d+)\s+reason_unknown=(\d+)\s+reason_over_limit=(\d+)\s+reason_expand_fallback=(\d+)\s+reason_pressure=(\d+)(?:\s+reason_reserve_low=(\d+))?\s+reason_cadence=(\d+)\s+reason_fflush=(\d+)\s+reason_fclose=(\d+)\s+reason_fread=(\d+)\s+reason_getc=(\d+)\s+reason_fseek=(\d+)\s+reason_ftell=(\d+)(?:\s+pressure_hold=(\d+)\s+reserve_hold=(\d+)\s+reserve_urgent=(\d+))?"
)
RE_PROFILE_SUMMARY_LEGACY = re.compile(
    r"profile summary:\s*meta_refresh=(\d+)\s+total=(\d+)\s+us,\s*cache_flush=(\d+)\s+bytes=(\d+)\s+total=(\d+)\s+us"
)
RE_CACHE_POOL_CONFIG = re.compile(
    r"LFS2N_CACHE_POOL_CONFIG\b.*?\bbudget=(\d+)\b.*?\bhard_cap=(\d+)\b.*?\bslots=(\d+)\b.*?\bchunk=(\d+)\b"
)
RE_CACHE_POOL_GUARD = re.compile(
    r"LFS2N_CACHE_POOL_GUARD\b.*?\brequested=(\d+)\b.*?\bin_use=(\d+)\b.*?\bbudget=(\d+)\b"
)
RE_META_REFRESH_STAGE = re.compile(
    r"LFS2N_META_REFRESH_STAGE\b.*?\bop=([a-z_]+)\b.*?\bstage=([a-z_]+)\b.*?\battempt=(\d+)\b.*?\bcost_us=(\d+)\b.*?\brc=(-?\d+)"
)
RE_META_REFRESH_CONT_DONE = re.compile(
    r"LFS2N_META_REFRESH_CONT\b.*?\bop=([a-z_]+)\b.*?\bevent=done\b.*?\bwork_us=(\d+)\b"
)
RE_META_REFRESH_SLOW = re.compile(r"\bmeta_refresh slow ([a-z_]+)\b.*?\bcost=(\d+)\s+us\b")
RE_LEGACY_META_STAGE = re.compile(
    r"\bspace metadata ([a-z_]+)\b.*?\battempt=(\d+)\b.*?\bcost=([^\s]+)\s+us\b"
)
RE_MOUNT_LEGACY_RECOVER = re.compile(r"\blfs2_nand mount legacy layout recover\b")
RE_SPACE_META_REBUILD = re.compile(r"\bspace metadata invalid, rebuilding\b")
RE_SPACE_META_DEFER = re.compile(r"\blfs2_nand mount load metadata failed, defer rebuild\b")


def _to_int(value, default=None):
    if value is None:
        return default
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _ratio(numerator, denominator):
    if denominator <= 0:
        return 0.0
    return round(float(numerator) / float(denominator), 6)


def _parse_kv_fields(line):
    return {k: v for k, v in re.findall(r"\b([a-zA-Z_]+)=([^\s,]+)", line)}


def _record_stage(metadata, op, stage_name, attempt, cost_us, rc):
    key = f"{op}.{stage_name}"
    stage = metadata["stage_timing"].setdefault(
        key,
        {
            "count": 0,
            "total_us": 0,
            "max_us": 0,
            "last_attempt": 0,
            "fail_count": 0,
        },
    )
    stage["count"] += 1
    stage["total_us"] += cost_us
    stage["max_us"] = max(stage["max_us"], cost_us)
    stage["last_attempt"] = attempt
    if rc != 0:
        stage["fail_count"] += 1

    overview = metadata["stage_overview"]
    overview["total_stage_count"] += 1
    overview["total_stage_us"] += cost_us
    overview["max_stage_us"] = max(overview["max_stage_us"], cost_us)
    if rc != 0:
        overview["failed_stage_count"] += 1

    by_op = overview["by_op"].setdefault(op, {"count": 0, "total_us": 0, "max_us": 0, "fail_count": 0})
    by_op["count"] += 1
    by_op["total_us"] += cost_us
    by_op["max_us"] = max(by_op["max_us"], cost_us)
    if rc != 0:
        by_op["fail_count"] += 1

    by_stage = overview["by_stage"].setdefault(
        stage_name,
        {"count": 0, "total_us": 0, "max_us": 0, "fail_count": 0},
    )
    by_stage["count"] += 1
    by_stage["total_us"] += cost_us
    by_stage["max_us"] = max(by_stage["max_us"], cost_us)
    if rc != 0:
        by_stage["fail_count"] += 1


def parse_metrics(lines):
    structured_stage_present = any(
        ("LFS2N_META_REFRESH_STAGE" in line or "LFS2N_METADATA_STAGE" in line)
        for line in lines
    )
    stage_latency_ms = {}
    io_summary = {op: {"calls": 0, "bytes": 0, "total_us": 0} for op in IO_OPS}
    writeback = {
        "trace_count": 0,
        "trace_bytes": 0,
        "trace_total_stall_us": 0,
        "trace_max_stall_us": 0,
        "reason_counts": {key: 0 for key in WRITEBACK_REASON_KEYS},
        "summary_count": 0,
        "summary_bytes": 0,
        "summary_stall_us": 0,
        "summary_pressure_hold_count": 0,
        "summary_reserve_hold_count": 0,
        "summary_reserve_urgent_count": 0,
        "window": {
            "count": 0,
            "high": 0,
            "low": 0,
            "reserve": 0,
            "free_min": 0,
            "free_max": 0,
            "last_free": 0,
            "reserve_low_hits": 0,
        },
        "summary_reason_counts": {key: 0 for key in WRITEBACK_REASON_KEYS},
    }
    cache_pool = {
        "config_seen": 0,
        "budget": 0,
        "hard_cap": 0,
        "slots": 0,
        "chunk": 0,
        "guard_count": 0,
        "guard_requested_bytes": 0,
    }
    metadata = {
        "meta_refresh_count": 0,
        "meta_refresh_total_us": 0,
        "meta_refresh_deferred_count": 0,
        "meta_refresh_force_count": 0,
        "stage_timing": {},
        "stage_overview": {
            "total_stage_count": 0,
            "total_stage_us": 0,
            "max_stage_us": 0,
            "failed_stage_count": 0,
            "by_op": {},
            "by_stage": {},
        },
    }
    mount_recovery = {
        "legacy_layout_recover_count": 0,
        "metadata_rebuild_count": 0,
        "metadata_defer_rebuild_count": 0,
    }
    summary_seen = False
    legacy_pending_stages = []

    for line in lines:
        m = RE_STAGE_MS.search(line)
        if m:
            stage_latency_ms[m.group(1)] = int(m.group(2))

        m = RE_TRACE_WRITEBACK.search(line)
        if m:
            reason = m.group(1)
            if reason not in writeback["reason_counts"]:
                reason = "unknown"
            writeback["trace_count"] += 1
            writeback["trace_bytes"] += int(m.group(2))
            stall_us = int(m.group(3))
            writeback["trace_total_stall_us"] += stall_us
            writeback["trace_max_stall_us"] = max(writeback["trace_max_stall_us"], stall_us)
            writeback["reason_counts"][reason] += 1

        m = RE_TRACE_CACHE.search(line)
        if m:
            writeback["trace_count"] += 1
            writeback["trace_bytes"] += int(m.group(1))
            stall_us = int(m.group(2))
            writeback["trace_total_stall_us"] += stall_us
            writeback["trace_max_stall_us"] = max(writeback["trace_max_stall_us"], stall_us)
            writeback["reason_counts"]["unknown"] += 1

        m = RE_WRITEBACK_WINDOW.search(line)
        if m:
            high = int(m.group(1))
            low = int(m.group(2))
            reserve = int(m.group(3))
            free = int(m.group(4))
            window = writeback["window"]
            window["count"] += 1
            window["high"] = high
            window["low"] = low
            window["reserve"] = reserve
            if window["count"] == 1:
                window["free_min"] = free
                window["free_max"] = free
            else:
                window["free_min"] = min(window["free_min"], free)
                window["free_max"] = max(window["free_max"], free)
            window["last_free"] = free
            if free <= reserve:
                window["reserve_low_hits"] += 1

        m = RE_IO_SUMMARY.search(line)
        if m:
            op = m.group(1)
            io_summary[op]["calls"] = int(m.group(2))
            io_summary[op]["bytes"] = int(m.group(3))
            io_summary[op]["total_us"] = int(m.group(4))

        m = RE_PROFILE_SUMMARY.search(line)
        if m:
            summary_seen = True
            metadata["meta_refresh_count"] = int(m.group(1))
            metadata["meta_refresh_total_us"] = int(m.group(2))
            if m.group(3) is not None:
                metadata["meta_refresh_deferred_count"] = int(m.group(3))
                metadata["meta_refresh_force_count"] = int(m.group(4))
            writeback["summary_count"] = int(m.group(5))
            writeback["summary_bytes"] = int(m.group(6))
            writeback["summary_stall_us"] = int(m.group(7))
            writeback["summary_reason_counts"]["unknown"] = int(m.group(8))
            writeback["summary_reason_counts"]["over_limit"] = int(m.group(9))
            writeback["summary_reason_counts"]["expand_fallback"] = int(m.group(10))
            writeback["summary_reason_counts"]["pressure"] = int(m.group(11))
            writeback["summary_reason_counts"]["reserve_low"] = int(m.group(12) or 0)
            writeback["summary_reason_counts"]["cadence"] = int(m.group(13))
            writeback["summary_reason_counts"]["fflush"] = int(m.group(14))
            writeback["summary_reason_counts"]["fclose"] = int(m.group(15))
            writeback["summary_reason_counts"]["fread"] = int(m.group(16))
            writeback["summary_reason_counts"]["getc"] = int(m.group(17))
            writeback["summary_reason_counts"]["fseek"] = int(m.group(18))
            writeback["summary_reason_counts"]["ftell"] = int(m.group(19))
            writeback["summary_pressure_hold_count"] = int(m.group(20) or 0)
            writeback["summary_reserve_hold_count"] = int(m.group(21) or 0)
            writeback["summary_reserve_urgent_count"] = int(m.group(22) or 0)
            for key in WRITEBACK_REASON_KEYS:
                writeback["reason_counts"][key] = max(
                    writeback["reason_counts"][key],
                    writeback["summary_reason_counts"][key],
                )

        m = RE_PROFILE_SUMMARY_LEGACY.search(line)
        if m:
            summary_seen = True
            metadata["meta_refresh_count"] = int(m.group(1))
            metadata["meta_refresh_total_us"] = int(m.group(2))
            writeback["summary_count"] = int(m.group(3))
            writeback["summary_bytes"] = int(m.group(4))
            writeback["summary_stall_us"] = int(m.group(5))

        m = RE_CACHE_POOL_CONFIG.search(line)
        if m:
            cache_pool["config_seen"] += 1
            cache_pool["budget"] = int(m.group(1))
            cache_pool["hard_cap"] = int(m.group(2))
            cache_pool["slots"] = int(m.group(3))
            cache_pool["chunk"] = int(m.group(4))

        m = RE_CACHE_POOL_GUARD.search(line)
        if m:
            cache_pool["guard_count"] += 1
            cache_pool["guard_requested_bytes"] += int(m.group(1))

        if "LFS2N_META_REFRESH_STAGE" in line or "LFS2N_METADATA_STAGE" in line:
            fields = _parse_kv_fields(line)
            op = fields.get("op")
            stage_name = fields.get("stage")
            attempt = _to_int(fields.get("attempt"), default=0)
            cost_us = _to_int(fields.get("cost_us"))
            rc = _to_int(fields.get("rc"))
            if op and stage_name and cost_us is not None and rc is not None:
                _record_stage(metadata, op, stage_name, attempt, cost_us, rc)
                continue

        m = RE_META_REFRESH_STAGE.search(line)
        if m:
            _record_stage(
                metadata,
                m.group(1),
                m.group(2),
                int(m.group(3)),
                int(m.group(4)),
                int(m.group(5)),
            )

        if not structured_stage_present:
            m = RE_LEGACY_META_STAGE.search(line)
            if m:
                stage_name = m.group(1)
                attempt = int(m.group(2))
                cost_us = _to_int(m.group(3))
                if cost_us is None:
                    legacy_pending_stages.append(("refresh", stage_name, attempt))
                else:
                    _record_stage(metadata, "refresh", stage_name, attempt, cost_us, 0)
                continue

        m = RE_META_REFRESH_CONT_DONE.search(line)
        if m and not summary_seen:
            metadata["meta_refresh_count"] += 1
            metadata["meta_refresh_total_us"] += int(m.group(2))
            if m.group(1) == "force":
                metadata["meta_refresh_force_count"] += 1
            if legacy_pending_stages:
                total_us = int(m.group(2))
                per = total_us // len(legacy_pending_stages)
                rem = total_us % len(legacy_pending_stages)
                for idx, pending in enumerate(legacy_pending_stages):
                    _record_stage(
                        metadata,
                        pending[0],
                        pending[1],
                        pending[2],
                        per + (1 if idx < rem else 0),
                        0,
                    )
                legacy_pending_stages = []
            continue

        m = RE_META_REFRESH_SLOW.search(line)
        if m and not summary_seen:
            metadata["meta_refresh_count"] += 1
            metadata["meta_refresh_total_us"] += int(m.group(2))
            if m.group(1) == "force":
                metadata["meta_refresh_force_count"] += 1
            if legacy_pending_stages:
                total_us = int(m.group(2))
                per = total_us // len(legacy_pending_stages)
                rem = total_us % len(legacy_pending_stages)
                for idx, pending in enumerate(legacy_pending_stages):
                    _record_stage(
                        metadata,
                        pending[0],
                        pending[1],
                        pending[2],
                        per + (1 if idx < rem else 0),
                        0,
                    )
                legacy_pending_stages = []
            continue

        if RE_MOUNT_LEGACY_RECOVER.search(line):
            mount_recovery["legacy_layout_recover_count"] += 1
        if RE_SPACE_META_REBUILD.search(line):
            mount_recovery["metadata_rebuild_count"] += 1
        if RE_SPACE_META_DEFER.search(line):
            mount_recovery["metadata_defer_rebuild_count"] += 1

    for pending in legacy_pending_stages:
        _record_stage(metadata, pending[0], pending[1], pending[2], 0, 0)

    total_latency_ms = 0
    has_pure_write_wall = "LFS2N_BASELINE_WRITE_PURE_WALL_MS" in stage_latency_ms
    for key, value in stage_latency_ms.items():
        if value < 0:
            continue
        if has_pure_write_wall and key == "LFS2N_BASELINE_WRITE_WALL_MS":
            continue
        total_latency_ms += value
    io_derived = {
        "read_us_per_prog_byte": _ratio(io_summary["read"]["total_us"], io_summary["prog"]["bytes"]),
        "read_bytes_per_prog_byte": _ratio(io_summary["read"]["bytes"], io_summary["prog"]["bytes"]),
        "read_calls_per_prog_call": _ratio(io_summary["read"]["calls"], io_summary["prog"]["calls"]),
    }
    metadata_stage = metadata["stage_overview"]
    return {
        "total_latency_ms": total_latency_ms,
        "stage_latency_ms": dict(sorted(stage_latency_ms.items())),
        "io_op_summary": io_summary,
        "io_derived": io_derived,
        "writeback": writeback,
        "cache_flush": {
            "trace_count": writeback["trace_count"],
            "trace_bytes": writeback["trace_bytes"],
            "trace_total_us": writeback["trace_total_stall_us"],
            "summary_count": writeback["summary_count"],
            "summary_bytes": writeback["summary_bytes"],
            "summary_total_us": writeback["summary_stall_us"],
        },
        "cache_pool": cache_pool,
        "metadata_refresh": metadata,
        "comparison_summary": {
            "metadata_stage": {
                "count": metadata_stage["total_stage_count"],
                "total_us": metadata_stage["total_stage_us"],
                "max_us": metadata_stage["max_stage_us"],
                "fail_count": metadata_stage["failed_stage_count"],
            },
            "read_amplification": io_derived,
        },
        "mount_recovery": mount_recovery,
    }


def main():
    parser = argparse.ArgumentParser(
        description="Extract normalized baseline metrics from lfs2n regression logs."
    )
    parser.add_argument("log_file", help="Path to regression log file")
    parser.add_argument("--json-out", help="Optional path to write normalized JSON")
    parser.add_argument("--require-cache-config", action="store_true",
                        help="Fail if cache pool config log was not found")
    parser.add_argument("--require-cache-guard", action="store_true",
                        help="Fail if cache pool guard log was not found")
    parser.add_argument("--require-writeback-telemetry", action="store_true",
                        help="Fail if writeback flush telemetry is missing")
    parser.add_argument("--require-writeback-reason", action="store_true",
                        help="Fail if no concrete writeback reason code was observed")
    args = parser.parse_args()

    log_path = Path(args.log_file)
    lines = log_path.read_text(encoding="utf-8", errors="ignore").splitlines()
    metrics = parse_metrics(lines)

    output = json.dumps(metrics, ensure_ascii=False, indent=2, sort_keys=True)
    print(output)

    if args.require_cache_config and metrics["cache_pool"]["config_seen"] <= 0:
        raise SystemExit("missing required cache pool config log")
    if args.require_cache_guard and metrics["cache_pool"]["guard_count"] <= 0:
        raise SystemExit("missing required cache pool guard log")
    if args.require_writeback_telemetry and metrics["writeback"]["trace_count"] <= 0:
        raise SystemExit("missing required writeback telemetry")
    if args.require_writeback_reason:
        reason_total = sum(
            v for k, v in metrics["writeback"]["reason_counts"].items()
            if k != "unknown"
        )
        if reason_total <= 0:
            raise SystemExit("missing required writeback reason code")

    if args.json_out:
        out_path = Path(args.json_out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(output + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
