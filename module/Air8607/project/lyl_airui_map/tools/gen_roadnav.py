# -*- coding: utf-8 -*-
"""
gen_roadnav.py —— 读 fetch_osrm.py 产出的 osrm_raw.json，
生成设备用的 roadnav.lua：道路折线 M.points + 转弯播报表 M.turns。

M.turns 每条：{at=距起点米数, verb="右转/左转/..."}
设备按"距该转弯的剩余里程"触发播报。
"""
import json
import math
import os

EARTH_R = 6371008.8


def hav(a, b):
    lo1, la1 = a
    lo2, la2 = b
    p1, p2 = math.radians(la1), math.radians(la2)
    dp = p2 - p1
    dl = math.radians(lo2 - lo1)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_R * math.asin(math.sqrt(min(1, max(0, h))))


# OSRM 动作/修饰词 -> 中文播报
_MOD = {
    "left": "左转", "slight left": "靠左前方行驶",
    "sharp left": "向左急转", "right": "右转",
    "slight right": "靠右前方行驶", "sharp right": "向右急转",
    "straight": "直行", "uturn": "请掉头",
}


def verb_of(step):
    t = (step.get("type") or "").lower()
    mod = (step.get("mod") or "").lower()
    if t in ("roundabout", "rotary"):
        return "进入环岛"
    if t in ("merge",):
        return ("并入左侧车道" if "left" in mod else
                "并入右侧车道" if "right" in mod else "注意并入车道")
    if t in ("fork",):
        if "left" in mod:
            return "前方岔路靠左"
        if "right" in mod:
            return "前方岔路靠右"
        return "前方岔路请按路线行驶"
    if t == "turn":
        return _MOD.get(mod, "前方转弯")
    if t in ("new name", "continue"):
        return _MOD.get(mod, "继续沿当前道路行驶")
    return _MOD.get(mod)  # 其余（end of road 等）尽量映射，None 则不播报


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    raw = json.load(open(os.path.join(here, "osrm_raw.json"), encoding="utf-8"))
    coords = raw["coords"]
    steps = raw.get("steps", [])

    # 每个折线索引对应的累计里程
    cum = [0.0]
    for i in range(1, len(coords)):
        cum.append(cum[-1] + hav(coords[i - 1], coords[i]))
    total = cum[-1]

    # 转弯点匹配到最近折线索引
    turns = []
    for st in steps:
        verb = verb_of(st)
        if not verb:
            continue
        best_i, best_d = None, None
        for i, c in enumerate(coords):
            d = (c[0] - st["lon"]) ** 2 + (c[1] - st["lat"]) ** 2
            if best_d is None or d < best_d:
                best_d, best_i = d, i
        at = cum[best_i]
        if at < 30:          # 太靠近起点（出发指令），跳过
            continue
        if turns and abs(turns[-1][0] - at) < 25:
            continue         # 同一位置去重
        turns.append((at, verb))

    body = ",\n".join("{lon=%.7f,lat=%.7f}" % (lo, la) for lo, la in coords)
    tbody = ",\n".join("{at=%.1f,verb=\"%s\"}" % (at, v) for at, v in turns)

    tpl = '''--[[
@module  roadnav
@summary 沿真实道路行驶的模拟导航数据（OSRM/OpenStreetMap，WGS84）
@version 1.1
@date    2026.10.29
@usage
皇宋大观 -> 鼎立国际城E区 真实驾车道路，全程约 %.2f km。
M.points：道路折线；M.turns：转弯播报点 {at=距起点米, verb=中文动作}。
接真实 GPS / 云端算路时，本模块可整体移除。
]]

local M = {}

M.name = "皇宋大观->鼎立国际城E区"
M.total = %.1f

M.points = {
%s
}

M.turns = {
%s
}

return M
'''
    out = os.path.join(here, "..", "roadnav.lua")
    open(out, "w", encoding="utf-8").write(
        tpl % (total / 1000, total, body, tbody))
    print("written %d points, %d turns, %.0f m -> %s"
          % (len(coords), len(turns), total, out))
    for at, v in turns:
        print("  %6.0f m  %s" % (at, v))


if __name__ == "__main__":
    main()
