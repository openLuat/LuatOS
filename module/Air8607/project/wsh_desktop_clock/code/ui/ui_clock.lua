--[[
@module  ui_clock
@summary 桌面时钟主界面：大时钟 + 日期 + 干支生肖 + 当月日历 + 倒计时
@author  王世豪
@version 1.0
@date    2026.10.26

=== 布局（1024x600 横屏）===
左侧 0..620    时钟区（时分大号 + 秒 + 日期 + 星期/干支生肖）
右侧 620..1000 当月日历（7 列 x 6 行，固定 42 格）
底部 44..760   倒计时卡片区（最多 3 个）
右下角         设置按钮（由 main 挂到 M.on_settings）

=== 刷新策略 ===
main 每秒调 M.refresh()：
 - 时/分/秒：值变了才 set_text（LVGL 每次 set_text 都会标脏，白重绘会掉帧）
 - 日期相关的（月历、今天高亮、倒计时）：只在跨天时重算，不是每秒
]]
local conf = require "conf"
local theme = require "theme"
local du = require "date_util"
local rtc_util = require "rtc_util"

local M = {}

local C = theme.C
local SW, SH = conf.W, conf.H

local root = nil
local lb_hm, lb_sec, lb_date, lb_week, lb_zodiac, lb_month
local cells = {}
local ev_name, ev_days = {}, {}

-- 由 main 注入：点击「设置」时要做的事
M.on_settings = nil

-- Lua 侧缓存：避免每个 tick 都 set_text
local cache = { hm = "", sec = "", date = "" }

local CELL_W, CELL_H = 52, 46
local GRID_X, GRID_Y = 636, 132

-- ==================== 构建 ====================
local function build_clock_area(parent)
    lb_hm     = theme.label(parent, 56, 92, 460, 170, "00:00", 132, C.ink)
    lb_sec    = theme.label(parent, 520, 148, 110, 72, "00", 46, C.accent)
    lb_date   = theme.label(parent, 60, 266, 560, 52, "", 34, C.ink)
    lb_week   = theme.label(parent, 60, 326, 560, 42, "", 26, C.ink2)
    lb_zodiac = theme.label(parent, 60, 372, 560, 38, "", 24, C.ink3)
end

local function build_calendar(parent)
    lb_month = theme.label(parent, GRID_X, 58, 340, 46, "", 32, C.ink)
    for i = 1, 7 do
        local col = (i == 1) and C.today or C.ink3
        theme.label(parent, GRID_X + (i - 1) * CELL_W, GRID_Y - 40, CELL_W, 32,
            du.WEEK_CN[i], 20, col, airui.TEXT_ALIGN_CENTER)
    end
    for i = 0, 41 do
        local c = i % 7
        local r = math.floor(i / 7)
        cells[i + 1] = theme.label(parent, GRID_X + c * CELL_W, GRID_Y + r * CELL_H,
            CELL_W, CELL_H, "", 22, C.ink2, airui.TEXT_ALIGN_CENTER)
    end
end

local function build_events(parent)
    local events = conf.events or {}
    for i = 1, math.min(#events, 3) do
        local x = 44 + (i - 1) * 232
        theme.card(parent, x, 466, 212, 88, C.card, 14, C.line, 1)
        ev_name[i] = theme.label(parent, x + 14, 478, 184, 32, "", 20, C.ink2)
        ev_days[i] = theme.label(parent, x + 14, 512, 184, 36, "", 26, C.gold)
    end
end

-- ==================== 刷新 ====================
--[[重画月历：只在跨天/跨月时调用，不参与每秒刷新]]
local function draw_month(y, m, today_day)
    local grid = du.month_grid(y, m)
    for i = 1, 42 do
        local it = grid[i]
        local lb = cells[i]
        if lb then
            lb:set_text(tostring(it.day))
            if not it.cur then
                lb:set_color(C.ink3)          -- 上月/下月补位格
            elseif it.day == today_day then
                lb:set_color(C.accent)        -- 今天高亮
            else
                lb:set_color(C.ink)
            end
        end
    end
end

local function update_events(now)
    local events = conf.events or {}
    for i = 1, 3 do
        local ev = events[i]
        if ev then
            local days = du.days_until(ev, now)
            if ev_name[i] then ev_name[i]:set_text(ev.name or "") end
            if ev_days[i] then
                if days == nil then
                    ev_days[i]:set_text("--")
                elseif days == 0 then
                    ev_days[i]:set_text("就是今天")
                elseif days < 0 then
                    ev_days[i]:set_text("已过去")
                else
                    ev_days[i]:set_text(string.format("%d 天", days))
                end
            end
        end
    end
end

function M.refresh()
    local t = rtc_util.now()
    if not t then return end

    -- 1) 时/分
    local hm = string.format("%02d:%02d", t.hour, t.min)
    if hm ~= cache.hm then
        lb_hm:set_text(hm)
        cache.hm = hm
    end

    -- 2) 秒
    if conf.clock.show_sec then
        local s = string.format("%02d", t.sec)
        if s ~= cache.sec then
            lb_sec:set_text(s)
            cache.sec = s
        end
    end

    -- 3) 跨天才处理的重活
    local dstr = string.format("%04d年%02d月%02d日", t.year, t.month, t.day)
    if dstr ~= cache.date then
        lb_date:set_text(dstr)
        lb_week:set_text(string.format("星期%s", du.week_cn(t.wday)))
        -- 间隔号「·」(U+00B7) 不在 hzfont 字库里会显示成空白，
        -- 这里用中文全角括号（GB2312 一级字库，必定有字形）
        lb_zodiac:set_text(string.format("%s年（属%s）", du.ganzhi(t.year), du.zodiac(t.year)))
        lb_month:set_text(string.format("%04d年%02d月", t.year, t.month))
        draw_month(t.year, t.month, t.day)
        update_events(t)
        log.info("clock", "跨天刷新", dstr, "星期" .. du.week_cn(t.wday),
            "本月1号星期(1=周日)", du.wday_of(t.year, t.month, 1))
        cache.date = dstr
    end
end

-- ==================== 生命周期 ====================
function M.build(parent)
    root = airui.container({
        parent = parent, x = 0, y = 0, w = SW, h = SH,
        color = 0x000000, color_opacity = 0, radius = 0, border_width = 0,
    })
    build_clock_area(root)
    build_calendar(root)
    build_events(root)
    theme.button(root, 872, 500, 116, 56, "设置", 22, function()
        theme.defer(function()
            if M.on_settings then M.on_settings() end
        end)
    end)
    M.refresh()
    return root
end

function M.show()
    if root then root:set_hidden(false) end
    M.refresh()
end

function M.hide()
    if root then root:set_hidden(true) end
end

return M
