--[[
@module  settings_fota_win
@summary FOTA 升级设置页面
@version 1.0
@date    2026.05.20
@author  江访
@usage
固件升级设置页面，提供：
1. 开机自动检测开关
2. 定时检测间隔（小时）
3. 立即检测按钮
4. 检测状态/进度显示
]]

local window_id            = nil
local main_container
local content_area
local auto_switch          = nil -- 开机检测开关控件
local interval_input       = nil -- 定时间隔输入控件
local status_label         = nil -- 状态显示标签

local screen_w, screen_h   = 480, 800
local margin, card_w, padding, row_gap, label_w, input_w, input_h, row_h, btn_w, btn_h, font_size, font_size2

local titlebar             = require "settings_titlebar"

local COLOR_PRIMARY        = 0x007AFF
local COLOR_BG             = 0xF5F5F5
local COLOR_CARD           = 0xFFFFFF
local COLOR_TEXT           = 0x333333
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_WHITE          = 0xFFFFFF
local COLOR_GREEN          = 0x34C759

local function update_screen_size()
    local rot = airui.get_rotation()
    local pw, ph = lcd.getSize()
    if rot == 0 or rot == 180 then
        screen_w, screen_h = pw, ph
    else
        screen_w, screen_h = ph, pw
    end
    local d    = math.min(screen_w, screen_h)
    margin     = math.floor(screen_w * 0.03)
    card_w     = screen_w - 2 * margin
    padding    = math.floor(d * 0.015)
    row_gap    = math.floor(d * 0.015)
    label_w    = math.floor(card_w * 0.32)
    input_w    = math.floor(card_w * 0.2)
    input_h    = math.max(math.floor(d * 0.06), 30)
    row_h      = input_h + 2 * padding
    btn_w      = math.floor(card_w * 0.7)
    btn_h      = math.max(math.floor(d * 0.06), 30)
    font_size  = math.max(math.floor(d * 0.036), 14)
    font_size2 = math.max(math.floor(d * 0.030), 12)
end

-- ==================== 状态消息处理 ====================

local function on_fota_status(status, msg, extra)
    if not status_label then return end
    local text_map = {
        NO_NEW_VERSION    = "当前已是最新版本",
        DOWNLOAD_PROGRESS = msg or "正在下载...",
        DOWNLOAD_SUCCESS  = msg or "升级包已就绪",
        DOWNLOAD_FAIL     = msg or "下载失败",
        UPDATE_READY      = msg or "有新版本，重启可升级",
        REBOOTING         = msg or "正在重启...",
        CHECK_FAIL        = msg or "检查失败",
    }
    local text = text_map[status] or msg or ""
    status_label:set_text(text)
end

-- ==================== 重启确认弹窗 ====================

local function show_reboot_prompt(message)
    if not main_container then return end
    local mw = math.floor(card_w * 0.85)
    local mh = math.floor(screen_h * 0.28)
    airui.msgbox({
        parent = main_container,
        w = mw,
        h = mh,
        style = { text_font_size = font_size },
        title = "固件更新",
        text = message or "升级包已下载完成，是否重启设备进行升级？",
        buttons = { "稍后重启", "立即重启" },
        on_action = function(self, btn_label)
            self:destroy()
            if btn_label == "立即重启" then
                sys.publish("FOTA_CONFIRM_REBOOT")
            end
        end
    })
end

local function on_fota_reboot_prompt(message)
    show_reboot_prompt(message)
end

-- ==================== 设置值回填 ====================

local function on_fota_settings(auto, interval)
    if auto_switch then
        auto_switch:set_state(auto == true)
    end
    if interval_input then
        local hours = math.floor((interval or 7200) / 3600)
        if hours < 1 then hours = 1 end
        if hours > 168 then hours = 168 end
        interval_input:set_text(tostring(hours))
    end
end



-- ==================== UI构建 ====================

local function build_ui()
    update_screen_size()


    main_container = airui.container({
        x = 0,
        y = 0,
        w = screen_w,
        h = screen_h,
        color = COLOR_BG,
        parent = airui.screen
    })

    local _, th = titlebar.create(main_container, "系统更新", screen_w, function() exwin.close(window_id) end)

    content_area = airui.container({
        parent = main_container,
        x = 0,
        y = th,
        w = screen_w,
        h = screen_h - th,
        color = COLOR_BG,
        scrollable = true
    })

    local y = math.floor(screen_h * 0.03)

    -- ======== 设置卡片 ========
    local card_h = math.floor(screen_h * 0.22)
    local settings_card = airui.container({
        parent = content_area,
        x = margin,
        y = y,
        w = card_w,
        h = card_h,
        color = COLOR_CARD,
        radius = math.floor(row_h * 0.15)
    })

    -- 开机自动检测开关行
    local row1_y = math.floor(card_h * 0.12)
    airui.label({
        parent = settings_card,
        x = math.floor(card_w * 0.05),
        y = row1_y,
        w = label_w,
        h = input_h,
        text = "开机自动检测",
        font_size = font_size2,
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })

    auto_switch = airui.switch({
        parent = settings_card,
        x = card_w - math.floor(90 * _G.density_scale),
        y = row1_y + math.floor((input_h - math.floor(30 * _G.density_scale)) / 2),
        w = math.floor(70 * _G.density_scale),
        h = math.floor(30 * _G.density_scale),
    })

    -- 定时间隔行
    local row2_y = row1_y + row_h + row_gap
    airui.label({
        parent = settings_card,
        x = math.floor(card_w * 0.05),
        y = row2_y,
        w = label_w,
        h = input_h,
        text = "检测间隔(小时)",
        font_size = font_size2,
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })

    interval_input = airui.textarea({
        parent = settings_card,
        x = label_w + math.floor(card_w * 0.05),
        y = row2_y,
        w = input_w,
        h = input_h,
        text = "24",
        font_size = font_size2,
        keyboard = airui.keyboard({
            x = 0,
            y = 0,
            w = screen_w,
            h = math.floor(screen_h * 0.32),
            mode = "numeric",
            auto_hide = true,
            on_commit = function(self)
                self:hide()
            end
        })
    })

    airui.label({
        parent = settings_card,
        x = label_w + math.floor(card_w * 0.05) + input_w + math.floor(card_w * 0.03),
        y = row2_y,
        w = math.floor(card_w * 0.15),
        h = input_h,
        text = "小时",
        font_size = font_size2,
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })

    y = y + card_h + row_gap * 2

    -- ======== 操作按钮区 ========
    local bx = math.floor((card_w - btn_w) / 2)

    -- 立即检测按钮
    airui.button({
        parent = content_area,
        x = bx,
        y = y,
        w = btn_w,
        h = btn_h,
        text = "立即检测更新",
        font_size = font_size2,
        style = {
            bg_color = COLOR_PRIMARY,
            pressed_bg_color = 0x0056B3,
            text_color = COLOR_WHITE,
            radius = math.floor(btn_h * 0.2),
            border_width = 0
        },
        on_click = function()
            if status_label then status_label:set_text("正在检测...") end
            sys.publish("FOTA_CHECK_NOW")
        end
    })

    y = y + btn_h + row_gap * 2

    -- 保存设置按钮
    airui.button({
        parent = content_area,
        x = bx,
        y = y,
        w = btn_w,
        h = btn_h,
        text = "保存设置",
        font_size = font_size2,
        style = {
            bg_color = COLOR_GREEN,
            pressed_bg_color = 0x2DA94F,
            text_color = COLOR_WHITE,
            radius = math.floor(btn_h * 0.2),
            border_width = 0
        },
        on_click = function()
            if not auto_switch or not interval_input then return end
            local auto_on = auto_switch:get_state()
            local interval_str = interval_input:get_text() or "2"
            local interval = tonumber(interval_str) or 2
            if interval < 1 then interval = 1 end
            if interval > 168 then interval = 168 end
            sys.publish("FOTA_SAVE_SETTINGS", auto_on, interval * 3600)
            if status_label then status_label:set_text("设置已保存") end
        end
    })

    y = y + btn_h + row_gap * 3

    -- 状态标签
    status_label = airui.label({
        parent = content_area,
        x = margin,
        y = y,
        w = card_w,
        h = math.floor(screen_h * 0.05),
        text = "就绪",
        font_size = font_size2,
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 异步获取当前设置
    sys.publish("FOTA_GET_SETTINGS")
end

-- ==================== 窗口生命周期 ====================

local function on_create()
    sys.subscribe("FOTA_STATUS", on_fota_status)
    sys.subscribe("FOTA_PROMPT_REBOOT", on_fota_reboot_prompt)
    sys.subscribe("FOTA_SETTINGS", on_fota_settings)
    build_ui()
end

local function on_destroy()
    sys.unsubscribe("FOTA_STATUS", on_fota_status)
    sys.unsubscribe("FOTA_PROMPT_REBOOT", on_fota_reboot_prompt)
    sys.unsubscribe("FOTA_SETTINGS", on_fota_settings)
    if content_area then
        content_area:destroy(); content_area = nil
    end
    if main_container then
        main_container:destroy(); main_container = nil
    end
    status_label = nil
    auto_switch = nil
    interval_input = nil
end

local function on_get_focus()
    sys.publish("FOTA_GET_SETTINGS")
end

local function on_lose_focus() end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_FOTA_WIN", open_handler)
