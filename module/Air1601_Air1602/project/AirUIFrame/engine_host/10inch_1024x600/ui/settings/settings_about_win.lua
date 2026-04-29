-- settings_about_win.lua
--[[
@module  settings_about_win
@summary 关于设备子页面
@version 1.2 (自适应分辨率，移除内存信息)
@date    2026.04.16
]]

require "settings_about_app"

local win_id = nil
local main_container
local device_name_label
local model_label
local unique_id_label
local unique_id_hex_label
local version_label
local kernel_label
local edit_win = nil
local name_input
local keyboard

-- 屏幕尺寸
local screen_w, screen_h = 480, 800
local margin = 15
local card_w = 460

local COLOR_PRIMARY        = 0x007AFF
local COLOR_PRIMARY_DARK   = 0x0056B3
local COLOR_BG             = 0xF5F5F5
local COLOR_CARD           = 0xFFFFFF
local COLOR_TEXT           = 0x333333
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_DIVIDER        = 0xE0E0E0
local COLOR_WHITE          = 0xFFFFFF

local product_name = "合宙引擎主机"

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

local function update_device_info(info)
    if device_name_label and info.device_name then
        device_name_label:set_text(info.device_name)
    end
    if model_label and info.model then
        model_label:set_text(info.model)
    end
    if unique_id_label and info.unique_id then
        unique_id_label:set_text(info.unique_id)
    end
    if unique_id_hex_label and info.unique_id_hex then
        unique_id_hex_label:set_text(info.unique_id_hex)
    end
    if version_label and info.version then
        version_label:set_text(info.version)
    end
    if kernel_label and info.kernel then
        kernel_label:set_text(info.kernel)
    end
    log.info("settings_about_win", "UI更新设备信息")
end

local function create_clickable_row(parent, y, label_text, on_click)
    local row = airui.container({
        parent = parent,
        x = 0, y = y,
        w = card_w,
        h = math.floor(50 * _G.density_scale),
        color = COLOR_WHITE,
        on_click = on_click
    })
    airui.label({
        parent = row,
        x = math.floor(20 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(150 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = label_text,
        font_size = math.floor(22 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })
    airui.label({
        parent = row,
        x = card_w - math.floor(60 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(40 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = ">",
        font_size = math.floor(22 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_RIGHT
    })
    return row
end

local function create_info_row(parent, y, label_text, value_text)
    local is_kernel = (label_text == "内核版本")
    local row_height = math.floor((is_kernel and 120 or 70) * _G.density_scale)
    local value_width = card_w - math.floor(150 * _G.density_scale) - math.floor(30 * _G.density_scale)
    local value_height = math.floor((is_kernel and 100 or 50) * _G.density_scale)

    local row = airui.container({
        parent = parent,
        x = 0, y = y,
        w = card_w,
        h = row_height,
        color = COLOR_CARD
    })
    airui.label({
        parent = row,
        x = math.floor(20 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(150 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = label_text,
        font_size = math.floor(22 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })
    local value_label = airui.label({
        parent = row,
        x = math.floor(180 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = value_width,
        h = value_height,
        text = value_text,
        font_size = math.floor(22 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_RIGHT,
        long_mode = true
    })
    return value_label
end

local function create_edit_win(default_name)
    local win_w = math.floor(screen_w * 0.85)
    local win_h = math.floor(screen_h * 0.45)
    local padding = math.floor(20 * _G.density_scale)

    keyboard = airui.keyboard({
        x = 0, y = -math.floor(20 * _G.density_scale),
        w = screen_w, h = math.floor(280 * _G.density_scale),
        mode = "text",
        auto_hide = true,
        on_commit = function(self) self:hide() end
    })

    edit_win = airui.win({
        parent = main_container,
        title = "更改设备名称",
        w = win_w,
        h = win_h,
        close_btn = false,
        auto_center = true,
        style = {
            bg_color = COLOR_CARD,
            header_bg_color = COLOR_PRIMARY,
            content_bg_color = COLOR_CARD,
            title_text_color = COLOR_WHITE,
            radius = 12,
            title_align = airui.TEXT_ALIGN_CENTER,
            header_height = math.floor(50 * _G.density_scale),
        },
        on_close = function(self)
            log.info("settings_about_win", "编辑窗口已关闭")
            if keyboard then keyboard = nil end
            edit_win = nil
        end
    })

    name_input = airui.textarea({
        parent = edit_win,
        x = padding,
        y = math.floor(60 * _G.density_scale),
        w = win_w - 2 * padding - math.floor(40 * _G.density_scale),
        h = math.floor(60 * _G.density_scale),
        text = default_name or "",
        placeholder = "请输入设备名称",
        max_len = 32,
        font_size = math.floor(20 * _G.density_scale),
        keyboard = keyboard
    })

    local btn_w = math.floor(math.min(math.floor(120 * _G.density_scale), (win_w - 3 * padding) / 2))
    local btn_x1 = padding + math.floor(20 * _G.density_scale)
    local btn_x2 = win_w - padding - math.floor(20 * _G.density_scale) - btn_w

    airui.button({
        parent = edit_win,
        x = btn_x1, y = math.floor(150 * _G.density_scale),
        w = btn_w, h = math.floor(50 * _G.density_scale),
        text = "返回",
        font_size = math.floor(20 * _G.density_scale),
        style = {
            bg_color = COLOR_DIVIDER,
            pressed_bg_color = COLOR_DIVIDER,
            text_color = COLOR_TEXT,
            radius = 8,
            border_width = 1,
            border_color = COLOR_DIVIDER
        },
        on_click = function()
            if edit_win then edit_win:close() end
        end
    })
    airui.button({
        parent = edit_win,
        x = btn_x2, y = math.floor(150 * _G.density_scale),
        w = btn_w, h = math.floor(50 * _G.density_scale),
        text = "保存",
        font_size = math.floor(20 * _G.density_scale),
        style = {
            bg_color = COLOR_PRIMARY,
            pressed_bg_color = COLOR_PRIMARY_DARK,
            text_color = COLOR_WHITE,
            radius = 8,
            border_width = 0
        },
        on_click = function()
            local new_name = name_input:get_text()
            if new_name and #new_name > 0 then
                if device_name_label then
                    device_name_label:set_text(new_name)
                end
                sys.publish("CONFIG_SET_DEVICE_NAME", new_name)
                airui.msgbox({
                    title = "提示",
                    text = "设备名称已保存",
                    buttons = {"确定"},
                    on_action = function(self)
                        self:hide()
                        if edit_win then edit_win:close() end
                    end
                })
            else
                airui.msgbox({
                    title = "提示",
                    text = "设备名称不能为空",
                    buttons = {"确定"},
                    on_action = function(self) self:hide() end
                })
            end
        end
    })
end

local function create_ui()
    update_screen_size()

    local ok, model = pcall(hmeta.model)
    if ok and model then
        local suffix = tostring(model):gsub("^Air", "")
        product_name = "合宙引擎主机" .. suffix
    end

    main_container = airui.container({
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = COLOR_BG,
        parent = airui.screen
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = math.floor(60 * _G.density_scale),
        color = COLOR_PRIMARY
    })
    local btn_back = airui.container({
        parent = title_bar,
        x = 10, y = 10,
        w = math.floor(50 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        color = COLOR_PRIMARY,
        on_click = function() exwin.close(win_id) end
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
        x = math.floor(60 * _G.density_scale), y = math.floor(14 * _G.density_scale),
        w = math.floor(200 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        text = "关于设备",
        font_size = math.floor(32 * _G.density_scale),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 内容区域
    local title_h = math.floor(60 * _G.density_scale)
    local content = airui.container({
        parent = main_container,
        x = 0, y = title_h,
        w = screen_w, h = screen_h - title_h,
        color = COLOR_BG,
        scrollable = true,
    })

    -- 设备名称卡片
    local card_device_name = airui.container({
        parent = content,
        x = margin, y = math.floor(20 * _G.density_scale),
        w = card_w, h = math.floor(70 * _G.density_scale),
        color = COLOR_WHITE,
        radius = 8
    })
    create_clickable_row(card_device_name, math.floor(10 * _G.density_scale), "设备名称", function()
        local current_name = device_name_label and device_name_label:get_text() or ""
        create_edit_win(current_name)
    end)
    device_name_label = airui.label({
        parent = card_device_name,
        x = math.floor(90 * _G.density_scale), y = math.floor(20 * _G.density_scale),
        w = card_w - math.floor(130 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = product_name,
        font_size = math.floor(22 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_RIGHT
    })

    -- 设备信息卡片（无内存信息行）
    local card_info = airui.container({
        parent = content,
        x = margin, y = math.floor(110 * _G.density_scale),
        w = card_w, h = math.floor(380 * _G.density_scale),
        color = COLOR_WHITE,
        radius = 8
    })
    -- 删除内存信息可点击行，直接显示设备信息
    model_label = create_info_row(card_info, math.floor(10 * _G.density_scale), "设备型号", "--")
    unique_id_label = create_info_row(card_info, math.floor(70 * _G.density_scale), "设备 ID", "--")
    unique_id_hex_label = create_info_row(card_info, math.floor(130 * _G.density_scale), "设备 ID (HEX)", "--")
    version_label = create_info_row(card_info, math.floor(190 * _G.density_scale), "软件版本", "--")
    kernel_label = create_info_row(card_info, math.floor(250 * _G.density_scale), "内核版本", "--")
end

local function on_create()
    create_ui()
    sys.publish("ABOUT_DEVICE_GET_INFO")
    sys.publish("CONFIG_GET_DEVICE_NAME")
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    device_name_label = nil
    model_label = nil
    unique_id_label = nil
    unique_id_hex_label = nil
    version_label = nil
    kernel_label = nil
end

local function on_get_focus() end
local function on_lose_focus()
    if edit_win then edit_win:close() end
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("ABOUT_DEVICE_INFO", function(info) update_device_info(info) end)
sys.subscribe("CONFIG_DEVICE_NAME_VALUE", function(device_name)
    if device_name_label then
        device_name_label:set_text(device_name)
        log.info("settings_about_win", "更新设备名称", device_name)
    end
end)
sys.subscribe("OPEN_ABOUT_WIN", open_handler)