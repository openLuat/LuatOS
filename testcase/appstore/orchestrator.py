#!/usr/bin/env python3
"""
应用商店全生命周期编排器
1. 从 API 拉取全部应用列表
2. 对每个应用: 写配置 → 启动PC模拟器 → 读取结果
3. 汇总报告 (包括崩溃检测)
"""

import json
import os
import subprocess
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

# Windows GBK 终端 UTF-8 兼容
if sys.platform == 'win32':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
        sys.stderr.reconfigure(encoding='utf-8')
    except Exception:
        pass

# ==================== 配置 ====================

API_URL = "https://api.luatos.com/iot/appstore/list"
SIMULATOR = "D:/github/LuatOS/bsp/pc/build/out/luatos-lua.exe"
SCRIPT_DIRS = [
    "testcase/common/scripts/",
    "testcase/appstore/appstore_basic/scripts/",
]
WORK_DIR = Path("D:/github/LuatOS")
TESTRESULT_DIR = WORK_DIR / "testresult"

SINGLE_APP_FILE = TESTRESULT_DIR / "single_app.json"
RESULT_FILE = TESTRESULT_DIR / "result.json"

TIMEOUT_PER_APP = 300  # 5 分钟超时
PAGE_SIZE = 50  # 每页拉取数量

# ==================== 辅助函数 ====================

def fetch_all_apps():
    """分页拉取全部应用列表"""
    all_apps = []
    page = 1

    while True:
        body = json.dumps({
            "category": "全部",
            "sort": "recommend",
            "page": page,
            "size": PAGE_SIZE,
            "query": ""
        }).encode("utf-8")

        req = urllib.request.Request(
            API_URL,
            data=body,
            headers={"Content-Type": "application/json"}
        )

        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except Exception as e:
            print(f"[ERROR] 第{page}页请求失败: {e}")
            break

        if data.get("code") != 0:
            print(f"[ERROR] 第{page}页 API 错误: code={data.get('code')}")
            break

        value = data.get("value", {})
        records = value.get("records", [])
        total = int(value.get("total", 0))
        pages = int(value.get("pages", 1))

        for r in records:
            aid = r.get("app_name") or r.get("appname") or ""
            url = r.get("url") or ""
            name = r.get("title") or r.get("name") or aid
            if not url:
                continue
            all_apps.append({"aid": aid, "url": url, "name": name})

        print(f"  第{page}/{pages}页: {len(records)}个应用, 累计{len(all_apps)}/{total}")

        if page >= pages:
            break
        page += 1
        time.sleep(1)  # 避免请求过快

    return all_apps


def test_one_app(app, idx, total):
    """测试单个应用: 写配置 → 运行模拟器 → 读结果"""
    aid = app["aid"]
    name = app["name"]

    print(f"[{idx}/{total}] {name} ({aid}) ...", end=" ", flush=True)

    # 清理旧结果
    if RESULT_FILE.exists():
        RESULT_FILE.unlink()

    # 写配置
    TESTRESULT_DIR.mkdir(parents=True, exist_ok=True)
    with open(SINGLE_APP_FILE, "w", encoding="utf-8") as f:
        json.dump(app, f, ensure_ascii=False)

    # 清理上次测试残留的 /app_store/ 目录 (避免损坏的 meta.json 影响后续测试)
    app_store = WORK_DIR / "app_store"
    if app_store.exists():
        import shutil
        try:
            shutil.rmtree(str(app_store), ignore_errors=True)
        except Exception:
            pass

    # 清理上次测试残留的 /app_store/ 目录 (避免损坏的 meta.json 影响后续测试)
    app_store = WORK_DIR / "app_store"
    if app_store.exists():
        import shutil
        try:
            shutil.rmtree(str(app_store), ignore_errors=True)
        except Exception:
            pass

    # 运行模拟器
    cmd = [SIMULATOR, "--dep_strip=0"] + [str(WORK_DIR / d) for d in SCRIPT_DIRS]

    try:
        proc = subprocess.run(
            cmd,
            cwd=str(WORK_DIR),
            capture_output=True,
            timeout=TIMEOUT_PER_APP,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except subprocess.TimeoutExpired:
        print(f"[TIMEOUT] ({TIMEOUT_PER_APP}s)")
        return {
            "aid": aid, "name": name,
            "passed": False, "crashed": False,
            "stages": {}, "error": f"超时 ({TIMEOUT_PER_APP}s)",
            "exit_code": None,
        }

    exit_code = proc.returncode

    # 检查结果文件
    if RESULT_FILE.exists():
        try:
            with open(RESULT_FILE, "r", encoding="utf-8") as f:
                result = json.load(f)
        except (json.JSONDecodeError, IOError):
            result = {"passed": False, "error": "结果文件解析失败"}

        passed = result.get("passed", False)
        stages = result.get("stages", {})
        error = result.get("error")

        if passed:
            print(f"[PASS] PASS")
        else:
            # 找出失败的阶段
            failed_stages = [s for s, v in stages.items() if not v.get("ok")]
            stage_str = ",".join(failed_stages) if failed_stages else "?"
            print(f"[FAIL] FAIL [{stage_str}] {error or ''}")

        return {
            "aid": aid, "name": name,
            "passed": passed, "crashed": False,
            "stages": stages, "error": error,
            "exit_code": exit_code,
        }

    # 没有结果文件 → 崩溃
    # 检查 stderr 找 FATAL CRASH
    stderr = proc.stderr or ""
    stdout_tail = (proc.stdout or "")[-2000:]
    combined = stderr + stdout_tail

    # 检测崩溃: 文本标记 或 Windows NT 状态码 (0xC0000005=访问违例等)
    crashed = (
        "FATAL CRASH" in combined
        or "SIGSEGV" in combined
        or "SIGABRT" in combined
        or "SIGILL" in combined
        or "Lua VM exit" in combined
    )
    if not crashed and exit_code != 0:
        # Windows NT status codes: 0xC0000005=ACCESS_VIOLATION, 0xC0000135=DLL_NOT_FOUND, etc.
        # 负数值 (如 -1073741819) = 0xC0000005 的有符号表示
        nt_code = exit_code & 0xFFFFFFFF if exit_code < 0 else exit_code
        if nt_code & 0xC0000000 == 0xC0000000:
            crashed = True

    crash_reason = "未知崩溃"
    if "FATAL CRASH" in combined:
        for line in combined.split("\n"):
            if "FATAL CRASH" in line:
                crash_reason = line.strip()[:200]
                break
    elif "SIGSEGV" in combined:
        crash_reason = "SIGSEGV (段错误)"
    elif "SIGABRT" in combined:
        crash_reason = "SIGABRT (异常终止)"
    elif "SIGILL" in combined:
        crash_reason = "SIGILL (非法指令)"
    elif crashed:
        nt_code = exit_code & 0xFFFFFFFF if exit_code < 0 else exit_code
        crash_reason = f"NT异常 (0x{nt_code:08X})"

    if crashed:
        print(f"[CRASH] CRASH (exit={exit_code}) {crash_reason[:80]}")
    elif exit_code != 0:
        print(f"[WARN] NORESULT (exit={exit_code})")
    else:
        print(f"[WARN] NORESULT (exit=0)")

    return {
        "aid": aid, "name": name,
        "passed": False, "crashed": crashed,
        "stages": {}, "error": crash_reason,
        "exit_code": exit_code,
        "stderr_tail": combined[-500:],
    }


def main():
    print("=" * 60)
    print("应用商店全生命周期编排器")
    print("=" * 60)

    # 解析命令行参数
    filter_file = None
    no_cache = False
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--filter" and i + 1 < len(args):
            filter_file = args[i + 1]
            i += 2
        elif args[i] == "--no-cache":
            no_cache = True
            i += 1
        else:
            i += 1

    # 1. 拉取应用列表 (或从过滤文件加载)
    if filter_file:
        print(f"\n[1/3] 从过滤文件加载过滤列表: {filter_file}")
        with open(filter_file, "r", encoding="utf-8") as f:
            filter_apps = json.load(f)
        filter_aids = set(a["aid"] for a in filter_apps)
        print(f"过滤目标: {len(filter_aids)} 个应用")
        # 从API获取完整信息(含url)
        all_apps = fetch_all_apps()
        apps = [a for a in all_apps if a["aid"] in filter_aids]
        print(f"匹配到 {len(apps)}/{len(filter_aids)} 个应用")
        if len(apps) < len(filter_aids):
            missing = filter_aids - set(a["aid"] for a in apps)
            print(f"警告: {len(missing)} 个应用未在API中找到: {list(missing)[:5]}...")
    else:
        print("\n[1/3] 拉取应用列表...")
        apps = fetch_all_apps()
        print(f"共获取到 {len(apps)} 个应用")

    if not apps:
        # 回退到缓存的应用列表
        list_file = TESTRESULT_DIR / "app_list.json"
        if list_file.exists():
            with open(list_file, "r", encoding="utf-8") as f:
                apps = json.load(f)
            print(f"API失败, 使用缓存列表: {len(apps)} 个应用")
        else:
            print("错误: 未获取到任何应用且无缓存")
            sys.exit(1)

    # 保存应用列表
    list_file = TESTRESULT_DIR / "app_list.json"
    with open(list_file, "w", encoding="utf-8") as f:
        json.dump(apps, f, ensure_ascii=False, indent=2)

    # 2. 加载缓存 (删除 passed_cache.json 可强制重测全部)
    cache_file = TESTRESULT_DIR / "passed_cache.json"
    cache = {}
    if cache_file.exists():
        try:
            with open(cache_file, "r", encoding="utf-8") as f:
                cache = json.load(f)
            print(f"加载缓存: {len(cache)} 个已通过")
        except Exception as e:
            print(f"缓存读取失败, 忽略: {e}")
            cache = {}

    def save_cache():
        with open(cache_file, "w", encoding="utf-8") as f:
            json.dump(cache, f, ensure_ascii=False, indent=2)

    # 3. 逐个测试
    print(f"\n[2/3] 开始逐个测试 (超时={TIMEOUT_PER_APP}s/应用)...")
    results = []
    start_time = time.time()
    skipped = 0

    for i, app in enumerate(apps):
        aid = app["aid"]
        name = app["name"]

        # 检查缓存: 已测试的跳过 (删除 passed_cache.json 强制重测)
        if aid in cache:
            status = "[PASS]" if cache[aid].get("passed") else ("[CRASH]" if cache[aid].get("crashed") else "[FAIL]")
            print(f"[{i+1}/{len(apps)}] {name} ({aid}) ... [SKIP] {status} 已缓存")
            results.append(cache[aid])
            skipped += 1
            continue

        result = test_one_app(app, i + 1, len(apps))
        results.append(result)

        # 更新缓存 (通过的应用永久缓存, 失败的也记录供参考)
        cache[aid] = {
            "aid": aid, "name": name,
            "passed": result["passed"],
            "crashed": result.get("crashed", False),
            "stages": result.get("stages", {}),
            "error": result.get("error"),
            "exit_code": result.get("exit_code"),
        }
        save_cache()  # 每次测试后保存, 中断可续

        # 应用间隔: 服务器下载失败时等1分钟让限流恢复, 正常情况等1.5s
        err = result.get("error", "") or ""
        stages = result.get("stages", {})
        install_err = stages.get("install", {}).get("err", "") or ""
        if "安装失败" in err or "安装失败" in install_err:
            print(f"      检测到服务器下载失败, 等待 60s 让限流恢复...", flush=True)
            time.sleep(60)
        else:
            time.sleep(1.5)

        # 进度统计
        passed = sum(1 for r in results if r["passed"])
        crashed = sum(1 for r in results if r.get("crashed"))
        failed = sum(1 for r in results if not r["passed"] and not r.get("crashed"))
        elapsed = time.time() - start_time

        print(f"    进度: {passed}[PASS] {failed}[FAIL] {crashed}[CRASH] / {len(results)} | "
              f"耗时 {elapsed:.0f}s | 预估剩余 {(elapsed/(i+1)*(len(apps)-i-1)):.0f}s")

        # 定期保存中间结果
        if (i + 1) % 10 == 0:
            mid_file = TESTRESULT_DIR / "results_partial.json"
            with open(mid_file, "w", encoding="utf-8") as f:
                json.dump({"results": results, "total": len(apps), "tested": i + 1}, f, ensure_ascii=False, indent=2)

    # 3. 汇总报告
    total_time = time.time() - start_time
    passed = [r for r in results if r["passed"]]
    crashed = [r for r in results if r.get("crashed")]
    failed = [r for r in results if not r["passed"] and not r.get("crashed")]

    print("\n" + "=" * 60)
    print("[3/3] 测试结果汇总")
    print("=" * 60)
    print(f"总计: {len(results)} | [PASS] 通过: {len(passed)} | [FAIL] 失败: {len(failed)} | [CRASH] 崩溃: {len(crashed)}")
    print(f"通过率: {len(passed)/len(results)*100:.1f}%")
    print(f"总耗时: {total_time:.0f}s ({total_time/60:.1f}min)")

    # 输出通过列表
    if passed:
        print(f"\n[PASS] 通过 ({len(passed)}):")
        for r in passed:
            print(f"  {r['name']} ({r['aid']})")

    # 输出失败详情
    if failed:
        print(f"\n[FAIL] 失败 ({len(failed)}):")
        for r in failed:
            stages_str = ",".join(f"{s}={v.get('ok')}" for s, v in r.get("stages", {}).items())
            print(f"  {r['name']} ({r['aid']}) [{stages_str}] {r.get('error', '')}")

    # 输出崩溃详情
    if crashed:
        print(f"\n[CRASH] 崩溃 ({len(crashed)}):")
        for r in crashed:
            print(f"  {r['name']} ({r['aid']}) exit={r.get('exit_code')} {r.get('error', '')}")
            if r.get("stderr_tail"):
                print(f"    stderr: {r['stderr_tail'][:200]}")

    # 保存完整结果
    result_file = TESTRESULT_DIR / "results_full.json"
    with open(result_file, "w", encoding="utf-8") as f:
        json.dump({
            "total": len(results),
            "passed": len(passed),
            "failed": len(failed),
            "crashed": len(crashed),
            "pass_rate": len(passed)/len(results)*100 if results else 0,
            "total_time_s": total_time,
            "results": results,
        }, f, ensure_ascii=False, indent=2)

    print(f"\n完整结果已保存到: {result_file}")

    # 退出码
    if crashed:
        print(f"\n[WARN]️ {len(crashed)} 个应用导致模拟器崩溃!")
    if failed:
        print(f"\n[WARN]️ {len(failed)} 个应用测试失败!")

    return 0 if not crashed and not failed else 1


if __name__ == "__main__":
    sys.exit(main())
