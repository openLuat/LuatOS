#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""固定1.9.0真实C库/Lua主机测试；不安装依赖、不连接业务router。"""
import json, datetime, tempfile
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
    # 接受本地归档/工作树；必须是与绑定同批的补丁SDK，不读取Git元数据。
    version = (root / "version.txt").read_text(encoding="utf-8").strip()
    if version != "1.9.0": raise RuntimeError("zenoh-pico must be 1.9.0")
    for name in ["include/zenoh-pico/utils/auth.h", "src/utils/auth.c", "src/utils/auth_sha3.c"]:
        if not (root/name).is_file(): raise RuntimeError("matching patched SDK missing " + name)
    if "#define ZP_LUATOS_PATCH_ABI 20261116" not in (root/"include/zenoh-pico/utils/auth.h").read_text():
        raise RuntimeError("matching patched SDK ABI required")
    files = sorted(root.glob("src/**/*.c"))
    files = [f for f in files if any(f.relative_to(root).as_posix().startswith("src/" + a + "/") for a in AREAS)]
    print("PUBLIC", hashlib.sha256("".join(f.name + ":" + hashlib.sha256(f.read_bytes()).hexdigest() for f in files).encode()).hexdigest(), flush=True)
    return files

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
    parser.add_argument("--zenoh-root", type=Path, help="外部 zenoh-pico 1.9.0 工作树; 默认用库内 vendored 源码")
    parser.add_argument("--build-dir", type=Path)
    parser.add_argument("--cc", default="clang")
    parser.add_argument("--lua-pkg", default="lua")
    parser.add_argument("--lua-root", type=Path, help="existing Lua prefix, without pkg-config")
    parser.add_argument("--router", type=Path)
    parser.add_argument("--run-dir", type=Path, help="new evidence directory; never overwrites")
    parser.add_argument("--sanitize", action="store_true")
    parser.add_argument("--tx-copy-baseline", action="store_true", help="test-only original second-copy path")
    suites = parser.add_mutually_exclusive_group()
    suites.add_argument("--perf-tests", action="store_true")
    suites.add_argument("--final-tests", action="store_true")
    suites.add_argument("--open-race-tests", action="store_true", help="real SDK open success/failure racing close")
    suites.add_argument("--payload-tests", action="store_true", help="256KiB real bidirectional payload and memory budget tests")
    suites.add_argument("--get-tests", action="store_true", help="run real bidirectional Get lifecycle tests instead of legacy Pub/Sub suite")
    suites.add_argument("--race-tests", choices=("dequeue", "enqueue", "both"), help="deterministic real worker close/admission interleavings")
    parser.add_argument("--skip-build", action="store_true", help="run existing binaries after test-only edits; hashes are printed")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[3]
    here = Path(__file__).resolve().parent
    component = repo / "components/zenoh_pico"
    output = args.build_dir or repo.parent / "build"
    output.mkdir(parents=True, exist_ok=True)
    # 默认用随库入库的 1.9.0 源码(components/zenoh_pico/zenoh-pico), 可用 --zenoh-root 指向外部工作树对照
    pico = (args.zenoh_root or (component / "zenoh-pico")).resolve()
    sources = source_files(pico)
    print("PIN", PIN, "host", platform.platform(), flush=True)
    inputs = sorted(set(p for root in [component, pico, here, repo / "luat/include", repo / "components/network/adapter", repo / "components/common"]
                        for p in root.rglob("*") if p.is_file() and p.suffix in [".c", ".h", ".lua", ".py"]))
    if args.lua_root: inputs += sorted(p for p in args.lua_root.rglob("*") if p.is_file())
    frozen = {str(p.resolve()):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    compiler_version = subprocess.check_output([args.cc,"--version"],text=True).strip()
    manifest = output / "build_inputs.json"
    if args.skip_build:
        old = json.loads(manifest.read_text())
        if old.get("sanitize") != args.sanitize or old.get("compiler") != args.cc or old.get("compiler_version") != compiler_version: raise RuntimeError("build configuration mismatch")
        if old.get("tx_copy_baseline",False) != args.tx_copy_baseline: raise RuntimeError("baseline build flag mismatch")
        if old["inputs"] != frozen: raise RuntimeError("source/header/Lua input drift; rebuild required")
        for name, digest in old["binaries"].items():
            if hashlib.sha256((output/name).read_bytes()).hexdigest() != digest: raise RuntimeError("binary drift")
    if not args.skip_build:
        includes = ["-I" + str(p) for p in (component / "include", pico / "include", repo / "luat/include", repo / "components/common", repo / "components/network/adapter")]
        # 真实对端(peer)走官方 unix 后端, 源码随 bsp/pc/zenoh_pico/unix_backend 提供, 不进组件目录
        peer_includes = includes + ["-I" + str(here / "unix_backend/include")]
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
        compiler = [args.cc, "-std=c11", "-O1", "-g", *defs, *host_defs, *peer_includes]
        if args.sanitize:
            compiler += ["-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
        host_files = [component / n for n in ("src/luat_zenoh_pico.c", "src/luat_lib_zenoh_pico.c", "src/zenoh_luatos_system.c", "src/zenoh_luatos_tcp.c")] + [here / n for n in ("host_main.c", "host_port.c")]
        generic_defs = ["-DZENOH_GENERIC", "-DLUAT_ZENOH_TEST_BARRIERS"]
        if args.tx_copy_baseline: generic_defs.append("-DLUAT_ZENOH_TEST_TX_COPY_BASELINE")
        run([args.cc, "-std=c11", "-Wall", "-Wextra", "-Werror", "-fsyntax-only", *defs, *generic_defs, *includes, *[a for a in lua_flags if a.startswith("-I")], *host_files])
        common = [*sources, here / "unix_backend/system.c", here / "unix_backend/network.c"]
        generic_compiler = [a for a in compiler if a not in host_defs] + generic_defs
        run([*generic_compiler, *sources, *host_files, *lua_flags, "-pthread", "-o", output / "zenoh_host_test"])
        run([*compiler, *common, here / "peer.c", "-pthread", "-o", output / "zenoh_peer"])
        # 分片R位必须保持枚举语义，覆盖可靠/尽力两种首、续、末片。
        run([*compiler, *common, here / "host_fragment_test.c", "-pthread", "-o", output / "host_fragment_test"])
        run([output / "host_fragment_test"])
        run([*compiler, *common, here / "host_response_final.c", "-pthread", "-o", output / "host_response_final"])
        run([output / "host_response_final"])
        # 真实socketpair合同覆盖事件预算、4096B短写、期限与短读字节守恒。
        for name in ("host_transport_test", "host_rx_test"):
            binary = output / name
            run([*generic_compiler, "-Wall", "-Wextra", "-Werror", here / (name + ".c"),
                 component / "src/zenoh_luatos_tcp.c", "-pthread", "-o", binary])
            run([binary])
        for name in ("host_sdk_memory_test", "host_auth_test"):
            files = [p for p in host_files if p.name != "host_main.c"] + [here / (name + ".c")]
            run([*generic_compiler, *sources, *files, *lua_flags, "-pthread", "-o", output / name])
        for case in ("make", "move", "expand", "expand_bytes", "copy", "bytes", "internal_bytes", "owned_bytes", "reply_closed"):
            run([output / "host_sdk_memory_test", case])
        run([output / "host_auth_test"])
        import hmac
        unit = output / "host_auth_test"
        for n in (0,1,3,135,136,137,271,272,273,1024):
            data = bytes(i % 251 for i in range(n))
            actual = subprocess.check_output([str(unit), "hash", data.hex()], text=True).strip()
            if actual != hashlib.sha3_256(data).hexdigest(): raise RuntimeError("SHA3 oracle mismatch")
        for nonce in (0,127,128,2**56-1,2**56,2**63,2**64-1):
            for n in (1,127,128):
                password = "x" * n
                actual = subprocess.check_output([str(unit), "hmac", format(nonce,"x"), password],text=True).strip()
                if actual != hmac.new(nonce.to_bytes(8,"little"), password.encode(), hashlib.sha3_256).hexdigest():
                    raise RuntimeError("HMAC oracle mismatch")
        print("AUTH_ORACLE_PASS vectors=31", flush=True)
        names = ["host_response_final", "zenoh_host_test", "zenoh_peer", "host_auth_test", "host_sdk_memory_test", "host_fragment_test", "host_rx_test", "host_transport_test"]
        if any(hashlib.sha256(Path(p).read_bytes()).hexdigest()!=digest for p,digest in frozen.items()): raise RuntimeError("inputs changed during build")
        manifest.write_text(json.dumps({"inputs":frozen,"compiler":args.cc,"compiler_version":compiler_version,"flags":compiler,"sanitize":args.sanitize,"tx_copy_baseline":args.tx_copy_baseline,
            "binaries":{n:hashlib.sha256((output/n).read_bytes()).hexdigest() for n in names}},indent=2)+"\n")
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
    # 所有子进程输出直接写文件，避免长回归堵在未读取的PIPE。
    evidence = args.run_dir or output / ("run_" + datetime.datetime.now().strftime("%Y%m%d%H%M%S%f"))
    evidence.mkdir(parents=True,exist_ok=False)
    result = {"router_version":version,"build_manifest_sha256":hashlib.sha256(manifest.read_bytes()).hexdigest(),
              "started":datetime.datetime.now().astimezone().isoformat(),"exits":{},"cleanup":[]}
    endpoint, prefix = "tcp/127.0.0.1:17447", f"test/zenohpico/pr-{os.getpid()}"
    procs = []; streams = []
    def spawn(name, argv, env=None):
        stream=(evidence/(name+".log")).open("xb"); streams.append(stream)
        proc=subprocess.Popen(list(map(str,argv)),stdout=stream,stderr=subprocess.STDOUT,env=env,start_new_session=True)
        procs.append((name,proc)); return proc
    try:
        with socket.socket() as probe:
            probe.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1);probe.bind(("127.0.0.1",17447))
        router=spawn("router",[args.router,"--listen",endpoint,"--no-multicast-scouting","--adminspace-permissions","none",
            "--cfg","scouting/gossip/enabled:false","--cfg","plugins:{}"])
        for _ in range(80):
            if router.poll() is not None: raise RuntimeError("router startup failed")
            try:
                with socket.create_connection(("127.0.0.1",17447),timeout=.1): break
            except OSError: time.sleep(.05)
        else: raise TimeoutError("router listen")
        peer=spawn("peer",[output/"zenoh_peer",endpoint,prefix]+(["--payload"] if args.payload_tests else ["--get"] if args.get_tests or args.final_tests else []),dict(os.environ,ZENOH_FINAL_FAULT_TEST="1") if args.final_tests else dict(os.environ,ZENOH_PERF_TEST="1") if args.perf_tests else None)
        until=time.monotonic()+10
        while "READY" not in (evidence/"peer.log").read_text():
            if peer.poll() is not None or time.monotonic()>until: raise RuntimeError("peer did not open")
            time.sleep(.03)
        test_file = here / ("host_final_test.lua" if args.final_tests else "host_perf_test.lua" if args.perf_tests else "host_payload_test.lua" if args.payload_tests else "host_open_race.lua" if args.open_race_tests else "host_get_race.lua" if args.race_tests else "host_get_test.lua" if args.get_tests else "host_test.lua")
        environment=os.environ.copy()
        if args.race_tests: environment["ZENOH_TEST_RACE_CASE"]=args.race_tests
        host=spawn("host",[output/"zenoh_host_test",test_file,endpoint,prefix],environment)
        result["exits"]["host"]=host.wait(timeout=300 if args.perf_tests or args.payload_tests else 150 if args.get_tests else 65)
        if host.returncode: raise RuntimeError("host test failed")
        result["exits"]["peer"]=peer.wait(timeout=8)
        if peer.returncode: raise RuntimeError("peer did not confirm stop")
        result["passed"]=True
    except Exception as exc:
        result["passed"]=False;result["error"]=str(exc)
    finally:
        for name,proc in reversed(procs):
            running=proc.poll() is None;forced=False
            if running:
                proc.terminate()
                try:proc.wait(timeout=5)
                except subprocess.TimeoutExpired:forced=True;proc.kill();proc.wait()
            result["cleanup"].append({"process":name,"exit":proc.returncode,"owner_terminated":running,"forced":forced})
        for stream in streams:stream.close()
        result["sanitizer_error"]=any("AddressSanitizer" in p.read_text() or "runtime error:" in p.read_text() for p in evidence.glob("*.log"))
        try:
            with socket.socket() as probe:
                probe.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1);probe.bind(("127.0.0.1",17447))
            result["listen_released"]=True
        except OSError:result["listen_released"]=False
        result["passed"]=result.get("passed",False) and not result["sanitizer_error"] and result["listen_released"] and not any(x["forced"] for x in result["cleanup"])
        result["ended"]=datetime.datetime.now().astimezone().isoformat()
        (evidence/"actual.json").write_text(json.dumps(result,indent=2)+"\n")
        print("EVIDENCE",evidence,flush=True)
    if not result["passed"]: raise RuntimeError(result.get("error","invalid terminal evidence"))
    print("INTEROP_PASS",flush=True)

if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print("FAIL", ("command exited " + str(error.returncode)) if isinstance(error, subprocess.CalledProcessError) else str(error), file=sys.stderr)
        sys.exit(1)
