--[[
@module  ui_alarm
@summary 报警页：记录列表 + 弹窗 + 清空/复位
@version 1.0.0
@date    2026.11.12
]]
local M = {}

M.TITLE = "报警记录"

local conf = require "conf"
local theme = require "ui_theme"
local C = theme.C
local alarm = require "app_alarm"
local seq = require "app_seq"

local ROW_MAX = 8
local ROW_H = 44
local list_rows = {}
local list_api = nil

-- 页面跳转由 ui_main 反向注册，避免本模块反向依赖 ui_main 造成循环依赖；
-- 同时也避开烧录合并工具的静态扫描（它会贪婪匹配 require 后面的字符串）。
M.nav_to = nil

--[[
注册页面跳转函数（由 ui_main 调用）
@param fn function(page_id)
@return nil
]]
function M.set_nav(fn)
    M.nav_to = fn
end

--[[
构建一行记录控件
@param body table 父容器
@param y number 纵坐标
@return table {idx, time, motor, text, code}
]]
local function build_row(body, y)
    local row = theme.card(body, 20, y, 984, ROW_H - 6, C.panel2, 8, C.line, 1)
    local r = {}
    r.time  = theme.label(row, 14, 9, 150, 24, "", 14, C.ink3)
    r.motor = theme.label(row, 168, 9, 120, 24, "", 14, C.ink2)
    r.text  = theme.label(row, 292, 9, 560, 24, "", 16, C.ink)
    r.code  = theme.label(row, 856, 9, 114, 24, "", 14, C.ink3, airui.TEXT_ALIGN_RIGHT)
    return r
end

local function refresh_rows()
    if not list_api then return end
    for i = 1, ROW_MAX do
        local r = list_rows[i]
        local rec = alarm.recs[i]
        if r then
            if rec then
                theme.set_text(r.time, rec.t or "")
                theme.set_text(r.motor, rec.m or "")
                theme.set_text(r.text, rec.text or "")
                theme.set_text(r.code, (rec.code and rec.code ~= 0)
                    and string.format("#%d", rec.code) or "")
                theme.set_color(r.text, (rec.code and rec.code ~= 0) and C.danger or C.warn)
            else
                theme.set_text(r.time, "")
                theme.set_text(r.motor, "")
                theme.set_text(r.text, i == 1 and "暂无报警记录" or "")
                theme.set_text(r.code, "")
            end
        end
    end
end

function M.build(body, hdr)
    local api = {}
    list_api = api
    list_rows = {}

    theme.label(body, 20, 2, 600, 24, "最近 8 条，新的在最上面", 14, C.ink3)

    for i = 1, ROW_MAX do
        list_rows[i] = build_row(body, 30 + (i - 1) * ROW_H)
    end

    theme.button(body, 640, 424, 160, 48, "清空记录", 17, C.panel2, C.ink, function()
        theme.defer(function()
            alarm.clear()
            refresh_rows()
        end)
    end, 10)

    theme.button(body, 812, 424, 192, 48, "故障复位", 17, C.cyan, 0x05141C, function()
        theme.defer(function()
            seq.reset_fault()
        end)
    end, 10)

    api.tip = theme.label(body, 20, 434, 580, 26, "", 14, C.ink3)

    refresh_rows()
    return api
end

function M.refresh(api)
    refresh_rows()
    if api and api.tip then
        if seq.estop then
            theme.set_text(api.tip, "急停锁存中，请到监控页复位后再启动")
            theme.set_color(api.tip, C.danger)
        else
            theme.set_text(api.tip, "")
        end
    end
end

function M.on_show()
    refresh_rows()
end

-- ===== 弹窗 =====

local popup = nil
local popup_text = nil
local popup_title = nil
local popup_code = nil

--[[
关闭弹窗
@return nil
]]
function M.close_popup()
    if popup then
        pcall(popup.destroy, popup)
        popup = nil
        popup_text, popup_title, popup_code = nil, nil, nil
    end
end

--[[
打开弹窗（显示最新一条记录）
@return nil
]]
function M.open_popup()
    M.close_popup()

    local W, H = conf.W, conf.H
    local pw, ph = 600, 280
    local px, py = math.floor((W - pw) / 2), math.floor((H - ph) / 2)

    popup = airui.container({
        parent = nil, x = 0, y = 0, w = W, h = H,
        color = 0x000000, color_opacity = 120, radius = 0, border_width = 0,
    })

    local card = theme.card(popup, px, py, pw, ph, C.panel, 14, C.red, 2)
    theme.accent_bar(card, 14, 0, pw - 28, C.red)

    popup_title = theme.label(card, 28, 30, pw - 56, 30, "报警", 24, C.danger)
    popup_code = theme.label(card, pw - 150, 34, 122, 24, "", 15, C.ink3,
        airui.TEXT_ALIGN_RIGHT)
    popup_text = theme.label(card, 28, 80, pw - 56, 90, "", 18, C.ink)

    theme.ghost_button(card, 28, ph - 76, 200, 50, "知道了", 18, C.ink, function()
        theme.defer(function()
            M.close_popup()
        end)
    end, C.line2)

    theme.button(card, pw - 228, ph - 76, 200, 50, "去报警页", 18, C.cyan, 0x05141C, function()
        theme.defer(function()
            M.close_popup()
            if M.nav_to then
                M.nav_to("alarm")
            end
        end)
    end, 10)

    M.refresh_popup()
end

--[[
刷新弹窗内容（每 500ms 由 ui_main 调用）
@return nil
]]
function M.refresh_popup()
    if not popup then return end
    local rec = alarm.recs[1]
    if not rec then
        M.close_popup()
        return
    end
    theme.set_text(popup_title, rec.m or "报警")
    theme.set_text(popup_text, rec.text or "")
    theme.set_text(popup_code, (rec.code and rec.code ~= 0)
        and string.format("#%d", rec.code) or "")
end

return M
