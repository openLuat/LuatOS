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

local COLORS = {
    download_green = 0x1E6F5C,
    upload_red = 0xC4452C,
    primary_dark = 0x222F44,
    text_primary = 0x1E2A44,
    text_secondary = 0x6A7A99,
    text_aux = 0x2C3E66,
    text_label = 0x7A89A8,
    white = 0xFFFFFF,
    bg_card = 0xF8FAFE,
    border = 0xEFF3F9,
    success = 0x27AE60,
    warning = 0xE67E22,
    danger = 0xEF4444
}

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
        color = COLORS.white
    })

    local title_bar = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = title_h,
        color = 0x3F51B5
    })
    local btn_back = airui.container({
        parent = title_bar,
        x = 10, y = 10,
        w = 50, h = 40,
        color = 0x3F51B5,
        on_click = function()
            if win_id then exwin.close(win_id) end
        end
    })
    airui.label({
        parent = btn_back,
        x = 0, y = 5,
        w = 50, h = 30,
        text = "<",
        font_size = 28,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = title_bar,
        x = 60, y = 8,
        w = 140, h = 40,
        text = "网络测速",
        font_size = 32,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_LEFT
    })

    local content_y = title_h + 10
    local content_h = screen_h - content_y

    local card_w = math.floor((screen_w - margin * 3) / 2)
    local card_h = math.floor(content_h * 0.35)

    local aux_w = card_w
    local aux_h = math.floor(card_h * 0.65)

    local button_w = math.floor(screen_w * 0.65)
    local button_h = math.min(60, math.floor(screen_h * 0.075))

    local card_y = content_y
    local card_gap = margin

    local download_card = airui.container({
        parent = main_container,
        x = margin,
        y = card_y,
        w = card_w,
        h = card_h,
        color = COLORS.bg_card,
        radius = 48
    })
    local icon_size = math.min(40, math.floor(card_w * 0.19))
    local icon_y = math.floor(card_h * 0.08)
    airui.label({
        parent = download_card,
        x = 0,
        y = icon_y + icon_size + 5,
        w = card_w,
        h = math.floor(card_h * 0.12),
        text = "下载速度",
        font_size = math.floor(card_h * 0.09),
        color = COLORS.text_secondary,
        align = airui.TEXT_ALIGN_CENTER
    })
    download_label = airui.label({
        parent = download_card,
        x = 0,
        y = math.floor(card_h * 0.45),
        w = card_w,
        h = math.floor(card_h * 0.28),
        text = "--",
        font_size = math.floor(card_h * 0.26),
        color = COLORS.download_green,
        align = airui.TEXT_ALIGN_CENTER
    })
    download_unit_label = airui.label({
        parent = download_card,
        x = 0,
        y = math.floor(card_h * 0.78),
        w = card_w,
        h = math.floor(card_h * 0.12),
        text = "Kbps",
        font_size = math.floor(card_h * 0.09),
        color = COLORS.text_secondary,
        align = airui.TEXT_ALIGN_CENTER
    })

    local upload_card = airui.container({
        parent = main_container,
        x = margin + card_w + card_gap,
        y = card_y,
        w = card_w,
        h = card_h,
        color = COLORS.bg_card,
        radius = 48
    })
    airui.label({
        parent = upload_card,
        x = 0,
        y = icon_y + icon_size + 5,
        w = card_w,
        h = math.floor(card_h * 0.12),
        text = "上传速度",
        font_size = math.floor(card_h * 0.09),
        color = COLORS.text_secondary,
        align = airui.TEXT_ALIGN_CENTER
    })
    upload_label = airui.label({
        parent = upload_card,
        x = 0,
        y = math.floor(card_h * 0.45),
        w = card_w,
        h = math.floor(card_h * 0.28),
        text = "--",
        font_size = math.floor(card_h * 0.26),
        color = COLORS.upload_red,
        align = airui.TEXT_ALIGN_CENTER
    })
    upload_unit_label = airui.label({
        parent = upload_card,
        x = 0,
        y = math.floor(card_h * 0.78),
        w = card_w,
        h = math.floor(card_h * 0.12),
        text = "Kbps",
        font_size = math.floor(card_h * 0.09),
        color = COLORS.text_secondary,
        align = airui.TEXT_ALIGN_CENTER
    })

    local aux_y = card_y + card_h + margin
    local ping_card = airui.container({
        parent = main_container,
        x = margin,
        y = aux_y,
        w = aux_w,
        h = aux_h,
        color = COLORS.bg_card,
        radius = 36
    })
    airui.label({
        parent = ping_card,
        x = 0,
        y = math.floor(aux_h * 0.12),
        w = aux_w,
        h = math.floor(aux_h * 0.16),
        text = "延迟 (Ping)",
        font_size = math.floor(aux_h * 0.11),
        color = COLORS.text_label,
        align = airui.TEXT_ALIGN_CENTER
    })
    ping_label = airui.label({
        parent = ping_card,
        x = 0,
        y = math.floor(aux_h * 0.34),
        w = aux_w,
        h = math.floor(aux_h * 0.32),
        text = "--",
        font_size = math.floor(aux_h * 0.24),
        color = COLORS.text_aux,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = ping_card,
        x = 0,
        y = math.floor(aux_h * 0.76),
        w = aux_w,
        h = math.floor(aux_h * 0.16),
        text = "ms",
        font_size = math.floor(aux_h * 0.12),
        color = COLORS.text_label,
        align = airui.TEXT_ALIGN_CENTER
    })

    local jitter_card = airui.container({
        parent = main_container,
        x = margin + card_w + card_gap,
        y = aux_y,
        w = aux_w,
        h = aux_h,
        color = COLORS.bg_card,
        radius = 36
    })
    airui.label({
        parent = jitter_card,
        x = 0,
        y = math.floor(aux_h * 0.12),
        w = aux_w,
        h = math.floor(aux_h * 0.16),
        text = "抖动 (Jitter)",
        font_size = math.floor(aux_h * 0.11),
        color = COLORS.text_label,
        align = airui.TEXT_ALIGN_CENTER
    })
    jitter_label = airui.label({
        parent = jitter_card,
        x = 0,
        y = math.floor(aux_h * 0.34),
        w = aux_w,
        h = math.floor(aux_h * 0.32),
        text = "--",
        font_size = math.floor(aux_h * 0.24),
        color = COLORS.text_aux,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = jitter_card,
        x = 0,
        y = math.floor(aux_h * 0.76),
        w = aux_w,
        h = math.floor(aux_h * 0.16),
        text = "ms",
        font_size = math.floor(aux_h * 0.12),
        color = COLORS.text_label,
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
        font_size = math.floor(button_h * 0.35),
        font_color = COLORS.white,
        bg_color = COLORS.primary_dark,
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
        font_size = math.floor(screen_h * 0.022),
        color = COLORS.text_secondary,
        align = airui.TEXT_ALIGN_CENTER
    })
end

local function on_spdtest_started()
    if start_btn then
        start_btn:set_text("测速中...")
        start_btn:set_style({ bg_color = COLORS.text_secondary })
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
        start_btn:set_style({ bg_color = COLORS.primary_dark })
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