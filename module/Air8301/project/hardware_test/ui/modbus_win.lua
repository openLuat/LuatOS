--[[
@module  modbus_win
@summary Modbus配置与状态页面
@version 1.0
@date    2026.09.04
@author  江访
@usage
显示Modbus当前模式(主站/从站)、端口、从站地址、轮询间隔等。
]]

local win_id = nil
local main_container, content
local mode_label, port_label, addr_label, status_label

local function on_back_click()
    if not exwin.is_active(win_id) then return end
    exwin.close(win_id)
end

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = T.SCREEN_W, h = T.SCREEN_H, color = T.COLOR_BG, parent = airui.screen })

    T.titlebar(main_container, "Modbus通信", on_back_click)

    content = airui.container({ parent = main_container, x = 0, y = T.CONTENT_Y, w = T.SCREEN_W, h = T.CONTENT_H, color = T.COLOR_BG })

    -- 运行状态
    local c1 = airui.container({ parent = content, x = T.MARGIN, y = 10, w = T.CARD_W, h = 40, color = T.COLOR_CARD, radius = T.CARD_RADIUS })
    airui.label({ parent = c1, x = 15, y = 10, w = 100, h = 20, text = "状态", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    status_label = airui.label({ parent = c1, x = 120, y = 10, w = 200, h = 20, text = "未启用", font_size = T.FONT_BODY, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })

    -- 工作模式
    local c2 = airui.container({ parent = content, x = T.MARGIN, y = 58, w = T.CARD_W, h = 40, color = T.COLOR_CARD, radius = T.CARD_RADIUS })
    airui.label({ parent = c2, x = 15, y = 10, w = 100, h = 20, text = "模式", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    mode_label = airui.label({ parent = c2, x = 120, y = 10, w = 200, h = 20, text = "--", font_size = T.FONT_BODY, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })

    -- 端口
    local c3 = airui.container({ parent = content, x = T.MARGIN, y = 106, w = T.CARD_W, h = 40, color = T.COLOR_CARD, radius = T.CARD_RADIUS })
    airui.label({ parent = c3, x = 15, y = 10, w = 100, h = 20, text = "端口", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    port_label = airui.label({ parent = c3, x = 120, y = 10, w = 200, h = 20, text = "--", font_size = T.FONT_BODY, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })

    -- 从站地址
    local c4 = airui.container({ parent = content, x = T.MARGIN, y = 154, w = T.CARD_W, h = 40, color = T.COLOR_CARD, radius = T.CARD_RADIUS })
    airui.label({ parent = c4, x = 15, y = 10, w = 100, h = 20, text = "从站地址", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    addr_label = airui.label({ parent = c4, x = 120, y = 10, w = 200, h = 20, text = "--", font_size = T.FONT_BODY, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })

    -- 说明
    airui.label({ parent = content, x = T.MARGIN, y = 202, w = T.CARD_W, h = 20, text = "在 device_config.json 的 uart.modbus 中配置", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_CENTER })
end

local function on_create()
    create_ui()
    sys.publish("MODBUS_QUERY")
end

local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    mode_label = nil; port_label = nil; addr_label = nil; status_label = nil; win_id = nil
end

local function on_get_focus()
    sys.publish("MODBUS_QUERY")
end
local function on_lose_focus() end

sys.subscribe("MODBUS_STATUS", function(data)
    if not status_label then return end
    if data.running then
        status_label:set_text("运行中")
        status_label:set_color(T.COLOR_GREEN)
    else
        status_label:set_text("未启用")
        status_label:set_color(T.COLOR_TEXT_SECONDARY)
    end
    if data.mode then
        local mode_str = data.mode == "master" and "主站(Master)" or "从站(Slave)"
        mode_label:set_text(mode_str)
    end
    if data.port then
        local port_names = {rs485_1 = "RS485-1(UART1)", rs485_2 = "RS485-2(UART11)", rs232_1 = "RS232-1(UART2)", tcp = "TCP(以太网)"}
        port_label:set_text(port_names[data.port] or data.port)
    end
    addr_label:set_text(tostring(1))
end)

local function open_handler()
    win_id = exwin.open({ on_create = on_create, on_destroy = on_destroy, on_lose_focus = on_lose_focus, on_get_focus = on_get_focus })
end

sys.subscribe("OPEN_MODBUS_WIN", open_handler)
