--[[
@module  ui_alarm
@summary 报警记录页：统计卡 + 级别过滤 + 报警列表
@version 1.0.0
@date    2026.10.25
]]
local conf = require "conf"
local theme = require "theme"
local mbdev = require "mbdev"
local mbmaster = require "mbmaster"

local M = {}
local C = theme.C
local SW, SH = conf.W, conf.H
local NAV_Y = 548

local root = nil
local app_ref = nil
local filter = "all"

local statCards = {}
local filterBtns = {}
local rows = {}
local headerRight

local ROW_N = 9

local FILTERS = {
    { id = "all",    name = "全部" },
    { id = "danger", name = "报警" },
    { id = "warn",   name = "偏离" },
    { id = "comm",   name = "通讯" },
}

local function match(a)
    if filter == "all" then return true end
    if filter == "comm" then return a.key == "" end
    return a.level == filter
end

local function refresh_filters()
    for i, b in ipairs(filterBtns) do
        if b then
            local on = (FILTERS[i].id == filter)
            b:set_style({
                bg_color = on and C.cyan or C.panel2,
                text_color = on and 0x05141C or C.ink2,
                border_color = on and C.cyan or C.line2,
                radius = 8,
            })
        end
    end
end

local function build_stats()
    local defs = {
        { key = "total", name = "记录总数", color = C.cyan },
        { key = "danger", name = "报警 (危险)", color = C.red },
        { key = "warn", name = "偏离 (预警)", color = C.amber },
    }
    for i, d in ipairs(defs) do
        local x = 24 + (i - 1) * 328
        local c = theme.card(root, x, 66, 316, 70)
        theme.accent_bar(c, 16, 0, 44, d.color)
        theme.label(c, 16, 12, 200, 20, d.name, 14, C.ink2)
        local v = theme.label(c, 16, 34, 284, 30, "0", 26, d.color)
        statCards[d.key] = v
    end
end

local function build_list()
    local card = theme.card(root, 24, 148, 976, 388)
    theme.accent_bar(card, 16, 0, 50, C.red)
    theme.label(card, 16, 12, 200, 22, "报警与事件", 16, C.ink)

    for i, f in ipairs(FILTERS) do
        filterBtns[i] = theme.button(card, 560 + (i - 1) * 100, 8, 92, 26, f.name, 12,
            C.panel2, C.ink2, function()
                theme.defer(function()
                    filter = f.id
                    refresh_filters()
                    M.refresh()
                end)
            end, 8)
    end

    local heads = { "时间", "级别", "来源设备", "事件描述" }
    local hx = { 14, 82, 144, 320 }
    for i, h in ipairs(heads) do
        theme.label(card, hx[i], 44, 100, 18, h, 12, C.ink3)
    end
    theme.box(card, 14, 64, 948, 1, C.line)

    for i = 1, ROW_N do
        local y = 72 + (i - 1) * 36
        if i % 2 == 0 then theme.box(card, 8, y - 4, 960, 32, 0x101A28, 4) end
        local t = theme.label(card, 14, y, 64, 20, "", 12, C.ink3)
        local pill, pillText = theme.pill(card, 82, y, 54, 18, "—", C.ink3, 11)
        local src = theme.label(card, 144, y, 170, 20, "", 12, C.ink2)
        local txt = theme.label(card, 320, y, 640, 20, "", 13, C.ink)
        rows[i] = { time = t, pill = pill, pillText = pillText, src = src, text = txt }
    end
end

function M.build(app)
    M.destroy()
    app_ref = app

    root = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = C.bg1, radius = 0, border_width = 0,
    })
    theme.gradient(root, 0, 0, SW, SH, C.bg1, C.bg2, 12)

    theme.page_header(root, "报警记录 · Alarm", "", C.ink3)
    theme.button(root, 860, 12, 140, 32, "清空记录", 14, C.panel2, C.red, function()
        theme.defer(function()
            mbdev.clear_alarms()
            if app_ref then app_ref.toast("报警记录已清空") end
            M.refresh()
        end)
    end, 9)

    build_stats()
    build_list()

    theme.navbar(root, "alarm", NAV_Y, function(id)
        if app_ref then app_ref.show(id) end
    end)

    refresh_filters()
    M.refresh()
end

function M.refresh()
    if not root then return end

    local all = mbdev.alarms()
    if statCards.total then statCards.total:set_text(tostring(#all)) end
    if statCards.danger then statCards.danger:set_text(tostring(mbdev.alarm_count("danger"))) end
    if statCards.warn then statCards.warn:set_text(tostring(mbdev.alarm_count("warn"))) end

    local n = 0
    for _, a in ipairs(all) do
        if match(a) then
            n = n + 1
            if n > ROW_N then break end
            local r = rows[n]
            if r then
                r.time:set_text(a.time)
                local col = (a.level == "danger") and C.danger or
                            (a.level == "warn") and C.warn or C.ok
                r.pill:set_color(col)
                r.pillText:set_text((a.level == "danger") and "报警" or
                                    (a.level == "warn") and "偏离" or "恢复")
                r.pillText:set_color(col)
                r.src:set_text(a.dev or "系统")
                r.text:set_text(a.text)
                r.text:set_color(col)
            end
        end
    end
    for i = n + 1, ROW_N do
        local r = rows[i]
        if r then
            r.time:set_text("")
            r.pill:set_color(C.panel2)
            r.pillText:set_text("")
            r.src:set_text("")
            r.text:set_text("")
        end
    end
end

function M.destroy()
    if root then
        pcall(function() root:destroy() end)
        root = nil
    end
    app_ref = nil
    statCards, filterBtns, rows = {}, {}, {}
    headerRight = nil
end

return M
