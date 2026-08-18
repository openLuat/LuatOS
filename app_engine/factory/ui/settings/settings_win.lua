--[[
@module  settings_win
@summary 设置主页面窗口
@version 1.1 (自适应分辨率)
@date    2026.04.16
@author  江访
]]

require "settings_display_win"
require "settings_storage_win"
require "storage_pri_win"
require "settings_about_win"
require "settings_sound_win"
require "wifi_list_win"
require "settings_iot_win"
require "settings_fota_win"
require "settings_auto_win"
local titlebar = require "settings_titlebar"

local window_id = nil
local main_container
local screen_w, screen_h = 480, 800
local margin = 10
local card_w = 460
local card_h = 70
local card_spacing = 20

local COLOR_PRIMARY        = 0x007AFF
local COLOR_BG             = 0xF5F5F5
local COLOR_CARD           = 0xFFFFFF
local COLOR_TEXT           = 0x333333
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_DIVIDER        = 0xE0E0E0
local COLOR_WHITE          = 0xFFFFFF

-- 是否为低分辨率横屏（如 480x272）：设置页改为紧凑两列布局
local is_compact = false

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_w, screen_h = phys_h, phys_w
    end
    is_compact = (screen_h > 0 and screen_h < 320) and (screen_w > screen_h)
    margin = math.floor(screen_w * 0.02)
    if is_compact then
        -- 紧凑两列：卡片横排，宽度约占 46%，高度 40px 足够放 16 号字（文字高 24px）
        card_w = math.floor((screen_w - 3 * margin) / 2)
        card_h = 40
        card_spacing = 2
    else
        card_w = screen_w - 2 * margin
        card_h = math.max(42, math.floor(screen_h * 0.09))
        card_spacing = math.floor(screen_h * 0.015)
    end
end

local function build_ui()
    update_screen_size()
    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = COLOR_BG
    })

    -- 标题栏（使用共享组件）
    local _, th = titlebar.create(main_container, "设置", screen_w, function() exwin.close(window_id) end)
    local ct = airui.container({
        parent = main_container,
        x = 0, y = th,
        w = screen_w, h = screen_h - th,
        color = COLOR_BG
    })

    local function create_card(x, y, w, h, title, on_click)
        local card = airui.container({
            parent = ct,
            x = x, y = y,
            w = w, h = h,
            color = COLOR_WHITE,
            radius = 8,
            on_click = on_click
        })
        -- 文字高度按实际字号预留：16 号字至少需 24px（字号+8 余量），字号更大则按更大的预留
        local font_size = math.floor((is_compact and 16 or 24) * _G.density_scale)
        local label_h = font_size + 8
        local label_y = math.floor((h - label_h) / 2)
        airui.label({
            parent = card,
            x = math.floor((is_compact and 8 or 20) * _G.density_scale), y = label_y,
            w = math.floor((is_compact and 120 or 200) * _G.density_scale), h = label_h,
            text = title,
            font_size = font_size,
            color = COLOR_TEXT,
            align = airui.TEXT_ALIGN_LEFT
        })
        if not is_compact then
            airui.label({
                parent = card,
                x = w - math.floor(50 * _G.density_scale), y = label_y,
                w = math.floor(30 * _G.density_scale), h = label_h,
                text = ">",
                font_size = font_size,
                color = COLOR_TEXT_SECONDARY,
                align = airui.TEXT_ALIGN_CENTER
            })
        end
    end

    local cfg = _G.project_config or {}
    local fe = cfg.features or {}
    local ui = cfg.ui or {}
    local has_wifi = fe.wifi
    local has_buzzer = fe.buzzer
    local has_storage = fe.sd_card or fe.nand_flash

    -- 收集入口列表
    local entries = {}
    local function add_entry(label, event)
        entries[#entries + 1] = { label = label, event = event }
    end
    add_entry("IOT账号", "OPEN_IOT_WIN")
    if has_wifi then add_entry("WiFi设置", "OPEN_WIFI_WIN") end
    add_entry("显示亮度", "OPEN_DISPLAY_WIN")
    if ui.show_storage_settings then add_entry("存储和内存", "OPEN_STORAGE_WIN") end
    if has_storage then add_entry("存储顺序", "OPEN_STORAGE_PRI_WIN") end
    add_entry("系统更新", "OPEN_FOTA_WIN")
    if has_buzzer and ui.show_buzzer_settings then add_entry("触摸音效", "OPEN_SOUND_WIN") end
    add_entry("后装APP自启", "OPEN_AUTOSTART_WIN")
    add_entry("关于设置", "OPEN_ABOUT_WIN")

    if is_compact then
        -- 两列网格：行数 = ceil(n/2)，行高 = card_h + card_spacing
        local cols = 2
        local top_pad = math.floor(8 * _G.density_scale)
        local y0 = top_pad
        for i, e in ipairs(entries) do
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            local x = margin + col * (card_w + margin)
            local y = y0 + row * (card_h + card_spacing)
            create_card(x, y, card_w, card_h, e.label, function() sys.publish(e.event) end)
        end
    else
        local function add_card(label, event, y)
            create_card(margin, y, card_w, card_h, label, function() sys.publish(event) end)
            return y + card_h + card_spacing
        end
        local y = math.floor(20 * _G.density_scale)
        for _, e in ipairs(entries) do
            y = add_card(e.label, e.event, y)
        end
    end
end

local function on_create() build_ui() end
local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
end
local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_SETTINGS_WIN", open_handler)
