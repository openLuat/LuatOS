--[[
@module  ecsend
@summary 快递柜寄件窗口模块
@version 2.2 (加深选中状态颜色，提高视觉对比度)
@date    2026.04.29
]]

local win_id = nil
local main_container
local screen_w, screen_h = 480, 800
local margin = 15
local title_h = math.floor(60 * _G.density_scale)
local keyboard = nil
local send_code_textarea = nil
local selected_box_size = nil
local box_containers = {}

local box_sizes = {
    { name = "小格口", height = "高8cm", weight = "限重1kg", description = "适合文件、手机等", color = 0xBBDEFB, selected_color = 0x64B5F6 },
    { name = "中格口", height = "高19cm", weight = "限重3kg", description = "适合衣服、鞋子等", color = 0xC8E6C9, selected_color = 0x81C784 },
    { name = "大格口", height = "高29cm", weight = "限重5kg", description = "适合厚外套、被褥等", color = 0xFFF9C4, selected_color = 0xFFD54F }
}

local function create_door_open_dialog()
    local modal = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0x000000,
        opacity = 0.6
    })

    local modal_content = airui.container({
        parent = modal,
        x = math.floor((screen_w - math.floor(300 * _G.density_scale)) / 2),
        y = math.floor((screen_h - math.floor(200 * _G.density_scale)) / 2),
        w = math.floor(300 * _G.density_scale),
        h = math.floor(200 * _G.density_scale),
        color = 0xFFFFFF,
        radius = math.floor(10 * _G.density_scale)
    })

    airui.label({
        parent = modal_content,
        x = 0, y = math.floor(30 * _G.density_scale),
        w = math.floor(300 * _G.density_scale),
        h = math.floor(30 * _G.density_scale),
        text = "柜门已打开",
        font_size = math.floor(20 * _G.density_scale),
        color = 0x007AFF,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600
    })

    airui.label({
        parent = modal_content,
        x = math.floor(20 * _G.density_scale),
        y = math.floor(70 * _G.density_scale),
        w = math.floor(260 * _G.density_scale),
        h = math.floor(40 * _G.density_scale),
        text = "请放入您的快递",
        font_size = math.floor(14 * _G.density_scale),
        color = 0x666666,
        align = airui.TEXT_ALIGN_CENTER
    })

    airui.button({
        parent = modal_content,
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
            modal:destroy()
            exwin.close(win_id)
        end
    })

    return modal
end

local function update_selected_visuals()
    for i, container in ipairs(box_containers) do
        if i == selected_box_size then
            container:set_color(box_sizes[i].selected_color)
        else
            container:set_color(box_sizes[i].color)
        end
    end
end

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

    keyboard = airui.keyboard({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = math.floor(200 * _G.density_scale),
        mode = "numeric",
        auto_hide = true,
        preview = true,
        on_commit = function(self) self:hide() end,
    })

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
        text = "寄件",
        color = 0xFFFFFF,
        font_size = math.floor(24 * _G.density_scale),
        font_weight = 600,
        align = airui.TEXT_ALIGN_CENTER
    })

    local content = airui.container({
        parent = main_container,
        x = 0, y = title_h,
        w = screen_w, h = screen_h - title_h - math.floor(80 * _G.density_scale),
        color = 0xF5F5F5,
        scroll = true
    })
    
    airui.label({
        parent = content,
        x = margin, y = math.floor(20 * _G.density_scale),
        w = screen_w - 2 * margin, h = math.floor(25 * _G.density_scale),
        text = "寄件码",
        color = 0x666666,
        font_size = math.floor(14 * _G.density_scale),
        align = airui.TEXT_ALIGN_LEFT
    })

    send_code_textarea = airui.textarea({
        parent = content,
        x = margin, y = math.floor(45 * _G.density_scale),
        w = screen_w - 2 * margin, h = math.floor(50 * _G.density_scale),
        placeholder = "请输入寄件码",
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

    airui.label({
        parent = content,
        x = margin, y = math.floor(110 * _G.density_scale),
        w = screen_w - 2 * margin, h = math.floor(25 * _G.density_scale),
        text = "选择箱子大小",
        color = 0x666666,
        font_size = math.floor(14 * _G.density_scale),
        align = airui.TEXT_ALIGN_LEFT
    })

    local size_note = airui.container({
        parent = content,
        x = margin, y = math.floor(135 * _G.density_scale),
        w = screen_w - 2 * margin, h = math.floor(40 * _G.density_scale),
        color = 0xE3F2FD,
        border_color = 0x2196F3,
        border_width = 1,
        radius = math.floor(5 * _G.density_scale),
    })
    
    airui.label({
        parent = size_note,
        x = math.floor(10 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = screen_w - 2 * margin - math.floor(20 * _G.density_scale), 
        h = math.floor(20 * _G.density_scale),
        text = "箱口长和宽统一为34cm×45cm",
        color = 0x1976D2,
        font_size = math.floor(12 * _G.density_scale),
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600
    })

    for i, box in ipairs(box_sizes) do
        local box_container = airui.container({
            parent = content,
            x = margin, 
            y = math.floor(180 * _G.density_scale) + (i - 1) * math.floor(90 * _G.density_scale),
            w = screen_w - 2 * margin, 
            h = math.floor(80 * _G.density_scale),
            color = box.color,
            border_color = 0x9E9E9E,
            border_width = 1,
            radius = math.floor(5 * _G.density_scale),
            on_click = function()
                selected_box_size = i
                update_selected_visuals()
            end
        })

        table.insert(box_containers, box_container)

        airui.image({
            parent = box_container,
            x = math.floor(15 * _G.density_scale), 
            y = math.floor(15 * _G.density_scale),
            w = math.floor(40 * _G.density_scale), 
            h = math.floor(40 * _G.density_scale),
            src = "/luadb/xiangzi.png",
        })

        airui.label({
            parent = box_container,
            x = math.floor(65 * _G.density_scale), 
            y = math.floor(10 * _G.density_scale),
            w = screen_w - 2 * margin - math.floor(75 * _G.density_scale), 
            h = math.floor(20 * _G.density_scale),
            text = box.name,
            color = 0x000000,
            font_size = math.floor(16 * _G.density_scale),
            align = airui.TEXT_ALIGN_LEFT,
            font_weight = 600
        })

        airui.label({
            parent = box_container,
            x = math.floor(65 * _G.density_scale), 
            y = math.floor(35 * _G.density_scale),
            w = screen_w - 2 * margin - math.floor(75 * _G.density_scale), 
            h = math.floor(18 * _G.density_scale),
            text = box.height,
            color = 0x666666,
            font_size = math.floor(12 * _G.density_scale),
            align = airui.TEXT_ALIGN_LEFT
        })

        airui.label({
            parent = box_container,
            x = math.floor(65 * _G.density_scale), 
            y = math.floor(55 * _G.density_scale),
            w = screen_w - 2 * margin - math.floor(75 * _G.density_scale), 
            h = math.floor(18 * _G.density_scale),
            text = box.weight,
            color = 0xD32F2F,
            font_size = math.floor(12 * _G.density_scale),
            align = airui.TEXT_ALIGN_LEFT,
            font_weight = 600
        })
    end

    update_selected_visuals()

    airui.button({
        parent = main_container,
        x = margin, 
        y = screen_h - math.floor(60 * _G.density_scale),
        w = math.floor((screen_w - 3 * margin) / 2), 
        h = math.floor(50 * _G.density_scale),
        text = "确认寄件",
        style = {
            bg_color = 0x28A745,
            text_color = 0xFFFFFF,
            radius = math.floor(5 * _G.density_scale),
            font_size = math.floor(14 * _G.density_scale),
            font_weight = 600,
        },
        on_click = function()
            if not selected_box_size then
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
                    text = "请选择箱子大小",
                    font_size = math.floor(16 * _G.density_scale),
                    color = 0x666666,
                    align = airui.TEXT_ALIGN_CENTER
                })
                
                sys.timerStart(function()
                    toast_modal:destroy()
                end, 2000)
                
                return
            end
            
            exwin.close(win_id)
            sys.publish("OPEN_EXPRESS_SEND_PAY_WIN")
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
    selected_box_size = 1
    box_containers = {}
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
    })
end

sys.subscribe("OPEN_EXPRESS_SEND_WIN", open_handler)