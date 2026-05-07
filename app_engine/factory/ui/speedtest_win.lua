--[[
@module  speedtest_win
@summary 网络测速窗口模块（UI层）
@version 1.0.0
@date    2026.04.28
]]

local win_id = nil
local main_container = nil

local download_label = nil
local upload_label = nil
local ping_label = nil
local jitter_label = nil
local status_label = nil
local start_btn = nil
local download_unit_label = nil
local upload_unit_label = nil

local screen_w, screen_h = 480, 800
local margin = 15
local title_h = 60

local COLOR_PRIMARY        = 0x007AFF
local COLOR_PRIMARY_DARK   = 0x0056B3
local COLOR_BG             = 0xF5F5F5
local COLOR_CARD           = 0xFFFFFF
local COLOR_TEXT           = 0x333333
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_DIVIDER        = 0xE0E0E0
local COLOR_WHITE          = 0xFFFFFF
local COLOR_DANGER         = 0xE63946

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_w, screen_h = phys_h, phys_w
    end
    margin = math.floor(screen_w * 0.03)
    title_h = 60
end

local function format_speed(value)
    if value == nil then return "--" end
    local kbps = value * 1000
    if kbps >= 1000 then
        return string.format("%.1f", kbps / 1000)
    else
        return string.format("%d", math.floor(kbps))
    end
end

local function get_speed_unit(value)
    if value == nil then return "Kbps" end
    local kbps = value * 1000
    if kbps >= 1000 then
        return "Mbps"
    else
        return "Kbps"
    end
end

local function format_latency(value)
    if value == nil then return "--" end
    return string.format("%d", math.floor(value))
end

local function reset_display()
    if download_label then download_label:set_text("--") end
    if upload_label then upload_label:set_text("--") end
    if ping_label then ping_label:set_text("--") end
    if jitter_label then jitter_label:set_text("--") end
    if status_label then status_label:set_text("就绪") end
end

local function create_ui()
    update_screen_size()
    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = COLOR_CARD,
        scrollable = true,
    })

    local title_bar = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = math.floor(title_h * _G.density_scale),
        color = COLOR_PRIMARY
    })
    local btn_back = airui.container({
        parent = title_bar,
        x = math.floor(10 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(50 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        color = COLOR_PRIMARY,
        on_click = function()
            if win_id then exwin.close(win_id) end
        end
    })
    airui.label({
        parent = btn_back,
        x = 0, y = math.floor(5 * _G.density_scale),
        w = math.floor(50 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = "<",
        font_size = math.floor(28 * _G.density_scale),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = title_bar,
        x = math.floor(60 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(140 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        text = "网络测速",
        font_size = math.floor(32 * _G.density_scale),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_LEFT
    })

    local content_y = math.floor((title_h + 10) * _G.density_scale)
    local content_h = screen_h - content_y

    local card_w = math.floor((screen_w - margin * 3) / 2)
    local card_h = math.min(math.floor(content_h * 0.35), math.floor(250 * _G.density_scale))

    local aux_w = card_w
    local aux_h = math.floor(card_h * 0.65)

    local button_w = math.floor(screen_w * 0.65)
    local button_h = math.floor(math.min(math.floor(60 * _G.density_scale), math.floor(screen_h * 0.075 * _G.density_scale)))

    local card_y = content_y
    local card_gap = margin

    local download_card = airui.container({
        parent = main_container,
        x = margin,
        y = card_y,
        w = card_w,
        h = card_h,
        color = COLOR_CARD,
        radius = 48
    })
    local icon_size = math.floor(math.min(math.floor(40 * _G.density_scale), math.floor(card_w * 0.19 * _G.density_scale)))
    local icon_y = math.floor(card_h * 0.08)
    airui.label({
        parent = download_card,
        x = 0,
        y = icon_y + icon_size + math.floor(5 * _G.density_scale),
        w = card_w,
        h = math.floor(card_h * 0.12),
        text = "下载速度",
        font_size = math.floor(card_h * 0.09 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    download_label = airui.label({
        parent = download_card,
        x = 0,
        y = math.floor(card_h * 0.45),
        w = card_w,
        h = math.floor(card_h * 0.28),
        text = "--",
        font_size = math.min(math.floor(card_h * 0.3), math.floor(60 * _G.density_scale)),
        color = COLOR_PRIMARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    download_unit_label = airui.label({
        parent = download_card,
        x = 0,
        y = math.floor(card_h * 0.78),
        w = card_w,
        h = math.floor(card_h * 0.12),
        text = "Kbps",
        font_size = math.min(math.floor(card_h * 0.09), math.floor(20 * _G.density_scale)),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    local upload_card = airui.container({
        parent = main_container,
        x = margin + card_w + card_gap,
        y = card_y,
        w = card_w,
        h = card_h,
        color = COLOR_CARD,
        radius = 48
    })
    airui.label({
        parent = upload_card,
        x = 0,
        y = icon_y + icon_size + math.floor(5 * _G.density_scale),
        w = card_w,
        h = math.floor(card_h * 0.12),
        text = "上传速度",
        font_size = math.floor(card_h * 0.09 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    upload_label = airui.label({
        parent = upload_card,
        x = 0,
        y = math.floor(card_h * 0.45),
        w = card_w,
        h = math.floor(card_h * 0.28),
        text = "--",
        font_size = math.min(math.floor(card_h * 0.3), math.floor(60 * _G.density_scale)),
        color = COLOR_DANGER,
        align = airui.TEXT_ALIGN_CENTER
    })
    upload_unit_label = airui.label({
        parent = upload_card,
        x = 0,
        y = math.floor(card_h * 0.78),
        w = card_w,
        h = math.floor(card_h * 0.12),
        text = "Kbps",
        font_size = math.min(math.floor(card_h * 0.09), math.floor(20 * _G.density_scale)),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    local aux_y = card_y + card_h + margin
    local ping_card = airui.container({
        parent = main_container,
        x = margin,
        y = aux_y,
        w = aux_w,
        h = aux_h,
        color = COLOR_CARD,
        radius = 36
    })
    airui.label({
        parent = ping_card,
        x = 0,
        y = math.floor(aux_h * 0.12),
        w = aux_w,
        h = math.floor(aux_h * 0.16),
        text = "延迟 (Ping)",
        font_size = math.floor(aux_h * 0.11 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    ping_label = airui.label({
        parent = ping_card,
        x = 0,
        y = math.floor(aux_h * 0.34),
        w = aux_w,
        h = math.floor(aux_h * 0.32),
        text = "--",
        font_size = math.floor(aux_h * 0.24 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = ping_card,
        x = 0,
        y = math.floor(aux_h * 0.76),
        w = aux_w,
        h = math.floor(aux_h * 0.16),
        text = "ms",
        font_size = math.floor(aux_h * 0.12 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    local jitter_card = airui.container({
        parent = main_container,
        x = margin + card_w + card_gap,
        y = aux_y,
        w = aux_w,
        h = aux_h,
        color = COLOR_CARD,
        radius = 36
    })
    airui.label({
        parent = jitter_card,
        x = 0,
        y = math.floor(aux_h * 0.12),
        w = aux_w,
        h = math.floor(aux_h * 0.16),
        text = "抖动 (Jitter)",
        font_size = math.floor(aux_h * 0.11 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    jitter_label = airui.label({
        parent = jitter_card,
        x = 0,
        y = math.floor(aux_h * 0.34),
        w = aux_w,
        h = math.floor(aux_h * 0.32),
        text = "--",
        font_size = math.floor(aux_h * 0.24 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = jitter_card,
        x = 0,
        y = math.floor(aux_h * 0.76),
        w = aux_w,
        h = math.floor(aux_h * 0.16),
        text = "ms",
        font_size = math.floor(aux_h * 0.12 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    local btn_y = aux_y + aux_h + margin
    start_btn = airui.button({
        parent = main_container,
        x = math.floor((screen_w - button_w) / 2),
        y = btn_y,
        w = button_w,
        h = button_h,
        text = "开始测速",
        font_size = math.floor(button_h * 0.35 * _G.density_scale),
        font_color = COLOR_WHITE,
        bg_color = COLOR_PRIMARY,
        radius = button_h / 2,
        on_click = function()
            sys.publish("SPEEDTEST_START")
        end
    })

    local status_y = btn_y + button_h + math.floor(margin * 1.5)
    status_label = airui.label({
        parent = main_container,
        x = 0,
        y = status_y,
        w = screen_w,
        h = math.floor(screen_h * 0.04),
        text = "就绪",
        font_size = math.floor(screen_h * 0.022 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
end

local function on_spdtest_started()
    if start_btn then
        start_btn:set_text("测速中...")
        start_btn:set_style({ bg_color = COLOR_TEXT_SECONDARY, text_color = COLOR_WHITE })
    end
    reset_display()
end

local function on_spdtest_result(results)
    if results.ping then
        if ping_label then ping_label:set_text(format_latency(results.ping)) end
    else
        if ping_label then ping_label:set_text("ERR") end
    end
    if results.jitter then
        if jitter_label then jitter_label:set_text(string.format("%.1f", results.jitter)) end
    else
        if jitter_label then jitter_label:set_text("ERR") end
    end
    if results.download then
        if download_label then download_label:set_text(format_speed(results.download)) end
        if download_unit_label then download_unit_label:set_text(get_speed_unit(results.download)) end
    else
        if download_label then download_label:set_text("失败") end
        if download_unit_label then download_unit_label:set_text("") end
    end
    if results.upload then
        if upload_label then upload_label:set_text(format_speed(results.upload)) end
        if upload_unit_label then upload_unit_label:set_text(get_speed_unit(results.upload)) end
    else
        if upload_label then upload_label:set_text("失败") end
        if upload_unit_label then upload_unit_label:set_text("") end
    end
end

local function on_spdtest_status(status)
    if status_label then status_label:set_text(status) end
end

local function on_spdtest_finished()
    if start_btn then
        start_btn:set_text("重新测速")
        start_btn:set_style({ bg_color = COLOR_PRIMARY_DARK, text_color = COLOR_WHITE })
    end
end

local function on_create()
    create_ui()
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    -- 将组件引用置nil，避免测速回调中操作已销毁的UI对象导致死机
    download_label = nil
    upload_label = nil
    ping_label = nil
    jitter_label = nil
    status_label = nil
    start_btn = nil
    download_unit_label = nil
    upload_unit_label = nil
    win_id = nil
end

local function on_get_focus() end

local function on_lose_focus() end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_SPEEDTEST_WIN", open_handler)
sys.subscribe("SPDTEST_STARTED", on_spdtest_started)
sys.subscribe("SPDTEST_RESULT", on_spdtest_result)
sys.subscribe("SPDTEST_STATUS", on_spdtest_status)
sys.subscribe("SPDTEST_FINISHED", on_spdtest_finished)