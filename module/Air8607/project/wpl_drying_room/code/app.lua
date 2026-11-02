--[[
@module  app
@summary 应用状态机 + 数据刷新编排 + 全局提示条
@version 1.0
@date    2026.10.24

页面：dashboard（主控大屏） / metric（指标详情：波形+调节） / settings（设置）
]]
local conf = require "conf"
local theme = require "theme"
local sim = require "sim"
local ui_dashboard = require "ui_dashboard"
local ui_metric = require "ui_metric"
local ui_settings = require "ui_settings"

local M = {}
local C = theme.C

local state = "none"

-- toast
local toastBox, toastLabel, toastTimer, toastToken = nil, nil, nil, 0

function M.toast(msg)
    toastToken = toastToken + 1
    local tk = toastToken
    if toastBox then
        pcall(function() toastBox:destroy() end)
        toastBox, toastLabel = nil, nil
    end
    toastBox = airui.container({
        parent = nil, x = 262, y = 528, w = 500, h = 52,
        color = 0x201109, color_opacity = 240,
        radius = 26, border_color = C.amber, border_width = 1,
    })
    toastLabel = theme.label(toastBox, 0, 14, 500, 24, "", 17, C.ink, airui.TEXT_ALIGN_CENTER)
    toastLabel:set_text(msg)
    if toastTimer then sys.timerStop(toastTimer) end
    toastTimer = sys.timerStart(function()
        toastTimer = nil
        if tk == toastToken and toastBox then toastBox:set_hidden(true) end
    end, 2600)
    log.info("app", msg)
end

-- ==================== 页面路由 ====================
-- 页面构建失败时不能留下半成品页面，记录错误后退回看板
local function build_page(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        log.error("app", "页面构建失败", tostring(err))
    end
    return ok
end

function M.show_dashboard()
    ui_settings.destroy()
    ui_metric.destroy()
    ui_dashboard.destroy()
    state = "dashboard"
    if not build_page(ui_dashboard.build, M) then
        M.toast("界面构建失败")
    end
end

function M.open_metric(key)
    if state ~= "dashboard" then return end
    ui_dashboard.destroy()
    ui_metric.destroy()
    state = "metric"
    if not build_page(ui_metric.build, M, key) then
        M.show_dashboard()
    end
end

function M.close_metric()
    if state ~= "metric" then return end
    M.show_dashboard()
end

function M.open_settings()
    if state ~= "dashboard" then return end
    ui_dashboard.destroy()
    ui_settings.destroy()
    state = "settings"
    if not build_page(ui_settings.build, M) then
        M.show_dashboard()
    end
end

function M.close_settings()
    if state ~= "settings" then return end
    M.show_dashboard()
end

function M.state_name() return state end

-- ==================== 启动 ====================
local refreshTimer = nil

function M.start()
    sim.init()
    M.show_dashboard()
    if refreshTimer then sys.timerStop(refreshTimer) end
    refreshTimer = sys.timerLoopStart(function()
        sim.tick()
        if state == "dashboard" then
            ui_dashboard.refresh()
        elseif state == "metric" then
            ui_metric.refresh()
        end
    end, conf.sim.interval_ms)
    log.info("app", "烘干室模拟引擎已启动")
end

return M
