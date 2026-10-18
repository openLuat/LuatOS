# AI-MANAGED: true
"""显式运行主机C回归；不接网络或串口，不加载到固件。"""
import argparse
import hashlib
import os
from pathlib import Path
import re
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
DRIVER = "components/airlink/src/driver/luat_airlink_drv_uart.c"
UART = "luat/modules/luat_lib_uart.c"


def rx_function(source):
    start = source.index("static int l_uart_rx(lua_State *L)")
    opening = source.index("{", start)
    depth = 0
    for i in range(opening, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[start:i + 1]
    raise ValueError("l_uart_rx function boundary not found")


def run(args):
    build = args.output.resolve()
    build.mkdir(parents=True, exist_ok=False)
    compiler = os.environ.get("CC", "clang")
    base_driver = subprocess.run(
        ["git", "-C", str(ROOT), "show", f"{args.baseline}:{DRIVER}"],
        check=True, capture_output=True, text=True).stdout
    base_uart = subprocess.run(
        ["git", "-C", str(ROOT), "show", f"{args.baseline}:{UART}"],
        check=True, capture_output=True, text=True).stdout
    current_driver = (ROOT / DRIVER).read_text()
    current_uart = (ROOT / UART).read_text()
    variants = [
        ("driver_original", "driver_test.c", base_driver, [], "driver_original", True),
        ("lua_rx_original", "lua_rx_test.c", rx_function(base_uart), ["-DTEST_BASELINE"], "lua_rx_fixed", True),
        ("driver_fixed", "driver_test.c", current_driver, ["-DTEST_FIXED"], "driver_fixed", False),
        ("lua_rx_fixed", "lua_rx_test.c", rx_function(current_uart), [], "lua_rx_fixed", False),
    ]
    report = ["# UART主机回归实际结果", "", f"基线：{args.baseline}",
              "原版成功退出表示按预期检出缺陷，不能解释为原驱动正确。", "",
              "目标FreeRTOS、固件链接及真机未验证；仅编译真实C及主机平台夹具。", ""]
    failed = False
    for name, fixture, source, defines, binary_name, baseline in variants:
        source = re.sub(r'^#include[^\n]*', '', source, flags=re.MULTILINE)
        fixture_text = (HERE / fixture).read_text()
        assert fixture_text.count("/* SOURCE_UNDER_TEST */") == 1
        combined = fixture_text.replace("/* SOURCE_UNDER_TEST */", source)
        binary = build / binary_name
        command = [compiler, "-std=c11", "-Wall", "-Wextra", "-pthread",
                   "-fsanitize=address,undefined", *defines, "-x", "c", "-", "-o", str(binary)]
        if not baseline:
            command.insert(1, "-Werror")
        report += [f"## {name}", "", f"实际源SHA256：{hashlib.sha256(source.encode()).hexdigest()}"]
        try:
            for stage in ("compile", "run"):
                started = time.monotonic()
                result = subprocess.run(
                    command if stage == "compile" else [str(binary)],
                    input=combined.encode() if stage == "compile" else None,
                    capture_output=True, timeout=30)
                (build / f"{name}_{stage}.stdout").write_bytes(result.stdout)
                (build / f"{name}_{stage}.stderr").write_bytes(result.stderr)
                report.append(f"- {stage}: actual_exit={result.returncode}, seconds={time.monotonic() - started:.6f}")
                print(name, stage, "actual_exit=" + str(result.returncode), flush=True)
                if stage == "run":
                    print(result.stdout.decode(errors="replace"), end="", flush=True)
                if result.returncode != 0:
                    failed = True
                    break
                if stage == "run" and baseline:
                    if b"DEFECT_REPRODUCED" not in result.stdout:
                        raise AssertionError("baseline did not reproduce expected defect")
        except subprocess.TimeoutExpired:
            report.append("- TIMEOUT：真实退出未知，不伪造0；不运行后续阶段。")
            failed = True
        finally:
            if binary.exists():
                binary.unlink()
            report.append("")
            (build / "RESULT.md").write_text("\n".join(report) + "\n")
        if failed:
            break
    report.append("总结果：" + ("FAIL，原件保留。" if failed else "PASS，四个实际编译/运行对完成。"))
    (build / "RESULT.md").write_text("\n".join(report) + "\n")
    return 1 if failed else 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--output", type=Path, required=True)
    raise SystemExit(run(parser.parse_args()))
