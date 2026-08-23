#!/usr/bin/env python3
# -*- coding: UTF-8 -*-
# 审计工具: 找出 C 代码里通过 sys_pub 发布、但没有 @sys_pub 文档注释的系统消息
# 用法: .venv/Scripts/python.exe tools/sys_pub_audit.py
import os
import re
import io
import json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCAN_DIRS = ["luat", "lua", "components", "bsp"]

def iter_c_files():
    for d in SCAN_DIRS:
        base = os.path.join(ROOT, d)
        for home, dirs, files in os.walk(base):
            for fn in files:
                if fn.endswith(".c") or fn.endswith(".h"):
                    yield os.path.join(home, fn)

# ---------- 1. 提取已文档化的 topic (@sys_pub 注释块) ----------
documented = {}  # topic -> (file, mod)
for path in iter_c_files():
    try:
        with io.open(path, "r", encoding="utf-8") as f:
            lines = f.read().splitlines()
    except Exception:
        continue
    for i in range(len(lines) - 3):
        m = re.match(r"\s*@sys_pub\s+(\S+)", lines[i], re.I)
        if m and lines[i+3].strip() and not lines[i+1].strip().startswith("@") \
           and not lines[i+2].strip().startswith("@"):
            # 兼容两种格式: @sys_pub 在块内任意行; topic 取块内第一个全大写标识行
            pass
    # 更稳的做法: 找 @sys_pub 行, 在后续 5 行内找第一个像 TOPIC 的行
    for i, line in enumerate(lines):
        m = re.match(r"\s*@sys_pub\s+(\S+)", line, re.I)
        if not m:
            continue
        mod = m.group(1)
        for j in range(i + 1, min(i + 6, len(lines))):
            t = lines[j].strip()
            if re.match(r"^[A-Z][A-Z0-9_/\.]{2,}$", t):
                documented[t] = (os.path.relpath(path, ROOT), mod)
                break

# ---------- 2. 提取实际发布的 topic (lua_getglobal(L, "sys_pub") 调用点) ----------
published = {}  # topic -> list of (file, line)
getglobal_re = re.compile(r'lua_getglobal\s*\(\s*L\s*,\s*"sys_pub"\s*\)')
push_re = re.compile(r'lua_push(?:literal|lstring|fstring|string)\s*\(\s*L\s*,\s*"([^"]+)"')
push_var_re = re.compile(r'lua_push(?:lstring|fstring|string)\s*\(\s*L\s*,\s*([^"\s,)]+)')

def strip_comments(lines):
    """去掉 // 行注释和 /* */ 块注释, 避免把注释掉的 sys_pub 调用误报为发布点"""
    out = []
    in_block = False
    for line in lines:
        buf = ""
        i = 0
        while i < len(line):
            if in_block:
                end = line.find("*/", i)
                if end < 0:
                    i = len(line)
                else:
                    in_block = False
                    i = end + 2
            elif line.startswith("/*", i):
                in_block = True
                i += 2
            elif line.startswith("//", i):
                break
            else:
                buf += line[i]
                i += 1
        out.append(buf)
    return out

for path in iter_c_files():
    try:
        with io.open(path, "r", encoding="utf-8") as f:
            lines = strip_comments(f.read().splitlines())
    except Exception:
        continue
    rel = os.path.relpath(path, ROOT)
    for i, line in enumerate(lines):
        if not getglobal_re.search(line):
            continue
        # 在调用点前后各 60 行内找 lua_push(l/f)string 的 topic
        found = False
        lo = max(0, i - 60)
        hi = min(i + 60, len(lines))
        for j in list(range(i + 1, hi)) + list(range(i - 1, lo - 1, -1)):
            if getglobal_re.search(lines[j]) and j != i:
                break
            m = push_re.search(lines[j])
            if m:
                published.setdefault(m.group(1), []).append((rel, j + 1))
                found = True
                break
            mv = push_var_re.search(lines[j])
            if mv and '"' not in lines[j]:
                published.setdefault("<动态:%s>" % mv.group(1), []).append((rel, j + 1))
                found = True
                break
        if not found:
            published.setdefault("<未识别>", []).append((rel, i + 1))

# ---------- 3. Lua 层 sys.publish (script/) ----------
lua_pub = {}
lua_re = re.compile(r'sys\.publish\s*\(\s*"([^"]+)"')
for home, dirs, files in os.walk(os.path.join(ROOT, "script")):
    for fn in files:
        if not fn.endswith(".lua"):
            continue
        path = os.path.join(home, fn)
        try:
            with io.open(path, "r", encoding="utf-8") as f:
                for n, line in enumerate(f, 1):
                    if line.strip().startswith("--"):
                        continue
                    m = lua_re.search(line)
                    if m:
                        lua_pub.setdefault(m.group(1), []).append(
                            (os.path.relpath(path, ROOT), n))
        except Exception:
            continue

# ---------- 4. 比对 ----------
# 动态后缀 topic 的归一化: 代码里是 IO_QUEUE_DONE_%d, 文档里写作 IO_QUEUE_DONE_N
def norm(topic):
    return topic.replace("%d", "N")

documented_norm = {norm(t) for t in documented}
undoc_c = {t: v for t, v in sorted(published.items()) if norm(t) not in documented_norm}
doc_topics = sorted(documented.keys())

print("=" * 70)
print("已文档化的 topic (@sys_pub): %d 个" % len(doc_topics))
for t in doc_topics:
    f, mod = documented[t]
    print("  [doc] %-28s mod=%-12s %s" % (t, mod, f))
print()
print("=" * 70)
print("C 层发布但未文档化的 topic: %d 个" % len(undoc_c))
for t, locs in undoc_c.items():
    print("  [undoc] %s" % t)
    for f, n in locs:
        print("          %s:%d" % (f, n))
print()
print("=" * 70)
print("Lua 层 (script/) sys.publish 的 topic: %d 个 (供参考, sys_pub.py 不扫描 lua)" % len(lua_pub))
for t in sorted(lua_pub):
    locs = lua_pub[t]
    print("  [lua] %-32s %s" % (t, locs[0][0] + (" +%d处" % (len(locs)-1) if len(locs) > 1 else "")))
