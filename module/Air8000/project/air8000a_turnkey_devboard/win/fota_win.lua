--[[
@module  fota_win
@summary FOTA设置窗口
@version 1.0
@date    2026.03.20
@author  江访
@usage
订阅"OPEN_FOTA_WIN"事件打开窗口。
包含当前版本显示、AirUI版本显示、开机自动更新开关、自动更新时间间隔（秒）、保存设置按钮、手动升级按钮。
通过消息与fota_app交互，不直接操作存储。
]]

local win_id = nil
local main_container
local version_label, airui_version_label, auto_switch, interval_textarea, save_btn, upgrade_btn
local keyboard
local settings_loaded = false

-- 重试定时器函数（具名，便于停止）
local function retry_timer_func()
    -- 窗口可能已关闭，检查控件是否存在
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
    -- 重试计数（存储在函数属性中）
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

-- 停止重试定时器
local function stop_retry_timer()
    sys.timerStop(retry_timer_func)
end

-- 启动重试定时器
local function start_retry_timer()
    stop_retry_timer()
    retry_timer_func.retry_count = 0
    sys.timerLoopStart(retry_timer_func, 2000)
end

-- 创建UI
local function create_ui()
    main_container = airui.container({
        x = 0,
        y = 0,
        w = 480,
        h = 320,
        color = 0xF8F9FA,
        parent = airui.screen
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 480,
        h = 40,
        color = 0x3F51B5
    })
    airui.label({
        parent = title_bar,
        x = 0,
        y = 4,
        w = 480,
        h = 32,
        text = "FOTA设置",
        font_size = 24,
        color = 0xfefefe,
        align = airui.TEXT_ALIGN_CENTER
    })
    local back_btn = airui.button({
        parent = main_container,
        x = 400,
        y = 5,
        w = 70,
        h = 30,
        text = "返回",
        font_size = 16,
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
    
    -- 内容区域
    local content = airui.container({
        parent = main_container,
        x = 0,
        y = 40,
        w = 480,
        h = 280,
        color = 0xF3F4F6
    })

    -- 当前固件版本
    airui.label({
        parent = content,
        x = 20,
        y = 15,
        w = 160,
        h = 30,
        text = "当前固件版本:",
        font_size = 18,
        color = 0x000000,
        align = airui.TEXT_ALIGN_RIGHT
    })
    local version_bg = airui.container({
        parent = content,
        x = 190,
        y = 12,
        w = 200,
        h = 28,
        color = 0xEEEEEE,
        radius = 4
    })
    version_label = airui.label({
        parent = version_bg,
        x = 8,
        y = 6,
        w = 184,
        h = 20,
        text = "获取中...",
        font_size = 16,
        color = 0x000000,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- AirUI版本
    airui.label({
        parent = content,
        x = 20,
        y = 50,
        w = 160,
        h = 30,
        text = "AirUI版本:",
        font_size = 18,
        color = 0x000000,
        align = airui.TEXT_ALIGN_RIGHT
    })
    local airui_version_bg = airui.container({
        parent = content,
        x = 190,
        y = 47,
        w = 200,
        h = 28,
        color = 0xEEEEEE,
        radius = 4
    })
    airui_version_label = airui.label({
        parent = airui_version_bg,
        x = 8,
        y = 6,
        w = 184,
        h = 20,
        text = "获取中...",
        font_size = 16,
        color = 0x000000,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 开机自动更新开关
    airui.label({
        parent = content,
        x = 20,
        y = 90,
        w = 160,
        h = 30,
        text = "开机自动更新:",
        font_size = 18,
        color = 0x000000,
        align = airui.TEXT_ALIGN_RIGHT
    })
    auto_switch = airui.switch({
        parent = content,
        x = 190,
        y = 87,
        w = 60,
        h = 30,
        checked = false,
        on_change = function(self)
            log.info("auto_switch", "state", self:get_state())
        end
    })

    -- 自动更新时间间隔（秒）
    airui.label({
        parent = content,
        x = 20,
        y = 130,
        w = 160,
        h = 30,
        text = "自动更新间隔(秒):",
        font_size = 18,
        color = 0x000000,
        align = airui.TEXT_ALIGN_RIGHT
    })

    -- 数字键盘
    keyboard = airui.keyboard({
        mode = "numeric",
        auto_hide = true,
        preview = true,
        preview_height = 40,
        w = 480,
        h = 120
    })

    interval_textarea = airui.textarea({
        parent = content,
        x = 190,
        y = 125,
        w = 150,
        h = 36,
        placeholder = "3600",
        text = "",
        max_len = 10,
        font_size = 18,
        keyboard = keyboard
    })

    -- 保存按钮
    save_btn = airui.button({
        parent = content,
        x = 90,
        y = 200,
        w = 140,
        h = 40,
        text = "保存设置",
        font_size = 16,
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

    -- 固件升级按钮
    upgrade_btn = airui.button({
        parent = content,
        x = 250,
        y = 200,
        w = 140,
        h = 40,
        text = "固件升级",
        font_size = 16,
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

-- 安全获取固件版本
local function get_version()
    local ver = _G.VERSION
    if ver and ver ~= "" then return ver end
    local ok, result = pcall(rtos.version)
    if ok and result then return result end
    return "未知"
end

-- 更新版本显示
local function update_version()
    if version_label then
        version_label:set_text(get_version())
    end
    if airui_version_label then
        local airui_ver = airui.version()
        airui_version_label:set_text(airui_ver or "未知")
    end
end

-- 处理设置响应消息
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

-- 窗口创建
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
    stop_retry_timer()  -- 关键：停止重试定时器
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

local function on_lose_focus()
    -- 无操作
end

-- 订阅打开窗口的消息
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_FOTA_WIN", open_handler)