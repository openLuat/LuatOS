--[[
@module  fota_progress_win
@summary FOTA升级过程显示窗口
@version 1.0
@date    2026.03.26
@author  江访
]]

local win_id = nil
local main_container
local status_label, back_btn, progress_bar
local close_enabled = false

local function create_ui()
    main_container = airui.container({
        x = 0,
        y = 0,
        w = 800,
        h = 480,
        color = 0xF8F9FA,
        parent = airui.screen
    })

    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 800,
        h = 60,
        color = 0x3F51B5
    })
    airui.label({
        parent = title_bar,
        x = 0,
        y = 12,
        w = 800,
        h = 40,
        text = "FOTA升级中",
        font_size = 32,
        color = 0xfefefe,
        align = airui.TEXT_ALIGN_CENTER
    })

    back_btn = airui.button({
        parent = main_container,
        x = 710,
        y = 15,
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
        y = 60,
        w = 800,
        h = 420,
        color = 0xF3F4F6
    })

    status_label = airui.label({
        parent = content,
        x = 20,
        y = 60,
        w = 760,
        h = 80,
        text = "正在启动升级...",
        font_size = 24,
        color = 0x000000,
        align = airui.TEXT_ALIGN_LEFT,
        multiline = true
    })

    progress_bar = airui.bar({
        parent = content,
        x = 20,
        y = 180,
        w = 760,
        h = 30,
        min = 0,
        max = 100,
        value = 0,
        radius = 6,
        indicator_color = 0x3F51B5,
        bg_color = 0xCCCCCC,
        show_progress_text = true,
        progress_text_format = "%d%%",
        border_width = 0
    })
end

local function set_back_btn_enabled(enabled)
    close_enabled = enabled
    if enabled then
        back_btn:set_style({
            bg_color = 0x2195F6,
            text_color = 0xfefefe
        })
    else
        back_btn:set_style({
            bg_color = 0xCCCCCC,
            text_color = 0x666666
        })
    end
end

local function on_fota_status(status, msg, extra)
    if not exwin.is_active(win_id) then return end
    log.info("fota_progress_win.on_fota_status", status, msg, extra)

    status_label:set_text(msg or status)

    if status == "DOWNLOAD_PROGRESS" then
        local percent = extra or 0
        progress_bar:set_value(percent, true)
    elseif status == "DOWNLOADING" then
        progress_bar:set_value(0, false)
    elseif status == "UPGRADE_SUCCESS" or status == "UPGRADE_FAIL" or
         status == "NO_NEW_VERSION" or status == "CHECK_FAIL" then
        set_back_btn_enabled(true)
        progress_bar:set_value(0, false)
    elseif status == "DOWNLOADING" or status == "DOWNLOAD_PROGRESS" then
        set_back_btn_enabled(false)
    end
end

local function on_create()
    create_ui()
    sys.subscribe("FOTA_STATUS", on_fota_status)
    status_label:set_text("正在连接服务器...")
    set_back_btn_enabled(false)
    progress_bar:set_value(0, false)
end

local function on_destroy()
    sys.unsubscribe("FOTA_STATUS", on_fota_status)
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    status_label, back_btn, progress_bar = nil, nil, nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_FOTA_PROGRESS_WIN", open_handler)