--[[
@module  settings_autostart_win
@summary 后装APP开机自启设置页面
@version 1.0
@date    2026.06.03
@author  江访

页面结构：
1. 开关卡片 — 开启/关闭开机自启
2. 自启APP选择卡片 — 从已安装APP中选择一个
3. 关闭密码卡片 — 设置/修改/清除密码

密码保护范围（互斥，同一时刻只能有一个APP自启）：
- 退出自启APP（NES_CTRL RETURN）
- 关闭设置中的自启开关
- 重新设置自启目标APP

LVGL win 组件内部结构：
- win = header(content_height) + content_area(win_w × (win_h - header_height))
- content_area 默认有默认 padding(~16px)，可通过 style.content_pad 设置
- 子元素直接挂到 win 上时，实际挂到 content_area 内部，坐标相对 content_area 原点
- 设置 content_pad=0 后 content_area = win_w × (win_h - header_height)，子元素坐标从 (0,0) 开始
]]

local window_id = nil
local main_container = nil
local target_label = nil
local password_label = nil
local switch_bg = nil
local switch_is_on = false

local screen_w, screen_h = 480, 800
local margin = 15
local card_w = 460
local card_h = 70
local card_spacing = 20

local titlebar = require "settings_titlebar"

local COLOR_PRIMARY        = 0x007AFF
local COLOR_PRIMARY_DARK   = 0x0056B3
local COLOR_BG             = 0xF5F5F5
local COLOR_CARD           = 0xFFFFFF
local COLOR_TEXT           = 0x333333
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_DIVIDER        = 0xE0E0E0
local COLOR_WHITE          = 0xFFFFFF
local COLOR_DANGER         = 0xE63946

-- 配置缓存
local current_enabled = false
local current_target = ""
local current_target_name = ""
local current_has_password = false
local pending_apps = {}

-- 弹出窗口引用
local app_list_win = nil
local password_edit_win = nil
local verify_password_win = nil
local exit_password_win = nil
local soft_keyboard = nil

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_w, screen_h = phys_h, phys_w
    end
    margin = math.floor(screen_w * 0.02)
    card_w = screen_w - 2 * margin
    card_h = math.max(42, math.floor(screen_h * 0.09))
    card_spacing = math.floor(screen_h * 0.015)
end

-- ==================== 弹窗关闭 ====================

local function close_all_popups()
    if soft_keyboard then
        soft_keyboard:hide()
        soft_keyboard:destroy()
        soft_keyboard = nil
    end
    if app_list_win then app_list_win:destroy(); app_list_win = nil end
    if password_edit_win then password_edit_win:destroy(); password_edit_win = nil end
    if verify_password_win then verify_password_win:destroy(); verify_password_win = nil end
    if exit_password_win then exit_password_win:destroy(); exit_password_win = nil end
end

-- ==================== 密码输入弹窗 ====================

local function show_password_input(title, on_confirm, on_cancel)
    close_all_popups()
    local win_w = math.floor(screen_w * 0.80)
    local header_h = math.floor(44 * _G.density_scale)
    -- content_pad=0 → content_area = win_w × (win_h - header_h)，子元素相对 content_area (0,0) 开始
    local item_margin = math.floor(16 * _G.density_scale)
    local input_h = math.floor(46 * _G.density_scale)
    local btn_h = math.floor(44 * _G.density_scale)
    local label_h = math.floor(22 * _G.density_scale)
    local gap = math.floor(12 * _G.density_scale)

    local content_h = item_margin + label_h + gap + input_h + gap + btn_h + item_margin
    local win_h = header_h + content_h

    soft_keyboard = airui.keyboard({
        x = 0, y = -math.floor(20 * _G.density_scale),
        w = screen_w, h = math.floor(240 * _G.density_scale),
        mode = "text", auto_hide = true, preview = true,
        on_commit = function(self) self:hide() end,
    })

    local win = airui.win({
        parent = main_container, title = title,
        w = win_w, h = win_h, close_btn = false, auto_center = true,
        style = { bg_color = COLOR_CARD, header_bg_color = COLOR_PRIMARY, content_bg_color = COLOR_CARD,
            title_text_color = COLOR_WHITE, radius = 12, title_align = airui.TEXT_ALIGN_CENTER,
            header_height = header_h, content_pad = 0 },
        on_close = function(self)
            if soft_keyboard then soft_keyboard:hide(); soft_keyboard:destroy(); soft_keyboard = nil end
            verify_password_win = nil
        end,
    })
    verify_password_win = win

    -- 内容从 content_area 原点 (0,0) 开始布局（content_pad=0）
    local y_off = item_margin
    -- 提示标签
    airui.label({
        parent = win, x = item_margin, y = y_off,
        w = win_w - 2 * item_margin, h = label_h,
        text = "请输入密码", font_size = math.floor(16 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT,
    })
    y_off = y_off + label_h + gap
    -- 密码输入框
    local pwd_input = airui.textarea({
        parent = win, x = item_margin, y = y_off,
        w = win_w - 2 * item_margin, h = input_h,
        text = "", placeholder = "请输入密码", max_len = 16,
        font_size = math.floor(18 * _G.density_scale), keyboard = soft_keyboard,
    })
    y_off = y_off + input_h + gap
    -- 按钮
    local btn_w = math.floor((win_w - 2 * item_margin - gap) / 2)
    airui.button({
        parent = win, x = item_margin, y = y_off,
        w = btn_w, h = btn_h,
        text = "取消", font_size = math.floor(18 * _G.density_scale),
        style = { bg_color = COLOR_DIVIDER, pressed_bg_color = COLOR_DIVIDER, text_color = COLOR_TEXT, radius = 8,
            border_width = 1, border_color = COLOR_DIVIDER },
        on_click = function() close_all_popups(); if on_cancel then on_cancel() end end,
    })
    airui.button({
        parent = win, x = item_margin + btn_w + gap, y = y_off,
        w = btn_w, h = btn_h,
        text = "确定", font_size = math.floor(18 * _G.density_scale),
        style = { bg_color = COLOR_PRIMARY, pressed_bg_color = COLOR_PRIMARY_DARK, text_color = COLOR_WHITE, radius = 8,
            border_width = 0 },
        on_click = function()
            local pwd = pwd_input:get_text() or ""
            close_all_popups()
            if on_confirm then on_confirm(pwd) end
        end,
    })
end

-- ==================== 密码修改弹窗 ====================

local function show_password_edit()
    close_all_popups()
    local win_w = math.floor(screen_w * 0.80)
    local header_h = math.floor(44 * _G.density_scale)
    local item_margin = math.floor(16 * _G.density_scale)
    local input_h = math.floor(46 * _G.density_scale)
    local btn_h = math.floor(44 * _G.density_scale)
    local label_h = math.floor(22 * _G.density_scale)
    local gap = math.floor(10 * _G.density_scale)

    -- 计算内容高度
    local content_h = item_margin
    local old_pwd_input = nil
    if current_has_password then
        content_h = content_h + label_h + gap + input_h + gap
    end
    content_h = content_h + label_h + gap + input_h + gap + btn_h + item_margin
    local win_h = header_h + content_h

    soft_keyboard = airui.keyboard({
        x = 0, y = -math.floor(20 * _G.density_scale),
        w = screen_w, h = math.floor(240 * _G.density_scale),
        mode = "text", auto_hide = true, preview = true,
        on_commit = function(self) self:hide() end,
    })

    local win = airui.win({
        parent = main_container, title = "设置自启密码",
        w = win_w, h = win_h, close_btn = false, auto_center = true,
        style = { bg_color = COLOR_CARD, header_bg_color = COLOR_PRIMARY, content_bg_color = COLOR_CARD,
            title_text_color = COLOR_WHITE, radius = 12, title_align = airui.TEXT_ALIGN_CENTER,
            header_height = header_h, content_pad = 0 },
        on_close = function(self)
            if soft_keyboard then soft_keyboard:hide(); soft_keyboard:destroy(); soft_keyboard = nil end
            password_edit_win = nil
        end,
    })
    password_edit_win = win

    local element_w = win_w - 2 * item_margin
    local y_off = item_margin

    if current_has_password then
        airui.label({ parent = win, x = item_margin, y = y_off, w = element_w, h = label_h,
            text = "原密码", font_size = math.floor(16 * _G.density_scale), color = COLOR_TEXT })
        y_off = y_off + label_h + gap
        old_pwd_input = airui.textarea({
            parent = win, x = item_margin, y = y_off, w = element_w, h = input_h,
            text = "", placeholder = "请输入原密码", max_len = 16,
            font_size = math.floor(18 * _G.density_scale), keyboard = soft_keyboard,
        })
        y_off = y_off + input_h + gap
    end

    airui.label({ parent = win, x = item_margin, y = y_off, w = element_w, h = label_h,
        text = "新密码（留空则清除密码）", font_size = math.floor(16 * _G.density_scale), color = COLOR_TEXT })
    y_off = y_off + label_h + gap
    local new_pwd_input = airui.textarea({
        parent = win, x = item_margin, y = y_off, w = element_w, h = input_h,
        text = "", placeholder = "请输入新密码或留空", max_len = 16,
        font_size = math.floor(18 * _G.density_scale), keyboard = soft_keyboard,
    })
    y_off = y_off + input_h + gap

    local btn_w = math.floor((win_w - 2 * item_margin - gap) / 2)
    airui.button({
        parent = win, x = item_margin, y = y_off, w = btn_w, h = btn_h,
        text = "取消", font_size = math.floor(18 * _G.density_scale),
        style = { bg_color = COLOR_DIVIDER, pressed_bg_color = COLOR_DIVIDER, text_color = COLOR_TEXT, radius = 8,
            border_width = 1, border_color = COLOR_DIVIDER },
        on_click = function() close_all_popups() end,
    })
    airui.button({
        parent = win, x = item_margin + btn_w + gap, y = y_off, w = btn_w, h = btn_h,
        text = "保存", font_size = math.floor(18 * _G.density_scale),
        style = { bg_color = COLOR_PRIMARY, pressed_bg_color = COLOR_PRIMARY_DARK, text_color = COLOR_WHITE, radius = 8,
            border_width = 0 },
        on_click = function()
            local old = (old_pwd_input and old_pwd_input:get_text()) or ""
            local new_pwd = new_pwd_input:get_text() or ""
            close_all_popups()
            sys.publish("AUTOSTART_SET_PASSWORD", old, new_pwd)
        end,
    })
end

-- ==================== APP 选择列表弹窗 ====================

local function show_app_selector()
    close_all_popups()
    local win_w = math.floor(screen_w * 0.80)
    local header_h = math.floor(44 * _G.density_scale)
    local item_h = math.floor(56 * _G.density_scale)
    local item_gap = 2

    local max_visible = 7
    local visible_count = math.min(#pending_apps, max_visible)
    local content_h = visible_count * (item_h + item_gap)
    local win_h = header_h + content_h

    local win = airui.win({
        parent = main_container, title = "选择自启APP",
        w = win_w, h = win_h, close_btn = true, auto_center = true,
        style = { bg_color = COLOR_CARD, header_bg_color = COLOR_PRIMARY, content_bg_color = COLOR_CARD,
            title_text_color = COLOR_WHITE, radius = 12, title_align = airui.TEXT_ALIGN_CENTER,
            header_height = header_h, content_pad = 0 },
        on_close = function(self) app_list_win = nil end,
    })
    app_list_win = win

    local label_pad = math.floor(16 * _G.density_scale)
    local item_y = 0

    for _, app in ipairs(pending_apps) do
        local is_selected = (app.path == current_target)
        local item_name = app.name or ""
        local display_text = is_selected and ("[已选] " .. item_name) or item_name

        local item = airui.container({
            parent = win, x = 0, y = item_y, w = win_w, h = item_h,
            color = is_selected and COLOR_DIVIDER or COLOR_CARD,
            on_click = function()
                if is_selected then return end
                if current_has_password then
                    show_password_input("验证密码以设置自启APP",
                        function(pwd)
                            close_all_popups()
                            sys.publish("AUTOSTART_SET_TARGET", app.path, pwd)
                        end
                    )
                else
                    close_all_popups()
                    sys.publish("AUTOSTART_SET_TARGET", app.path, "")
                end
            end,
        })
        airui.label({
            parent = item, x = label_pad, y = math.floor((item_h - 24) / 2),
            w = win_w - label_pad - math.floor(16 * _G.density_scale), h = math.floor(24 * _G.density_scale),
            text = display_text, font_size = math.floor(20 * _G.density_scale),
            color = is_selected and COLOR_PRIMARY or COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT,
        })
        item_y = item_y + item_h + item_gap
    end
end

-- ==================== 退出自启APP密码弹窗 ====================

local function show_exit_password_dialog()
    close_all_popups()
    local win_w = math.floor(screen_w * 0.80)
    local header_h = math.floor(44 * _G.density_scale)
    local item_margin = math.floor(16 * _G.density_scale)
    local input_h = math.floor(46 * _G.density_scale)
    local btn_h = math.floor(44 * _G.density_scale)
    local label_h = math.floor(22 * _G.density_scale)
    local gap = math.floor(12 * _G.density_scale)

    local content_h = item_margin + label_h + gap + input_h + gap + btn_h + item_margin
    local win_h = header_h + content_h

    soft_keyboard = airui.keyboard({
        x = 0, y = -math.floor(20 * _G.density_scale),
        w = screen_w, h = math.floor(240 * _G.density_scale),
        mode = "text", auto_hide = true, preview = true,
        on_commit = function(self) self:hide() end,
    })

    local win = airui.win({
        parent = airui.screen, title = "退出自启APP",
        w = win_w, h = win_h, close_btn = false, auto_center = true,
        style = { bg_color = COLOR_CARD, header_bg_color = COLOR_PRIMARY, content_bg_color = COLOR_CARD,
            title_text_color = COLOR_WHITE, radius = 12, title_align = airui.TEXT_ALIGN_CENTER,
            header_height = header_h, content_pad = 0 },
        on_close = function(self)
            if soft_keyboard then soft_keyboard:hide(); soft_keyboard:destroy(); soft_keyboard = nil end
            exit_password_win = nil
            sys.publish("AUTOSTART_EXIT_PASSWORD_RESULT", false)
        end,
    })
    exit_password_win = win

    local y_off = item_margin
    airui.label({
        parent = win, x = item_margin, y = y_off,
        w = win_w - 2 * item_margin, h = label_h,
        text = "请输入密码以退出自启APP", font_size = math.floor(16 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_CENTER,
    })
    y_off = y_off + label_h + gap

    local pwd_input = airui.textarea({
        parent = win, x = item_margin, y = y_off,
        w = win_w - 2 * item_margin, h = input_h,
        text = "", placeholder = "请输入密码", max_len = 16,
        font_size = math.floor(18 * _G.density_scale), keyboard = soft_keyboard,
    })
    y_off = y_off + input_h + gap

    local btn_w = math.floor((win_w - 2 * item_margin - gap) / 2)
    airui.button({
        parent = win, x = item_margin, y = y_off,
        w = btn_w, h = btn_h,
        text = "取消", font_size = math.floor(18 * _G.density_scale),
        style = { bg_color = COLOR_DIVIDER, pressed_bg_color = COLOR_DIVIDER, text_color = COLOR_TEXT, radius = 8,
            border_width = 1, border_color = COLOR_DIVIDER },
        on_click = function()
            close_all_popups()
            sys.publish("AUTOSTART_EXIT_PASSWORD_RESULT", false)
        end,
    })
    airui.button({
        parent = win, x = item_margin + btn_w + gap, y = y_off,
        w = btn_w, h = btn_h,
        text = "确定", font_size = math.floor(18 * _G.density_scale),
        style = { bg_color = COLOR_PRIMARY, pressed_bg_color = COLOR_PRIMARY_DARK, text_color = COLOR_WHITE, radius = 8,
            border_width = 0 },
        on_click = function()
            local pwd = pwd_input:get_text() or ""
            close_all_popups()
            sys.publish("AUTOSTART_EXIT_SUBMIT_PASSWORD", pwd)
        end,
    })
end

-- ==================== 卡片构建 ====================

local function create_info_card(parent, y, label_text, value_text, on_click, dimmed)
    local r = airui.container({
        parent = parent, x = margin, y = y, w = card_w, h = card_h,
        color = dimmed and COLOR_DIVIDER or COLOR_CARD, radius = 8,
        on_click = on_click,
    })
    local lh = math.floor(28 * _G.density_scale)
    local ly = math.floor((card_h - lh) / 2)
    airui.label({
        parent = r, x = math.floor(20 * _G.density_scale), y = ly,
        w = math.floor(120 * _G.density_scale), h = lh,
        text = label_text, font_size = math.floor(22 * _G.density_scale),
        color = dimmed and COLOR_TEXT_SECONDARY or COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT,
    })
    local vl = airui.label({
        parent = r, x = math.floor(150 * _G.density_scale), y = ly,
        w = card_w - math.floor(190 * _G.density_scale), h = lh,
        text = value_text or "", font_size = math.floor(20 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_RIGHT, long_mode = true,
    })
    airui.label({
        parent = r, x = card_w - math.floor(45 * _G.density_scale), y = ly,
        w = math.floor(25 * _G.density_scale), h = lh,
        text = ">", font_size = math.floor(22 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_CENTER,
    })
    return vl
end

local function create_switch_card(parent, y, label_text, is_on, on_toggle)
    local r = airui.container({
        parent = parent, x = margin, y = y, w = card_w, h = card_h,
        color = COLOR_CARD, radius = 8,
    })
    local lh = math.floor(28 * _G.density_scale)
    local ly = math.floor((card_h - lh) / 2)
    airui.label({
        parent = r, x = math.floor(20 * _G.density_scale), y = ly,
        w = math.floor(200 * _G.density_scale), h = lh,
        text = label_text, font_size = math.floor(22 * _G.density_scale),
        color = COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT,
    })

    local sw_w = math.floor(60 * _G.density_scale)
    local sw_h = math.floor(34 * _G.density_scale)
    local sw_x = card_w - sw_w - math.floor(20 * _G.density_scale)
    local sw_y = math.floor((card_h - sw_h) / 2)

    switch_bg = airui.container({
        parent = r, x = sw_x, y = sw_y, w = sw_w, h = sw_h,
        color = is_on and COLOR_PRIMARY or COLOR_DIVIDER,
        radius = math.floor(sw_h / 2),
        on_click = function() on_toggle(not switch_is_on) end,
    })
    switch_is_on = is_on
end

-- ==================== 主UI构建 ====================

local function build_ui()
    update_screen_size()

    main_container = airui.container({
        x = 0, y = 0, w = screen_w, h = screen_h,
        color = COLOR_BG, parent = airui.screen,
    })

    local _, th = titlebar.create(main_container, "后装APP自启", screen_w, function() exwin.close(window_id) end)

    local ct = airui.container({
        parent = main_container, x = 0, y = th, w = screen_w, h = screen_h - th,
        color = COLOR_BG,
    })

    local y = math.floor(20 * _G.density_scale)

    -- 1. 开关卡片
    create_switch_card(ct, y, "开机自启", current_enabled, function(toggle_on)
        if toggle_on == false and current_has_password then
            show_password_input("验证密码以关闭自启", function(pwd)
                sys.publish("AUTOSTART_SET_ENABLED", false, pwd)
            end)
        else
            sys.publish("AUTOSTART_SET_ENABLED", toggle_on, "")
        end
    end)
    y = y + card_h + card_spacing

    -- 2. 自启APP选择卡片
    target_label = create_info_card(ct, y, "自启APP",
        current_target_name ~= "" and current_target_name or "未选择",
        function()
            if not current_enabled then
                local mb = airui.msgbox({
                    w = math.min(400, screen_w - 80), h = math.floor(screen_h * 0.22),
                    style = { text_font_size = math.floor(18 * _G.density_scale) },
                    title = "提示", text = "请先开启开机自启",
                    buttons = { "确定" }, on_action = function(self, btn_label) self:hide() end,
                })
                mb:show()
                return
            end
            sys.publish("AUTOSTART_GET_INSTALLED_APPS")
        end,
        not current_enabled
    )
    y = y + card_h + card_spacing

    -- 3. 关闭密码卡片
    password_label = create_info_card(ct, y, "关闭密码",
        current_has_password and "已设置" or "未设置",
        function()
            if not current_enabled then
                local mb = airui.msgbox({
                    w = math.min(400, screen_w - 80), h = math.floor(screen_h * 0.22),
                    style = { text_font_size = math.floor(18 * _G.density_scale) },
                    title = "提示", text = "请先开启开机自启",
                    buttons = { "确定" }, on_action = function(self, btn_label) self:hide() end,
                })
                mb:show()
                return
            end
            show_password_edit()
        end,
        not current_enabled
    )
end

-- ==================== 事件回调 ====================

local function on_settings_value(data)
    if not data then return end
    local changed = false
    if current_enabled ~= data.enabled then changed = true end
    if current_target ~= (data.target or "") then changed = true end
    if current_target_name ~= (data.target_name or "") then changed = true end
    if current_has_password ~= data.has_password then changed = true end

    current_enabled = data.enabled
    current_target = data.target or ""
    current_target_name = data.target_name or ""
    current_has_password = data.has_password

    if changed then
        close_all_popups()
        if main_container then
            main_container:destroy()
            main_container = nil
        end
        switch_bg = nil
        target_label = nil
        password_label = nil
        build_ui()
    end
end

local function on_config_changed()
    sys.publish("AUTOSTART_SETTINGS_GET")
end

local function on_password_result(success, msg)
    if not success then
        local mb = airui.msgbox({
            w = math.min(400, screen_w - 80), h = math.floor(screen_h * 0.22),
            style = { text_font_size = math.floor(18 * _G.density_scale) },
            title = "提示", text = msg or "操作失败",
            buttons = { "确定" }, on_action = function(self, btn_label) self:hide() end,
        })
        mb:show()
    end
end

local function on_installed_apps(apps)
    pending_apps = apps or {}
    show_app_selector()
end

local function on_request_exit_password()
    show_exit_password_dialog()
end

-- ==================== 窗口生命周期 ====================

local function on_create()
    build_ui()
    sys.subscribe("AUTOSTART_SETTINGS_VALUE", on_settings_value)
    sys.subscribe("AUTOSTART_CONFIG_CHANGED", on_config_changed)
    sys.subscribe("AUTOSTART_PASSWORD_RESULT", on_password_result)
    sys.subscribe("AUTOSTART_INSTALLED_APPS_VALUE", on_installed_apps)
    sys.subscribe("AUTOSTART_REQUEST_EXIT_PASSWORD", on_request_exit_password)
    sys.publish("AUTOSTART_SETTINGS_GET")
end

local function on_destroy()
    sys.unsubscribe("AUTOSTART_SETTINGS_VALUE", on_settings_value)
    sys.unsubscribe("AUTOSTART_CONFIG_CHANGED", on_config_changed)
    sys.unsubscribe("AUTOSTART_PASSWORD_RESULT", on_password_result)
    sys.unsubscribe("AUTOSTART_INSTALLED_APPS_VALUE", on_installed_apps)
    sys.unsubscribe("AUTOSTART_REQUEST_EXIT_PASSWORD", on_request_exit_password)
    close_all_popups()
    if main_container then main_container:destroy(); main_container = nil end
    switch_bg = nil
    target_label = nil
    password_label = nil
    pending_apps = {}
end

local function on_get_focus() end
local function on_lose_focus() close_all_popups() end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_AUTOSTART_WIN", open_handler)
