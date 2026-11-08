--[[
@module  forecast
@summary 七天预报页：左滑从右侧滑入，七列等宽卡片（天气图标 + 高低温 + 温度区间条）
@version 1.0
@date    2026.11.08

=== 为什么整页是一个容器 ===
滑动是「容器整体 set_pos」实现的，比逐个控件移动便宜得多，也不会出现
"文字先到、图标后到"的错位。容器自带整页底色，滑入时把桌面盖住。

=== 背景要和桌面一致 ===
页面不能只是一块深蓝底（滑进来像换了个 App），也不能透明（桌面上的时间/城市
会从卡片缝里透出来跟预报文字叠在一起）。所以 fc_shape 里按 scene 给的同一套
环境色重画一遍天空渐变 + 草地，等于"同一片天，上面浮着七张卡片"。
天空色 5 分钟才变一次，set_sky 内部按颜色缓存，不会每帧重画。

=== 页内控件分成两层 ===
fc_shape（天空 / 卡片底 / 图标 / 温度条）先建，标签后建 —— LVGL 同一父对象内
后创建的子对象画在上面，顺序反过来标签会被卡片底色盖住。

=== 文字避坑 ===
hzfont 没有 "·"(U+00B7) 字形，标题里用 ASCII 的 "|" 分隔城市名。
]]

local draw = require "draw"
local hud = require "hud"
local conf = require "conf"

local M = {}

local W, H = conf.W, conf.H
local F = conf.F

local C = {
    bg      = 0x0A1526,   -- 容器兜底色：fc_shape 万一没画天空，至少是一块深色而不是透明
    card    = 0x0E1B33,
    line    = 0x5C7699,
    ink     = 0xF4F8FF,
    ink2    = 0xDCE7F7,
    ink3    = 0xA8B8D0,
    track   = 0x2A3F63,
    today   = 0xFFC84A,
}

-- CARD_Y 116：标题带（0..108）压不到卡片顶边
local CARD_X0, CARD_Y, CARD_W, CARD_H, CARD_GAP = 26, 116, 130, 396, 10

local COND_COLOR = {
    ["晴"] = 0xFFC84A, ["多云"] = 0x8FD0EA, ["阴"] = 0x9FB0CC,
    ["雨"] = 0x5FA8E8, ["雪"] = 0xE8F2FF,
}

local panel, fc_shape, P
local lb_title, lb_sub, lb_foot
local cards = {}

-- airui.label 构造配置不含 align 字段，必须建完再 set_align（见 hud.lua 同名注释）
local function label(parent, x, y, w, h, text, size, color, align)
    local o = airui.label({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text or "", font_size = size, color = color or C.ink,
    })
    o:set_align(align or airui.TEXT_ALIGN_CENTER)
    return o
end

local function card_x(i)
    return CARD_X0 + (i - 1) * (CARD_W + CARD_GAP)
end

-- ==================== 卡片底 / 图标 / 温度条 ====================

local last_wx, last_env
local last_sky_key

--- 重画整页：天空背景（与桌面同一套色）+ 七张卡片
local function render()
    local e = last_env
    local days = (last_wx and last_wx.daily) or {}

    -- 全局温度范围：所有卡片共用一条刻度，条形长度才有可比性
    local lo, hi = 999, -999
    for i = 1, 7 do
        local d = days[i]
        if d and d.high and d.low then
            if d.low < lo then lo = d.low end
            if d.high > hi then hi = d.high end
        end
    end
    if hi - lo < 6 then hi = lo + 6 end

    P:reset()

    -- 背景：照抄桌面 sky 层（60 条渐变 + 草地），滑进来才是"同一片天"
    if e then
        local hor = e.ground_y or 470
        local bands = 60
        local bh = math.ceil(hor / bands)
        for i = 0, bands - 1 do
            local t = (i + 0.5) / bands
            local c
            if t < 0.55 then
                c = draw.mix(e.sky_top, e.sky_mid, t / 0.55)
            else
                c = draw.mix(e.sky_mid, e.sky_horizon, (t - 0.55) / 0.45)
            end
            P:box(0, i * bh, W, bh + 1, c, 255)
        end
        P:box(0, hor, W, H - hor, e.ground, 255)
        P:line(0, hor, W, hor, e.ground_light, 2, 255)
    end

    -- 标题带 / 页脚带：白字压在浅色天空上也读得清
    -- 分档渐变，硬边会变成一条横贯屏幕的分界线
    for i = 0, 5 do
        local y0, y1 = math.floor(i * 108 / 6), math.floor((i + 1) * 108 / 6)
        P:box(0, y0, W, y1 - y0, 0x061020, 100 - 16 * i)
    end
    for i = 0, 5 do
        local y0, y1 = 528 + math.floor(i * 72 / 6), 528 + math.floor((i + 1) * 72 / 6)
        P:box(0, y0, W, y1 - y0, 0x061020, 26 + 16 * i)
    end

    for i = 1, 7 do
        local x = card_x(i)
        local d = days[i]
        local cond = d and d.cond or "多云"

        -- 卡片半透明：天空的颜色透进来一点，才像浮在背景上而不是贴了张黑纸
        P:box(x, CARD_Y, CARD_W, CARD_H, C.card, 205, 18)
        P:frame(x, CARD_Y, CARD_W, CARD_H, C.line, 1, 150, 18)
        if i == 1 then
            P:box(x + 22, CARD_Y + 2, CARD_W - 44, 4, C.today, 255, 2)
        end

        hud.icon(P, x + CARD_W / 2, CARD_Y + 122, cond, false, 0.95)

        -- 温度区间条
        local bar_x, bar_y, bar_w, bar_h = x + (CARD_W - 14) / 2, CARD_Y + 300, 14, 84
        P:box(bar_x, bar_y, bar_w, bar_h, C.track, 255, 6)
        if d and d.high and d.low then
            local t_hi = (hi - d.high) / (hi - lo)
            local t_lo = (hi - d.low) / (hi - lo)
            local fy = bar_y + t_hi * bar_h
            local fh = (t_lo - t_hi) * bar_h
            if fh < 6 then fh = 6 end
            P:box(bar_x, fy, bar_w, fh, COND_COLOR[cond] or C.ink2, 255, 6)
        end
    end

    P:finish()
    fc_shape:set_items(P.items)
end

-- ==================== 对外接口 ====================

function M.build(parent)
    panel = airui.container({
        parent = parent, x = W, y = 0, w = W, h = H,
        color = C.bg, color_opacity = 252, radius = 0, border_width = 0,
    })
    panel:set_hidden(true)

    P = draw.pool()
    fc_shape = airui.shape({ parent = panel, x = 0, y = 0, w = W, h = H })

    lb_title = label(panel, 36, 24, 640, 54, "未来七天", F.big, C.ink, airui.TEXT_ALIGN_LEFT)
    lb_sub = label(panel, 700, 34, 288, 32, "右滑返回", F.tiny, C.ink3, airui.TEXT_ALIGN_RIGHT)

    for i = 1, 7 do
        local x = card_x(i)
        local c = {}
        c.wd = label(panel, x, CARD_Y + 20, CARD_W, 38, "--", F.mid, C.ink)
        c.date = label(panel, x, CARD_Y + 60, CARD_W, 26, "--", F.tiny, C.ink3)
        c.cond = label(panel, x, CARD_Y + 154, CARD_W, 32, "--", F.small, C.ink2)
        c.high = label(panel, x, CARD_Y + 196, CARD_W, 56, "--", F.big, C.ink)
        c.low = label(panel, x, CARD_Y + 252, CARD_W, 38, "--", F.small, C.ink3)
        cards[i] = c
    end

    lb_foot = label(panel, 26, 546, W - 52, 28,
        "数据来源 open-meteo  |  每 30 分钟自动刷新", F.tiny, C.ink3)
end

--- 天空配色同步（时间/日夜变化时调用；内部按颜色缓存，不会每帧重画）
function M.set_sky(e)
    if not fc_shape or not e then return end
    last_env = e
    local key = string.format("%d|%d|%d|%d", e.sky_top, e.sky_mid, e.sky_horizon, e.ground)
    if key == last_sky_key then return end
    last_sky_key = key
    render()
end

--- 刷新数据（天气更新时调用一次）
function M.set_data(wx)
    if not panel then return end
    last_wx = wx

    local city = (wx and wx.city) or ""
    lb_title:set_text(city ~= "" and ("未来七天 | " .. city) or "未来七天")

    local days = (wx and wx.daily) or {}
    for i = 1, 7 do
        local d = days[i]
        local c = cards[i]
        if d then
            c.wd:set_text(d.wd or "--")
            c.date:set_text(d.date or "--")
            c.cond:set_text(d.cond or "--")
            c.high:set_text(d.high and (tostring(d.high) .. "℃") or "--")
            c.low:set_text(d.low and (tostring(d.low) .. "℃") or "--")
        else
            c.wd:set_text("--"); c.date:set_text("--"); c.cond:set_text("--")
            c.high:set_text("--"); c.low:set_text("--")
        end
    end

    render()
end

function M.show() if panel then panel:set_hidden(false) end end
function M.hide() if panel then panel:set_hidden(true) end end
function M.set_x(x) if panel then panel:set_pos(x, 0) end end
function M.panel() return panel end

return M
