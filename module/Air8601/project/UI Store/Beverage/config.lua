-- 所有设备端文件均放在本目录；LuatTools 平铺添加全部 .lua。
local C = {}
C.WIDTH, C.HEIGHT = 1024, 600
-- existing：与展示UI目录下现有工程一致的 PIN43/GPIO13 接线。
-- official_v010：合宙当前 factory/config/eng_8601_7i_4g.lua 的 PWM3 接线。
C.BOARD_PROFILE = "existing"
C.TICK_MS = 50
C.EMPTY_HOLD_MS = 800 -- 空瓶停留后自动回到首页待选状态
-- 局部小人物动画：24次/秒采样，2秒一轮；不切换图片、不重建控件。
C.MASCOT = {enabled=true,fps=24,cycle_ms=2000,x=720,y=12,w=96,h=96,
    move_x=4,move_y=6,report_ms=10000}
C.SIZES = {
    {name = "大杯", fraction = "满瓶", level = 3000, duration_ms = 15000},
    {name = "中杯", fraction = "2/3瓶", level = 2000, duration_ms = 10000},
    {name = "小杯", fraction = "1/3瓶", level = 1000, duration_ms = 5000},
}
C.DRINKS = {
    {name = "可乐", english = "COLA", note = "经典气泡 · 快乐冒泡", color = 0xA86C50, liquid = 0xA4562B},
    {name = "雪碧", english = "SPRITE", note = "柠檬清爽 · 咕嘟一下", color = 0x4F9476, liquid = 0xB3D878},
    {name = "橙汁", english = "ORANGE", note = "阳光香橙 · 元气满满", color = 0xDA8A25, liquid = 0xFFBA45},
    {name = "桃汁", english = "PEACH", note = "软萌蜜桃 · 甜甜一口", color = 0xC47C91, liquid = 0xF4B0C0},
}
return C
