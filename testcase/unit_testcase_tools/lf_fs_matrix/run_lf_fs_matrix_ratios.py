#!/usr/bin/env python3
import argparse
import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
BSP_PC = ROOT / "bsp" / "pc"
EXE_PATH = BSP_PC / "build" / "out" / "luatos-lua.exe"
COMMON_SCRIPTS = ROOT / "testcase" / "common" / "scripts"
MATRIX_SCRIPTS = ROOT / "testcase" / "unit_testcase_tools" / "lf_fs_matrix" / "scripts"
OUTPUT_DIR = ROOT / "testcase" / "unit_testcase_tools" / "lf_fs_matrix" / "outputs"
RATIOS = (0.01, 0.05, 0.10)


def run_cmd(cmd, cwd, env, timeout):
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
        return completed.returncode, stdout, stderr
    except subprocess.TimeoutExpired as exc:
        stdout = (exc.stdout or b"").decode("utf-8", errors="ignore")
        stderr = (exc.stderr or b"").decode("utf-8", errors="ignore")
        return -1, stdout, (stderr + f"\nTIMEOUT after {timeout}s")


def ensure_output_dir():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


def run_ratio(ratio, timeout):
    env = os.environ.copy()
    env["LUAT_PC_NAND_BAD_BLOCK_RATIO"] = f"{ratio:.2f}"
    env.setdefault("LUAT_PC_NAND_SEED", "0x13572468")
    env.setdefault("LUAT_PC_NAND_PROFILE", "fast")
    rc, stdout, stderr = run_cmd(
        [str(EXE_PATH), str(COMMON_SCRIPTS), str(MATRIX_SCRIPTS)],
        cwd=BSP_PC,
        env=env,
        timeout=timeout,
    )
    log_path = OUTPUT_DIR / f"lf_fs_matrix_ratio_{ratio:.2f}.log"
    log_path.write_text(stdout + ("\n" + stderr if stderr else ""), encoding="utf-8", errors="ignore")
    return rc, log_path


def main():
    parser = argparse.ArgumentParser(description="Run lf_fs_matrix with NAND bad-block ratios 1%/5%/10%")
    parser.add_argument("--timeout", type=int, default=240, help="per-case timeout in seconds")
    args = parser.parse_args()

    ensure_output_dir()
    failures = []
    for ratio in RATIOS:
        rc, log_path = run_ratio(ratio, args.timeout)
        state = "PASS" if rc == 0 else "FAIL"
        print(f"ratio={ratio:.2f} result={state} log={log_path.relative_to(ROOT)}")
        if rc != 0:
            failures.append(ratio)

    if failures:
        print("failed ratios:", ", ".join(f"{r:.2f}" for r in failures))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
