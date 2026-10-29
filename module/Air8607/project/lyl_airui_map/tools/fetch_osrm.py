#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
fetch_osrm.py —— 用 OSRM 公共服务取真实驾车道路几何（纯标准库，需联网）

数据来自 OpenStreetMap，输入/输出均为 WGS84，和设备地图 input_crs="wgs84" 一致。

用法：
    python fetch_osrm.py 起点经度,起点纬度 终点经度,终点纬度
    python fetch_osrm.py 114.325115,34.796553 114.315058,34.816085

默认把道路折线存到 osrm_raw.json，紧接着跑 gen_roadnav.py 即可生成 roadnav.lua。
若从高德/腾讯网页拾到的是 GCJ02 坐标，加 --crs gcj02，会先转回 WGS84。
"""

import argparse
import json
import math
import os
import ssl
import sys
import urllib.request

_A = 6378245.0
_EE = 0.00669342162296594323


def _out_of_china(lon, lat):
    return not (73.66 < lon < 135.05 and 3.86 < lat < 53.55)


def _dlat(x, y):
    ret = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * math.sqrt(abs(x))
    ret += (20 * math.sin(6 * x * math.pi) + 20 * math.sin(2 * x * math.pi)) * 2 / 3
    ret += (20 * math.sin(y * math.pi) + 40 * math.sin(y / 3 * math.pi)) * 2 / 3
    ret += (160 * math.sin(y / 12 * math.pi) + 320 * math.sin(y * math.pi / 30)) * 2 / 3
    return ret


def _dlon(x, y):
    ret = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * math.sqrt(abs(x))
    ret += (20 * math.sin(6 * x * math.pi) + 20 * math.sin(2 * x * math.pi)) * 2 / 3
    ret += (20 * math.sin(x * math.pi) + 40 * math.sin(x / 3 * math.pi)) * 2 / 3
    ret += (150 * math.sin(x / 12 * math.pi) + 300 * math.sin(x / 30 * math.pi)) * 2 / 3
    return ret


def gcj02_to_wgs84(lon, lat):
    if _out_of_china(lon, lat):
        return lon, lat
    wlon, wlat = lon, lat
    for _ in range(2):
        dlat = _dlat(wlon - 105, wlat - 35) / 180
        dlon = _dlon(wlon - 105, wlat - 35) / 180
        rad = wlat / 180 * math.pi
        magic = 1 - _EE * math.sin(rad) ** 2
        sq = math.sqrt(magic)
        dlat = dlat * 180 / ((_A * (1 - _EE)) / (magic * sq) * math.pi)
        dlon = dlon * 180 / (_A / sq * math.cos(rad) * math.pi)
        wlon, wlat = lon - dlon, lat - dlat
    return wlon, wlat


def parse_pt(s, crs):
    parts = s.replace("，", ",").split(",")
    lon, lat = float(parts[0]), float(parts[1])
    if crs == "gcj02":
        lon, lat = gcj02_to_wgs84(lon, lat)
    return lon, lat


def main():
    ap = argparse.ArgumentParser(description="OSRM 真实驾车路线抓取（WGS84）")
    ap.add_argument("origin", help="起点：经度,纬度")
    ap.add_argument("dest", help="终点：经度,纬度")
    ap.add_argument("--crs", default="wgs84", choices=["wgs84", "gcj02"],
                    help="输入坐标的坐标系，默认 wgs84")
    ap.add_argument("--out", default="osrm_raw.json", help="输出折线 JSON")
    args = ap.parse_args()

    o = parse_pt(args.origin, args.crs)
    d = parse_pt(args.dest, args.crs)
    url = ("https://router.project-osrm.org/route/v1/driving/"
           "%.6f,%.6f;%.6f,%.6f?overview=full&geometries=geojson&steps=true"
           % (o[0], o[1], d[0], d[1]))

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    data = json.load(urllib.request.urlopen(req, timeout=25, context=ctx))
    if data.get("code") != "Ok" or not data.get("routes"):
        print("取路失败：%s" % data.get("code"), file=sys.stderr)
        return 1

    route = data["routes"][0]
    coords = route["geometry"]["coordinates"]

    # 转弯步骤：只保留真正需要播报的（出发/到达/普通直行段除外）
    steps = []
    for leg in route.get("legs", []):
        for st in leg.get("steps", []):
            man = st.get("maneuver", {})
            mtype = man.get("type", "")
            mpoint = man.get("location", [])
            if mtype in ("depart", "arrive") or not mpoint:
                continue
            steps.append({
                "lon": mpoint[0], "lat": mpoint[1],
                "mod": man.get("modifier", ""),
                "type": mtype,
                "after": st.get("distance", 0),  # 转弯后到下一指令的路长(米)
            })

    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, args.out)
    json.dump({"coords": coords, "steps": steps},
              open(out, "w", encoding="utf-8"), ensure_ascii=False)

    print("里程 %.2f km，约 %.1f 分钟，道路拐点 %d 个，转弯指令 %d 条"
          % (route["distance"] / 1000, route["duration"] / 60,
             len(coords), len(steps)))
    print("已存：%s" % out)
    print("下一步：python gen_roadnav.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
