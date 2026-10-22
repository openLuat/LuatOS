--[[
@module  ui_status
@summary 顶部状态栏（1024x600）：WLAN 信号强度 / 时间 / USB 摄像头 / 微信通话状态
@version 1.2.0
@date    2026.10.21
]]

local T   = require "ui_theme"
local net = require "net_mgr"
local cam = require "usb_cam"
local wx  = require "wx_call"

local M = {}

local BAR_H = 88

local WEEK = { "周日", "周一", "周二", "周三", "周四", "周五", "周六" }

local lbl_time, lbl_sec, lbl_date
local lbl_wifi
local bar_cells = {}
local dot_cam, lbl_cam
local dot_wx, lbl_wx

-- 脏检查缓存：值没变就不调用 set_*，避免无谓的重排与局部刷新
local last_hhmm, last_sec, last_date
local last_sig, last_wifi
local last_cam, last_wx

local function box(parent, x, y, w, h, color, radius)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = color, radius = radius or 0,
    })
end

local function text(parent, str, x, y, w, h, size, color, align)
    return airui.label({
        parent = parent, text = str, x = x, y = y, w = w, h = h,
        font = "hzfont", font_size = size, color = color,
        align = align or airui.TEXT_ALIGN_LEFT,
    })
end

local function icon(parent, symbol, x, y, w, h, size, color)
    return airui.label({
        parent = parent, text = "", symbol = symbol, x = x, y = y, w = w, h = h,
        font = "hzfont", font_size = size, color = color, align = airui.TEXT_ALIGN_CENTER,
    })
end

-- 秒级刷新只碰秒位（约 1/8 面积）；时分与日期只在真正变化时才重绘
local function clock()
    local t = os.date("*t")

    if lbl_time then
        local s = string.format("%02d:%02d", t.hour, t.min)
        if s ~= last_hhmm then
            last_hhmm = s
            lbl_time:set_text(s)
        end
    end
    if lbl_sec then
        local s = string.format("%02d", t.sec)
        if s ~= last_sec then
            last_sec = s
            lbl_sec:set_text(s)
        end
    end
    if lbl_date then
        local s = string.format("%04d-%02d-%02d %s", t.year, t.month, t.day, WEEK[t.wday] or "")
        if s ~= last_date then
            last_date = s
            lbl_date:set_text(s)
        end
    end
end

local function set_signal(level)
    if level == last_sig then return end
    last_sig = level
    for i = 1, 4 do
        if bar_cells[i] then
            bar_cells[i]:set_color(i <= level and T.ORANGE or T.LINE)
        end
    end
end

local function set_wifi(s)
    if s == last_wifi then return end
    last_wifi = s
    if lbl_wifi then lbl_wifi:set_text(s) end
end

local CAM_STATE = {
    online      = { T.GREEN, "在线" },
    warming     = { T.YELLOW, "预热中" },
    offline     = { T.RED, "未连接" },
    disabled    = { T.YELLOW, "已关闭" },
    unsupported = { T.YELLOW, "不支持" },
}

local WX_STATE = {
    offline    = { T.TEXT_DIM, "未就绪" },
    idle       = { T.GREEN, "空闲" },
    connecting = { T.YELLOW, "连接中" },
    ringing    = { T.ORANGE, "来电" },
    talking    = { T.ORANGE, "通话中" },
}

local function apply_cam(state)
    if state == last_cam then return end
    last_cam = state
    local m = CAM_STATE[state] or { T.TEXT_DIM, "检测中" }
    if dot_cam then dot_cam:set_color(m[1]) end
    if lbl_cam then lbl_cam:set_text(m[2]) end
end

local function apply_wx(state)
    if state == last_wx then return end
    last_wx = state
    local m = WX_STATE[state] or { T.TEXT_DIM, wx.name(state) }
    if dot_wx then dot_wx:set_color(m[1]) end
    if lbl_wx then lbl_wx:set_text(m[2]) end
end

--- 创建顶栏（高 88）
-- @param parent 父容器
function M.create(parent)
    local W = UI_W or 1024
    local bar = box(parent, 0, 0, W, BAR_H, T.BAR)

    -- 顶部橙色光条 + 底部分隔线
    box(parent, 0, 0, W, 4, T.ORANGE)
    box(bar, 0, BAR_H - 1, W, 1, T.LINE)

    -- 品牌
    text(bar, "智能门禁", 28, 16, 220, 40, 32, T.ORANGE)
    text(bar, "SMART DOOR · AIR8101B", 28, 58, 240, 18, 11, T.TEXT_DIM)

    box(bar, 300, 18, 1, 52, T.LINE)

    -- WLAN 信号
    icon(bar, airui.SYMBOL_WIFI, 316, 20, 34, 30, 26, T.ORANGE)
    lbl_wifi = text(bar, "未连接", 356, 18, 112, 24, 16, T.TEXT_SUB)
    for i = 1, 4 do
        local h = 8 + (i - 1) * 4
        bar_cells[i] = box(bar, 358 + (i - 1) * 12, 64 - h, 8, h, T.LINE, 2)
    end

    box(bar, 478, 18, 1, 52, T.LINE)

    -- 时间：时分为大字号（一分钟才变一次），秒位单独小字号（每秒只重绘这一小块）
    lbl_time = text(bar, "00:00", 496, 6, 132, 50, 40, T.TEXT)
    text(bar, ":", 626, 20, 10, 30, 22, T.TEXT_DIM)
    lbl_sec  = text(bar, "00", 636, 20, 56, 30, 22, T.TEXT_SUB)
    lbl_date = text(bar, "---- -- --", 496, 60, 232, 20, 13, T.TEXT_DIM)

    box(bar, 740, 18, 1, 52, T.LINE)

    -- USB 摄像头
    text(bar, "USB CAM", 760, 16, 140, 18, 13, T.TEXT_DIM)
    dot_cam = box(bar, 760, 50, 10, 10, T.TEXT_DIM, 5)
    lbl_cam = text(bar, "检测中", 778, 42, 116, 26, 17, T.TEXT_SUB)

    box(bar, 900, 18, 1, 52, T.LINE)

    -- 微信通话
    text(bar, "微信通话", 918, 16, 100, 18, 13, T.TEXT_DIM)
    dot_wx = box(bar, 918, 50, 10, 10, T.TEXT_DIM, 5)
    lbl_wx = text(bar, "空闲", 936, 42, 80, 26, 17, T.TEXT_SUB)

    -- 数据订阅
    sys.subscribe("NET_STATUS", function(n)
        if not n then return end
        if n.ready and type(n.rssi) == "number" then
            set_signal(net.level(n.rssi))
            set_wifi(string.format("%d dBm", n.rssi))
        elseif n.ready then
            set_signal(4)
            set_wifi("已连接")
        else
            set_signal(0)
            set_wifi("未连接")
        end
    end)

    sys.subscribe("USB_CAM", apply_cam)
    sys.subscribe("WX_CALL_STATE", function(state) apply_wx(state) end)

    -- 初始状态
    set_signal(0)
    apply_cam(cam.state)
    apply_wx(wx.state)

    clock()
    sys.timerLoopStart(clock, 1000)
end

return M
