--[[
@module  dash_page
@summary 86盒深色部件仪表盘的整页排布，表盘、日期与四个部件的位置调度
@version 1.0
@date    2026.11.04
@author  江访
@usage
本文件为86盒深色部件仪表盘的整页排布，核心业务逻辑为：
1、左上一块大表盘，时间外面套一圈虚线点环，右上是日期，星期与月是小字、日数字放到72的大字号上；
2、下半左边是音乐部件，右边上面是月历部件、下面是家庭部件；
3、表盘时间走设备实时时刻，每秒刷新一次时间、日期和日数字；
4、四个部件各自建卡片区，本文件只管给它们摆位置，不碰部件内部；

本文件的对外接口有1个：
1、dash_page.create()：创建整页并启动走时刷新

更多说明参考本目录下的readme.md文件
]]

local dash_theme = require "dash_theme"
local dash_data = require "dash_data"
local dash_widget_music = require "dash_widget_music"
local dash_widget_calendar = require "dash_widget_calendar"
local dash_widget_home = require "dash_widget_home"

local dash_page = {}

-- ==================== 页面布局参数 ====================

local SCREEN_W = 480         -- 屏幕宽度
local SCREEN_H = 480         -- 屏幕高度

-- 大表盘，直接画在整屏背景上，不套卡片
local CLOCK_X = 66           -- 时间文字横坐标
local CLOCK_Y = 58           -- 时间文字纵坐标
local CLOCK_W = 160          -- 时间文字宽度
local CLOCK_H = 52           -- 时间文字高度
local RING_CENTER_X = 146    -- 点环圆心横坐标
local RING_CENTER_Y = 84     -- 点环圆心纵坐标
local RING_RADIUS = 64       -- 点环半径，比时间文字的墨迹范围留一圈余量
local RING_DOT_R = 3         -- 点环上每个点的半径
local RING_DOT_COUNT = 36    -- 点环上点的个数

-- 日期，同样直接画在整屏背景上
local DATE_X = 290           -- 星期与月的横坐标
local DATE_Y = 42            -- 星期与月的纵坐标
local DATE_W = 170           -- 星期与月的宽度
local DATE_H = 26            -- 星期与月的高度
local DAY_X = 290            -- 日数字的横坐标
local DAY_Y = 72             -- 日数字的纵坐标
local DAY_W = 170            -- 日数字的宽度
local DAY_H = 80             -- 日数字的高度

-- 四个部件的位置，内部排布由各部件自己管
local MUSIC_X = 20           -- 音乐部件横坐标
local MUSIC_Y = 164          -- 音乐部件纵坐标
local MUSIC_W = 440          -- 音乐部件宽度
local MUSIC_H = 92           -- 音乐部件高度
local CALENDAR_X = 20        -- 月历部件横坐标
local CALENDAR_Y = 268       -- 月历部件纵坐标
local CALENDAR_W = 252       -- 月历部件宽度
local CALENDAR_H = 194       -- 月历部件高度
local HOME_X = 284           -- 家庭部件横坐标
local HOME_Y = 268           -- 家庭部件纵坐标
local HOME_W = 176           -- 家庭部件宽度
local HOME_H = 194           -- 家庭部件高度

-- 走时刷新周期，1秒一次
local CLOCK_REFRESH_MS = 1000

-- ==================== 运行状态 ====================

-- 表盘时间文字对象
local time_label = nil

-- 星期与月文字对象
local date_label = nil

-- 日数字文字对象
local day_label = nil

-- ==================== 内部函数 ====================

--[[
生成表盘外面那圈虚线点环的图元；
点均匀摆在一个圆周上，图元画在2倍半径加点半径的方框里，圆心取方框正中；

@function (内部函数) build_ring_items

@return table
shape图元数组
]]
local function build_ring_items()
    local local_center = RING_RADIUS + RING_DOT_R
    local items = {}
    for i = 1, RING_DOT_COUNT do
        -- 角度取弧度，从3点钟方向起算，一圈均匀分RING_DOT_COUNT份
        local angle = i * 2 * math.pi / RING_DOT_COUNT
        local dot_x = local_center + math.cos(angle) * RING_RADIUS
        local dot_y = local_center + math.sin(angle) * RING_RADIUS
        items[i] = {
            type = "circle",
            cx = math.floor(dot_x + 0.5),
            cy = math.floor(dot_y + 0.5),
            r = RING_DOT_R,
            color = dash_theme.COLOR.TEXT_SUB,
            width = 1,
            fill = true,
            fill_color = dash_theme.COLOR.TEXT_SUB,
        }
    end
    return items
end

--[[
搭建大表盘；
先画点环再压时间文字，创建顺序决定绘制层级；

@function (内部函数) create_clock

@userdata page_root
页面根容器；

@usage
create_clock(page_root)
]]
local function create_clock(page_root)
    local ring_size = (RING_RADIUS + RING_DOT_R) * 2
    airui.shape({
        parent = page_root,
        x = RING_CENTER_X - RING_RADIUS - RING_DOT_R,
        y = RING_CENTER_Y - RING_RADIUS - RING_DOT_R,
        w = ring_size, h = ring_size,
        items = build_ring_items(),
    })

    time_label = dash_theme.label(page_root, CLOCK_X, CLOCK_Y, CLOCK_W, CLOCK_H,
        "", dash_theme.FONT_SIZE.CLOCK,
        dash_theme.COLOR.TEXT, airui.TEXT_ALIGN_CENTER)
end

--[[
搭建日期区；
上面一行是星期与月，用品红小字；下面是日数字，用72的大字号；

@function (内部函数) create_date

@userdata page_root
页面根容器；

@usage
create_date(page_root)
]]
local function create_date(page_root)
    date_label = dash_theme.label(page_root, DATE_X, DATE_Y, DATE_W, DATE_H,
        "", dash_theme.FONT_SIZE.TITLE,
        dash_theme.COLOR.ACCENT, airui.TEXT_ALIGN_LEFT)

    day_label = dash_theme.label(page_root, DAY_X, DAY_Y, DAY_W, DAY_H,
        "", dash_theme.FONT_SIZE.DAY,
        dash_theme.COLOR.TEXT, airui.TEXT_ALIGN_LEFT)
end

--[[
刷新表盘与日期；
一次把时间、星期与月、日数字三处都刷成当前时刻；

@function (内部函数) refresh_clock

@usage
refresh_clock()
]]
local function refresh_clock()
    time_label:set_text(dash_data.get_clock_text())
    date_label:set_text(dash_data.get_date_text())
    day_label:set_text(dash_data.get_day_text())
end

--[[
走时定时器的回调函数；
每秒被调用一次，刷一遍表盘与日期；

@function (内部函数) on_clock_timer_cbfunc

@usage
on_clock_timer_cbfunc()
]]
local function on_clock_timer_cbfunc()
    refresh_clock()
end

-- ==================== 对外接口 ====================

--[[
创建整页并启动走时刷新；
先摆表盘和日期，再依次摆音乐、月历、家庭三个部件，最后刷一遍当前时刻并起走时定时器；

@api dash_page.create(page_root)

@userdata page_root
页面根容器，由home_dash_ui_main创建；

@usage
dash_page.create(page_root)
]]
function dash_page.create(page_root)
    create_clock(page_root)
    create_date(page_root)

    dash_widget_music.create(page_root, MUSIC_X, MUSIC_Y, MUSIC_W, MUSIC_H)
    dash_widget_calendar.create(page_root, CALENDAR_X, CALENDAR_Y, CALENDAR_W, CALENDAR_H)
    dash_widget_home.create(page_root, HOME_X, HOME_Y, HOME_W, HOME_H)

    refresh_clock()
    sys.timerLoopStart(on_clock_timer_cbfunc, CLOCK_REFRESH_MS)

    log.info("dash_page", "仪表盘创建完成", SCREEN_W, SCREEN_H)
end

return dash_page
