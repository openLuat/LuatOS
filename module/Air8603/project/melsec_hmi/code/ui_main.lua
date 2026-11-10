--[[
@module  ui_main
@summary 页面路由 + 顶栏 + 底部导航 + 全局刷新
@version 1.0.0
@date    2026.11.09

页面约定（每个 ui_xxx 模块实现）：
    TITLE   string  顶栏标题
    build(body, hdr) → api   在内容区建界面，返回给 refresh 用的句柄表
    refresh(api)             可选，每 500ms 调用一次
    on_show() / on_hide()    可选，页面显示/销毁时调用
]]
local M = {}

local conf = require "conf"
local theme = require "ui_theme"
local C = theme.C
local data = require "app_data"
local alarm = require "app_alarm"
local ui_alarm = require "ui_alarm"

local W, H = conf.W, conf.H
local HDR_H = 56
local NAV_H = 48

local pages = {}
local cur = nil

--[[
注册页面模块
@param id string 页面 id
@param mod table 页面模块
@return nil
]]
function M.register(id, mod)
    pages[id] = mod
end

--[[
当前页面 id
@return string|nil
]]
function M.current()
    return cur and cur.id
end

local function build_header(root, title)
    local hdr = {}

    theme.box(root, 0, 0, W, HDR_H, 0x0A1420)
    theme.accent_bar(root, 0, HDR_H - 3, W, C.line)
    theme.label(root, 24, 12, 300, 32, title or "", 22, C.ink)

    hdr.dot = theme.dot(root, 336, 23, 5, C.off)
    hdr.status = theme.label(root, 352, 16, 76, 24, "离线", 15, C.danger)
    hdr.info = theme.label(root, 434, 18, 178, 22, "等待通讯", 13, C.ink3)
    hdr.time = theme.label(root, 616, 16, 128, 24, "--:--:--", 15, C.ink2,
        airui.TEXT_ALIGN_RIGHT)

    hdr.mute = theme.ghost_button(root, 760, 12, 96, 32, "消音", 15, C.ink2, function()
        theme.defer(function()
            alarm.mute()
        end)
    end)
    hdr.bell = theme.ghost_button(root, 866, 12, 134, 32, "报警记录", 15, C.ink2, function()
        theme.defer(function()
            M.show("alarm")
        end)
    end)

    return hdr
end

local function refresh_header(hdr)
    if not hdr then
        return
    end

    local online = data.online
    pcall(hdr.dot.set_color, hdr.dot, online and C.ok or C.danger)
    theme.set_text(hdr.status, online and "在线" or "离线")
    theme.set_color(hdr.status, online and C.ok or C.danger)
    theme.set_text(hdr.info, string.format("成功 %d  失败 %d", data.ok_count, data.err_count))
    theme.set_text(hdr.time, os.date("%H:%M:%S"))

    local lv = alarm.max_level()
    local nrec = #alarm.recs
    if hdr._lv ~= lv or hdr._nrec ~= nrec then
        hdr._lv, hdr._nrec = lv, nrec
        theme.set_text(hdr.bell, lv > 0 and string.format("报警 %d 条", nrec) or "报警记录")
        pcall(hdr.bell.set_style, hdr.bell, {
            bg_color = (lv == 2 and C.danger) or (lv == 1 and C.warn) or C.panel2,
            bg_opa = 255,
            text_color = lv > 0 and 0x05141C or C.ink2,
            radius = 9,
            border_width = 1,
            border_color = lv > 0 and C.red or C.line2,
            pressed_bg_color = C.line2,
            pressed_text_color = 0xFFFFFF,
        })
    end

    if hdr._muted ~= alarm.muted then
        hdr._muted = alarm.muted
        theme.set_text(hdr.mute, alarm.muted and "已消音" or "消音")
        theme.set_color(hdr.mute, alarm.muted and C.amber or C.ink2)
    end
end

local function destroy_cur()
    if not cur then
        return
    end
    if cur.mod and cur.mod.on_hide then
        pcall(cur.mod.on_hide)
    end
    if cur.root then
        pcall(cur.root.destroy, cur.root)
    end
    cur = nil
end

--[[
切换页面（会销毁旧页面，释放 LVGL 对象）
@param id string 页面 id
@return nil
]]
function M.show(id)
    local mod = pages[id]
    if not mod then
        log.error("ui_main", "页面未注册", id)
        return
    end

    destroy_cur()
    ui_alarm.close_popup()

    local root = airui.container({
        parent = nil, x = 0, y = 0, w = W, h = H,
        color = C.bg1, radius = 0, border_width = 0,
    })
    theme.gradient(root, 0, 0, W, H, C.bg1, C.bg2, 12)

    local hdr = build_header(root, mod.TITLE)

    local body = airui.container({
        parent = root, x = 0, y = HDR_H + 8, w = W, h = H - HDR_H - 8 - NAV_H,
        color = C.bg1, color_opacity = 0, radius = 0, border_width = 0,
    })
    local api = mod.build(body, hdr) or {}

    theme.navbar(root, id, H - NAV_H + 4, function(nid)
        M.show(nid)
    end)

    cur = { id = id, mod = mod, root = root, api = api, hdr = hdr }
    cur.api.hdr = hdr

    refresh_header(hdr)
    if mod.on_show then
        pcall(mod.on_show, api)
    end
end

-- 全局刷新：顶栏 + 当前页面 + 报警弹窗
sys.taskInit(function()
    while true do
        sys.wait(500)
        if cur then
            local ok, err = pcall(function()
                refresh_header(cur.hdr)
                if cur.mod.refresh then
                    cur.mod.refresh(cur.api)
                end
                ui_alarm.refresh_popup()
            end)
            if not ok then
                log.error("ui_main", "刷新异常", tostring(err))
            end
        end
    end
end)

-- 新报警自动弹窗（不打断当前报警页）
alarm.on_change(function(evt)
    if evt == "new" and conf.alarm.popup then
        theme.defer(function()
            if M.current() ~= "alarm" then
                ui_alarm.open_popup()
            else
                ui_alarm.refresh_popup()
            end
        end, 30)
    end
end)

--[[
启动 UI：注册页面并显示首页
@return nil
]]
function M.start()
    M.register("dashboard", require "ui_dash")
    M.register("trend", require "ui_trend")
    M.register("alarm", require "ui_alarm")
    M.register("settings", require "ui_settings")

    M.show("dashboard")
end

return M
