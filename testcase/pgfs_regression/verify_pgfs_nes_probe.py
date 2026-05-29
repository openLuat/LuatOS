#!/usr/bin/env python3
import argparse
import math
import re
import subprocess
import sys
from pathlib import Path


RE_PASS = re.compile(r"### PGFS_NES_UNZIP_PASS ###")
RE_FAIL = re.compile(r"### PGFS_NES_UNZIP_FAIL ###")
RE_PREFIX_SECONDS = re.compile(r"\[(\d+\.\d+)\]")
RE_METRIC = re.compile(r"### PGFS_NES_UNZIP_METRIC ###\s+unzip_ms=(\d+)\s+reset_ms=(\d+)\s+entries=(\d+)")
RE_PGFS_CLOSE_TOTAL = re.compile(r"D/pgfs perf close .*?\btotal=(\d+)\b")

DEFAULT_MAX_ELAPSED_S = 90.0
DEFAULT_MAX_CLOSE_TOTAL_MS = 20000
DEFAULT_MAX_CLOSE_P95_MS = 15000
DEFAULT_MIN_CLOSE_COUNT = 8


def p95(values):
    if not values:
        return 0
    ordered = sorted(values)
    idx = max(0, math.ceil(len(ordered) * 0.95) - 1)
    return ordered[idx]


def parse_log_text(text: str):
    lines = text.splitlines()
    pass_seen = any(RE_PASS.search(line) for line in lines)
    fail_seen = any(RE_FAIL.search(line) for line in lines)

    metric = None
    for line in lines:
        m = RE_METRIC.search(line)
        if m:
            metric = {
                "unzip_ms": int(m.group(1)),
                "reset_ms": int(m.group(2)),
                "entries": int(m.group(3)),
            }

    elapsed_s = 0.0
    for line in lines:
        if RE_PASS.search(line):
            m = RE_PREFIX_SECONDS.search(line)
            if m:
                elapsed_s = float(m.group(1))
            break

    close_totals_ms = []
    for line in lines:
        m = RE_PGFS_CLOSE_TOTAL.search(line)
        if m:
            close_totals_ms.append(int(m.group(1)))

    return {
        "pass_seen": pass_seen,
        "fail_seen": fail_seen,
        "elapsed_s": elapsed_s,
        "metric": metric,
        "close_totals_ms": close_totals_ms,
    }


def run_probe(simulator: Path, common_scripts: Path, probe_scripts: Path):
    cmd = [str(simulator), str(common_scripts), str(probe_scripts)]
    proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    text = (proc.stdout or "") + (proc.stderr or "")
    return proc.returncode, text


def main():
    parser = argparse.ArgumentParser(description="Run/verify PGFS NES unzip probe with coarse regression bounds.")
    parser.add_argument("--log", type=Path, help="Parse an existing probe log instead of running simulator")
    parser.add_argument("--simulator", type=Path, default=Path("bsp/pc/build/out/luatos-lua.exe"))
    parser.add_argument("--common", type=Path, default=Path("testcase/common/scripts"))
    parser.add_argument("--probe", type=Path, default=Path("testcase/unit_testcase_tools/pgfs_nes_unzip_probe/scripts"))
    parser.add_argument("--max-elapsed-s", type=float, default=DEFAULT_MAX_ELAPSED_S)
    parser.add_argument("--max-close-total-ms", type=int, default=DEFAULT_MAX_CLOSE_TOTAL_MS)
    parser.add_argument("--max-close-p95-ms", type=int, default=DEFAULT_MAX_CLOSE_P95_MS)
    parser.add_argument("--min-close-count", type=int, default=DEFAULT_MIN_CLOSE_COUNT)
    args = parser.parse_args()

    if args.log:
        text = args.log.read_text(encoding="utf-8", errors="replace")
        rc = 0
    else:
        rc, text = run_probe(args.simulator, args.common, args.probe)

    parsed = parse_log_text(text)

    if rc != 0:
        print(f"[pgfs-probe] FAIL: simulator exit code={rc}")
        print(text)
        return 1
    if parsed["fail_seen"]:
        print("[pgfs-probe] FAIL: found FAIL token")
        return 1
    if not parsed["pass_seen"]:
        print("[pgfs-probe] FAIL: PASS token missing")
        return 1
    if parsed["elapsed_s"] <= 0 or parsed["elapsed_s"] > args.max_elapsed_s:
        print(f"[pgfs-probe] FAIL: elapsed_s={parsed['elapsed_s']:.3f} exceeds {args.max_elapsed_s}")
        return 1

    metric = parsed["metric"]
    if metric is None:
        print("[pgfs-probe] FAIL: metric token missing")
        return 1

    close_totals = parsed["close_totals_ms"]
    if len(close_totals) < args.min_close_count:
        print(f"[pgfs-probe] FAIL: close hotspot count={len(close_totals)} < {args.min_close_count}")
        return 1

    close_max = max(close_totals)
    close_p95 = p95(close_totals)
    if close_max > args.max_close_total_ms:
        print(f"[pgfs-probe] FAIL: close_max_ms={close_max} exceeds {args.max_close_total_ms}")
        return 1
    if close_p95 > args.max_close_p95_ms:
        print(f"[pgfs-probe] FAIL: close_p95_ms={close_p95} exceeds {args.max_close_p95_ms}")
        return 1

    print(
        "[pgfs-probe] PASS "
        f"elapsed_s={parsed['elapsed_s']:.3f} "
        f"unzip_ms={metric['unzip_ms']} reset_ms={metric['reset_ms']} entries={metric['entries']} "
        f"hotspot_count={len(close_totals)} hotspot_max_ms={close_max} hotspot_p95_ms={close_p95}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
