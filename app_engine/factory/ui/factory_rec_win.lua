--[[
@module  factory_rec_win
@summary 应用工厂-录音播放窗口（UI层）
@version 1.1
@date    2026.08.12
@author  江访

消息协议:
订阅: OPEN_FACTORY_REC_WIN   → 创建录音播放窗口
订阅: FACTORY_REC_READY      → 音频初始化结果
订阅: FACTORY_REC_STATE      → 状态变更 idle/recording/playing
订阅: FACTORY_REC_STATUS     → 提示文本
订阅: FACTORY_REC_DURATION   → 录音计时
订阅: FACTORY_REC_FILE       → 录音完成文件大小
发布: FACTORY_REC_SETUP      → 初始化音频（进入时）
发布: FACTORY_REC_START      → 开始录音
发布: FACTORY_REC_STOP       → 停止录音
发布: FACTORY_REC_PLAY       → 播放录音
发布: FACTORY_REC_STOP_PLAY  → 停止播放
发布: FACTORY_REC_RESET      → 清理下电（退出时）

设计要点:
- 进入窗口 on_create 时初始化音频驱动（进APP开关，不常开）
- 退出窗口 on_destroy 时停止+下电
- 录音/播放互斥（状态机由业务层维护，UI 只反映状态）
- 录音按钮：空闲点按开始录音（最长 max_record_time 秒，到时自动停止）；
  录音中点按停止录音（audio_v2 新框架下 record_stop 真正停止）
]]

local window_id = nil
local main_container = nil

local rec_btn = nil
local play_btn = nil
local stop_btn = nil
local status_label = nil
local timer_label = nil
local size_label = nil

local current_state = "idle"

local screen_w, screen_h = 480, 800
local margin = 15

local COLOR_PRIMARY        = 0x007AFF
local COLOR_PRIMARY_DARK   = 0x0056B3
local COLOR_BG             = 0xF5F5F5
local COLOR_CARD           = 0xFFFFFF
local COLOR_TEXT           = 0x333333
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_DIVIDER        = 0xE0E0E0
local COLOR_WHITE          = 0xFFFFFF
local COLOR_DANGER         = 0xE63946
local COLOR_ACCENT         = 0xFF9800
local COLOR_GREEN          = 0x34C759

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_w, screen_h = phys_h, phys_w
    end
    margin = math.floor(screen_w * 0.03)
end

-- ==================== 按钮状态管理 ====================

local function set_button_style(btn, bg, fg)
    if not btn then return end
    btn:set_style({ bg_color = bg, text_color = fg })
end

local function set_state(s)
    current_state = s or "idle"
    if not rec_btn or not play_btn then return end
    if current_state == "recording" then
        rec_btn:set_text("停止录音")
        set_button_style(rec_btn, COLOR_DANGER, COLOR_WHITE)
        set_button_style(play_btn, COLOR_DIVIDER, COLOR_TEXT_SECONDARY)
        set_button_style(stop_btn, COLOR_DIVIDER, COLOR_TEXT_SECONDARY)
    elseif current_state == "playing" then
        rec_btn:set_text("开始录音")
        set_button_style(rec_btn, COLOR_PRIMARY, COLOR_WHITE)
        play_btn:set_text("停止播放")
        set_button_style(play_btn, COLOR_ACCENT, COLOR_WHITE)
        set_button_style(stop_btn, COLOR_DIVIDER, COLOR_TEXT_SECONDARY)
    else
        rec_btn:set_text("开始录音")
        set_button_style(rec_btn, COLOR_PRIMARY, COLOR_WHITE)
        play_btn:set_text("播放录音")
        set_button_style(play_btn, COLOR_GREEN, COLOR_WHITE)
        set_button_style(stop_btn, COLOR_DIVIDER, COLOR_TEXT_SECONDARY)
    end
end

-- ==================== 事件回调 ====================

local function on_ready(ok, msg)
    if status_label then
        if ok then
            status_label:set_text("音频就绪")
        else
            status_label:set_text(msg or "音频初始化失败")
        end
    end
end

local function on_state(data)
    if data and data.state then
        set_state(data.state)
    end
end

local function on_status(msg)
    if status_label and msg then
        status_label:set_text(msg)
    end
end

local function on_duration(sec)
    if timer_label then
        timer_label:set_text(string.format("%02d:%02d", math.floor(sec / 60), sec % 60))
    end
end

local function on_file(data)
    if size_label and data then
        local sz = data.size or 0
        if sz > 0 then
            size_label:set_text(string.format("文件大小: %.1f KB", sz / 1024))
        end
    end
end

-- ==================== UI 构建 ====================

local function build_ui()
    update_screen_size()
    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = COLOR_BG,
    })

    local titlebar = require "settings_titlebar"
    local _, th = titlebar.create(main_container, "录音播放", screen_w, function()
        if window_id then exwin.close(window_id) end
    end)

    local ct = airui.container({
        parent = main_container,
        x = 0, y = th,
        w = screen_w, h = screen_h - th,
        color = COLOR_BG,
    })

    local card_w = screen_w - 2 * margin

    -- 计时显示卡片
    local timer_card = airui.container({
        parent = ct,
        x = margin, y = math.floor(30 * _G.density_scale),
        w = card_w, h = math.floor(150 * _G.density_scale),
        color = COLOR_CARD,
        radius = 12,
    })
    timer_label = airui.label({
        parent = timer_card,
        x = 0, y = math.floor(25 * _G.density_scale),
        w = card_w, h = math.floor(70 * _G.density_scale),
        text = "00:00",
        font_size = math.floor(60 * _G.density_scale),
        color = COLOR_PRIMARY,
        align = airui.TEXT_ALIGN_CENTER,
    })
    size_label = airui.label({
        parent = timer_card,
        x = 0, y = math.floor(105 * _G.density_scale),
        w = card_w, h = math.floor(30 * _G.density_scale),
        text = "",
        font_size = math.floor(18 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 录音 / 播放 主按钮
    local btn_w = math.floor((card_w - margin) / 2)
    local btn_h = math.floor(70 * _G.density_scale)
    local btn_y = math.floor(210 * _G.density_scale)

    rec_btn = airui.button({
        parent = ct,
        x = margin, y = btn_y,
        w = btn_w, h = btn_h,
        text = "开始录音",
        font_size = math.floor(24 * _G.density_scale),
        bg_color = COLOR_PRIMARY,
        font_color = COLOR_WHITE,
        radius = 12,
        on_click = function()
            if current_state == "recording" then
                sys.publish("FACTORY_REC_STOP")
            else
                sys.publish("FACTORY_REC_START")
            end
        end,
    })

    play_btn = airui.button({
        parent = ct,
        x = margin + btn_w + margin, y = btn_y,
        w = btn_w, h = btn_h,
        text = "播放录音",
        font_size = math.floor(24 * _G.density_scale),
        bg_color = COLOR_GREEN,
        font_color = COLOR_WHITE,
        radius = 12,
        on_click = function()
            if current_state == "playing" then
                sys.publish("FACTORY_REC_STOP_PLAY")
            else
                sys.publish("FACTORY_REC_PLAY")
            end
        end,
    })

    -- 停止按钮
    local stop_w = card_w
    local stop_h = math.floor(60 * _G.density_scale)
    stop_btn = airui.button({
        parent = ct,
        x = margin, y = btn_y + btn_h + margin,
        w = stop_w, h = stop_h,
        text = "停止",
        font_size = math.floor(22 * _G.density_scale),
        bg_color = COLOR_DIVIDER,
        font_color = COLOR_TEXT_SECONDARY,
        radius = 12,
        on_click = function()
            if current_state == "recording" then
                sys.publish("FACTORY_REC_STOP")
            elseif current_state == "playing" then
                sys.publish("FACTORY_REC_STOP_PLAY")
            end
        end,
    })

    -- 状态文本
    status_label = airui.label({
        parent = ct,
        x = 0, y = btn_y + btn_h + margin + stop_h + math.floor(15 * _G.density_scale),
        w = screen_w, h = math.floor(30 * _G.density_scale),
        text = "就绪",
        font_size = math.floor(20 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER,
    })
end

-- ==================== 窗口生命周期 ====================

local function on_create()
    build_ui()
    current_state = "idle"
    sys.subscribe("FACTORY_REC_READY", on_ready)
    sys.subscribe("FACTORY_REC_STATE", on_state)
    sys.subscribe("FACTORY_REC_STATUS", on_status)
    sys.subscribe("FACTORY_REC_DURATION", on_duration)
    sys.subscribe("FACTORY_REC_FILE", on_file)
    -- 进入功能页才初始化音频驱动（进APP开关，不常开）
    sys.publish("FACTORY_REC_SETUP")
end

local function on_destroy()
    sys.unsubscribe("FACTORY_REC_READY", on_ready)
    sys.unsubscribe("FACTORY_REC_STATE", on_state)
    sys.unsubscribe("FACTORY_REC_STATUS", on_status)
    sys.unsubscribe("FACTORY_REC_DURATION", on_duration)
    sys.unsubscribe("FACTORY_REC_FILE", on_file)
    -- 退出时停止录音/播放 + 下电 + 删临时文件
    sys.publish("FACTORY_REC_RESET")
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    rec_btn = nil
    play_btn = nil
    stop_btn = nil
    status_label = nil
    timer_label = nil
    size_label = nil
    current_state = "idle"
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

sys.subscribe("OPEN_FACTORY_REC_WIN", open_handler)
