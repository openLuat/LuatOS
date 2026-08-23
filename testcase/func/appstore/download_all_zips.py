#!/usr/bin/env python3
"""
预下载全部应用 ZIP 到 testresult/app_zips/
"""
import json
import os
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

API_URL = "https://api.luatos.com/iot/appstore/list"
PAGE_SIZE = 50
ZIP_DIR = Path("D:/github/LuatOS/testresult/app_zips")

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
        time.sleep(1)

    return all_apps


def download_zip(aid, url):
    """下载单个应用 ZIP"""
    dest = ZIP_DIR / f"{aid}.zip"
    if dest.exists():
        size_mb = dest.stat().st_size / (1024 * 1024)
        return "EXISTS", size_mb

    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={
                "User-Agent": "LuatOS-TestRunner/1.0"
            })
            with urllib.request.urlopen(req, timeout=120) as resp:
                data = resp.read()
            if not data or len(data) < 100:
                raise Exception(f"下载内容过小: {len(data)} bytes")

            dest.parent.mkdir(parents=True, exist_ok=True)
            with open(dest, "wb") as f:
                f.write(data)
            size_mb = len(data) / (1024 * 1024)
            print(f"        -> 下载成功 {size_mb:.1f}MB")
            return "OK", size_mb

        except Exception as e:
            print(f"        -> 第{attempt+1}次失败: {e}")
            if attempt < 2:
                time.sleep(5)
            else:
                return "FAIL", str(e)

    return "FAIL", "unknown"


def main():
    print("=" * 60)
    print("全量预下载应用 ZIP")
    print("=" * 60)

    print("\n[1/2] 拉取应用列表...")
    apps = fetch_all_apps()
    print(f"共获取到 {len(apps)} 个应用")

    if not apps:
        print("错误: 未获取到任何应用")
        sys.exit(1)

    # 保存列表
    list_file = Path("D:/github/LuatOS/testresult/app_list.json")
    list_file.parent.mkdir(parents=True, exist_ok=True)
    with open(list_file, "w", encoding="utf-8") as f:
        json.dump(apps, f, ensure_ascii=False, indent=2)
    print(f"应用列表已保存: {list_file}")

    print(f"\n[2/2] 下载 ZIP 到 {ZIP_DIR}...")
    ok = 0
    exists = 0
    fail = 0
    total = len(apps)
    total_size = 0.0

    for i, app in enumerate(apps):
        aid = app["aid"]
        url = app["url"]
        name = app["name"]
        print(f"[{i+1}/{total}] {name} ({aid})", end=" ", flush=True)

        status, info = download_zip(aid, url)
        if status == "OK":
            ok += 1
            total_size += info
        elif status == "EXISTS":
            exists += 1
            total_size += info
            print(f"        -> 已存在 {info:.1f}MB")
        else:
            fail += 1
            print(f"        -> 失败: {info}")

        # 进度
        if (i + 1) % 10 == 0:
            print(f"    进度: {ok}新增 {exists}已有 {fail}失败 / {total} | {total_size:.0f}MB")

        # 下载间隔，避免服务器限流
        if status == "OK":
            time.sleep(1.5)
        elif status == "FAIL":
            time.sleep(3)

    print("\n" + "=" * 60)
    print("下载完成")
    print(f"总计: {total} | 新增: {ok} | 已有: {exists} | 失败: {fail}")
    print(f"总大小: {total_size:.0f}MB")
    print("=" * 60)

    return 0 if fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
