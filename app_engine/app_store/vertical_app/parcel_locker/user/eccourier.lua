--[[
@module  eccourier
@summary 快递柜快递员窗口模块
@version 1.5 (添加键盘组件)
@date    2026.04.29
]]

local win_id = nil
local main_container
local screen_w, screen_h = 480, 800
local margin = 15
local title_h = math.floor(60 * _G.density_scale)
local keyboard = nil
local courier_id_textarea = nil
local password_textarea = nil

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_w, screen_h = phys_h, phys_w
    end
    margin = math.floor(screen_w * 0.03)
    title_h = math.floor(60 * _G.density_scale)
end

local function create_ui()
    update_screen_size()
    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0xF5F5F5
    })

    -- 键盘
    keyboard = airui.keyboard({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = math.floor(200 * _G.density_scale),
        mode = "text",
        auto_hide = true,
        preview = true,
        on_commit = function(self) self:hide() end,
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = title_h,
        color = 0x2C3E50
    })
    
    airui.button({
        parent = title_bar,
        x = math.floor(10 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(70 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        text = "返回",
        style = {
            bg_color = 0x6C757D,
            text_color = 0xFFFFFF,
            radius = math.floor(5 * _G.density_scale),
            font_size = math.floor(14 * _G.density_scale),
            font_weight = 600,
        },
        on_click = function() exwin.close(win_id) end
    })
    
    airui.label({
        parent = title_bar,
        x = 0, y = math.floor(14 * _G.density_scale),
        w = screen_w, h = math.floor(40 * _G.density_scale),
        text = "快递员",
        color = 0xFFFFFF,
        font_size = math.floor(24 * _G.density_scale),
        font_weight = 600,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 内容区域
    local content = airui.container({
        parent = main_container,
        x = 0, y = title_h,
        w = screen_w, h = screen_h - title_h - math.floor(80 * _G.density_scale),
        color = 0xF5F5F5,
        scroll = true
    })
    
    -- 快递员ID输入
    airui.label({
        parent = content,
        x = margin, y = math.floor(20 * _G.density_scale),
        w = screen_w - 2 * margin, h = math.floor(25 * _G.density_scale),
        text = "快递员ID",
        color = 0x666666,
        font_size = math.floor(14 * _G.density_scale),
        align = airui.TEXT_ALIGN_LEFT
    })

    courier_id_textarea = airui.textarea({
        parent = content,
        x = margin, y = math.floor(45 * _G.density_scale),
        w = screen_w - 2 * margin, h = math.floor(50 * _G.density_scale),
        placeholder = "请输入快递员ID",
        style = {
            bg_color = 0xFFFFFF,
            border_color = 0xDDDDDD,
            border_width = 1,
            radius = math.floor(5 * _G.density_scale),
            font_size = math.floor(16 * _G.density_scale),
            text_color = 0x000000,
        },
        keyboard = keyboard,
    })

    -- 密码输入
    airui.label({
        parent = content,
        x = margin, y = math.floor(110 * _G.density_scale),
        w = screen_w - 2 * margin, h = math.floor(25 * _G.density_scale),
        text = "密码",
        color = 0x666666,
        font_size = math.floor(14 * _G.density_scale),
        align = airui.TEXT_ALIGN_LEFT
    })

    password_textarea = airui.textarea({
        parent = content,
        x = margin, y = math.floor(135 * _G.density_scale),
        w = screen_w - 2 * margin, h = math.floor(50 * _G.density_scale),
        placeholder = "请输入密码",
        style = {
            bg_color = 0xFFFFFF,
            border_color = 0xDDDDDD,
            border_width = 1,
            radius = math.floor(5 * _G.density_scale),
            font_size = math.floor(16 * _G.density_scale),
            text_color = 0x000000,
            input_type = "password",
        },
        keyboard = keyboard,
    })

    -- 二维码区域
    airui.label({
        parent = content,
        x = margin, y = math.floor(200 * _G.density_scale),
        w = screen_w - 2 * margin, h = math.floor(25 * _G.density_scale),
        text = "扫描二维码访问官网",
        color = 0x666666,
        font_size = math.floor(14 * _G.density_scale),
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 二维码
    airui.qrcode({
        parent = content,
        x = math.floor((screen_w - math.floor(150 * _G.density_scale)) / 2), 
        y = math.floor(230 * _G.density_scale),
        size = math.floor(150 * _G.density_scale),
        data = "https://docs.openluat.com/",
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true,
    })

    -- 操作按钮
    airui.button({
        parent = main_container,
        x = margin, 
        y = screen_h - math.floor(60 * _G.density_scale),
        w = math.floor((screen_w - 3 * margin) / 2), 
        h = math.floor(50 * _G.density_scale),
        text = "确定",
        style = {
            bg_color = 0x28A745,
            text_color = 0xFFFFFF,
            radius = math.floor(5 * _G.density_scale),
            font_size = math.floor(14 * _G.density_scale),
            font_weight = 600,
        },
        on_click = function()
            exwin.close(win_id)
        end
    })

    airui.button({
        parent = main_container,
        x = math.floor((screen_w - 3 * margin) / 2) + 2 * margin, 
        y = screen_h - math.floor(60 * _G.density_scale),
        w = math.floor((screen_w - 3 * margin) / 2), 
        h = math.floor(50 * _G.density_scale),
        text = "返回",
        style = {
            bg_color = 0x6C757D,
            text_color = 0xFFFFFF,
            radius = math.floor(5 * _G.density_scale),
            font_size = math.floor(14 * _G.density_scale),
            font_weight = 600,
        },
        on_click = function()
            exwin.close(win_id)
        end
    })
end

local function on_create()
    create_ui()
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
    })
end

sys.subscribe("OPEN_EXPRESS_COURIER_WIN", open_handler)
