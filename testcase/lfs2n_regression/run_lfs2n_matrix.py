#!/usr/bin/env python3
import argparse
import csv
import json
import os
import re
import subprocess
import time
from pathlib import Path

from extract_baseline_metrics import parse_metrics


ROOT = Path(__file__).resolve().parents[2]
BSP_PC = ROOT / "bsp" / "pc"
OUT_DIR = ROOT / "testcase" / "lfs2n_regression" / "outputs"
EXE_PATH = BSP_PC / "build" / "out" / "luatos-lua.exe"
COMMON_SCRIPTS = ROOT / "testcase" / "common" / "scripts"
REGRESSION_SCRIPTS = ROOT / "testcase" / "lfs2n_regression" / "lfs2n_regression_basic" / "scripts"

RE_WRITEBACK_THRESHOLD = re.compile(r"\bthreshold=(\d+)\b")
RE_TIMEOUT_WORD = re.compile(r"timeout risk|timed out|超时", re.IGNORECASE)

DEFAULT_KNOBS = {
    "LUAT_LFS2N_CACHE_POOL_BUDGET": 131072,
    "LUAT_LFS2N_CACHE_POOL_SLOTS": 8,
    "LUAT_LFS2N_CACHE_POOL_CHUNK": 4096,
    "LUAT_LFS2N_FILE_CACHE_LIMIT": 65536,
    "LUAT_LFS2N_WRITEBACK_FLUSH_CADENCE_US": 50000,
    "LUAT_LFS2N_WRITEBACK_PRESSURE_HIGH_PCT": 87,
    "LUAT_LFS2N_WRITEBACK_PRESSURE_LOW_PCT": 62,
    "LUAT_LFS2N_WRITEBACK_RESERVE_PCT": 12,
    "LUAT_LFS2N_WRITEBACK_RESERVE_URGENT_PCT": 4,
    "LUAT_LFS2N_WRITEBACK_RESERVE_DEFER_US": 5000000,
    "LUAT_LFS2N_META_REFRESH_MIN_INTERVAL_US": 100000,
    "LUAT_LFS2N_META_REFRESH_MAX_DELAY_US": 3000000,
}

KNOB_RANGES = {
    "LUAT_LFS2N_CACHE_POOL_BUDGET": [65536, 131072],
    "LUAT_LFS2N_CACHE_POOL_SLOTS": [4, 8, 16],
    "LUAT_LFS2N_CACHE_POOL_CHUNK": [2048, 4096],
    "LUAT_LFS2N_FILE_CACHE_LIMIT": [32768, 65536],
    "LUAT_LFS2N_WRITEBACK_FLUSH_CADENCE_US": [20000, 50000, 100000],
    "LUAT_LFS2N_WRITEBACK_PRESSURE_HIGH_PCT": [80, 87, 92],
    "LUAT_LFS2N_WRITEBACK_PRESSURE_LOW_PCT": [50, 62, 70],
    "LUAT_LFS2N_WRITEBACK_RESERVE_PCT": [8, 12, 20],
    "LUAT_LFS2N_WRITEBACK_RESERVE_URGENT_PCT": [2, 4, 8],
    "LUAT_LFS2N_WRITEBACK_RESERVE_DEFER_US": [1000000, 5000000, 10000000],
    "LUAT_LFS2N_META_REFRESH_MIN_INTERVAL_US": [50000, 100000, 200000],
    "LUAT_LFS2N_META_REFRESH_MAX_DELAY_US": [1000000, 3000000, 5000000],
}


def build_factorial_cases():
    cases = []
    idx = 1
    for budget in (65536, 131072):
        for limit in (32768, 65536):
            for chunk in (2048, 4096):
                cfg = dict(DEFAULT_KNOBS)
                cfg["LUAT_LFS2N_CACHE_POOL_BUDGET"] = budget
                cfg["LUAT_LFS2N_FILE_CACHE_LIMIT"] = limit
                cfg["LUAT_LFS2N_CACHE_POOL_CHUNK"] = chunk
                cases.append({"id": f"factorial_{idx:02d}", "config": cfg})
                idx += 1
    return cases


def build_matrix_cases():
    cases = build_factorial_cases()
    extras = [
        ("slots_04", {"LUAT_LFS2N_CACHE_POOL_SLOTS": 4}),
        ("slots_16", {"LUAT_LFS2N_CACHE_POOL_SLOTS": 16}),
        (
            "cadence_fast_meta_fresh",
            {
                "LUAT_LFS2N_WRITEBACK_FLUSH_CADENCE_US": 20000,
                "LUAT_LFS2N_META_REFRESH_MIN_INTERVAL_US": 50000,
                "LUAT_LFS2N_META_REFRESH_MAX_DELAY_US": 1000000,
            },
        ),
        (
            "cadence_slow_meta_stale",
            {
                "LUAT_LFS2N_WRITEBACK_FLUSH_CADENCE_US": 100000,
                "LUAT_LFS2N_META_REFRESH_MIN_INTERVAL_US": 200000,
                "LUAT_LFS2N_META_REFRESH_MAX_DELAY_US": 5000000,
            },
        ),
        (
            "strategyA_base_64k",
            {
                "LUAT_LFS2N_FILE_CACHE_LIMIT": 65536,
                "LUAT_LFS2N_WRITEBACK_PRESSURE_HIGH_PCT": 87,
                "LUAT_LFS2N_WRITEBACK_PRESSURE_LOW_PCT": 62,
                "LUAT_LFS2N_WRITEBACK_RESERVE_PCT": 12,
                "LUAT_LFS2N_WRITEBACK_RESERVE_URGENT_PCT": 4,
                "LUAT_LFS2N_WRITEBACK_RESERVE_DEFER_US": 5000000,
            },
        ),
        (
            "strategyA_early_guard",
            {
                "LUAT_LFS2N_FILE_CACHE_LIMIT": 65536,
                "LUAT_LFS2N_WRITEBACK_FLUSH_CADENCE_US": 20000,
                "LUAT_LFS2N_WRITEBACK_PRESSURE_HIGH_PCT": 78,
                "LUAT_LFS2N_WRITEBACK_PRESSURE_LOW_PCT": 52,
                "LUAT_LFS2N_WRITEBACK_RESERVE_PCT": 20,
                "LUAT_LFS2N_WRITEBACK_RESERVE_URGENT_PCT": 8,
                "LUAT_LFS2N_WRITEBACK_RESERVE_DEFER_US": 800000,
            },
        ),
        (
            "strategyA_balanced",
            {
                "LUAT_LFS2N_FILE_CACHE_LIMIT": 65536,
                "LUAT_LFS2N_WRITEBACK_FLUSH_CADENCE_US": 30000,
                "LUAT_LFS2N_WRITEBACK_PRESSURE_HIGH_PCT": 82,
                "LUAT_LFS2N_WRITEBACK_PRESSURE_LOW_PCT": 56,
                "LUAT_LFS2N_WRITEBACK_RESERVE_PCT": 16,
                "LUAT_LFS2N_WRITEBACK_RESERVE_URGENT_PCT": 6,
                "LUAT_LFS2N_WRITEBACK_RESERVE_DEFER_US": 1500000,
            },
        ),
        (
            "strategyA_late_reserve",
            {
                "LUAT_LFS2N_FILE_CACHE_LIMIT": 65536,
                "LUAT_LFS2N_WRITEBACK_FLUSH_CADENCE_US": 50000,
                "LUAT_LFS2N_WRITEBACK_PRESSURE_HIGH_PCT": 90,
                "LUAT_LFS2N_WRITEBACK_PRESSURE_LOW_PCT": 70,
                "LUAT_LFS2N_WRITEBACK_RESERVE_PCT": 8,
                "LUAT_LFS2N_WRITEBACK_RESERVE_URGENT_PCT": 2,
                "LUAT_LFS2N_WRITEBACK_RESERVE_DEFER_US": 8000000,
            },
        ),
    ]
    for case_id, patch in extras:
        cfg = dict(DEFAULT_KNOBS)
        cfg.update(patch)
        cases.append({"id": case_id, "config": cfg})
    return cases


def run_cmd(cmd, cwd, env=None, timeout=600):
    start = time.time()
    try:
        completed = subprocess.run(
            cmd,
            cwd=str(cwd),
            env=env,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
        stdout = (completed.stdout or b"").decode("utf-8", errors="ignore")
        stderr = (completed.stderr or b"").decode("utf-8", errors="ignore")
        return {
            "returncode": completed.returncode,
            "stdout": stdout,
            "stderr": stderr,
            "elapsed_s": round(time.time() - start, 3),
            "timed_out": False,
        }
    except subprocess.TimeoutExpired as exc:
        stdout = (exc.stdout or b"").decode("utf-8", errors="ignore")
        stderr = (exc.stderr or b"").decode("utf-8", errors="ignore")
        return {
            "returncode": -1,
            "stdout": stdout,
            "stderr": stderr,
            "elapsed_s": round(time.time() - start, 3),
            "timed_out": True,
        }


def parse_threshold_metrics(lines):
    values = [int(m.group(1)) for m in map(RE_WRITEBACK_THRESHOLD.search, lines) if m]
    if not values:
        return {"count": 0, "first": 0, "max": 0}
    return {"count": len(values), "first": values[0], "max": max(values)}


def run_case(case):
    case_id = case["id"]
    cfg = case["config"]
    env = os.environ.copy()
    for key, val in cfg.items():
        env[key] = str(val)
    env["LUAT_BUILD_MODE"] = "summary"

    build_ret = run_cmd(
        ["cmd", "/c", "build_windows_32bit_msvc.bat"],
        cwd=BSP_PC,
        env=env,
        timeout=900,
    )
    if build_ret["returncode"] != 0 or build_ret["timed_out"]:
        return {
            "case_id": case_id,
            "config": cfg,
            "build": build_ret,
            "run": None,
            "timeout_occurrence": bool(build_ret["timed_out"]),
            "error": "build_failed",
        }

    run_ret = run_cmd(
        [
            str(EXE_PATH),
            str(COMMON_SCRIPTS),
            str(REGRESSION_SCRIPTS),
        ],
        cwd=BSP_PC,
        env=env,
        timeout=240,
    )

    log_text = run_ret["stdout"] + ("\n" + run_ret["stderr"] if run_ret["stderr"] else "")
    log_lines = log_text.splitlines()
    metrics = parse_metrics(log_lines)
    threshold = parse_threshold_metrics(log_lines)
    timeout_occurrence = bool(run_ret["timed_out"]) or bool(RE_TIMEOUT_WORD.search(log_text))

    log_path = OUT_DIR / f"pc_lfs2n_matrix_{case_id}.log"
    log_path.write_text(log_text, encoding="utf-8", errors="ignore")

    return {
        "case_id": case_id,
        "config": cfg,
        "build": build_ret,
        "run": {
            "returncode": run_ret["returncode"],
            "elapsed_s": run_ret["elapsed_s"],
            "timed_out": run_ret["timed_out"],
            "log_path": str(log_path.relative_to(ROOT)).replace("\\", "/"),
        },
        "timeout_occurrence": timeout_occurrence,
        "metrics": metrics,
        "writeback_threshold": threshold,
    }


def refresh_case_from_log(existing_case):
    case = dict(existing_case)
    run_info = case.get("run") or {}
    rel_log_path = run_info.get("log_path")
    if not rel_log_path:
        case["timeout_occurrence"] = bool(run_info.get("timed_out"))
        return case
    log_path = ROOT / rel_log_path.replace("/", os.sep)
    if not log_path.exists():
        case["timeout_occurrence"] = bool(run_info.get("timed_out"))
        return case
    log_text = log_path.read_text(encoding="utf-8", errors="ignore")
    log_lines = log_text.splitlines()
    case["metrics"] = parse_metrics(log_lines)
    case["writeback_threshold"] = parse_threshold_metrics(log_lines)
    case["timeout_occurrence"] = bool(run_info.get("timed_out")) or bool(RE_TIMEOUT_WORD.search(log_text))
    return case


def to_summary_row(result):
    metrics = result.get("metrics", {})
    writeback = metrics.get("writeback", {})
    md = metrics.get("metadata_refresh", {})
    config = result.get("config", {})
    stage_ms = metrics.get("stage_latency_ms", {})
    write_wall_ms = stage_ms.get(
        "LFS2N_BASELINE_WRITE_PURE_WALL_MS",
        stage_ms.get("LFS2N_BASELINE_WRITE_WALL_MS", 0),
    )
    return {
        "case_id": result["case_id"],
        "pool_budget": config.get("LUAT_LFS2N_CACHE_POOL_BUDGET", 0),
        "pool_slots": config.get("LUAT_LFS2N_CACHE_POOL_SLOTS", 0),
        "pool_chunk": config.get("LUAT_LFS2N_CACHE_POOL_CHUNK", 0),
        "file_cache_limit": config.get("LUAT_LFS2N_FILE_CACHE_LIMIT", 0),
        "writeback_cadence_us": config.get("LUAT_LFS2N_WRITEBACK_FLUSH_CADENCE_US", 0),
        "writeback_pressure_high_pct": config.get("LUAT_LFS2N_WRITEBACK_PRESSURE_HIGH_PCT", 87),
        "writeback_pressure_low_pct": config.get("LUAT_LFS2N_WRITEBACK_PRESSURE_LOW_PCT", 62),
        "writeback_reserve_pct": config.get("LUAT_LFS2N_WRITEBACK_RESERVE_PCT", 12),
        "writeback_reserve_urgent_pct": config.get("LUAT_LFS2N_WRITEBACK_RESERVE_URGENT_PCT", 4),
        "writeback_reserve_defer_us": config.get("LUAT_LFS2N_WRITEBACK_RESERVE_DEFER_US", 5000000),
        "meta_min_interval_us": config.get("LUAT_LFS2N_META_REFRESH_MIN_INTERVAL_US", 0),
        "meta_max_delay_us": config.get("LUAT_LFS2N_META_REFRESH_MAX_DELAY_US", 0),
        "total_latency_ms": metrics.get("total_latency_ms", 0),
        "mount_ms": stage_ms.get("LFS2N_BASELINE_MOUNT_MS", 0),
        "write_wall_ms": write_wall_ms,
        "write_ms": stage_ms.get("LFS2N_WRITE_MS", 0),
        "writeback_flush_count": writeback.get("trace_count", 0),
        "writeback_stall_total_us": writeback.get("trace_total_stall_us", 0),
        "writeback_stall_max_us": writeback.get("trace_max_stall_us", 0),
        "meta_refresh_count": md.get("meta_refresh_count", 0),
        "meta_refresh_deferred_count": md.get("meta_refresh_deferred_count", 0),
        "meta_refresh_force_count": md.get("meta_refresh_force_count", 0),
        "threshold_first": result.get("writeback_threshold", {}).get("first", 0),
        "threshold_max": result.get("writeback_threshold", {}).get("max", 0),
        "timeout_occurrence": int(bool(result.get("timeout_occurrence"))),
        "run_returncode": result.get("run", {}).get("returncode", -1) if result.get("run") else -1,
        "run_elapsed_s": result.get("run", {}).get("elapsed_s", 0) if result.get("run") else 0,
    }


def main():
    parser = argparse.ArgumentParser(description="Run lfs2n parameter matrix on PC simulator.")
    parser.add_argument(
        "--reuse-existing",
        action="store_true",
        help="Reuse existing logs/results JSON to regenerate normalized artifacts without rebuilding/rerunning.",
    )
    parser.add_argument(
        "--only-case",
        help="Run a single case_id from the predefined matrix and merge into existing JSON if present.",
    )
    args = parser.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    cases = build_matrix_cases()
    results = []
    json_path = OUT_DIR / "pc_lfs2n_matrix_results.json"
    if args.reuse_existing:
        if not json_path.exists():
            raise SystemExit(f"missing existing results: {json_path}")
        existing = json.loads(json_path.read_text(encoding="utf-8"))
        for run in existing.get("runs", []):
            results.append(refresh_case_from_log(run))
        cases = [{"id": r.get("case_id", f"case_{i}"), "config": r.get("config", {})} for i, r in enumerate(results, 1)]
    else:
        if args.only_case:
            cases = [c for c in cases if c["id"] == args.only_case]
            if not cases:
                raise SystemExit(f"unknown case id: {args.only_case}")
        for case in cases:
            result = run_case(case)
            results.append(result)
        if args.only_case and json_path.exists():
            existing = json.loads(json_path.read_text(encoding="utf-8"))
            existing_runs = {r.get("case_id"): r for r in existing.get("runs", [])}
            for run in results:
                existing_runs[run["case_id"]] = run
            ordered = []
            for case in build_matrix_cases():
                if case["id"] in existing_runs:
                    ordered.append(existing_runs[case["id"]])
            results = ordered
            cases = [{"id": r.get("case_id"), "config": r.get("config", {})} for r in results]

    payload = {
        "generated_at_epoch_s": int(time.time()),
        "workload": "testcase/common/scripts + testcase/lfs2n_regression/lfs2n_regression_basic/scripts",
        "matrix_size": len(cases),
        "knob_ranges": KNOB_RANGES,
        "default_knobs": DEFAULT_KNOBS,
        "runs": results,
    }

    json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    csv_path = OUT_DIR / "pc_lfs2n_matrix_results.csv"
    rows = [to_summary_row(r) for r in results]
    fieldnames = list(rows[0].keys()) if rows else []
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    failures = [r for r in results if r.get("error") or r.get("timeout_occurrence") or (r.get("run") and r["run"]["returncode"] != 0)]
    print(json.dumps({
        "matrix_size": len(cases),
        "json": str(json_path.relative_to(ROOT)).replace("\\", "/"),
        "csv": str(csv_path.relative_to(ROOT)).replace("\\", "/"),
        "failed_or_timeout_runs": len(failures),
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
