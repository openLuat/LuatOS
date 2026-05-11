--[[
@module  ecsettings_detail
@summary 快递柜设置详情页面（开箱功能）
@version 1.2 (修复数字键盘和布局)
@date    2026.05.07
]]

local win_id = nil
local main_container
local screen_w, screen_h = 480, 800
local margin = 15
local title_h = math.floor(60 * _G.density_scale)
local keyboard = nil
local box_number_textarea = nil

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

    -- 数字键盘
    keyboard = airui.keyboard({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = math.floor(200 * _G.density_scale),
        mode = "numeric",
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

    -- 内容区域（不滚动）
    local content = airui.container({
        parent = main_container,
        x = 0, y = title_h,
        w = screen_w, h = screen_h - title_h - math.floor(60 * _G.density_scale) - math.floor(20 * _G.density_scale),
        color = 0xF5F5F5,
        scroll = false
    })
    
    -- 查看所有箱子状态按钮
    airui.button({
        parent = content,
        x = margin, y = math.floor(30 * _G.density_scale),
        w = screen_w - 2 * margin,
        h = math.floor(50 * _G.density_scale),
        text = "查看所有箱子状态",
        style = {
            bg_color = 0x28A745,
            text_color = 0xFFFFFF,
            radius = math.floor(5 * _G.density_scale),
            font_size = math.floor(16 * _G.density_scale),
            font_weight = 600,
        },
        on_click = function()
            sys.publish("OPEN_EXPRESS_BOXSTATUS_WIN")
        end
    })

    -- 箱子编号标签
    airui.label({
        parent = content,
        x = margin, y = math.floor(100 * _G.density_scale),
        w = screen_w - 2 * margin, h = math.floor(25 * _G.density_scale),
        text = "箱子编号",
        color = 0x666666,
        font_size = math.floor(14 * _G.density_scale),
        font_weight = 600,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 箱子编号输入框（使用数字键盘）
    box_number_textarea = airui.textarea({
        parent = content,
        x = margin, y = math.floor(130 * _G.density_scale),
        w = screen_w - 2 * margin, h = math.floor(50 * _G.density_scale),
        placeholder = "请输入箱子编号",
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

    -- 开箱按钮
    airui.button({
        parent = content,
        x = margin, y = math.floor(200 * _G.density_scale),
        w = screen_w - 2 * margin,
        h = math.floor(50 * _G.density_scale),
        text = "开箱",
        style = {
            bg_color = 0x28A745,
            text_color = 0xFFFFFF,
            radius = math.floor(5 * _G.density_scale),
            font_size = math.floor(16 * _G.density_scale),
            font_weight = 600,
        },
        on_click = function()
            local box_number = box_number_textarea:get_text()
            if not box_number or box_number == "" then
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
                    text = "请输入箱子编号",
                    font_size = math.floor(16 * _G.density_scale),
                    color = 0xD32F2F,
                    align = airui.TEXT_ALIGN_CENTER
                })
                
                sys.timerStart(function()
                    toast_modal:destroy()
                end, 2000)
                return
            end
            
            local box_num = tonumber(box_number)
            if not box_num or box_num < 1 or box_num > 30 then
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
                    text = "箱子编号必须在1-30之间",
                    font_size = math.floor(16 * _G.density_scale),
                    color = 0xD32F2F,
                    align = airui.TEXT_ALIGN_CENTER
                })
                
                sys.timerStart(function()
                    toast_modal:destroy()
                end, 2000)
                return
            end
            
            -- 开箱成功弹窗
            local success_modal = airui.container({
                parent = airui.screen,
                x = 0, y = 0,
                w = screen_w, h = screen_h,
                color = 0x000000,
                opacity = 0.6
            })
            
            local success_content = airui.container({
                parent = success_modal,
                x = math.floor((screen_w - math.floor(300 * _G.density_scale)) / 2),
                y = math.floor((screen_h - math.floor(200 * _G.density_scale)) / 2),
                w = math.floor(300 * _G.density_scale),
                h = math.floor(200 * _G.density_scale),
                color = 0xFFFFFF,
                radius = math.floor(10 * _G.density_scale)
            })
            
            airui.label({
                parent = success_content,
                x = 0, y = math.floor(40 * _G.density_scale),
                w = math.floor(300 * _G.density_scale),
                h = math.floor(30 * _G.density_scale),
                text = "柜门已打开",
                font_size = math.floor(20 * _G.density_scale),
                color = 0x28A745,
                align = airui.TEXT_ALIGN_CENTER,
                font_weight = 600
            })
            
            airui.label({
                parent = success_content,
                x = 0, y = math.floor(80 * _G.density_scale),
                w = math.floor(300 * _G.density_scale),
                h = math.floor(40 * _G.density_scale),
                text = "第" .. box_number .. "号箱门已打开",
                font_size = math.floor(14 * _G.density_scale),
                color = 0x666666,
                align = airui.TEXT_ALIGN_CENTER
            })
            
            airui.button({
                parent = success_content,
                x = math.floor(75 * _G.density_scale),
                y = math.floor(130 * _G.density_scale),
                w = math.floor(150 * _G.density_scale),
                h = math.floor(45 * _G.density_scale),
                text = "确定",
                style = {
                    bg_color = 0x007AFF,
                    text_color = 0xFFFFFF,
                    radius = math.floor(5 * _G.density_scale),
                    font_size = math.floor(16 * _G.density_scale),
                    font_weight = 600
                },
                on_click = function()
                    success_modal:destroy()
                    box_number_textarea:set_text("")
                end
            })
        end
    })

    -- 二维码
    airui.qrcode({
        parent = content,
        x = math.floor((screen_w - math.floor(150 * _G.density_scale)) / 2),
        y = math.floor(280 * _G.density_scale),
        size = math.floor(150 * _G.density_scale),
        data = "https://docs.openluat.com/",
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true,
    })

    -- 取消按钮（固定在底部）
    airui.button({
        parent = main_container,
        x = margin,
        y = screen_h - math.floor(55 * _G.density_scale),
        w = screen_w - 2 * margin,
        h = math.floor(50 * _G.density_scale),
        text = "取消",
        style = {
            bg_color = 0x6C757D,
            text_color = 0xFFFFFF,
            radius = math.floor(5 * _G.density_scale),
            font_size = math.floor(16 * _G.density_scale),
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

sys.subscribe("OPEN_EXPRESS_SETTINGS_DETAIL_WIN", open_handler)