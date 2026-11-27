--[[
@module  dash_theme
@summary 86盒深色部件仪表盘的主题，配色、字号、图标图元与基础皮肤组件
@version 1.0
@date    2026.11.04
@author  江访
@usage
本文件为86盒深色部件仪表盘的皮肤层，核心业务逻辑为：
1、定义纯黑底的深色界面配色和6种配件类型色，颜色值按0xRRGGBB书写，模块加载时统一换算成这块屏显存需要的颜色值；
2、定义字号档位，最小档16是这块屏实测能正常出字的下限，再小会渲染成方框；
3、按配件类型返回图标图元数组，图标画在44x44的画布里，再按需整体缩放；
4、提供部件卡片、文字、胶囊按钮3个基础皮肤组件，部件模块只管往里填内容；

本文件的对外接口有8个：
1、dash_theme.COLOR：换算后的界面配色表
2、dash_theme.TYPE_COLOR：换算后的配件类型色表
3、dash_theme.FONT_SIZE：字号档位表
4、dash_theme.build_icon_items()：按配件类型生成图标图元数组
5、dash_theme.card()：创建部件卡片
6、dash_theme.label()：创建文字
7、dash_theme.pill()：创建胶囊按钮
8、dash_theme.knob_pos()：算开关滑块在轨道里的位置

更多说明参考本目录下的readme.md文件
]]

local exd_st7102_rgb = require "exd_st7102_rgb"

local dash_theme = {}

-- ==================== 界面配色 ====================

-- 界面配色定义，颜色值为0xRRGGBB格式
-- BG：整屏背景色，纯黑
-- CARD：部件卡片背景色，深灰
-- CARD_HI：卡片上凸起的小块背景色，比卡片略亮
-- TEXT：主文字色，纯白
-- TEXT_SUB：次要文字色
-- ACCENT：强调色，品红，日期星期、播放按钮、开关开启色
-- TRACK_OFF：开关关闭时的轨道色
-- KNOB：开关滑块色
-- WHITE：纯白，图标线条色
-- BLACK：纯黑，备用文字色
local COLOR_DEF = {
    BG = 0x000000,
    CARD = 0x1C1C1E,
    CARD_HI = 0x2C2C2E,
    TEXT = 0xFFFFFF,
    TEXT_SUB = 0x8E8E93,
    ACCENT = 0xBF5AF2,
    TRACK_OFF = 0x39393D,
    KNOB = 0xFFFFFF,
    WHITE = 0xFFFFFF,
    BLACK = 0x000000,
}

-- 配件类型色定义，键为配件类型标识，值为0xRRGGBB格式
-- 灯光用橙、空调用蓝、窗帘用紫、插座用绿、传感器用青、门锁用红
local TYPE_COLOR_DEF = {
    light = 0xFF9F0A,
    ac = 0x0A84FF,
    curtain = 0xBF5AF2,
    plug = 0x30D158,
    sensor = 0x64D2FF,
    lock = 0xFF453A,
}

-- 字号档位，单位像素
-- CLOCK：大表盘时间
-- DAY：日期里的日数字
-- TITLE：部件标题、日期里的星期与月
-- BODY：正文、配件名、按钮
-- MINI：日历格子与星期行，取这块屏实测的下限16
local FONT_SIZE_DEF = {
    CLOCK = 44,
    DAY = 72,
    TITLE = 20,
    BODY = 16,
    MINI = 16,
}

-- 图标画布边长，图元坐标都按这个边长给
local ICON_CANVAS = 44

-- 图元整体缩放时的最小线宽，再细会在小圆底上看不清
local MIN_STROKE_WIDTH = 2

-- 开关滑块与轨道两端的横向内边距，纵向内边距按轨道高度与滑块边长居中算
local KNOB_PAD_X = 2

--[[
把颜色定义逐项换算成这块屏显存需要的颜色值；
换算只在模块加载时做一次，部件模块直接用换算后的值；

@function (内部函数) build_color_table

@table color_def
0xRRGGBB格式的颜色定义表；

@return table
换算后的颜色表，键与传入的color_def一致
]]
local function build_color_table(color_def)
    local color_table = {}
    for name, value in pairs(color_def) do
        color_table[name] = exd_st7102_rgb.to_panel_color(value)
    end
    return color_table
end

-- ==================== 图标图元 ====================

--[[
生成灯泡图标；
一个圆头加两道灯头横线；

@function (内部函数) build_light_icon_items

@number color
图标线条颜色；

@return table
shape图元数组
]]
local function build_light_icon_items(color)
    return {
        { type = "circle", cx = 22, cy = 17, r = 8, color = color, width = 2, round_start = true },
        { type = "line", x1 = 17, y1 = 28, x2 = 27, y2 = 28, color = color, width = 2, round_start = true, round_end = true },
        { type = "line", x1 = 19, y1 = 33, x2 = 25, y2 = 33, color = color, width = 2, round_start = true, round_end = true },
    }
end

--[[
生成空调图标；
一个圆角机身加两道出风横线；

@function (内部函数) build_ac_icon_items

@number color
图标线条颜色；

@return table
shape图元数组
]]
local function build_ac_icon_items(color)
    return {
        { type = "rect", x = 7, y = 11, w = 30, h = 16, radius = 5, color = color, width = 2 },
        { type = "line", x1 = 13, y1 = 32, x2 = 31, y2 = 32, color = color, width = 2, round_start = true, round_end = true },
        { type = "line", x1 = 17, y1 = 37, x2 = 27, y2 = 37, color = color, width = 2, round_start = true, round_end = true },
    }
end

--[[
生成窗帘图标；
一道横杆加三道褶皱竖线；

@function (内部函数) build_curtain_icon_items

@number color
图标线条颜色；

@return table
shape图元数组
]]
local function build_curtain_icon_items(color)
    return {
        { type = "line", x1 = 8, y1 = 11, x2 = 36, y2 = 11, color = color, width = 3, round_start = true, round_end = true },
        { type = "line", x1 = 13, y1 = 15, x2 = 13, y2 = 34, color = color, width = 2, round_start = true, round_end = true },
        { type = "line", x1 = 22, y1 = 15, x2 = 22, y2 = 29, color = color, width = 2, round_start = true, round_end = true },
        { type = "line", x1 = 31, y1 = 15, x2 = 31, y2 = 34, color = color, width = 2, round_start = true, round_end = true },
    }
end

--[[
生成插座图标；
一个圆角面板加两根插脚竖线；

@function (内部函数) build_plug_icon_items

@number color
图标线条颜色；

@return table
shape图元数组
]]
local function build_plug_icon_items(color)
    return {
        { type = "rect", x = 10, y = 12, w = 24, h = 20, radius = 5, color = color, width = 2 },
        { type = "line", x1 = 17, y1 = 18, x2 = 17, y2 = 26, color = color, width = 2, round_start = true, round_end = true },
        { type = "line", x1 = 27, y1 = 18, x2 = 27, y2 = 26, color = color, width = 2, round_start = true, round_end = true },
    }
end

--[[
生成传感器图标；
三层同心圆环，读作雷达波；

@function (内部函数) build_sensor_icon_items

@number color
图标线条颜色；

@return table
shape图元数组
]]
local function build_sensor_icon_items(color)
    return {
        { type = "circle", cx = 22, cy = 22, r = 4, color = color, width = 2, round_start = true },
        { type = "circle", cx = 22, cy = 22, r = 10, color = color, width = 2, round_start = true },
        { type = "circle", cx = 22, cy = 22, r = 16, color = color, width = 2, round_start = true },
    }
end

--[[
生成门锁图标；
一个圆角锁体加一道半圆锁梁，锁体上一个钥匙孔圆点；

@function (内部函数) build_lock_icon_items

@number color
图标线条颜色；

@return table
shape图元数组
]]
local function build_lock_icon_items(color)
    return {
        { type = "arc", cx = 22, cy = 20, r = 7, start_angle = 180, end_angle = 360, color = color, width = 2, rounded = true },
        { type = "rect", x = 11, y = 20, w = 22, h = 16, radius = 3, color = color, width = 2 },
        { type = "circle", cx = 22, cy = 27, r = 2, color = color, width = 2, fill = true, fill_color = color },
    }
end

--[[
把一组图元按比例整体缩放；
缩放只动坐标和尺寸这些几何量，颜色、圆头、填充这些属性原样保留；
线宽单独算，缩完取最小线宽，避免小圆底上线条太细看不清；

@function (内部函数) scale_icon_items

@table item_list
44x44画布上的图元数组；

@number scale
缩放比例，目标边长除以44；

@return table
缩放后的图元数组
]]
local function scale_icon_items(item_list, scale)
    local GEOMETRY_KEY_LIST = {
        cx = true, cy = true, r = true,
        x = true, y = true, w = true, h = true, radius = true,
        x1 = true, y1 = true, x2 = true, y2 = true,
    }
    local new_list = {}
    for i = 1, #item_list do
        local src_item = item_list[i]
        local new_item = {}
        for key, value in pairs(src_item) do
            if GEOMETRY_KEY_LIST[key] then
                new_item[key] = math.floor(value * scale + 0.5)
            elseif key == "width" then
                local new_width = math.floor(value * scale + 0.5)
                if new_width < MIN_STROKE_WIDTH then
                    new_width = MIN_STROKE_WIDTH
                end
                new_item[key] = new_width
            else
                new_item[key] = value
            end
        end
        new_list[i] = new_item
    end
    return new_list
end

-- 对外暴露的界面配色表，键名与COLOR_DEF一致，值为换算后的颜色值
dash_theme.COLOR = build_color_table(COLOR_DEF)

-- 对外暴露的配件类型色表，键名与TYPE_COLOR_DEF一致，值为换算后的颜色值
dash_theme.TYPE_COLOR = build_color_table(TYPE_COLOR_DEF)

-- 对外暴露的字号档位表
dash_theme.FONT_SIZE = FONT_SIZE_DEF

-- 图标画布边长
dash_theme.ICON_CANVAS = ICON_CANVAS

-- 把配色表逐项打进串口日志，核对实际传给airui的颜色值
for name, value in pairs(COLOR_DEF) do
    log.info("dash_theme", name,
        string.format("源0x%06X 换算0x%06X", value, dash_theme.COLOR[name]))
end

--[[
按配件类型生成图标图元数组；
图标先画在44x44的画布里，再按目标边长整体缩放，线条颜色统一由调用方传入；
认不出的类型按传感器处理；

@api dash_theme.build_icon_items(icon_kind, color, icon_size)

@string icon_kind
配件类型标识，取"light"、"ac"、"curtain"、"plug"、"sensor"、"lock"；

@number color
图标线条颜色，传换算后的颜色值；

@number or nil
icon_size
图标画布目标边长，不传则按44的原始大小返回；

@return table
shape图元数组，可直接交给airui.shape的items或set_items；

@usage
local items = dash_theme.build_icon_items("light", dash_theme.COLOR.WHITE, 30)
]]
function dash_theme.build_icon_items(icon_kind, color, icon_size)
    local item_list
    if icon_kind == "light" then
        item_list = build_light_icon_items(color)
    elseif icon_kind == "ac" then
        item_list = build_ac_icon_items(color)
    elseif icon_kind == "curtain" then
        item_list = build_curtain_icon_items(color)
    elseif icon_kind == "plug" then
        item_list = build_plug_icon_items(color)
    elseif icon_kind == "lock" then
        item_list = build_lock_icon_items(color)
    else
        item_list = build_sensor_icon_items(color)
    end
    if icon_size == nil or icon_size == ICON_CANVAS then
        return item_list
    end
    return scale_icon_items(item_list, icon_size / ICON_CANVAS)
end

--[[
算开关滑块在轨道里的位置；
滑块在轨道里靠左是关闭、靠右是开启，横向两端各留同样内边距，纵向按轨道高度居中；

@api dash_theme.knob_pos(track_w, track_h, knob_size, is_on)

@number track_w
开关轨道宽度，单位像素；

@number track_h
开关轨道高度，单位像素；

@number knob_size
开关滑块边长，单位像素；

@boolean is_on
开关状态，true为开启；

@return number, number
滑块的横坐标与纵坐标，都是相对轨道左上角的偏移

@usage
local knob_x, knob_y = dash_theme.knob_pos(34, 20, 16, true)
]]
function dash_theme.knob_pos(track_w, track_h, knob_size, is_on)
    local knob_y = math.floor((track_h - knob_size) / 2 + 0.5)
    local knob_x = KNOB_PAD_X
    if is_on then
        knob_x = track_w - knob_size - KNOB_PAD_X
    end
    return knob_x, knob_y
end

--[[
创建一张部件卡片；
卡片是深灰圆角方块，子控件的坐标原点是卡片的内容区左上角；
边框宽度取0，子控件坐标不需要再内缩；

@api dash_theme.card(parent, x, y, w, h)

@userdata or nil
parent
父对象，传nil则挂在当前屏幕上；

@number x
卡片左上角的横坐标，单位像素；

@number y
卡片左上角的纵坐标，单位像素；

@number w
卡片宽度，单位像素；

@number h
卡片高度，单位像素；

@return userdata
卡片容器对象；

@usage
local card = dash_theme.card(nil, 20, 164, 440, 92)
]]
function dash_theme.card(parent, x, y, w, h)
    local card_obj = airui.container({
        parent = parent,
        x = x, y = y, w = w, h = h,
        color = dash_theme.COLOR.CARD,
        radius = 20,
        border_width = 0,
    })
    return card_obj
end

--[[
创建一行文字；
文字左对齐或居中或右对齐，高度按字号加富余量给足，避免汉字上沿被裁；

@api dash_theme.label(parent, x, y, w, h, text, font_size, color, align)

@userdata or nil
parent
父对象，传nil则挂在当前屏幕上；

@number x
文字左上角的横坐标，单位像素；

@number y
文字左上角的纵坐标，单位像素；

@number w
文字宽度，单位像素；

@number h
文字高度，单位像素；

@string text
文字内容；

@number or nil
font_size
字号，不传则用正文档位；

@number or nil
color
文字颜色，不传则用主文字色；

@number or nil
align
对齐方式，取airui.TEXT_ALIGN_LEFT、airui.TEXT_ALIGN_CENTER、airui.TEXT_ALIGN_RIGHT，不传则左对齐；

@return userdata
文字对象；

@usage
local text = dash_theme.label(nil, 20, 20, 200, 30, "我的家", 20, nil, airui.TEXT_ALIGN_LEFT)
]]
function dash_theme.label(parent, x, y, w, h, text, font_size, color, align)
    local label_obj = airui.label({
        parent = parent,
        x = x, y = y, w = w, h = h,
        text = text,
        font_size = font_size or FONT_SIZE_DEF.BODY,
        color = color or dash_theme.COLOR.TEXT,
        align = align or airui.TEXT_ALIGN_LEFT,
    })
    return label_obj
end

--[[
创建一个胶囊按钮；
胶囊由一块圆角底板和一行居中文字组成，底板和文字分开返回，
播放暂停这种状态翻转只改这两个对象的文字与颜色，不销毁重建；

@api dash_theme.pill(parent, x, y, w, h, text, bg_color, text_color)

@userdata or nil
parent
父对象，传nil则挂在当前屏幕上；

@number x
胶囊左上角的横坐标，单位像素；

@number y
胶囊左上角的纵坐标，单位像素；

@number w
胶囊宽度，单位像素；

@number h
胶囊高度，单位像素；

@string text
胶囊文字，同时用作回调里反查身份的标识；

@number or nil
bg_color
胶囊底色，不传则用卡片凸起色；

@number or nil
text_color
胶囊文字色，不传则用主文字色；

@return userdata, userdata
胶囊底板对象与胶囊文字对象；

@usage
local pill_bg, pill_text = dash_theme.pill(nil, 352, 193, 72, 34, "暂停")
]]
function dash_theme.pill(parent, x, y, w, h, text, bg_color, text_color)
    local pill_bg = airui.container({
        parent = parent,
        x = x, y = y, w = w, h = h,
        color = bg_color or dash_theme.COLOR.CARD_HI,
        radius = h / 2,
        border_width = 0,
    })
    local pill_text = airui.label({
        parent = pill_bg,
        x = 0, y = 0, w = w, h = h,
        text = text,
        font_size = FONT_SIZE_DEF.BODY,
        color = text_color or dash_theme.COLOR.TEXT,
        align = airui.TEXT_ALIGN_CENTER,
    })
    return pill_bg, pill_text
end

return dash_theme
