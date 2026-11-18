# -*- coding: utf-8 -*-
"""静态符号检查：找 C./L./SZ./sim./R. 里"本文件集里根本没有定义"的字段引用。
本机没有 Lua 运行时，这条能抓住真机上最常见的 nil 崩溃：删了卡片/字段还留引用、字段拼错。
判定口径 = 该名字在对应的定义文件里从未以 `name =` / `function M.name` 出现过。
"""
import io, os, re, sys

DOCS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(DOCS, "..", "code")


def read(p):
    return io.open(p, encoding="utf-8").read()


def defined_names(path):
    """文件里所有形如 `key =` / `function M.key` / `M.key =` 的名字，作为已定义集合"""
    txt = read(path)
    names = set(re.findall(r"^\s*(?:p\.|M\.)?(\w+)\s*=", txt, re.M))
    # 一行写多个字段的情况：`card_h1 = 152, card_h2 = 152, card_h3 = 92,`
    names |= set(re.findall(r"[,{]\s*(\w+)\s*=(?!=)", txt))
    names |= set(re.findall(r"^function\s+M\.(\w+)", txt, re.M))
    names |= set(re.findall(r"^local\s+function\s+(\w+)", txt, re.M))
    return names


CFG = os.path.join(ROOT, "app", "app_config.lua")
SIM = os.path.join(ROOT, "app", "app_sim.lua")
cfg_names = defined_names(CFG)
sim_names = defined_names(SIM)

problems = []


def scan(path):
    txt = read(path)
    name = os.path.basename(path)
    for ns, pool in (("C", cfg_names), ("L", cfg_names), ("SZ", cfg_names)):
        for m in re.finditer(r"(?<![\w.])%s\.(\w+)" % ns, txt):
            if m.group(1) not in pool:
                problems.append("%s: %s.%s 未定义" % (name, ns, m.group(1)))
    for m in re.finditer(r"(?<![\w.])sim\.(\w+)", txt):
        if m.group(1) not in sim_names:
            problems.append("%s: sim.%s 未定义" % (name, m.group(1)))
    # R.xxx 必须在本文件被赋过值（R.x = / R.x, / R.x[ 追加）
    assigned = set(re.findall(r"\bR\.(\w+)\s*=(?!=)", txt))
    for m in re.finditer(r"\bR\.(\w+)", txt):
        if m.group(1) not in assigned:
            problems.append("%s: R.%s 只读未赋值" % (name, m.group(1)))


for d in ("ui", "app"):
    for f in sorted(os.listdir(os.path.join(ROOT, d))):
        if f.endswith(".lua"):
            scan(os.path.join(ROOT, d, f))

print("定义域: config %d 名 / sim %d 名" % (len(cfg_names), len(sim_names)))
uniq = sorted(set(problems))
if uniq:
    print("PROBLEMS %d:" % len(uniq))
    for p in uniq:
        print("  " + p)
    sys.exit(1)
print("SYMBOLS: 0 problems")
