--[[
@module  ecsend_pay
@summary 寄件付款页面
@version 1.2
@date    2026.05.07
]]

local win_id = nil
local main_container
local screen_w, screen_h = 480, 800
local density = 1
local margin = 15

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_w, screen_h = phys_h, phys_w
    end
    density = _G.density_scale or 1
    margin = math.floor(15 * density)
end

local function create_ui()
    update_screen_size()
    
    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0xF0F2F5
    })

    -- 顶部导航栏
    local nav_h = math.floor(80 * density)
    local nav_bar = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = nav_h,
        color = 0x2C3E50
    })

    -- 返回按钮
    airui.button({
        parent = nav_bar,
        x = margin,
        y = math.floor(20 * density),
        w = math.floor(70 * density),
        h = math.floor(40 * density),
        text = "返回",
        style = {
            bg_color = 0x34495E,
            text_color = 0xFFFFFF,
            radius = math.floor(5 * density),
            font_size = math.floor(14 * density),
        },
        on_click = function()
            exwin.close(win_id)
        end
    })

    -- 标题
    airui.label({
        parent = nav_bar,
        text = "寄件操作",
        x = 0,
        y = math.floor((nav_h - math.floor(30 * density)) / 2),
        w = screen_w,
        h = math.floor(30 * density),
        font_size = math.floor(24 * density),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })

    -- 提示文字
    airui.label({
        parent = main_container,
        text = "请扫描二维码完成付款",
        x = 0,
        y = nav_h + math.floor(30 * density),
        w = screen_w,
        h = math.floor(40 * density),
        font_size = math.floor(18 * density),
        color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 600,
    })

    -- 二维码背景
    local qr_size = math.floor(220 * density)
    airui.container({
        parent = main_container,
        x = math.floor((screen_w - qr_size) / 2),
        y = nav_h + math.floor(80 * density),
        w = qr_size,
        h = qr_size,
        color = 0xFFFFFF,
        radius = math.floor(10 * density),
        border_color = 0xE8E8E8,
        border_width = 1,
    })

    -- 二维码
    local qr_inner_size = math.floor(180 * density)
    local qr_x = math.floor((screen_w - qr_inner_size) / 2)
    local qr_y = nav_h + math.floor(100 * density)
    
    airui.qrcode({
        parent = main_container,
        x = qr_x,
        y = qr_y,
        size = qr_inner_size,
        data = "https://docs.openluat.com/",
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true,
    })

    -- 二维码下方提示
    airui.label({
        parent = main_container,
        text = "扫码支付完成寄件",
        x = 0,
        y = qr_y + qr_inner_size + math.floor(20 * density),
        w = screen_w,
        h = math.floor(30 * density),
        font_size = math.floor(14 * density),
        color = 0x999999,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 温馨提示
    local tips_y = qr_y + qr_inner_size + math.floor(60 * density)
    airui.container({
        parent = main_container,
        x = margin,
        y = tips_y,
        w = screen_w - 2 * margin,
        h = math.floor(40 * density),
        color = 0xFFFBEB,
        radius = math.floor(8 * density),
    })
    
    airui.label({
        parent = main_container,
        text = "温馨提示：请将包裹放入柜中后再付款",
        x = margin,
        y = tips_y,
        w = screen_w - 2 * margin,
        h = math.floor(40 * density),
        font_size = math.floor(12 * density),
        color = 0x8B4513,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 完成寄件按钮
    airui.button({
        parent = main_container,
        x = margin,
        y = screen_h - math.floor(70 * density),
        w = screen_w - 2 * margin,
        h = math.floor(50 * density),
        text = "完成寄件",
        style = {
            bg_color = 0x28A745,
            text_color = 0xFFFFFF,
            radius = math.floor(8 * density),
            font_size = math.floor(16 * density),
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

sys.subscribe("OPEN_EXPRESS_SEND_PAY_WIN", open_handler)

return open_handler