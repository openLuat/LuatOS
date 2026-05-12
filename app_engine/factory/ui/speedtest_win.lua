--[[
@module  speedtest_win
@summary 网络测速窗口模块（UI层）
@version 1.0.0
@date    2026.04.28
@author  江访
]]

local window_id = nil
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
local top_h = 60

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
    top_h = 60
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

local function build_ui()
    update_screen_size()
    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = COLOR_CARD,
        scrollable = true,
    })

    local tb = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = math.floor(top_h * _G.density_scale),
        color = COLOR_PRIMARY
    })
    local bb = airui.container({
        parent = tb,
        x = math.floor(10 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(50 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        color = COLOR_PRIMARY,
        on_click = function()
            if window_id then exwin.close(window_id) end
        end
    })
    airui.label({
        parent = bb,
        x = 0, y = math.floor(5 * _G.density_scale),
        w = math.floor(50 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = "<",
        font_size = math.floor(28 * _G.density_scale),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = tb,
        x = math.floor(60 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(140 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        text = "网络测速",
        font_size = math.floor(32 * _G.density_scale),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_LEFT
    })

    local cy = math.floor((top_h + 10) * _G.density_scale)
    local ch = screen_h - cy

    local cw = math.floor((screen_w - margin * 3) / 2)
    local cah = math.min(math.floor(ch * 0.35), math.floor(250 * _G.density_scale))

    local aw = cw
    local ah = math.floor(cah * 0.65)

    local bw = math.floor(screen_w * 0.65)
    local bh = math.floor(math.min(math.floor(60 * _G.density_scale), math.floor(screen_h * 0.075 * _G.density_scale)))

    local cay = cy
    local cg = margin

    local dc = airui.container({
        parent = main_container,
        x = margin,
        y = cay,
        w = cw,
        h = cah,
        color = COLOR_CARD,
        radius = 48
    })
    local isz = math.floor(math.min(math.floor(40 * _G.density_scale), math.floor(cw * 0.19 * _G.density_scale)))
    local iy = math.floor(cah * 0.08)
    airui.label({
        parent = dc,
        x = 0,
        y = iy + isz + math.floor(5 * _G.density_scale),
        w = cw,
        h = math.floor(cah * 0.12),
        text = "下载速度",
        font_size = math.floor(cah * 0.09 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    download_label = airui.label({
        parent = dc,
        x = 0,
        y = math.floor(cah * 0.45),
        w = cw,
        h = math.floor(cah * 0.28),
        text = "--",
        font_size = math.min(math.floor(cah * 0.3), math.floor(60 * _G.density_scale)),
        color = COLOR_PRIMARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    download_unit_label = airui.label({
        parent = dc,
        x = 0,
        y = math.floor(cah * 0.78),
        w = cw,
        h = math.floor(cah * 0.12),
        text = "Kbps",
        font_size = math.min(math.floor(cah * 0.09), math.floor(20 * _G.density_scale)),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    local uc = airui.container({
        parent = main_container,
        x = margin + cw + cg,
        y = cay,
        w = cw,
        h = cah,
        color = COLOR_CARD,
        radius = 48
    })
    airui.label({
        parent = uc,
        x = 0,
        y = iy + isz + math.floor(5 * _G.density_scale),
        w = cw,
        h = math.floor(cah * 0.12),
        text = "上传速度",
        font_size = math.floor(cah * 0.09 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    upload_label = airui.label({
        parent = uc,
        x = 0,
        y = math.floor(cah * 0.45),
        w = cw,
        h = math.floor(cah * 0.28),
        text = "--",
        font_size = math.min(math.floor(cah * 0.3), math.floor(60 * _G.density_scale)),
        color = COLOR_DANGER,
        align = airui.TEXT_ALIGN_CENTER
    })
    upload_unit_label = airui.label({
        parent = uc,
        x = 0,
        y = math.floor(cah * 0.78),
        w = cw,
        h = math.floor(cah * 0.12),
        text = "Kbps",
        font_size = math.min(math.floor(cah * 0.09), math.floor(20 * _G.density_scale)),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    local ay = cay + cah + margin
    local pc = airui.container({
        parent = main_container,
        x = margin,
        y = ay,
        w = aw,
        h = ah,
        color = COLOR_CARD,
        radius = 36
    })
    airui.label({
        parent = pc,
        x = 0,
        y = math.floor(ah * 0.12),
        w = aw,
        h = math.floor(ah * 0.16),
        text = "延迟 (Ping)",
        font_size = math.floor(ah * 0.11 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    ping_label = airui.label({
        parent = pc,
        x = 0,
        y = math.floor(ah * 0.34),
        w = aw,
        h = math.floor(ah * 0.32),
        text = "--",
        font_size = math.floor(ah * 0.24 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = pc,
        x = 0,
        y = math.floor(ah * 0.76),
        w = aw,
        h = math.floor(ah * 0.16),
        text = "ms",
        font_size = math.floor(ah * 0.12 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    local jc = airui.container({
        parent = main_container,
        x = margin + cw + cg,
        y = ay,
        w = aw,
        h = ah,
        color = COLOR_CARD,
        radius = 36
    })
    airui.label({
        parent = jc,
        x = 0,
        y = math.floor(ah * 0.12),
        w = aw,
        h = math.floor(ah * 0.16),
        text = "抖动 (Jitter)",
        font_size = math.floor(ah * 0.11 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    jitter_label = airui.label({
        parent = jc,
        x = 0,
        y = math.floor(ah * 0.34),
        w = aw,
        h = math.floor(ah * 0.32),
        text = "--",
        font_size = math.floor(ah * 0.24 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = jc,
        x = 0,
        y = math.floor(ah * 0.76),
        w = aw,
        h = math.floor(ah * 0.16),
        text = "ms",
        font_size = math.floor(ah * 0.12 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    local by = ay + ah + margin
    start_btn = airui.button({
        parent = main_container,
        x = math.floor((screen_w - bw) / 2),
        y = by,
        w = bw,
        h = bh,
        text = "开始测速",
        font_size = math.floor(bh * 0.35 * _G.density_scale),
        font_color = COLOR_WHITE,
        bg_color = COLOR_PRIMARY,
        radius = bh / 2,
        on_click = function()
            sys.publish("SPEEDTEST_START")
        end
    })

    local sy = by + bh + math.floor(margin * 1.5)
    status_label = airui.label({
        parent = main_container,
        x = 0,
        y = sy,
        w = screen_w,
        h = math.floor(screen_h * 0.04),
        text = "就绪",
        font_size = math.floor(screen_h * 0.022 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })
end

local function on_test_started()
    if start_btn then
        start_btn:set_text("测速中...")
        start_btn:set_style({ bg_color = COLOR_TEXT_SECONDARY, text_color = COLOR_WHITE })
    end
    reset_display()
end

local function on_test_result(result)
    if result.ping then
        if ping_label then ping_label:set_text(format_latency(result.ping)) end
    else
        if ping_label then ping_label:set_text("ERR") end
    end
    if result.jitter then
        if jitter_label then jitter_label:set_text(string.format("%.1f", result.jitter)) end
    else
        if jitter_label then jitter_label:set_text("ERR") end
    end
    if result.download then
        if download_label then download_label:set_text(format_speed(result.download)) end
        if download_unit_label then download_unit_label:set_text(get_speed_unit(result.download)) end
    else
        if download_label then download_label:set_text("失败") end
        if download_unit_label then download_unit_label:set_text("") end
    end
    if result.upload then
        if upload_label then upload_label:set_text(format_speed(result.upload)) end
        if upload_unit_label then upload_unit_label:set_text(get_speed_unit(result.upload)) end
    else
        if upload_label then upload_label:set_text("失败") end
        if upload_unit_label then upload_unit_label:set_text("") end
    end
end

local function on_status_text(st)
    if status_label then status_label:set_text(st) end
end

local function on_test_finished()
    if start_btn then
        start_btn:set_text("重新测速")
        start_btn:set_style({ bg_color = COLOR_PRIMARY_DARK, text_color = COLOR_WHITE })
    end
end

local function on_create()
    build_ui()
    sys.subscribe("SPDTEST_STARTED", on_test_started)
    sys.subscribe("SPDTEST_RESULT", on_test_result)
    sys.subscribe("SPDTEST_STATUS", on_status_text)
    sys.subscribe("SPDTEST_FINISHED", on_test_finished)
end

local function on_destroy()
    sys.unsubscribe("SPDTEST_STARTED", on_test_started)
    sys.unsubscribe("SPDTEST_RESULT", on_test_result)
    sys.unsubscribe("SPDTEST_STATUS", on_status_text)
    sys.unsubscribe("SPDTEST_FINISHED", on_test_finished)
    sys.publish("SPEEDTEST_CANCEL")
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    download_label = nil
    upload_label = nil
    ping_label = nil
    jitter_label = nil
    status_label = nil
    start_btn = nil
    download_unit_label = nil
    upload_unit_label = nil
    window_id = nil
end

local function ongf() end

local function onlf() end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = ongf,
        on_lose_focus = onlf,
    })
end

sys.subscribe("OPEN_SPEEDTEST_WIN", open_handler)