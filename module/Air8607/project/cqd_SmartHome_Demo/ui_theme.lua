--[[
@module ui_theme
@summary 界面主题：暖色系配色、圆角、字号、透明度
@version 1.0
@usage 所有界面模块统一从这里取色值/尺寸，改主题只需要改这一个文件。
       颜色格式与 AirUI 一致：0xRRGGBB。
       透明度（opacity）取值范围 0-255，越小越透明。
]]

local M = {}

M.c = {
    -- 文字（卡片是半透明暖白毛玻璃，所以文字用深暖褐）
    text      = 0x4A2B14,   -- 主要文字
    text_sub  = 0x8B6647,   -- 次要文字
    text_dim  = 0xA98A6E,   -- 更弱的说明文字
    text_light= 0xFFF2E2,   -- 深色背景上的文字

    -- 卡片 / 面板
    card      = 0xFFFFFF,   -- 毛玻璃卡片底色
    card_edge = 0xFFE0BC,   -- 卡片高光描边
    panel     = 0xFFF6EA,   -- 卡片内嵌面板
    divider   = 0xE3C7A6,   -- 分隔线
    shadow    = 0x53290D,   -- 卡片投影

    -- 强调色（暖色系）
    amber     = 0xF0891F,   -- 琥珀橙（主强调）
    amber_lt  = 0xFFB25E,   -- 浅琥珀
    clay      = 0xDD7A3C,   -- 陶土橙（窗帘）
    green     = 0x4F9E6A,   -- 在线状态

    -- 控件
    sw_on     = 0xF2A93B,   -- 开关：开
    sw_off    = 0xB9A695,   -- 开关：关
    btn       = 0xF0891F,   -- 圆角按钮底色
    btn_text  = 0xFFFFFF,
    chip_on   = 0xF0891F,   -- 档位按钮：选中
    chip_on_t = 0xFFFFFF,
    chip_off  = 0xFFFFFF,   -- 档位按钮：未选中
    chip_off_t= 0x8B6647,
    knob      = 0xFFFFFF,
}

-- 透明度
M.o = {
    card      = 66,    -- 毛玻璃卡片
    panel     = 150,   -- 卡片内嵌面板
    topbar    = 88,    -- 顶部栏
    chip      = 140,   -- 未选中档位按钮
    sw_off    = 200,
    btn       = 255,
}

-- 圆角
M.r = {
    card   = 26,
    panel  = 20,
    chip   = 17,
    button = 22,
}

-- 字号（hzfont 矢量字库支持 12-255 号）
M.f = {
    h1    = 32,   -- 页面主标题
    title = 28,   -- 卡片房间名
    temp  = 46,   -- 卡片大温度
    ac    = 32,   -- 空调设定温度
    body  = 18,
    sub   = 15,
    mini  = 14,
}

-- 布局常量（Air8601 屏幕：1024x600）
M.screen = { w = 1024, h = 600 }

return M
