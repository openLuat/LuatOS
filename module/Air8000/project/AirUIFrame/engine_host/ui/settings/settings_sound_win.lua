--[[
@module  settings_sound_win
@summary 声音与触摸子页面
@version 1.0
@date    2026.04.24
]]

local win_id = nil
local main_container
local screen_w, screen_h = 480, 800
local margin = 15
local card_w = 460

-- UI 引用
local toggle_switch
local duration_slider, duration_label
local volume_slider, volume_label

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_w, screen_h = phys_h, phys_w
    end
    margin = math.floor(screen_w * 0.03)
    card_w = screen_w - 2 * margin
end

local function create_ui()
    update_screen_size()
    local btn_w = 50
    local btn_margin = 20
    local bar_x = btn_margin + btn_w + 10
    local bar_w = card_w - 2 * btn_margin - 2 * btn_w - 20
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = screen_w,
        h = screen_h,
        color = 0xF5F5F5
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = screen_w,
        h = 60,
        color = 0x3F51B5
    })
    local btn_back = airui.container({
        parent = title_bar,
        x = 10,
        y = 10,
        w = 50,
        h = 40,
        color = 0x3F51B5,
        on_click = function() exwin.close(win_id) end
    })
    airui.label({
        parent = btn_back,
        x = 0,
        y = 5,
        w = 50,
        h = 30,
        text = "<",
        font_size = 28,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = title_bar,
        x = 60,
        y = 14,
        w = 200,
        h = 40,
        text = "触摸音效",
        font_size = 32,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 内容区域
    local content = airui.container({
        parent = main_container,
        x = 0,
        y = 60,
        w = screen_w,
        h = screen_h - 60,
        color = 0xF5F5F5
    })

    -- 开启/关闭触摸反馈卡片
    local card_toggle = airui.container({
        parent = content,
        x = margin,
        y = 20,
        w = card_w,
        h = 70,
        color = 0xFFFFFF,
        radius = 8
    })
    airui.label({
        parent = card_toggle,
        x = 20,
        y = 20,
        w = 200,
        h = 30,
        text = "触摸反馈",
        font_size = 24,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 开关按钮（使用airui.switch）
    toggle_switch = airui.switch({
        parent = card_toggle,
        x = card_w - 80,
        y = 15,
        w = 60,
        h = 30,
        checked = true,
        on_change = function(self)
            sys.publish("BUZZER_SET_ENABLED", self:get_state())
        end
    })

    -- 按下发声时长卡片
    local card_duration = airui.container({
        parent = content,
        x = margin,
        y = 110,
        w = card_w,
        h = 140,
        color = 0xFFFFFF,
        radius = 8
    })
    airui.label({
        parent = card_duration,
        x = 20,
        y = 10,
        w = 200,
        h = 30,
        text = "按下发声时长",
        font_size = 24,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })
    duration_label = airui.label({
        parent = card_duration,
        x = card_w - 120,
        y = 10,
        w = 100,
        h = 30,
        text = "50ms",
        font_size = 22,
        color = 0x666666,
        align = airui.TEXT_ALIGN_RIGHT
    })
    airui.button({
        parent = card_duration,
        x = btn_margin,
        y = 55,
        w = btn_w,
        h = 40,
        text = "-10",
        font_size = 20,
        style = {
            bg_color = 0xE0E0E0,
            pressed_bg_color = 0xFF9800,
            text_color = 0x333333,
            radius = 8,
            border_width = 1,
            border_color = 0xBDBDBD
        },
        on_click = function() sys.publish("BUZZER_DURATION_DECREASE") end
    })
    duration_slider = airui.bar({
        parent = card_duration,
        x = bar_x,
        y = 65,
        w = bar_w,
        h = 25,
        min = 20,
        max = 500,
        value = 50,
        indicator_color = 0xFF9800,
        bg_color = 0xE0E0E0
    })
    airui.button({
        parent = card_duration,
        x = card_w - btn_margin - btn_w,
        y = 55,
        w = btn_w,
        h = 40,
        text = "+10",
        font_size = 20,
        style = {
            bg_color = 0xE0E0E0,
            pressed_bg_color = 0xFF9800,
            text_color = 0x333333,
            radius = 8,
            border_width = 1,
            border_color = 0xBDBDBD
        },
        on_click = function() sys.publish("BUZZER_DURATION_INCREASE") end
    })
    airui.label({
        parent = card_duration,
        x = 20,
        y = 110,
        w = 80,
        h = 25,
        text = "测试",
        font_size = 20,
        color = 0x2196F3,
        align = airui.TEXT_ALIGN_LEFT,
        on_click = function()
            sys.publish("BUZZER_PLAY_TEST")
        end
    })

    -- 声音大小卡片
    local card_volume = airui.container({
        parent = content,
        x = margin,
        y = 270,
        w = card_w,
        h = 140,
        color = 0xFFFFFF,
        radius = 8
    })
    airui.label({
        parent = card_volume,
        x = 20,
        y = 10,
        w = 200,
        h = 30,
        text = "声音大小",
        font_size = 24,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })
    volume_label = airui.label({
        parent = card_volume,
        x = card_w - 120,
        y = 10,
        w = 100,
        h = 30,
        text = "50",
        font_size = 22,
        color = 0x666666,
        align = airui.TEXT_ALIGN_RIGHT
    })
    airui.button({
        parent = card_volume,
        x = btn_margin,
        y = 55,
        w = btn_w,
        h = 40,
        text = "-10",
        font_size = 20,
        style = {
            bg_color = 0xE0E0E0,
            pressed_bg_color = 0xE91E63,
            text_color = 0x333333,
            radius = 8,
            border_width = 1,
            border_color = 0xBDBDBD
        },
        on_click = function() sys.publish("BUZZER_VOLUME_DECREASE") end
    })
    volume_slider = airui.bar({
        parent = card_volume,
        x = bar_x,
        y = 65,
        w = bar_w,
        h = 25,
        min = 10,
        max = 100,
        value = 50,
        indicator_color = 0xE91E63,
        bg_color = 0xE0E0E0
    })
    airui.button({
        parent = card_volume,
        x = card_w - btn_margin - btn_w,
        y = 55,
        w = btn_w,
        h = 40,
        text = "+10",
        font_size = 20,
        style = {
            bg_color = 0xE0E0E0,
            pressed_bg_color = 0xE91E63,
            text_color = 0x333333,
            radius = 8,
            border_width = 1,
            border_color = 0xBDBDBD
        },
        on_click = function() sys.publish("BUZZER_VOLUME_INCREASE") end
    })
    airui.label({
        parent = card_volume,
        x = 20,
        y = 110,
        w = 80,
        h = 25,
        text = "测试",
        font_size = 20,
        color = 0x2196F3,
        align = airui.TEXT_ALIGN_LEFT,
        on_click = function()
            sys.publish("BUZZER_PLAY_TEST")
        end
    })
end

-- ==================== UI 更新回调 ====================

local function update_enabled_ui(val)
    if not toggle_switch then return end
    if toggle_switch:get_state() == val then return end
    toggle_switch:set_state(val)
end

local function update_duration_ui(val)
    if duration_label then
        duration_label:set_text(tostring(val) .. "ms")
    end
    if duration_slider then
        duration_slider:set_value(val)
    end
end

local function update_volume_ui(val)
    if volume_label then
        volume_label:set_text(tostring(val))
    end
    if volume_slider then
        volume_slider:set_value(val)
    end
end

-- ==================== 窗口生命周期 ====================

local function on_create()
    create_ui()
    sys.publish("BUZZER_GET_ENABLED")
    sys.publish("BUZZER_GET_DURATION")
    sys.publish("BUZZER_GET_VOLUME")
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    toggle_switch = nil
    duration_slider = nil
    duration_label = nil
    volume_slider = nil
    volume_label = nil
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

-- ==================== 事件订阅 ====================

sys.subscribe("BUZZER_ENABLED_VALUE", function(val)
    update_enabled_ui(val)
end)

sys.subscribe("BUZZER_ENABLED_CHANGED", update_enabled_ui)
sys.subscribe("BUZZER_DURATION_VALUE", update_duration_ui)
sys.subscribe("BUZZER_DURATION_CHANGED", update_duration_ui)
sys.subscribe("BUZZER_VOLUME_VALUE", update_volume_ui)
sys.subscribe("BUZZER_VOLUME_CHANGED", update_volume_ui)

sys.subscribe("OPEN_SOUND_WIN", open_handler)
