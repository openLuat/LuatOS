-- fota_win.lua
--[[
@module  fota_win
@summary FOTA设置窗口
@version 1.0
@date    2026.03.26
@author  江访
]]

local win_id = nil
local main_container
local version_label, airui_version_label, auto_switch, interval_textarea, save_btn, upgrade_btn
local keyboard
local settings_loaded = false

local function retry_timer_func()
    if not auto_switch or not interval_textarea then
        log.warn("fota_win", "window destroyed, stop retry timer")
        sys.timerStop(retry_timer_func)
        return
    end
    if not exwin.is_active(win_id) then
        log.debug("fota_win", "window not active, skip retry")
        return
    end
    if settings_loaded then
        sys.timerStop(retry_timer_func)
        return
    end
    local retry_count = (retry_timer_func.retry_count or 0) + 1
    if retry_count >= 5 then
        log.warn("fota_win", "settings response timeout, use default")
        if auto_switch and interval_textarea then
            auto_switch:set_state(false)
            interval_textarea:set_text("3600")
        end
        sys.timerStop(retry_timer_func)
        return
    end
    sys.publish("FOTA_GET_SETTINGS")
    retry_timer_func.retry_count = retry_count
end

local function stop_retry_timer()
    sys.timerStop(retry_timer_func)
end

local function start_retry_timer()
    stop_retry_timer()
    retry_timer_func.retry_count = 0
    sys.timerLoopStart(retry_timer_func, 2000)
end

local function create_ui()
    main_container = airui.container({
        x = 0,
        y = 0,
        w = 720,
        h = 1280,
        color = 0xF8F9FA,
        parent = airui.screen
    })

    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 720,
        h = 80,
        color = 0x3F51B5
    })
    airui.label({
        parent = title_bar,
        x = 0,
        y = 20,
        w = 720,
        h = 48,
        text = "FOTA设置",
        font_size = 36,
        color = 0xfefefe,
        align = airui.TEXT_ALIGN_CENTER
    })
    local back_btn = airui.button({
        parent = main_container,
        x = 630,
        y = 20,
        w = 80,
        h = 40,
        text = "返回",
        font_size = 20,
        style = {
            bg_color = 0x2195F6,
            pressed_bg_color = 0x0B5EA8,
            text_color = 0xFFFFFF,
            pressed_text_color = 0xFFFFFF,
            radius = 8,
            border_width = 0,
            pad = 8,
            focus_outline_color = 0xFFB300,
            focus_outline_width = 2,
        },
        on_click = function() if win_id then exwin.close(win_id) end end
    })

    local content = airui.container({
        parent = main_container,
        x = 0,
        y = 80,
        w = 720,
        h = 1120,
        color = 0xF3F4F6
    })

    airui.label({
        parent = content,
        x = 30,
        y = 40,
        w = 160,
        h = 48,
        text = "当前固件版本:",
        font_size = 26,
        color = 0x000000,
        align = airui.TEXT_ALIGN_RIGHT
    })
    local version_bg = airui.container({
        parent = content,
        x = 200,
        y = 40,
        w = 490,
        h = 48,
        color = 0xEEEEEE,
        radius = 4
    })
    version_label = airui.label({
        parent = version_bg,
        x = 10,
        y = 10,
        w = 470,
        h = 30,
        text = "获取中...",
        font_size = 24,
        color = 0x000000,
        align = airui.TEXT_ALIGN_LEFT
    })

    airui.label({
        parent = content,
        x = 30,
        y = 120,
        w = 160,
        h = 48,
        text = "AirUI版本:",
        font_size = 26,
        color = 0x000000,
        align = airui.TEXT_ALIGN_RIGHT
    })
    local airui_version_bg = airui.container({
        parent = content,
        x = 200,
        y = 120,
        w = 490,
        h = 48,
        color = 0xEEEEEE,
        radius = 4
    })
    airui_version_label = airui.label({
        parent = airui_version_bg,
        x = 10,
        y = 10,
        w = 470,
        h = 30,
        text = "获取中...",
        font_size = 24,
        color = 0x000000,
        align = airui.TEXT_ALIGN_LEFT
    })

    airui.label({
        parent = content,
        x = 30,
        y = 200,
        w = 160,
        h = 48,
        text = "开机自动更新:",
        font_size = 26,
        color = 0x000000,
        align = airui.TEXT_ALIGN_RIGHT
    })
    auto_switch = airui.switch({
        parent = content,
        x = 200,
        y = 200,
        w = 70,
        h = 40,
        checked = false,
        on_change = function(self)
            log.info("auto_switch", "state", self:get_state())
        end
    })

    airui.label({
        parent = content,
        x = 20,
        y = 280,
        w = 170,
        h = 48,
        text = "自动更新间隔(秒):",
        font_size = 26,
        color = 0x000000,
        align = airui.TEXT_ALIGN_RIGHT
    })

    keyboard = airui.keyboard({
        mode = "numeric",
        auto_hide = true,
        preview = true,
        preview_height = 60,
        w = 720,
        h = 220
    })

    interval_textarea = airui.textarea({
        parent = content,
        x = 200,
        y = 280,
        w = 300,
        h = 48,
        placeholder = "3600",
        text = "",
        max_len = 10,
        font_size = 24,
        keyboard = keyboard
    })

    save_btn = airui.button({
        parent = content,
        x = 180,
        y = 380,
        w = 120,
        h = 56,
        text = "保存设置",
        font_size = 24,
        style = {
            bg_color = 0x2195F6,
            pressed_bg_color = 0x0B5EA8,
            text_color = 0xFFFFFF,
            pressed_text_color = 0xFFFFFF,
            radius = 8,
            border_width = 0,
            pad = 8,
            focus_outline_color = 0xFFB300,
            focus_outline_width = 2,
        },
        on_click = function()
            local auto = auto_switch:get_state()
            local interval_text = interval_textarea:get_text()
            local interval = tonumber(interval_text)
            if not interval or interval <= 0 then
                interval = 3600
                interval_textarea:set_text("3600")
            end
            sys.publish("FOTA_SAVE_SETTINGS", auto, interval)
        end
    })

    upgrade_btn = airui.button({
        parent = content,
        x = 320,
        y = 380,
        w = 120,
        h = 56,
        text = "固件升级",
        font_size = 24,
        style = {
            bg_color = 0xFF9A27,
            pressed_bg_color = 0xE68900,
            text_color = 0xFFFFFF,
            pressed_text_color = 0xFFFFFF,
            radius = 8,
            border_width = 0,
            pad = 8,
            focus_outline_color = 0xFFB300,
            focus_outline_width = 2,
        },
        on_click = function()
            sys.publish("FOTA_CHECK")
        end
    })
end

local function get_version()
    local ver = _G.VERSION
    if ver and ver ~= "" then return ver end
    local ok, result = pcall(rtos.version)
    if ok and result then return result end
    return "未知"
end

local function update_version()
    if version_label then
        version_label:set_text(get_version())
    end
    if airui_version_label then
        local airui_ver = airui.version()
        airui_version_label:set_text(airui_ver or "未知")
    end
end

local function on_settings_response(auto, interval)
    if not exwin.is_active(win_id) then
        log.debug("fota_win", "window not active, ignore settings response")
        return
    end
    if not auto_switch or not interval_textarea then
        log.warn("fota_win", "controls destroyed, ignore settings response")
        stop_retry_timer()
        return
    end
    auto_switch:set_state(auto)
    interval_textarea:set_text(tostring(interval))
    settings_loaded = true
    stop_retry_timer()
    log.info("fota_win", "settings loaded", auto, interval)
end

local function on_create()
    create_ui()
    update_version()
    settings_loaded = false
    sys.subscribe("FOTA_SETTINGS", on_settings_response)
    sys.publish("FOTA_GET_SETTINGS")
    start_retry_timer()
end

local function on_destroy()
    sys.unsubscribe("FOTA_SETTINGS", on_settings_response)
    stop_retry_timer()
    if keyboard then
        keyboard:destroy()
        keyboard = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    version_label, airui_version_label, auto_switch, interval_textarea, save_btn, upgrade_btn = nil, nil, nil, nil, nil, nil
    settings_loaded = false
end

local function on_get_focus()
    update_version()
    settings_loaded = false
    sys.publish("FOTA_GET_SETTINGS")
    start_retry_timer()
end

local function on_lose_focus() end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_FOTA_WIN", open_handler)