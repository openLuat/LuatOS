--[[
@module  ecsettings
@summary 快递柜设置密码验证页面
@version 1.7 (独立密码验证页面)
@date    2026.05.07
]]

local win_id = nil
local main_container
local screen_w, screen_h = 480, 800
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
    
    -- 返回按钮
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
    
    -- 标题
    airui.label({
        parent = title_bar,
        x = 0, y = math.floor(14 * _G.density_scale),
        w = screen_w, h = math.floor(40 * _G.density_scale),
        text = "系统设置",
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
    
    -- 操作面板
    local panel = airui.container({
        parent = content,
        x = margin, y = math.floor(20 * _G.density_scale),
        w = screen_w - 2 * margin, h = math.floor(200 * _G.density_scale),
        color = 0xFFFFFF,
        radius = math.floor(10 * _G.density_scale),
    })

    -- 管理员密码标签
    airui.label({
        parent = panel,
        x = math.floor(15 * _G.density_scale), y = math.floor(20 * _G.density_scale),
        w = screen_w - 2 * margin - math.floor(30 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = "管理员密码",
        color = 0x666666,
        font_size = math.floor(14 * _G.density_scale),
        font_weight = 600,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 密码输入框
    admin_password_textarea = airui.textarea({
        parent = panel,
        x = math.floor(15 * _G.density_scale), y = math.floor(55 * _G.density_scale),
        w = screen_w - 2 * margin - math.floor(30 * _G.density_scale), h = math.floor(50 * _G.density_scale),
        placeholder = "请输入管理员密码",
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

    -- 验证密码按钮
    airui.button({
        parent = panel,
        x = math.floor(15 * _G.density_scale), y = math.floor(120 * _G.density_scale),
        w = math.floor((screen_w - 2 * margin - math.floor(30 * _G.density_scale) - margin) / 2),
        h = math.floor(45 * _G.density_scale),
        text = "验证密码",
        style = {
            bg_color = 0x28A745,
            text_color = 0xFFFFFF,
            radius = math.floor(5 * _G.density_scale),
            font_size = math.floor(14 * _G.density_scale),
            font_weight = 600,
        },
        on_click = function()
            local input_password = admin_password_textarea:get_text()
            if input_password == "admin" then
                -- 密码正确，跳转到设置详情页面
                exwin.close(win_id)
                sys.publish("OPEN_EXPRESS_SETTINGS_DETAIL_WIN")
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
                    x = math.floor((screen_w - math.floor(250 * _G.density_scale)) / 2),
                    y = math.floor((screen_h - math.floor(100 * _G.density_scale)) / 2),
                    w = math.floor(250 * _G.density_scale),
                    h = math.floor(100 * _G.density_scale),
                    color = 0xFFFFFF,
                    radius = math.floor(10 * _G.density_scale)
                })
                
                airui.label({
                    parent = toast_content,
                    x = 0, y = math.floor(30 * _G.density_scale),
                    w = math.floor(250 * _G.density_scale),
                    h = math.floor(40 * _G.density_scale),
                    text = "密码错误！",
                    font_size = math.floor(16 * _G.density_scale),
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
        x = math.floor((screen_w - 2 * margin - math.floor(30 * _G.density_scale) - margin) / 2) + margin + math.floor(15 * _G.density_scale),
        y = math.floor(120 * _G.density_scale),
        w = math.floor((screen_w - 2 * margin - math.floor(30 * _G.density_scale) - margin) / 2),
        h = math.floor(45 * _G.density_scale),
        text = "取消",
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
    win_id = nil
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
    })
end

sys.subscribe("OPEN_EXPRESS_SETTINGS_WIN", open_handler)