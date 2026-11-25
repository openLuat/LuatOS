# -*- coding: utf-8 -*-
"""把本地工程提交到 LuatOS Studio 云端源码项目（走 LuatOS-Studio-Source 的 MCP over HTTP）。

用法：
  python submit_source.py --describe        # 打印 update_source_project 的说明与参数
  python submit_source.py --dry            # 只统计要提交的文件与要删的远端文件，不发请求
  python submit_source.py                   # 全量提交（文本走 files，PNG 走 assets_base64）
  python submit_source.py --check           # 只读云端 revision 与文件列表
  python submit_source.py --no-prune        # 不自动删除远端多余文件
  python submit_source.py --delete a.png,b.lua   # 额外指定要删的远端路径

删除：默认自动比对「云端文件列表 − 本地收集到的文件」，差集作为 delete_paths 传上去
（例如换贴图后残留的 kid_*.png 会被清掉），避免固件镜像里堆着没人引用的旧资源。

冲突处理：提交前先 get_source_project 取最新 revision 作为 base_revision；
若服务端报版本冲突，脚本会自动重读 revision 再重试一次。
"""
import base64
import json
import os
import sys
import urllib.request

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

MCP_URL = ("https://ui.luatos.com/mcp-source/"
           "plchmi_pqE_xBVlAuHQsVfuXlml7O_r2kypEyJv-xBTi2d2zcI")
PROJECT_ID = "dcf6ec8802764c99955e2e3b7873f8dc"

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

TEXT_EXT = {".lua", ".md", ".html", ".py", ".txt", ".json", ".csv"}
BIN_EXT = {".png", ".jpg", ".jpeg"}

# 不提交的东西：本地验证产物与临时日志
SKIP_DIRS = {"logs", "__pycache__", ".git"}
SKIP_FILES = {"sim_run.log", "probe_stdout.log"}


def skipped(name):
    # 只跳过验证时抓的 sim_N_*.png 截图，别把 sim_probe.py 这类工具也跳掉
    return name in SKIP_FILES or (name.startswith("sim_") and name.endswith(".png"))


def rpc(method, params, _id=1):
    body = json.dumps({"jsonrpc": "2.0", "id": _id, "method": method,
                       "params": params}).encode("utf-8")
    req = urllib.request.Request(
        MCP_URL, data=body,
        headers={"Content-Type": "application/json", "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read().decode("utf-8"))


def call_tool(name, args):
    r = rpc("tools/call", {"name": name, "arguments": args})
    if "error" in r:
        raise RuntimeError("MCP error: %s" % json.dumps(r["error"], ensure_ascii=False))
    content = r.get("result", {}).get("content", [])
    text = "\n".join(c.get("text", "") for c in content if c.get("type") == "text")
    return text


def read_revision():
    text = call_tool("get_source_project", {"project_id": PROJECT_ID})
    try:
        data = json.loads(text)
    except ValueError:
        return None, text
    return data.get("revision"), data


def collect():
    """云端源码工程是「脚本区镜像」：main.lua 必须在根，code/ 的内容平铺到根。

    服务端会校验「files 需要非空的 main.lua」，所以 code/xxx → xxx。
    docs/ 是本地开发资料（效果稿、验证脚本、截图），不进云端工程，避免被打进固件镜像；
    需要时从仓库取。
    """
    files, assets = {}, {}
    for base, dirs, names in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and d != "docs"]
        for n in names:
            if skipped(n):
                continue
            path = os.path.join(base, n)
            rel = os.path.relpath(path, ROOT).replace("\\", "/")
            if rel.startswith("code/"):
                rel = rel[len("code/"):]
            ext = os.path.splitext(n)[1].lower()
            if ext in TEXT_EXT:
                files[rel] = open(path, encoding="utf-8").read()
            elif ext in BIN_EXT:
                assets[rel] = base64.b64encode(open(path, "rb").read()).decode("ascii")
    return files, assets


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "--submit"

    if mode == "--describe":
        r = rpc("tools/list", {})
        for t in r["result"]["tools"]:
            if t["name"] == "update_source_project":
                print(t.get("description", ""))
                print(json.dumps(t.get("inputSchema", {}), ensure_ascii=False, indent=2))
        return

    rev, info = read_revision()
    print("云端 revision:", rev)
    if isinstance(info, dict):
        print("云端文件数:", len(info.get("files") or []), " awaitingSource:",
              info.get("awaitingSource"))
    if mode == "--check":
        print(json.dumps(info, ensure_ascii=False, indent=2)[:2000])
        return

    files, assets = collect()
    print("待提交：文本 %d 个，二进制 %d 个" % (len(files), len(assets)))
    for k in sorted(files):
        print("   txt", k)
    for k in sorted(assets):
        print("   bin", k, len(assets[k]) // 1024, "KB(base64)")

    # 自动清理：云端有、本地已没有的文件（换贴图/改文件名后最容易残留）
    delete_paths = []
    if "--delete" in sys.argv:
        for v in sys.argv[sys.argv.index("--delete") + 1].split(","):
            v = v.strip()
            if v:
                delete_paths.append(v)
    if "--no-prune" not in sys.argv and isinstance(info, dict):
        have = set(files) | set(assets)
        for remote in info.get("files") or []:
            if remote not in have and remote not in delete_paths:
                delete_paths.append(remote)
    print("待删除：%d 个" % len(delete_paths))
    for k in delete_paths:
        print("   del", k)
    if mode == "--dry":
        return

    for attempt in (1, 2):
        try:
            text = call_tool("update_source_project", {
                "project_id": PROJECT_ID,
                "base_revision": rev,
                "files": files,
                "assets_base64": assets,
                "delete_paths": delete_paths,
                "name": "儿童房控制面板",
                "board": "Air8607",
            })
            print("\n--- 提交结果 ---")
            print(text[:3000])
            try:
                res = json.loads(text)
                print("\nreviewUrl:", res.get("reviewUrl") or res.get("url"))
                print("revision:", res.get("revision"))
            except ValueError:
                pass
            return
        except Exception as exc:                     # noqa: BLE001
            print("提交失败(%d)：%s" % (attempt, exc))
            if attempt == 2:
                raise
            print("重新读取 revision 后重试…")
            rev, _ = read_revision()
            print("新 revision:", rev)


if __name__ == "__main__":
    main()
