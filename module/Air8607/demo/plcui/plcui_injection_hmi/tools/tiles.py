# -*- coding: utf-8 -*-
"""PLCUI 素材瓦片表（唯一来源）。

design/sheet.html 由本表生成，tools/export_assets.py 也读本表裁剪，
两边的尺寸 / 内边距不会漂。

字段
----
name  资源基名（也是导入后 PNG 的文件名主干，<=23 字节含扩展名）
w,h   组件在设备上的实际显示尺寸（页面 CSS 显示值）
pad   瓦片四周留白，用于保住 box-shadow / 辉光；导出到 XML 时
      x-pad, y-pad, w+2*pad, h+2*pad，视觉位置不变
html  瓦片内部结构，直接复用 theme.css 的 class
"""

TILES = [
    # 仪表指针：96×96 透明图，绕中心旋转
    ("nd_needle", 96, 96, 0,
     '<div class="needle" style="left:0;top:0;width:96px;height:96px"><i></i></div>'),
    # 表盘中心盖（压在指针之上）
    ("g_cap", 14, 14, 0,
     '<div class="gcap" style="left:0;top:0;width:14px;height:14px;margin:0"></div>'),

    # 状态点：运行 / 待机 / 故障 / 灭
    ("dot_run", 10, 10, 3,
     '<span class="dot dot--run" style="left:3px;top:3px;width:10px;height:10px"></span>'),
    ("dot_idle", 10, 10, 3,
     '<span class="dot dot--idle" style="left:3px;top:3px;width:10px;height:10px"></span>'),
    ("dot_fault", 10, 10, 3,
     '<span class="dot dot--fault" style="left:3px;top:3px;width:10px;height:10px"></span>'),
    ("dot_off", 10, 10, 3,
     '<span class="dot dot--off" style="left:3px;top:3px;width:10px;height:10px"></span>'),

    # 顶栏设备状态灯：三态
    ("lamp_run", 14, 14, 3,
     '<span class="lamp lamp--run" style="left:3px;top:3px;width:14px;height:14px"></span>'),
    ("lamp_idle", 14, 14, 3,
     '<span class="lamp lamp--idle" style="left:3px;top:3px;width:14px;height:14px"></span>'),
    ("lamp_alarm", 14, 14, 3,
     '<span class="lamp lamp--alarm" style="left:3px;top:3px;width:14px;height:14px"></span>'),

    # 负载条填充：绿 / 黄 / 红，运行时按比例 set_size
    ("barfill_g", 296, 6, 0,
     '<div class="bar-fill" style="left:0;top:0;width:296px;height:6px"></div>'),
    ("barfill_i", 296, 6, 0,
     '<div class="bar-fill i" style="left:0;top:0;width:296px;height:6px"></div>'),
    ("barfill_f", 296, 6, 0,
     '<div class="bar-fill f" style="left:0;top:0;width:296px;height:6px"></div>'),

    # 设备卡箭头：常态 / 选中
    ("arr_n", 20, 18, 2,
     '<div class="arrow" style="left:2px;top:2px;width:20px;height:18px">&#8250;</div>'),
    ("arr_c", 20, 18, 2,
     '<div class="arrow is-checked" style="left:2px;top:2px;width:20px;height:18px">&#8250;</div>'),

    # 报警确认键：常态 / 按下 / 已确认
    ("ack_n", 44, 18, 2,
     '<div class="ackbtn" style="left:2px;top:2px;width:44px;height:18px">确认</div>'),
    ("ack_p", 44, 18, 2,
     '<div class="ackbtn is-pressed" style="left:2px;top:2px;width:44px;height:18px">确认</div>'),
    ("ack_d", 44, 18, 2,
     '<div class="ackbtn is-disabled" style="left:2px;top:2px;width:44px;height:18px">已确认</div>'),

    # 底栏页签：常态 / 选中
    ("tab_ov_n", 66, 24, 0,
     '<div class="tab" style="left:0;top:0;width:66px;height:24px">总 览</div>'),
    ("tab_ov_c", 66, 24, 0,
     '<div class="tab is-checked" style="left:0;top:0;width:66px;height:24px">总 览</div>'),
    ("tab_tr_n", 66, 24, 0,
     '<div class="tab" style="left:0;top:0;width:66px;height:24px">趋 势</div>'),
    ("tab_tr_c", 66, 24, 0,
     '<div class="tab is-checked" style="left:0;top:0;width:66px;height:24px">趋 势</div>'),
    ("tab_al_n", 66, 24, 0,
     '<div class="tab" style="left:0;top:0;width:66px;height:24px">报 警</div>'),
    ("tab_al_c", 66, 24, 0,
     '<div class="tab is-checked" style="left:0;top:0;width:66px;height:24px">报 警</div>'),
    ("tab_st_n", 66, 24, 0,
     '<div class="tab" style="left:0;top:0;width:66px;height:24px">设 置</div>'),
    ("tab_st_c", 66, 24, 0,
     '<div class="tab is-checked" style="left:0;top:0;width:66px;height:24px">设 置</div>'),
    ("badge", 16, 16, 0,
     '<div class="badgeimg" style="left:0;top:0;width:16px;height:16px"></div>'),

    # 主控按钮：启动 / 停止 / 复位（图标与文字烘在图里）
    ("btnstart_n", 66, 56, 5,
     '<div class="btn btn-start" style="left:5px;top:5px;width:66px;height:56px;flex-direction:column;gap:2px;font-size:10px">'
     '<span class="ico">&#9654;</span><span>启动</span></div>'),
    ("btnstart_p", 66, 56, 5,
     '<div class="btn btn-start is-pressed" style="left:5px;top:5px;width:66px;height:56px;flex-direction:column;gap:2px;font-size:10px">'
     '<span class="ico">&#9654;</span><span>启动</span></div>'),
    ("btnstop_n", 66, 56, 5,
     '<div class="btn btn-stop" style="left:5px;top:5px;width:66px;height:56px;flex-direction:column;gap:2px;font-size:10px">'
     '<span class="ico">&#9632;</span><span>停止</span></div>'),
    ("btnstop_p", 66, 56, 5,
     '<div class="btn btn-stop is-pressed" style="left:5px;top:5px;width:66px;height:56px;flex-direction:column;gap:2px;font-size:10px">'
     '<span class="ico">&#9632;</span><span>停止</span></div>'),
    ("btnreset_n", 66, 56, 5,
     '<div class="btn btn-reset" style="left:5px;top:5px;width:66px;height:56px;flex-direction:column;gap:2px;font-size:10px">'
     '<span class="ico">&#8634;</span><span>复位</span></div>'),
    ("btnreset_p", 66, 56, 5,
     '<div class="btn btn-reset is-pressed" style="left:5px;top:5px;width:66px;height:56px;flex-direction:column;gap:2px;font-size:10px">'
     '<span class="ico">&#8634;</span><span>复位</span></div>'),

    # 急停蘑菇头
    ("estop_n", 66, 66, 4,
     '<div class="estop" style="left:4px;top:4px;width:66px;height:66px"><span class="head">急 停</span></div>'),
    ("estop_p", 66, 66, 4,
     '<div class="estop is-pressed" style="left:4px;top:4px;width:66px;height:66px"><span class="head">急 停</span></div>'),

    # 紧急停机旗标
    ("flag", 84, 22, 0,
     '<div class="estop-flag" style="left:0;top:0;width:84px;height:22px">&#9888; 紧急停机</div>'),

    # 管路流动条纹 4 帧（透明，叠在烘好的管身上）
    ("flow_0", 96, 14, 0,
     '<div class="flow" style="left:0;top:0;width:96px;height:14px;background-position-x:0"></div>'),
    ("flow_1", 96, 14, 0,
     '<div class="flow" style="left:0;top:0;width:96px;height:14px;background-position-x:8px"></div>'),
    ("flow_2", 96, 14, 0,
     '<div class="flow" style="left:0;top:0;width:96px;height:14px;background-position-x:17px"></div>'),
    ("flow_3", 96, 14, 0,
     '<div class="flow" style="left:0;top:0;width:96px;height:14px;background-position-x:25px"></div>'),

    # 参数开关两态
    ("sw_off", 48, 22, 0,
     '<div class="sw" style="left:0;top:0;width:48px;height:22px"><span></span></div>'),
    ("sw_on", 48, 22, 0,
     '<div class="sw on" style="left:0;top:0;width:48px;height:22px"><span></span></div>'),

    # 设定值旋钮
    ("knobsp", 62, 62, 2,
     '<div class="knob" style="left:2px;top:2px;width:62px;height:62px;--k:0deg"><i></i></div>'),

    # 滑块手柄：PLCUI 要求旋钮图是正方形，边长 == 滑块短边（本工程滑块高 24）
    ("thumb", 24, 24, 0,
     '<div class="thumbimg" style="left:0;top:0;width:24px;height:24px"></div>'),

    # 报警页两个功能键
    ("btnackall_n", 126, 32, 4,
     '<div class="btn" style="left:4px;top:4px;width:126px;height:32px;font-size:10px;letter-spacing:1.2px">全部确认</div>'),
    ("btnackall_p", 126, 32, 4,
     '<div class="btn is-pressed" style="left:4px;top:4px;width:126px;height:32px;font-size:10px;letter-spacing:1.2px">全部确认</div>'),
    ("btnclr_n", 122, 32, 4,
     '<div class="btn" style="left:4px;top:4px;width:122px;height:32px;font-size:10px;letter-spacing:1.2px">清除已确认</div>'),
    ("btnclr_p", 122, 32, 4,
     '<div class="btn is-pressed" style="left:4px;top:4px;width:122px;height:32px;font-size:10px;letter-spacing:1.2px">清除已确认</div>'),
    ("btnsave_n", 130, 32, 4,
     '<div class="btn btn-start" style="left:4px;top:4px;width:130px;height:32px;font-size:10.5px;letter-spacing:1.4px">保存参数</div>'),
    ("btnsave_p", 130, 32, 4,
     '<div class="btn btn-start is-pressed" style="left:4px;top:4px;width:130px;height:32px;font-size:10.5px;letter-spacing:1.4px">保存参数</div>'),
]

# 页面 data-asset-name -> pad（导出 XML 时按资源基名取含状态的资源）
def pad_of(asset, state=None):
    name = asset if state is None else "%s_%s" % (asset, state)
    for t in TILES:
        if t[0] == name:
            return t[3]
    return 0


def size_of(asset, state=None):
    name = asset if state is None else "%s_%s" % (asset, state)
    for t in TILES:
        if t[0] == name:
            return t[1], t[2], t[3]
    return None
