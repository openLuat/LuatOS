#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
make_route.py —— AirUI 离线地图「预生成路线」工具（纯标准库，不联网）

设备端 route.lua 读取的路线 JSON 结构：
{
  "name": "路线名",
  "points": [ {"lon": 114.30, "lat": 34.84, "name": "起点/途经点名(可空)"}, ... ]
}

== 怎么用 ==
1) 用点表生成（推荐，最可控）：
   编辑下面的 ROUTES，或自己写一个 CSV：
       python make_route.py --csv my_route.csv --out demo_route.json
   CSV 格式（首行表头，name 可留空）：
       lon,lat,name
       114.3068,34.8450,开封北站
       114.3140,34.7970,开封市政府

2) 直接看内置示例（开封北站 -> 开封市政府，沿途几个拐点）：
       python make_route.py --demo

生成的文件拷到 SD 卡：/sd/map/routes/demo_route.json
（map_demo 里“加载路线”按钮读的就是这个固定文件名；多路线可自行改名并改代码路径）

== 坐标说明（重要）==
设备地图 config 是 input_crs="wgs84"，所以本工具输入/输出一律 WGS84。
- 手机 GPS 记录、Google Earth、OpenStreetMap 取的坐标 = WGS84，直接用；
- 高德/腾讯网页上拾取的坐标是 GCJ02（火星坐标），直接填会偏移几十~几百米。
  用 --crs gcj02 或 CSV 加一列 crs=gcj02，本工具内置经典偏移公式转回 WGS84
  （该公式为社区通用近似反算，误差通常 <2m，离线导航足够）。

--interp 参数可在相邻途经点之间按固定间距插值加密（默认 80 米），
让设备上画的线在长直路段上依然平滑、沿线投影更稳；不需要可传 --interp 0。
"""

import argparse
import csv
import json
import math
import os
import sys

EARTH_R = 6371008.8

# ---------------------------------------------------------------------------
# 坐标转换：GCJ02 -> WGS84（国测局火星坐标，社区通用近似公式）
# ---------------------------------------------------------------------------
_A = 6378245.0
_EE = 0.00669342162296594323


def _out_of_china(lon, lat):
    return not (73.66 < lon < 135.05 and 3.86 < lat < 53.55)


def _transform_lat(x, y):
    ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y \
        + 0.1 * x * y + 0.2 * math.sqrt(abs(x))
    ret += (20.0 * math.sin(6.0 * x * math.pi)
            + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0
    ret += (20.0 * math.sin(y * math.pi)
            + 40.0 * math.sin(y / 3.0 * math.pi)) * 2.0 / 3.0
    ret += (160.0 * math.sin(y / 12.0 * math.pi)
            + 320 * math.sin(y * math.pi / 30.0)) * 2.0 / 3.0
    return ret


def _transform_lon(x, y):
    ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y \
        + 0.1 * math.sqrt(abs(x))
    ret += (20.0 * math.sin(6.0 * x * math.pi)
            + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0
    ret += (20.0 * math.sin(x * math.pi)
            + 40.0 * math.sin(x / 3.0 * math.pi)) * 2.0 / 3.0
    ret += (150.0 * math.sin(x / 12.0 * math.pi)
            + 300.0 * math.sin(x / 30.0 * math.pi)) * 2.0 / 3.0
    return ret


def gcj02_to_wgs84(lon, lat):
    """逐次逼近反算（2 次迭代，精度足够）。"""
    if _out_of_china(lon, lat):
        return lon, lat
    wlon, wlat = lon, lat
    for _ in range(2):
        dlat = _transform_lat(wlon - 105.0, wlat - 35.0) / 180.0
        dlon = _transform_lon(wlon - 105.0, wlat - 35.0) / 180.0
        rad = wlat / 180.0 * math.pi
        magic = math.sin(rad)
        magic = 1 - _EE * magic * magic
        sqrt_magic = math.sqrt(magic)
        dlat = (dlat * 180.0) / ((_A * (1 - _EE)) / (magic * sqrt_magic) * math.pi)
        dlon = (dlon * 180.0) / (_A / sqrt_magic * math.cos(rad) * math.pi)
        wlon = lon - dlon
        wlat = lat - dlat
    return wlon, wlat


# ---------------------------------------------------------------------------
# 地理计算
# ---------------------------------------------------------------------------
def haversine(p1, p2):
    lon1, lat1 = math.radians(p1[0]), math.radians(p1[1])
    lon2, lat2 = math.radians(p2[0]), math.radians(p2[1])
    dlat, dlon = lat2 - lat1, lon2 - lon1
    a = math.sin(dlat / 2) ** 2 \
        + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    a = min(1.0, max(0.0, a))
    return 2 * EARTH_R * math.asin(math.sqrt(a))


def initial_bearing(p1, p2):
    lon1, lat1 = math.radians(p1[0]), math.radians(p1[1])
    lon2, lat2 = math.radians(p2[0]), math.radians(p2[1])
    y = math.sin(lon2 - lon1) * math.cos(lat2)
    x = math.cos(lat1) * math.sin(lat2) \
        - math.sin(lat1) * math.cos(lat2) * math.cos(lon2 - lon1)
    return (math.degrees(math.atan2(y, x)) + 360) % 360


def interpolate(p1, p2, step_m):
    """在两点大圆路径上按 step_m 等距插值，返回 [p1 ... p2) 的中间点。"""
    dist = haversine(p1, p2)
    if step_m <= 0 or dist <= step_m:
        return []
    lon1, lat1 = math.radians(p1[0]), math.radians(p1[1])
    lon2, lat2 = math.radians(p2[0]), math.radians(p2[1])
    brg = math.radians(initial_bearing(p1, p2))
    ang = dist / EARTH_R
    out = []
    d = step_m
    while d < dist - 0.5:
        a = d / EARTH_R
        lat = math.asin(math.sin(lat1) * math.cos(a)
                        + math.cos(lat1) * math.sin(a) * math.cos(brg))
        lon = lon1 + math.atan2(
            math.sin(brg) * math.sin(a) * math.cos(lat1),
            math.cos(a) - math.sin(lat1) * math.sin(lat))
        out.append((math.degrees(lon), math.degrees(lat)))
        d += step_m
    return out


# ---------------------------------------------------------------------------
# 内置示例路线：开封北站 -> 西湖北岸 -> 清明上河园 -> 龙亭 -> 开封市政府
# 坐标为 WGS84 概略值（与 map_common 的瓦片范围同一城区，实地使用请自行校正）
# ---------------------------------------------------------------------------
DEMO_WAYPOINTS = [
    (114.306800, 34.845000, "开封北站"),
    (114.310500, 34.833000, ""),
    (114.318500, 34.824000, ""),
    (114.333500, 34.817500, "清明上河园"),
    (114.332500, 34.808500, "龙亭公园"),
    (114.325500, 34.802500, ""),
    (114.314000, 34.797000, "开封市政府"),
]


def read_csv(path, default_crs):
    pts = []
    with open(path, newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            lon = float(row["lon"])
            lat = float(row["lat"])
            name = (row.get("name") or "").strip()
            crs = (row.get("crs") or default_crs).strip().lower()
            pts.append((lon, lat, name, crs))
    return pts


def build_route(raw_pts, default_crs, interp_m):
    """raw_pts: [(lon,lat,name[,crs]), ...]"""
    points = []
    converted = []
    for item in raw_pts:
        lon, lat, name = item[0], item[1], item[2]
        crs = (item[3] if len(item) > 3 and item[3] else default_crs).lower()
        if crs in ("gcj02", "gcj", "amap"):
            lon, lat = gcj02_to_wgs84(lon, lat)
        converted.append((lon, lat, name))

    total = 0.0
    for i, (lon, lat, name) in enumerate(converted):
        if i > 0 and interp_m > 0:
            prev = (converted[i - 1][0], converted[i - 1][1])
            mids = interpolate(prev, (lon, lat), interp_m)
            for mlon, mlat in mids:
                points.append({"lon": round(mlon, 7), "lat": round(mlat, 7),
                               "name": ""})
        if i > 0:
            total += haversine((converted[i - 1][0], converted[i - 1][1]),
                               (lon, lat))
        points.append({"lon": round(lon, 7), "lat": round(lat, 7),
                       "name": name or ""})

    # 带名途经点统计
    named = [p["name"] for p in points if p["name"]]
    return points, total, named


def main():
    ap = argparse.ArgumentParser(
        description="AirUI 离线路线生成工具（输出 WGS84 JSON）")
    ap.add_argument("--csv", help="途经点 CSV：lon,lat,name[,crs]")
    ap.add_argument("--out", default="demo_route.json", help="输出 JSON 文件名")
    ap.add_argument("--name", default=None, help="路线名（默认取文件名/起点->终点）")
    ap.add_argument("--crs", default="wgs84", choices=["wgs84", "gcj02"],
                    help="未在 CSV 里逐行标注时的默认坐标系")
    ap.add_argument("--interp", type=float, default=80,
                    help="相邻点之间插值间距（米），0 表示不插值，默认 80")
    ap.add_argument("--demo", action="store_true", help="生成内置开封示例路线")
    args = ap.parse_args()

    if args.demo:
        raw = [(lon, lat, name, "wgs84") for lon, lat, name in DEMO_WAYPOINTS]
        route_name = args.name or "开封北站->开封市政府"
    elif args.csv:
        raw = read_csv(args.csv, args.crs)
        route_name = args.name
    else:
        ap.print_help()
        print("\n错误：请指定 --csv 文件或 --demo", file=sys.stderr)
        return 2

    if len(raw) < 2:
        print("错误：至少需要 2 个点", file=sys.stderr)
        return 2

    points, total, named = build_route(raw, args.crs, args.interp)
    if not route_name:
        first = named[0] if named else "起点"
        last = named[-1] if named else "终点"
        route_name = "%s->%s" % (first, last)

    data = {"name": route_name, "points": points}
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    print("已生成：%s" % os.path.abspath(args.out))
    print("路线名：%s" % route_name)
    print("总点数：%d（原始途经点 %d，带名 %d），总里程 %.2f km"
          % (len(points), len(raw), len(named), total / 1000))
    print("下一步：拷到 SD 卡 /sd/map/routes/%s" % os.path.basename(args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
