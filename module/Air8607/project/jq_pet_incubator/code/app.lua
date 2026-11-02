--[[
@module  app
@summary 页面路由 + 全局刷新 + 轻提示
@version 1.0
@date    2026.10.28

页面：home（房间筛选 + 设备卡片墙） / detail（单台设备详情 + 阈值设置）
]]
local conf = require "conf"
local theme = require "theme"
local store = require "store"
local alarm = require "alarm"
local ui_home = require "ui_home"
local ui_detail = require "ui_detail"
local ui_dialog = require "ui_dialog"

local M = {}
local C = theme.C

local state = "init"
local cur_id = nil
local refresh_timer = nil

--------------------------------------------------------------------
-- 轻提示
--------------------------------------------------------------------
local toast_box, toast_label, toast_timer, toast_token = nil, nil, nil, 0

function M.toast(msg)
    toast_token = toast_token + 1
    local tk = toast_token
    if toast_box then
        pcall(function() toast_box:destroy() end)
        toast_box, toast_label = nil, nil
    end
    toast_box = airui.container({
        parent = nil, x = 332, y = 500, w = 360, h = 46,
        color = 0x33302E, color_opacity = 235,
        radius = 23, border_color = C.pink, border_width = 2,
    })
    toast_label = theme.label_mid(toast_box, 0, 0, 360, 46, msg, 15, C.white, airui.TEXT_ALIGN_CENTER)
    if toast_timer then sys.timerStop(toast_timer) end
    toast_timer = sys.timerStart(function()
        toast_timer = nil
        if tk == toast_token and toast_box then toast_box:set_hidden(true) end
    end, 2200)
    log.info("app", msg)
end

--------------------------------------------------------------------
-- 路由
--------------------------------------------------------------------
-- 页面构建失败时不能留下半成品页面，记录错误后由调用方退回可用页面
local function build_page(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        log.error("app", "页面构建失败", tostring(err))
    end
    return ok
end

function M.show_home()
    ui_dialog.close()
    ui_detail.destroy()
    ui_home.destroy()
    state = "home"
    cur_id = nil
    if not build_page(ui_home.build, M) then
        M.toast("界面构建失败")
    end
end

function M.open_detail(id)
    if state ~= "home" then return end
    if not store.get(id) then
        M.toast("设备不存在")
        return
    end
    ui_dialog.close()
    ui_home.destroy()
    ui_detail.destroy()
    cur_id = id
    state = "detail"
    if not build_page(ui_detail.build, M, id) then
        state = "home"
        M.show_home()
    end
end

function M.close_detail()
    if state ~= "detail" then return end
    ui_dialog.close()
    ui_detail.destroy()
    M.show_home()
end

-- 房间/设备列表变化后重建主页
function M.reload_home()
    if state ~= "home" then return end
    if not build_page(ui_home.build, M) then
        M.toast("界面构建失败")
    end
end

function M.state() return state end
function M.cur_id() return cur_id end

--------------------------------------------------------------------
-- 启动
--------------------------------------------------------------------
function M.start()
    store.init()
    alarm.init()
    M.show_home()

    if refresh_timer then sys.timerStop(refresh_timer) end
    refresh_timer = sys.timerLoopStart(function()
        store.tick()
        local any = store.any_alarm()
        alarm.tick(any)
        if state == "home" then
            ui_home.refresh()
        elseif state == "detail" then
            ui_detail.refresh()
        end
    end, conf.sim.interval_ms)

    log.info("app", conf.name .. " 已启动", "设备", store.count(), "房间", #store.rooms())
end

return M
