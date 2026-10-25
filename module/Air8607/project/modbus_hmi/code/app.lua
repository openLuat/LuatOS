--[[
@module  app
@summary 页面路由 + 数据刷新编排 + 全局提示条
@version 1.0.0
@date    2026.10.25

页面：dashboard（总览）/ device（设备详情）/ trend（趋势）
      alarm（报警）/ regtool（寄存器工具）/ settings（设置）
]]
local conf = require "conf"
local theme = require "theme"
local mbdev = require "mbdev"
local mbmaster = require "mbmaster"

local ui_dashboard = require "ui_dashboard"
local ui_device = require "ui_device"
local ui_trend = require "ui_trend"
local ui_alarm = require "ui_alarm"
local ui_regtool = require "ui_regtool"
local ui_settings = require "ui_settings"

local M = {}
local C = theme.C

local state = "none"
local cur_dev = 1

-- ==================== toast ====================
local toastBox, toastLabel, toastTimer, toastToken = nil, nil, nil, 0

function M.toast(msg)
    toastToken = toastToken + 1
    local tk = toastToken
    if toastBox then
        pcall(function() toastBox:destroy() end)
        toastBox, toastLabel = nil, nil
    end
    toastBox = airui.container({
        parent = nil, x = 272, y = 492, w = 480, h = 48,
        color = 0x0C1826, color_opacity = 245,
        radius = 24, border_color = C.cyan, border_width = 1,
    })
    toastLabel = theme.label(toastBox, 0, 13, 480, 22, "", 17, C.ink, airui.TEXT_ALIGN_CENTER)
    toastLabel:set_text(msg)
    if toastTimer then sys.timerStop(toastTimer) end
    toastTimer = sys.timerStart(function()
        toastTimer = nil
        if tk == toastToken and toastBox then
            pcall(function() toastBox:destroy() end)
            toastBox, toastLabel = nil, nil
        end
    end, 2600)
    log.info("app", msg)
end

-- ==================== 路由 ====================
local PAGES = {
    dashboard = ui_dashboard, device = ui_device, trend = ui_trend,
    alarm = ui_alarm, regtool = ui_regtool, settings = ui_settings,
}

local function destroy_all()
    for _, p in pairs(PAGES) do pcall(function() p.destroy() end) end
end

function M.show(page)
    if not PAGES[page] then return end
    destroy_all()
    state = page
    if page == "device" then
        PAGES[page].build(M, cur_dev)
    else
        PAGES[page].build(M)
    end
end

function M.open_device(dev_id)
    cur_dev = dev_id
    M.show("device")
end

function M.back_to_dashboard() M.show("dashboard") end

function M.state_name() return state end
function M.cur_dev() return cur_dev end

-- ==================== 写点位（统一入口，失败弹提示） ====================
function M.write(key, v)
    if not key then return end
    local pt = mbdev.point(key)
    if not pt then return end
    local ok, msg = mbmaster.write_point(key, v)
    if ok then
        M.toast(string.format("%s 已写入 %s", pt.name, mbdev.fmt_with_unit(key, v)))
    else
        M.toast("写入失败：" .. tostring(msg))
    end
    return ok
end

-- ==================== 启动 ====================
function M.start()
    mbmaster.init()
    mbmaster.start()
    M.show("dashboard")
    sys.timerLoopStart(function()
        if state == "dashboard" then
            ui_dashboard.refresh()
        elseif state == "device" then
            ui_device.refresh()
        elseif state == "trend" then
            ui_trend.refresh()
        elseif state == "alarm" then
            ui_alarm.refresh()
        elseif state == "regtool" then
            ui_regtool.refresh()
        elseif state == "settings" then
            ui_settings.refresh()
        end
    end, conf.comm.poll_interval_ms)
    log.info("app", "Modbus 中控大屏已启动")
end

return M
