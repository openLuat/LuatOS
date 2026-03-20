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

--[[
更新接收数据显示

@local
@function update_receive
@param data string 接收到的数据
@return nil
@usage
-- 当串口收到数据时调用，将数据追加到接收区
-- 仅当窗口活跃时执行
]]
local function update_receive(data)
    if not exwin.is_active(win_id) then return end
    if receive_area then
        local old = receive_area:get_text() or ""
        receive_area:set_text(old .. data)
    end
end

-- 串口接收事件处理函数
local function uart_rx_handler(data)
    update_receive(data)
end

--[[
创建窗口UI

@local
@function create_ui
@return nil
@usage
-- 内部调用，创建全屏容器、标题栏、返回按钮、串口配置控件、发送接收区域
]]
local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=320, color=0xF8F9FA })

    -- 顶部返回栏
    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=40, color=0x3F51B5 })
    -- 返回按钮使用容器样式，与历史页面保持一致
    local back_btn = airui.container({ parent = header, x = 400, y = 5, w = 70, h = 30, color = 0x2195F6, radius = 5,
        on_click = function() if win_id then exwin.close(win_id) end end
    })
    airui.label({ parent = back_btn, x = 10, y = 5, w = 50, h = 20, text = "返回", font_size = 16, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    airui.label({ parent = header, x = 10, y = 4, w = 360, h = 32, align = airui.TEXT_ALIGN_CENTER, text="串口", font_size=24, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=40, w=480, h=280, color=0xF3F4F6 })

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
        read_only = true
    })
end

--[[
窗口创建回调

@local
@function on_create
@return nil
@usage
-- 窗口打开时调用，创建UI并订阅串口接收事件
]]
local function on_create()
    
    create_ui()
    sys.subscribe("UART_RX_DATA", uart_rx_handler)
end

--[[
窗口销毁回调

@local
@function on_destroy
@return nil
@usage
-- 窗口关闭时调用，取消订阅，销毁容器，关闭串口
]]
local function on_destroy()
    sys.unsubscribe("UART_RX_DATA", uart_rx_handler)
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
    -- 关闭串口
end

-- 窗口获得焦点回调（空实现）
local function on_get_focus()
    -- 刷新
end

-- 窗口失去焦点回调（空实现）
local function on_lose_focus()
    -- 可暂停接收显示（但订阅仍会触发，只是 is_active 阻止UI更新）
end

-- 订阅打开串口页面的消息
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end
sys.subscribe("OPEN_UART_WIN", open_handler)