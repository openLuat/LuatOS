--[[
@module  uart_win
@summary 串口调试页面模块
@version 1.0
@date    2026.03.16
@author  江访
@usage
本模块为串口调试页面，支持选择串口号、波特率，打开/关闭串口，发送和接收数据。
订阅"OPEN_UART_WIN"事件打开窗口。
]]

local win_id = nil
local main_container, content
local uart_dropdown, baud_dropdown, send_input, receive_area

local function update_receive(data)
    if not exwin.is_active(win_id) then return end
    if receive_area then
        local old = receive_area:get_text() or ""
        receive_area:set_text(old .. data)
    end
end

local function uart_rx_handler(data)
    update_receive(data)
end

local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=800, h=480, color=0xF8F9FA })

    local header = airui.container({ parent = main_container, x=0, y=0, w=800, h=60, color=0x3F51B5 })
    local back_btn = airui.container({ parent = header, x = 700, y = 15, w = 80, h = 40, color = 0x2195F6, radius = 5,
        on_click = function() if win_id then exwin.close(win_id) end end
    })
    airui.label({ parent = back_btn, x = 10, y = 10, w = 60, h = 24, text = "返回", font_size = 20, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    airui.label({ parent = header, x = 10, y = 12, w = 500, h = 40, align = airui.TEXT_ALIGN_CENTER, text="串口", font_size=32, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=60, w=800, h=420, color=0xF3F4F6 })

    airui.label({ parent = content, x=20, y=20, w=100, h=40, text="串口:", font_size=20, color=0x000000 })
    uart_dropdown = airui.dropdown({ parent = content, x=130, y=20, w=150, h=40, options = { "UART1", "UART2", "UART3" } })

    airui.label({ parent = content, x=300, y=20, w=100, h=40, text="波特率:", font_size=20, color=0x000000 })
    baud_dropdown = airui.dropdown({ parent = content, x=410, y=20, w=150, h=40, options = { "9600", "115200", "460800" } })

    airui.button({
        parent = content, x=20, y=80, w=100, h=40,
        text = "打开",
        font_size = 18,
        on_click = function()
            local uart = uart_dropdown:get_selected()
            local baud = baud_dropdown:get_selected()
            log.info("uart", "打开", uart, baud)
        end
    })

    send_input = airui.textarea({
        parent = content, x=20, y=140, w=550, h=50,
        placeholder = "输入要发送的数据",
        font_size = 20
    })
    airui.button({
        parent = content, x=590, y=140, w=100, h=50,
        text = "发送",
        font_size = 20,
        on_click = function()
            local data = send_input:get_text()
            log.info("uart", "发送", data)
        end
    })

    airui.label({ parent = content, x=20, y=210, w=100, h=30, text="接收:", font_size=20, color=0x000000 })
    receive_area = airui.textarea({
        parent = content, x=20, y=240, w=760, h=160,
        placeholder = "接收到的数据将显示在这里",
        read_only = true,
        font_size = 18
    })
end

local function on_create()
    create_ui()
    sys.subscribe("UART_RX_DATA", uart_rx_handler)
end

local function on_destroy()
    sys.unsubscribe("UART_RX_DATA", uart_rx_handler)
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end
sys.subscribe("OPEN_UART_WIN", open_handler)