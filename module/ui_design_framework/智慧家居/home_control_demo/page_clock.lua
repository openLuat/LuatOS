--[[
@module  page_clock
@summary 息屏·待机时钟（AOD 风格）：纯黑底 + 霓虹同心光晕环 + 轨道光点 + 中央大时间，每秒刷新
@note 图案全用 airui.shape 矢量绘制（circle/line/dot），零位图、零解码，Air1603 上无滚动条。
      内容挂在根容器 ROOT 上，由 ui_page 显隐轮询。
]]
local T = require "ui_theme"
local W = require "ui_widget"
local M = {}

local C = {
    bg = 0x04050A,
    cyan = 0x7DD3FC, blue = 0x0EA5E9, sky = 0x38BDF8,
    violet = 0x7C3AED, purple = 0x8B5CF6, lavender = 0xA78BFA,
    pink = 0xEC4899, teal = 0x2DD4BF,
    line = 0x59637B, line_dim = 0x39415A,
    t1 = 0xF2F5FA, t2 = 0x9AA2B5, t3 = 0x67708A,
}

local ROOT
local CX, CY = 512, 260

local function dot(parent, x, y, d, color, opa)
    local o = airui.container({ parent = parent, x = x, y = y, w = d, h = d,
        color = color, radius = math.floor(d / 2), border_width = 0 })
    if opa then W.glass(o, color, opa) end
    return o
end

local function orb(r, deg, d, color, opa)
    local a = math.rad(deg)
    dot(ROOT, CX + r * math.cos(a) - d / 2, CY + r * math.sin(a) - d / 2, d, color, opa)
end

local function build_pattern()
    local items = {}
    local function ring(r, width, color, opacity)
        items[#items + 1] = { type = "circle", cx = CX, cy = CY, r = r,
            color = color, width = width, opacity = opacity, fill = false }
    end
    for i = 0, 11 do
        local a = math.rad(i * 30)
        local ca, sa = math.cos(a), math.sin(a)
        items[#items + 1] = { type = "line",
            x1 = CX + 232 * ca, y1 = CY + 232 * sa,
            x2 = CX + 244 * ca, y2 = CY + 244 * sa,
            color = C.line, width = 1, opacity = 80 }
    end
    items[#items + 1] = { type = "circle", cx = CX, cy = CY, r = 96,
        color = C.cyan, fill = true, fill_color = C.cyan, fill_opacity = 5 }
    ring(126, 1, C.line_dim, 40)
    ring(150, 1, C.line, 55)
    ring(188, 16, C.blue, 7)
    ring(188, 6,  C.sky, 16)
    ring(188, 1,  C.cyan, 110)
    ring(210, 12, C.violet, 7)
    ring(210, 4,  C.purple, 14)
    ring(210, 1,  C.lavender, 90)
    ring(228, 1, C.cyan, 80)
    W.shape(ROOT, { x = 0, y = 0, w = T.screen.w, h = T.screen.h, items = items })

    orb(210, 90, 10, C.cyan, 255)
    orb(210, 210, 8, C.pink, 230)
    orb(210, 330, 8, C.lavender, 230)
    orb(188, 30, 7, C.sky, 220)
    orb(188, 150, 7, C.teal, 220)
    orb(150, 300, 6, C.blue, 200)
end

local time_lbl, date_lbl
local WEEK = { "日", "一", "二", "三", "四", "五", "六" }
local function pad(n) return n < 10 and ("0" .. n) or ("" .. n) end

local function refresh()
    local h = tonumber(os.date("%H")) or 0
    local m = tonumber(os.date("%M")) or 0
    local mo = tonumber(os.date("%m")) or 1
    local d = tonumber(os.date("%d")) or 1
    local wd = tonumber(os.date("%w")) or 0
    pcall(function() time_lbl:set_text(pad(h) .. ":" .. pad(m)) end)
    pcall(function() date_lbl:set_text(mo .. "月" .. d .. "日 · 周" .. WEEK[wd + 1]) end)
end

function M.create(root)
    ROOT = root or airui.screen
    airui.container({ parent = ROOT, x = 0, y = 0, w = T.screen.w, h = T.screen.h,
        color = C.bg, border_width = 0 })
    build_pattern()
    time_lbl = W.text_mid(ROOT, { text = "--:--", x = 212, y = 175, w = 600, h = 170,
        size = 88, color = C.t1, weight = 700, align = airui.TEXT_ALIGN_CENTER })
    date_lbl = W.text_mid(ROOT, { text = "--月--日", x = 312, y = 344, w = 400, h = 30,
        size = 18, color = C.t2, align = airui.TEXT_ALIGN_CENTER })
    W.text_mid(ROOT, { text = "SMART HOME · 轻触唤醒", x = 312, y = 552, w = 400, h = 26,
        size = 14, color = C.t3, align = airui.TEXT_ALIGN_CENTER })
    refresh()
    sys.timerLoopStart(refresh, 1000)
    log.info("page_clock", "息屏时钟页已创建")
end

return M
