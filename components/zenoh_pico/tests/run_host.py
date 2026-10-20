#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""固定1.9.0真实C库/Lua主机测试；不安装依赖、不连接业务router。"""
import argparse
import hashlib
import os
from pathlib import Path
import platform
import selectors
import shlex
import socket
import subprocess
import sys
import time

PIN = "e83d39b4415f6897e8d6c3b3b651ca88a05f4a17"
AREAS = ("api", "collections", "link", "net", "protocol", "runtime", "session", "transport", "utils", "system/common")

def run(args):
    print("COMMAND", str(args[0]), "C_sources=" + str(sum(str(a).endswith(".c") for a in args)), " ".join(str(a) for a in args if not str(a).endswith(".c") and str(a) != str(args[0])), flush=True)
    subprocess.run(list(map(str, args)), check=True)

def source_files(root):
    if subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip() != PIN:
        raise RuntimeError("zenoh-pico must be the pinned 1.9.0 commit")
    subprocess.run(["git", "-C", str(root), "diff", "--exit-code"], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["git", "-C", str(root), "diff", "--cached", "--exit-code"], check=True, stdout=subprocess.DEVNULL)
    names = subprocess.check_output(["git", "-C", str(root), "ls-tree", "-r", "--name-only", "HEAD"], text=True).splitlines()
    return [root / n for n in names if n.endswith(".c") and any(n.startswith("src/" + a + "/") for a in AREAS)]

def ready(proc, token, seconds=8):
    with selectors.DefaultSelector() as sel:
        sel.register(proc.stdout, selectors.EVENT_READ)
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if sel.select(0.1):
                line = proc.stdout.readline()
                print(line, end="", flush=True)
                if token in line:
                    return
            if proc.poll() is not None:
                raise RuntimeError(f"child exited {proc.returncode} before {token}")
        raise TimeoutError(token)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zenoh-root", required=True, type=Path)
    parser.add_argument("--build-dir", type=Path)
    parser.add_argument("--cc", default="clang")
    parser.add_argument("--lua-pkg", default="lua")
    parser.add_argument("--lua-root", type=Path, help="existing Lua prefix, without pkg-config")
    parser.add_argument("--router", type=Path)
    parser.add_argument("--sanitize", action="store_true")
    parser.add_argument("--get-tests", action="store_true", help="run real bidirectional Get lifecycle tests instead of legacy Pub/Sub suite")
    parser.add_argument("--race-tests", choices=("dequeue", "enqueue", "both"), help="deterministic real worker close/admission interleavings")
    parser.add_argument("--skip-build", action="store_true", help="run existing binaries after test-only edits; hashes are printed")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[3]
    component = repo / "components/zenoh_pico"
    output = args.build_dir or repo.parent / "build"
    output.mkdir(parents=True, exist_ok=True)
    pico = args.zenoh_root.resolve()
    sources = source_files(pico)
    print("PIN", PIN, "host", platform.platform(), flush=True)
    if not args.skip_build:
        includes = ["-I" + str(p) for p in (component / "include", pico / "include", repo / "luat/include", repo / "components/common", repo / "components/network/adapter")]
        defs = ["-DZENOH_C_STANDARD=11", "-DZENOH_COMPILER_CLANG"]
        # 独立检查真实设备平台C接口；非ARM ABI/固件链接证明。
        run([args.cc, "-std=c11", "-Wall", "-Wextra", "-Werror", "-fsyntax-only", "-DZENOH_GENERIC", *defs, *includes,
             component / "src/zenoh_luatos_system.c", component / "src/zenoh_luatos_tcp.c"])
        if args.lua_root:
            lua_root = args.lua_root.resolve()
            lua_include = lua_root / "include/lua"
            if not (lua_include / "lua.h").is_file():
                lua_include = lua_root / "include"
            if not (lua_include / "lua.h").is_file():
                raise RuntimeError("Lua headers missing")
            lua_flags = ["-I" + str(lua_include), "-L" + str(lua_root / "lib"), "-llua"]
            print("LUA_ROOT", lua_root, flush=True)
        else:
            lua_flags = shlex.split(subprocess.check_output(["pkg-config", "--cflags", "--libs", args.lua_pkg], text=True))
            print("LUA_PKG", subprocess.check_output(["pkg-config", "--modversion", args.lua_pkg], text=True).strip(), flush=True)
        host_defs = ["-DLUAT_ZENOH_HOST_TEST", "-DZENOH_MACOS" if sys.platform == "darwin" else "-DZENOH_LINUX"]
        compiler = [args.cc, "-std=c11", "-O1", "-g", *defs, *host_defs, *includes]
        if args.sanitize:
            compiler += ["-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
        host_files = [component / n for n in ("src/luat_zenoh_pico.c", "src/luat_lib_zenoh_pico.c", "src/zenoh_luatos_system.c", "src/zenoh_luatos_tcp.c", "tests/host_main.c", "tests/host_port.c")]
        generic_defs = ["-DZENOH_GENERIC", "-DLUAT_ZENOH_TEST_BARRIERS"]
        run([args.cc, "-std=c11", "-Wall", "-Wextra", "-Werror", "-fsyntax-only", *defs, *generic_defs, *includes, *[a for a in lua_flags if a.startswith("-I")], *host_files])
        common = [*sources, pico / "src/system/unix/system.c", pico / "src/system/unix/network.c"]
        generic_compiler = [a for a in compiler if a not in host_defs] + generic_defs
        run([*generic_compiler, *sources, *host_files, *lua_flags, "-pthread", "-o", output / "zenoh_host_test"])
        run([*compiler, *common, component / "tests/peer.c", "-pthread", "-o", output / "zenoh_peer"])
    else:
        for name in ("zenoh_host_test", "zenoh_peer"):
            binary = output / name
            print("BUILD_SKIPPED", binary, "sha256=" + hashlib.sha256(binary.read_bytes()).hexdigest(), flush=True)
    if not args.router:
        print("BUILD_PASS (interop not run)"); return
    version = subprocess.check_output([str(args.router), "--version"], text=True).strip()
    if not version.startswith("zenohd v1.9.0 "):
        raise RuntimeError("router must be zenohd 1.9.0")
    print("ROUTER", version, flush=True)
    # 只测本机专用端口；已有占用则停止，不复用/关闭他人进程。
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 17447))
    endpoint, prefix = "tcp/127.0.0.1:17447", f"test/zenohpico/pr-{os.getpid()}"
    router = peer = None
    try:
        router = subprocess.Popen([str(args.router), "--listen", endpoint, "--no-multicast-scouting", "--adminspace-permissions", "none",
            "--cfg", "scouting/gossip/enabled:false", "--cfg", "plugins:{}"], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        for _ in range(80):
            if router.poll() is not None:
                raise RuntimeError("router startup failed: " + router.stderr.read())
            try:
                with socket.create_connection(("127.0.0.1", 17447), timeout=0.1):
                    break
            except OSError:
                time.sleep(0.05)
        else:
            raise TimeoutError("router listen")
        peer = subprocess.Popen([str(output / "zenoh_peer"), endpoint, prefix] + (["--get"] if args.get_tests else []), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        ready(peer, "READY")
        test_file = "tests/host_get_race.lua" if args.race_tests else "tests/host_get_test.lua" if args.get_tests else "tests/host_test.lua"
        environment = os.environ.copy()
        if args.race_tests:
            environment["ZENOH_TEST_RACE_CASE"] = args.race_tests
        result = subprocess.run([str(output / "zenoh_host_test"), str(component / test_file), endpoint, prefix],
                                timeout=100 if args.get_tests else 65, env=environment)
        print("HOST_EXIT", result.returncode, flush=True)
        if result.returncode:
            peer.terminate()
            text, _ = peer.communicate(timeout=5)
            print(text, end="", flush=True); print("PEER_FAILURE_CLEANUP_EXIT", peer.returncode, flush=True)
            raise RuntimeError("host test failed")
        text, _ = peer.communicate(timeout=8)
        print(text, end="", flush=True); print("PEER_EXIT", peer.returncode)
        if peer.returncode:
            raise RuntimeError("peer did not confirm stop")
        print("INTEROP_PASS")
    finally:
        for proc in (peer, router):
            if proc and proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill(); proc.wait()

if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print("FAIL", ("command exited " + str(error.returncode)) if isinstance(error, subprocess.CalledProcessError) else str(error), file=sys.stderr)
        sys.exit(1)
