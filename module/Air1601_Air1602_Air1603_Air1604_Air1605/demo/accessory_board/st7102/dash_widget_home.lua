--[[
@module  dash_widget_home
@summary 86盒深色部件仪表盘的家庭部件，配件列表与开关
@version 1.0
@date    2026.11.04
@author  江访
@usage
本文件为86盒深色部件仪表盘的家庭部件，核心业务逻辑为：
1、卡片顶上一行写「我的家」，第二行写本部件开了几个配件；
2、下面是3行配件，一行一个，左边类型图标圆底、中间配件名、右边一个小开关；
3、点一行任意一块都翻转这个配件的开关，图标圆底和开关跟着变色；
4、开关是两个airui.container拼的，不用airui.switch，因为它的配色键过不了这块屏的颜色换算；

本文件的对外接口有1个：
1、dash_widget_home.create()：创建家庭部件

更多说明参考本目录下的readme.md文件
]]

local dash_theme = require "dash_theme"
local dash_data = require "dash_data"

local dash_widget_home = {}

-- ==================== 部件内部布局 ====================

-- 卡片头部
local HEAD_X = 14         -- 标题横坐标
local HEAD_Y = 10         -- 标题纵坐标
local HEAD_W = 120        -- 标题宽度
local HEAD_H = 26         -- 标题高度
local SUMMARY_X = 14      -- 汇总文字横坐标
local SUMMARY_Y = 38      -- 汇总文字纵坐标
local SUMMARY_W = 148     -- 汇总文字宽度
local SUMMARY_H = 22      -- 汇总文字高度

-- 配件行
local ROW_FIRST_Y = 70    -- 第一行的纵坐标
local ROW_STEP = 42       -- 行间距
local ROW_H = 36          -- 行高
local ICON_X = 14         -- 图标圆底横坐标
local ICON_SIZE = 30      -- 图标圆底边长
local NAME_X = 52         -- 配件名横坐标
local NAME_W = 72         -- 配件名宽度
local TRACK_X = 128       -- 开关轨道横坐标
local TRACK_Y = 8         -- 开关轨道在行内的纵坐标
local TRACK_W = 34        -- 开关轨道宽度
local TRACK_H = 20        -- 开关轨道高度
local KNOB_SIZE = 16      -- 开关滑块边长

-- 配件行数，与dash_data.HOME_LIST的条数一致
local ROW_COUNT = 3

-- ==================== 运行状态 ====================

-- 配件行控件表，下标即行号
local row_obj_list = {}

-- 底部汇总文字对象
local summary_label = nil

-- ==================== 内部函数 ====================

--[[
取某一行上的配件数据；
行号超过配件条数时返回nil；

@function (内部函数) get_row_device

@number row_index
配件行号，从1开始；

@return table or nil
配件数据，行空则返回nil
]]
local function get_row_device(row_index)
    return dash_data.HOME_LIST[row_index]
end

--[[
刷新一行配件的显示；
按开关状态改图标圆底颜色、图标线条、配件名颜色、开关轨道颜色和滑块位置；

@function (内部函数) refresh_row

@number row_index
配件行号，从1开始；

@usage
refresh_row(1)
]]
local function refresh_row(row_index)
    local obj = row_obj_list[row_index]
    local device_item = get_row_device(row_index)
    if device_item == nil then
        return
    end
    if device_item.on then
        obj.badge:set_color(dash_theme.TYPE_COLOR[device_item.icon])
        obj.icon:set_items(dash_theme.build_icon_items(device_item.icon,
            dash_theme.COLOR.WHITE, ICON_SIZE))
        obj.name_label:set_color(dash_theme.COLOR.TEXT)
        obj.track:set_color(dash_theme.COLOR.ACCENT)
    else
        obj.badge:set_color(dash_theme.COLOR.CARD_HI)
        obj.icon:set_items(dash_theme.build_icon_items(device_item.icon,
            dash_theme.COLOR.TEXT_SUB, ICON_SIZE))
        obj.name_label:set_color(dash_theme.COLOR.TEXT_SUB)
        obj.track:set_color(dash_theme.COLOR.TRACK_OFF)
    end
    local knob_x, knob_y = dash_theme.knob_pos(TRACK_W, TRACK_H, KNOB_SIZE, device_item.on)
    obj.knob:set_pos(knob_x, knob_y)
    obj.name_label:set_text(device_item.name)
end

--[[
统计家庭配件的总数和已开启数；

@function (内部函数) count_home_device

@return number, number
配件总数与已开启数
]]
local function count_home_device()
    local on_count = 0
    for i = 1, #dash_data.HOME_LIST do
        if dash_data.HOME_LIST[i].on then
            on_count = on_count + 1
        end
    end
    return #dash_data.HOME_LIST, on_count
end

--[[
刷新汇总文字；
写成本部件开了几个配件；

@function (内部函数) refresh_summary

@usage
refresh_summary()
]]
local function refresh_summary()
    local total_count, on_count = count_home_device()
    summary_label:set_text(string.format("%d/%d 已开启", on_count, total_count))
end

--[[
刷新整个家庭部件；
逐行刷新配件，最后刷新汇总文字；

@function (内部函数) refresh_home

@usage
refresh_home()
]]
local function refresh_home()
    for i = 1, ROW_COUNT do
        refresh_row(i)
    end
    refresh_summary()
end

--[[
翻转一行配件的开关状态；
翻转之后刷新这一行和汇总文字；

@function (内部函数) toggle_row

@number row_index
配件行号，从1开始；

@usage
toggle_row(1)
]]
local function toggle_row(row_index)
    local device_item = get_row_device(row_index)
    if device_item == nil then
        return
    end
    device_item.on = not device_item.on
    refresh_row(row_index)
    refresh_summary()
    log.info("dash_widget_home", "开关翻转", device_item.name, tostring(device_item.on))
end

--[[
把一行的点击回调绑到这一行上的每一个可点控件；
图标圆底、配件名、开关轨道、开关滑块都要绑，点哪一块都能翻转开关；
图标图元本身不带点击，事件会落到它的父圆底上；

@function (内部函数) bind_row_click

@table row_obj
一行配件的控件对象表；

@function click_func
点击回调函数；

@usage
bind_row_click(row_obj_list[1], ROW_CLICK_FUNC_LIST[1])
]]
local function bind_row_click(row_obj, click_func)
    row_obj.badge:set_on_click(click_func)
    row_obj.name_label:set_on_click(click_func)
    row_obj.track:set_on_click(click_func)
    row_obj.knob:set_on_click(click_func)
end

-- ==================== 回调函数 ====================

-- 3行配件的点击回调，一人一个具名函数，行号写死在函数体里
-- airui的sender是每次回调新建的对象，跟控件对象比对恒为假，所以不能靠sender认行号
local function on_home_1_click(sender)
    toggle_row(1)
end

local function on_home_2_click(sender)
    toggle_row(2)
end

local function on_home_3_click(sender)
    toggle_row(3)
end

-- 配件行点击回调表，下标即行号
local ROW_CLICK_FUNC_LIST = {
    on_home_1_click,
    on_home_2_click,
    on_home_3_click,
}

-- ==================== 部件搭建 ====================

--[[
搭建一行配件；
一行由图标圆底、图标图元、配件名、开关轨道和开关滑块组成，返回控件对象表；

@function (内部函数) create_row

@userdata card_obj
家庭部件卡片对象；

@number row_index
配件行号，从1开始，决定这一行的纵坐标；

@return table
本行的控件对象表
]]
local function create_row(card_obj, row_index)
    local row_y = ROW_FIRST_Y + (row_index - 1) * ROW_STEP

    local badge_obj = airui.container({
        parent = card_obj,
        x = ICON_X, y = row_y + math.floor((ROW_H - ICON_SIZE) / 2),
        w = ICON_SIZE, h = ICON_SIZE,
        color = dash_theme.COLOR.CARD_HI,
        radius = math.floor(ICON_SIZE / 2),
        border_width = 0,
    })

    local icon_obj = airui.shape({
        parent = badge_obj,
        x = 0, y = 0, w = ICON_SIZE, h = ICON_SIZE,
        items = dash_theme.build_icon_items("sensor", dash_theme.COLOR.TEXT_SUB, ICON_SIZE),
    })

    local name_obj = dash_theme.label(card_obj, NAME_X, row_y, NAME_W, ROW_H,
        "", dash_theme.FONT_SIZE.BODY, dash_theme.COLOR.TEXT_SUB, airui.TEXT_ALIGN_LEFT)

    local track_obj = airui.container({
        parent = card_obj,
        x = TRACK_X, y = row_y + TRACK_Y, w = TRACK_W, h = TRACK_H,
        color = dash_theme.COLOR.TRACK_OFF,
        radius = math.floor(TRACK_H / 2),
        border_width = 0,
    })

    local knob_obj = airui.container({
        parent = track_obj,
        x = 0, y = 0, w = KNOB_SIZE, h = KNOB_SIZE,
        color = dash_theme.COLOR.KNOB,
        radius = math.floor(KNOB_SIZE / 2),
        border_width = 0,
    })

    return {
        badge = badge_obj,
        icon = icon_obj,
        name_label = name_obj,
        track = track_obj,
        knob = knob_obj,
    }
end

-- ==================== 对外接口 ====================

--[[
创建家庭部件；
部件自己建一块卡片，标题、汇总、配件行依次挂在卡片下面，
内部布局按176x194的部件尺寸排的，改尺寸要同步改上面的布局常量；

@api dash_widget_home.create(parent, x, y, w, h)

@userdata or nil
parent
父对象，传nil则挂在当前屏幕上；

@number x
部件左上角的横坐标，单位像素；

@number y
部件左上角的纵坐标，单位像素；

@number w
部件宽度，单位像素；

@number h
部件高度，单位像素；

@usage
dash_widget_home.create(page_root, 284, 268, 176, 194)
]]
function dash_widget_home.create(parent, x, y, w, h)
    local card_obj = dash_theme.card(parent, x, y, w, h)

    dash_theme.label(card_obj, HEAD_X, HEAD_Y, HEAD_W, HEAD_H,
        "我的家", dash_theme.FONT_SIZE.TITLE,
        dash_theme.COLOR.TEXT, airui.TEXT_ALIGN_LEFT)

    summary_label = dash_theme.label(card_obj, SUMMARY_X, SUMMARY_Y, SUMMARY_W, SUMMARY_H,
        "", dash_theme.FONT_SIZE.BODY,
        dash_theme.COLOR.ACCENT, airui.TEXT_ALIGN_LEFT)

    for i = 1, ROW_COUNT do
        row_obj_list[i] = create_row(card_obj, i)
        bind_row_click(row_obj_list[i], ROW_CLICK_FUNC_LIST[i])
    end

    refresh_home()
    log.info("dash_widget_home", "家庭部件创建完成", ROW_COUNT)
end

return dash_widget_home
