-- 串口页面
local uart_page = {}

local main_container, content
local uart_dropdown, baud_dropdown, send_input, receive_area

function uart_page.create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=320, color=0xF8F9FA })

    -- 顶部返回栏
    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=50, color=0x3F51B5 })
    local back_btn =  airui.button({ parent = header, x=10, y=5, w=50, h=40, color=0x3F51B5,text = "返回",
        on_click = function() _G.go_back() end
    })
  
    airui.label({ parent = header, x=60, y=10, w=360, h=30, align = airui.TEXT_ALIGN_CENTER, text="串口", font_size=24, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=50, w=480, h=270, color=0xF3F4F6 })

    -- 串口选择
    airui.label({ parent = content, x=10, y=10, w=80, h=30, text="串口:", font_size=16, color=0x000000 })
    uart_dropdown = airui.dropdown({ parent = content, x=100, y=10, w=100, h=30, options = { "UART1", "UART2", "UART3" } })

    -- 波特率
    airui.label({ parent = content, x=210, y=10, w=80, h=30, text="波特率:", font_size=16, color=0x000000 })
    baud_dropdown = airui.dropdown({ parent = content, x=300, y=10, w=100, h=30, options = { "9600", "115200", "460800" } })

    -- 打开/关闭按钮
    airui.button({
        parent = content, x=10, y=50, w=80, h=30,
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
        parent = content, x=10, y=90, w=300, h=40,
        placeholder = "输入要发送的数据"
    })
    airui.button({
        parent = content, x=320, y=90, w=80, h=40,
        text = "发送",
        on_click = function()
            local data = send_input:get_text()
            -- TODO: 通过串口发送
            log.info("uart", "发送", data)
        end
    })

    -- 接收数据显示
    airui.label({ parent = content, x=10, y=140, w=100, h=20, text="接收:", font_size=16, color=0x000000 })
    receive_area = airui.textarea({
        parent = content, x=10, y=160, w=460, h=100,
        placeholder = "接收到的数据将显示在这里",
        read_only = true  -- 假设支持只读
    })
end

function uart_page.init()
    uart_page.create_ui()
    -- TODO: 订阅串口接收事件，更新 receive_area
end

function uart_page.cleanup()
    if main_container then main_container:destroy(); main_container = nil end
    -- 关闭串口
end

return uart_page