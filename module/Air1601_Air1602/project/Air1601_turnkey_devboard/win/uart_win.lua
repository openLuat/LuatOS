-- uart_win.lua - 串口页面(Air1601版本，适配1024x600分辨率)

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
    main_container = airui.container({ x = 0, y = 0, w = 1024, h = 600, color = 0xF8F9FA, parent = airui.screen })

    local header = airui.container({ parent = main_container, x = 0, y = 0, w = 1024, h = 60, color = 0x3F51B5 })
    local back_btn = airui.button({ parent = header, x = 924, y = 10, w = 80, h = 40, color = 0x2195F6, text = "返回", font_size = 30, text_color = 0xffffff,
        on_click = function() if win_id then exwin.close(win_id) win_id = nil end end
    })
    airui.label({ parent = header, x = 400, y = 10, w = 224, h = 40, text = "串口", font_size = 32, color = 0xffffff, align = airui.TEXT_ALIGN_CENTER })

    content = airui.container({ parent = main_container, x = 0, y = 60, w = 1024, h = 540, color = 0xF3F4F6 })

    -- 串口选择
    airui.label({ parent = content, x = 100, y = 40, w = 100, h = 40, text = "串口:", font_size = 24, color = 0x000000 })
    uart_dropdown = airui.dropdown({ parent = content, x = 200, y = 40, w = 150, h = 40, options = { "UART1", "UART2", "UART3" } })

    -- 波特率
    airui.label({ parent = content, x = 400, y = 40, w = 100, h = 40, text = "波特率:", font_size = 24, color = 0x000000 })
    baud_dropdown = airui.dropdown({ parent = content, x = 500, y = 40, w = 150, h = 40, options = { "9600", "115200", "460800" } })

    -- 打开/关闭按钮
    airui.button({
        parent = content, x = 700, y = 40, w = 100, h = 40,
        text = "打开",
        on_click = function()
            local uart = uart_dropdown:get_selected()
            local baud = baud_dropdown:get_selected()
            -- TODO: 打开串口
            log.info("uart", "打开", uart, baud)
        end
    })

    -- 发送输入框
    send_input = airui.textarea({
        parent = content, x = 100, y = 120, w = 600, h = 50,
        placeholder = "输入要发送的数据"
    })
    airui.button({
        parent = content, x = 720, y = 120, w = 100, h = 50,
        text = "发送",
        on_click = function()
            local data = send_input:get_text()
            -- TODO: 通过串口发送
            log.info("uart", "发送", data)
        end
    })

    -- 接收数据显示
    airui.label({ parent = content, x = 100, y = 200, w = 100, h = 30, text = "接收:", font_size = 24, color = 0x000000 })
    receive_area = airui.textarea({
        parent = content, x = 100, y = 240, w = 824, h = 200,
        placeholder = "接收到的数据将显示在这里",
        read_only = true
    })
end

local function on_create()
    win_id = create_ui()
    sys.subscribe("UART_RX_DATA", uart_rx_handler)
end

local function on_destroy()
    sys.unsubscribe("UART_RX_DATA", uart_rx_handler)
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
    -- 关闭串口
end

local function on_get_focus()
    -- 刷新
end

local function on_lose_focus()
    -- 可暂停接收显示（但订阅仍会触发，只是 is_active 阻止UI更新）
end

sys.subscribe("OPEN_UART_WIN", function()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({ 
            on_create = on_create, 
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus
        })
    end
end)
