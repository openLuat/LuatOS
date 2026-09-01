--[[
@module  eccourier
@summary 寄存柜管理员密码验证页面
@version 1.8 (蓝白风格统一)
@date    2026.05.13
@author  王城钧
@usage
寄存柜管理员密码验证页面：输入密码验证通过后进入管理功能。订阅 OPEN_COURIER_MANAGEMENT_WIN 打开
]]

local win_id = nil
local main_container
local screen_w, screen_h = 1024, 600
local margin = 15
local title_h = math.floor(60 * _G.density_scale)
local keyboard = nil
local admin_password_textarea = nil

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
    local density = _G.density_scale or 1
    
    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0xF8F9FA
    })

    -- 键盘
    keyboard = airui.keyboard({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = math.floor(200 * density),
        mode = "text",
        auto_hide = true,
        preview = true,
        on_commit = function(self) self:hide() end,
    })

    -- 顶部导航栏
    local header_h = math.floor(60 * density)
    local header = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = header_h,
        color = 0x4A90E2,
        radius = 0,
        shadow = {
            offset_x = 0,
            offset_y = math.floor(3 * density),
            blur = math.floor(8 * density),
            color = 0x000000,
            opacity = 0.12,
        }
    })
    
    -- 返回按钮
    airui.button({
        parent = header,
        x = math.floor(15 * density),
        y = math.floor((header_h - 35 * density) / 2),
        w = math.floor(70 * density),
        h = math.floor(35 * density),
        text = "返回",
        style = {
            bg_color = 0xFFFFFF, pressed_bg_color = 0xEFEFEF,
            text_color = 0x4A90E2, radius = math.floor(7 * density),
            font_size = math.floor(15 * density), font_weight = 500,
            border_width = 0,
        },
        on_click = function() exwin.close(win_id) end
    })

    -- 标题
    airui.label({
        parent = header,
        x = 0, y = math.floor((header_h - 28 * density) / 2),
        w = screen_w, h = math.floor(28 * density),
        text = "管理员",
        color = 0xFFFFFF,
        font_size = math.floor(24 * density),
        font_weight = 600,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 内容区域（不滚动）
    local content = airui.container({
        parent = main_container,
        x = 0, y = header_h,
        w = screen_w, h = screen_h - header_h - math.floor(80 * density),
        color = 0xF8F9FA,
        scroll = false
    })
    
    -- 操作面板
    local panel = airui.container({
        parent = content,
        x = margin, y = math.floor(20 * density),
        w = screen_w - 2 * margin, h = math.floor(200 * density),
        color = 0xFFFFFF,
        radius = math.floor(10 * density),
    })

    -- 管理员密码标签
    airui.label({
        parent = panel,
        x = math.floor(15 * density), y = math.floor(20 * density),
        w = screen_w - 2 * margin - math.floor(30 * density), h = math.floor(30 * density),
        text = "管理员密码",
        color = 0x4A90E2,
        font_size = math.floor(14 * density),
        font_weight = 600,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 密码输入框
    admin_password_textarea = airui.textarea({
        parent = panel,
        x = math.floor(15 * density), y = math.floor(55 * density),
        w = screen_w - 2 * margin - math.floor(30 * density), h = math.floor(50 * density),
        placeholder = "请输入管理员密码",
        style = {
            bg_color = 0xFFFFFF,
            border_color = 0xDDDDDD,
            border_width = 1,
            radius = math.floor(5 * density),
            font_size = math.floor(16 * density),
            text_color = 0x000000,
            input_type = "password",
        },
        keyboard = keyboard,
    })

    -- 验证密码按钮
    airui.button({
        parent = panel,
        x = math.floor(15 * density), y = math.floor(120 * density),
        w = math.floor((screen_w - 2 * margin - math.floor(30 * density) - margin) / 2),
        h = math.floor(45 * density),
        text = "验证密码",
        style = {
            bg_color = 0x4A90E2,
            text_color = 0xFFFFFF,
            radius = math.floor(5 * density),
            font_size = math.floor(14 * density),
            font_weight = 600,
        },
        on_click = function()
            local input_password = admin_password_textarea:get_text()
            if input_password == "admin" then
                -- 密码正确，跳转到设置详情页面
                exwin.close(win_id)
                sys.publish("OPEN_EXPRESS_COURIER_DETAIL_WIN")
            else
                -- 密码错误提示
                local toast_modal = airui.container({
                    parent = airui.screen,
                    x = 0, y = 0,
                    w = screen_w, h = screen_h,
                    color = 0x000000,
                    opacity = 0.5
                })
                
                local toast_content = airui.container({
                    parent = toast_modal,
                    x = math.floor((screen_w - math.floor(250 * density)) / 2),
                    y = math.floor((screen_h - math.floor(100 * density)) / 2),
                    w = math.floor(250 * density),
                    h = math.floor(100 * density),
                    color = 0xFFFFFF,
                    radius = math.floor(10 * density)
                })
                
                airui.label({
                    parent = toast_content,
                    x = 0, y = math.floor(30 * density),
                    w = math.floor(250 * density),
                    h = math.floor(40 * density),
                    text = "密码错误！",
                    font_size = math.floor(16 * density),
                    color = 0xD32F2F,
                    align = airui.TEXT_ALIGN_CENTER
                })
                
                sys.timerStart(function()
                    toast_modal:destroy()
                end, 2000)
                
                admin_password_textarea:set_text("")
            end
        end
    })

    -- 取消按钮
    airui.button({
        parent = panel,
        x = math.floor((screen_w - 2 * margin - math.floor(30 * density) - margin) / 2) + margin + math.floor(15 * density),
        y = math.floor(120 * density),
        w = math.floor((screen_w - 2 * margin - math.floor(30 * density) - margin) / 2),
        h = math.floor(45 * density),
        text = "取消",
        style = {
            bg_color = 0xF0F0F0,
            text_color = 0x666666,
            radius = math.floor(5 * density),
            font_size = math.floor(14 * density),
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
    win_id = nil
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
    })
end

sys.subscribe("OPEN_COURIER_MANAGEMENT_WIN", open_handler)