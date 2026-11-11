# -*- coding: utf-8 -*-
"""初始化注塑产线工程目录并从 PLC_SVG 图库复制选定素材（短名化）。一次性工具。"""
import os
import shutil

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = r"C:\Users\luat\Desktop\PLC_SVG\SVG"

MAP = {
    "Hopper/light/料斗1-蓝色.svg": "hopper.svg",
    "Chemical/light/加热式 干燥剂 干燥机-红色.svg": "dryer.svg",
    "Cooling/light/冷水机 1-蓝色.svg": "chiller.svg",
    "Cooling/light/冷却塔 2-红色.svg": "tower.svg",
    "Cooling/light/温度 控制 机组-蓝色.svg": "moldtemp.svg",
    "Motors/light/伺服-电机-1-橙色.svg": "servo.svg",
    "Pumps/light/离心泵 3-蓝色.svg": "pump.svg",
    "Building/light/厂房 1-蓝色.svg": "factory.svg",
    "Icons_3/light/垃圾桶 图标-黄色.svg": "recycle.svg",
    "Icons_2/light/注意 图标-黄色.svg": "attention.svg",
    "Arrow(color)/light/简单 箭头-绿色.svg": "arrow.svg",
    "Button/light/按钮 1-01-绿色.svg": "btn_g.svg",
    "Button/light/按钮 1-01-绿色-按下.svg": "btn_g_p.svg",
    "Button/light/按钮 1-01-红色.svg": "btn_r.svg",
    "Button/light/按钮 1-01-红色-按下.svg": "btn_r_p.svg",
    "Button/light/按钮 1-01-蓝色.svg": "btn_b.svg",
    "Button/light/按钮 1-01-蓝色-按下.svg": "btn_b_p.svg",
    "Button/light/按钮 1-01-黄色.svg": "btn_y.svg",
    "Button/light/按钮 1-01-黄色-按下.svg": "btn_y_p.svg",
    "Containers/light/瓦楞纸 箱 带 向上 箭头·封口-橙色.svg": "box.svg",
}


def main():
    lib = os.path.join(PROJ, "web", "img", "lib")
    os.makedirs(lib, exist_ok=True)
    os.makedirs(os.path.join(PROJ, "code", "res"), exist_ok=True)
    missing = []
    for k, name in MAP.items():
        frm = os.path.join(SRC, k.replace("/", os.sep))
        if os.path.isfile(frm):
            shutil.copy2(frm, os.path.join(lib, name))
        else:
            missing.append(k)
    for name in sorted(os.listdir(lib)):
        print(f"{name:16s} {os.path.getsize(os.path.join(lib, name)):7d} B")
    if missing:
        print("缺失:")
        for m in missing:
            print(" ", m)
    else:
        print("全部复制成功")


if __name__ == "__main__":
    main()
