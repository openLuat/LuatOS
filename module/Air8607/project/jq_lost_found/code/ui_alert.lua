--[[
@module  ui_alert
@summary 通用提示：模态弹窗（alert）+ 顶部轻提示（toast）
@version 1.0
@date    2026.10.30
@usage
local A = require "ui_alert"
A.alert("身份证号有误")   -- 模态，点"确定"关闭
A.toast("领取成功")       -- 顶部轻提示，1.6 秒后自动消失
]]

local conf = require "conf"
local theme = require "theme"

local M = {}

local SW, SH = conf.W, conf.H
local C = theme.C

-- ==================== 模态弹窗 ====================
local alert_root, alert_lb

local function build_alert()
    if alert_root then return end
    alert_root = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = 0x000000, color_opacity = 120, radius = 0, border_width = 0,
    })
    alert_root:set_hidden(true)

    local card = theme.card(alert_root, math.floor((SW - 440) / 2), math.floor((SH - 168) / 2), 440, 168, C.panel, 14, C.line2, 1)
    alert_lb = theme.label(card, 24, 40, 392, 60, "", 18, C.ink, airui.TEXT_ALIGN_CENTER)
    theme.button(card, 160, 108, 120, 40, "确定", 18, function() M.close() end, "primary")
end

-- ==================== 顶部轻提示 ====================
local toast_root, toast_lb, toast_timer

local function build_toast()
    if toast_root then return end
    toast_root = airui.container({
        parent = nil, x = 0, y = 150, w = SW, h = 64,
        color = 0x000000, color_opacity = 0, radius = 0, border_width = 0,
    })
    toast_root:set_hidden(true)
    local pill = theme.box(toast_root, math.floor((SW - 360) / 2), 4, 360, 52, 0x2A2724, 26, 235)
    toast_lb = theme.label(pill, 0, 13, 360, 26, "", 17, 0xFFFFFF, airui.TEXT_ALIGN_CENTER)
end

-- ==================== 对外 ====================
function M.build()
    build_alert()
    build_toast()
end

function M.alert(msg)
    build_alert()
    alert_lb:set_text(msg or "")
    alert_root:set_hidden(false)
end

function M.close()
    if alert_root then alert_root:set_hidden(true) end
end

function M.toast(msg)
    build_toast()
    toast_lb:set_text(msg or "")
    toast_root:set_hidden(false)
    if toast_timer then sys.timerStop(toast_timer) end
    toast_timer = sys.timerStart(function()
        if toast_root then toast_root:set_hidden(true) end
        toast_timer = nil
    end, 1600)
end

return M
