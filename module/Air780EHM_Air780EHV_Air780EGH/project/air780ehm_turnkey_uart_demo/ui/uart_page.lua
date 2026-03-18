--[[
@module  uart_page
@summary 酷炫版串口页面（完整功能版本）
@version 2.0
@date    2026.03.17
]]

local uart_page = {}

-- 加载串口应用模块
local uart_app = require("uart_app")

-- 加载虚拟键盘
local virtual_keyboard = require("virtual_keyboard")

-- UI控件引用
local main_container
local uart_dropdown
local baud_dropdown
local send_input
local receive_area
local hex_mode_switch
local send_btn
local clear_btn
local connect_btn
local status_indicator
local count_label

-- 状态变量
local uart_id = 1
local baudrate = "115200"
local hex_mode = false
local is_open = false

-- 接收数据缓冲区（最多保留2000字符）
local receive_buffer = ""
local MAX_BUFFER = 2000
local receive_count = 0
local send_count = 0

-- 格式化十六进制显示
local function to_hex_string(data)
    local hex_str = ""
    for i = 1, #data do
        local byte = data:byte(i)
        hex_str = hex_str .. string.format("%02X ", byte)
    end
    return hex_str
end

-- 从十六进制字符串转换到实际字节
local function from_hex_string(hex_str)
    -- 移除所有空格
    hex_str = hex_str:gsub("%s", "")

    local result = ""
    local i = 1
    while i <= #hex_str do
        -- 每两个字符转换为一个字节
        if i + 1 <= #hex_str then
            local hex_byte = hex_str:sub(i, i + 1)
            local byte_val = tonumber(hex_byte, 16)
            if byte_val then
                result = result .. string.char(byte_val)
            end
        end
        i = i + 2
    end
    return result
end

-- 更新接收区域显示
local function update_receive_display()
    if receive_area then
        local display_text = receive_buffer
        if #display_text == 0 then
            display_text = "等待接收数据..."
        end
        receive_area:set_text(display_text)
    end
end

-- 添加数据到接收缓冲区
local function add_to_receive(data)
    if hex_mode then
        receive_buffer = receive_buffer .. to_hex_string(data)
    else
        receive_buffer = receive_buffer .. data
    end

    -- 限制缓冲区大小
    if #receive_buffer > MAX_BUFFER then
        receive_buffer = receive_buffer:sub(-MAX_BUFFER)
    end

    receive_count = receive_count + #data
    update_receive_display()
    update_count_display()
end

-- 更新状态指示器
local function update_status()
    if status_indicator then
        if is_open then
            status_indicator:set_color(0x00ff88)
            -- 启动闪烁效果
            if not status_blink_timer then
                status_blink_timer = sys.timerLoopStart(status_blink, 500)
            end
        else
            status_indicator:set_color(0xff4444)
            -- 停止闪烁效果
            if status_blink_timer then
                sys.timerStop(status_blink_timer)
                status_blink_timer = nil
            end
        end
    end
    -- 更新连接按钮文字
    if connect_btn then
        if is_open then
            connect_btn:set_text("断开")
            connect_btn:set_stype({
                bg_color = 0xff4444,
                text_color = 0xffffff
            })
        else
            connect_btn:set_text("连接")
            connect_btn:set_stype({
                bg_color = 0x00ff88,
                text_color = 0x1a1a2e
            })
        end
    end
end

-- 更新计数器显示
local function update_count_display()
    if count_label then
        count_label:set_text(string.format("接收 Rx:%d Tx:%d", receive_count, send_count))
    end
end

-- 处理串口连接/断开
local function handle_connect()
    if is_open then
        -- 断开串口
        log.info("uart_page", "【连接按钮】用户点击断开串口按钮")

        -- 断开前隐藏键盘
        log.info("uart_page", "【键盘自动隐藏】断开串口前隐藏虚拟键盘")
        virtual_keyboard.hide()

        if uart_app.close() then
            is_open = false
            update_status()
            log.info("uart_page", "串口已断开")

            local msg = airui.msgbox({
                title = "提示",
                text = "串口已断开",
                buttons = { "确定" },
                timeout = 1000
            })
            msg:show()
        else
            log.warn("uart_page", "【连接按钮】串口断开失败")
        end
    else
        -- 连接串口
        log.info("uart_page", "【连接按钮】用户点击连接串口按钮")

        if not uart_dropdown then
            log.error("uart_page", "【连接按钮】错误 - uart_dropdown为nil")
            return
        end

        if not baud_dropdown then
            log.error("uart_page", "【连接按钮】错误 - baud_dropdown为nil")
            return
        end

        local uart_idx = uart_dropdown:get_selected()
        local baud_idx = baud_dropdown:get_selected()

        log.info("uart_page", "【连接按钮】下拉框选择 - UART索引:" .. tostring(uart_idx) .. " 波特率索引:" .. tostring(baud_idx))

        -- get_selected() 返回的是索引（从0开始），需要映射到实际值
        local uart_num = uart_idx + 1  -- UART1, UART2, UART3
        local uart_options = { "UART1", "UART2", "UART3" }
        local baud_options = { "9600", "115200", "460800" }

        baudrate = baud_options[baud_idx + 1] or "115200"
        local selected_uart = uart_options[uart_idx + 1] or "UART1"

        log.info("uart_page", "【连接按钮】准备连接串口 - 串口:" .. selected_uart .. " 波特率:" .. baudrate)

        if uart_app.open(uart_num, baudrate) then
            is_open = true
            update_status()
            log.info("uart_page", "串口连接成功", uart_num, baudrate)

            -- 显示成功提示
            local msg = airui.msgbox({
                title = "成功",
                text = string.format("串口 %s 已连接\n波特率: %s", selected_uart, baudrate),
                buttons = { "确定" },
                timeout = 1500
            })
            msg:show()

            -- 串口连接成功后自动显示键盘
            log.info("uart_page", "【键盘自动显示】串口已连接，自动显示虚拟键盘")
            virtual_keyboard.show(send_input, send_input:get_text())
        else
            log.error("uart_page", "串口连接失败", uart_num, baudrate)

            local msg = airui.msgbox({
                title = "失败",
                text = "串口连接失败，请检查配置",
                buttons = { "确定" }
            })
            msg:show()
        end
    end
end

-- 处理数据发送
local function handle_send()
    log.info("uart_page", "【发送按钮】用户点击发送按钮")

    if not is_open then
        log.warn("uart_page", "【发送按钮】警告 - 串口未连接")
        local msg = airui.msgbox({
            title = "提示",
            text = "请先连接串口",
            buttons = { "确定" },
            timeout = 2000
        })
        msg:show()
        return
    end

    local data = send_input:get_text()
    log.info("uart_page", "【发送按钮】获取发送数据 - 长度:" .. (#data or 0))

    if not data or #data == 0 then
        log.warn("uart_page", "【发送按钮】警告 - 输入框为空")
        local msg = airui.msgbox({
            title = "提示",
            text = "请输入要发送的数据",
            buttons = { "确定" },
            timeout = 2000
        })
        msg:show()
        return
    end

    log.info("uart_page", "【发送按钮】准备发送数据:" .. data)
    log.info("uart_page", "【发送按钮】十六进制模式:" .. tostring(hex_mode))

    -- 根据十六进制模式转换数据
    local data_to_send = data
    if hex_mode then
        data_to_send = from_hex_string(data)
        log.info("uart_page", "【发送按钮】hex转换后长度:" .. (#data_to_send or 0))
    end

    if uart_app.send(data_to_send) then
        send_count = send_count + #data_to_send
        update_count_display()
        log.info("uart_page", "发送成功", #data_to_send)
    else
        log.error("uart_page", "【发送按钮】发送失败")
    end

    send_input:set_text("")
    virtual_keyboard.set_text("")  -- 同时清空虚拟键盘的文本
end

-- 处理清空接收区
local function handle_clear()
    receive_buffer = ""
    receive_count = 0
    send_count = 0
    update_receive_display()
    update_count_display()
    log.info("uart_page", "清空接收区")
end

-- 创建酷炫UI
function uart_page.create_ui()
    log.info("uart_page", "【UI创建】开始创建串口页面UI")

    -- 主容器 - 深色主题
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 320,
        color = 0x1a1a2e
    })
    log.info("uart_page", "【UI创建】主容器创建完成")

    -- 顶部导航栏
    local header = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 480,
        h = 55,
        color = 0x16213e
    })

    -- 返回按钮
    local back_btn = airui.button({
        parent = header,
        x = 10,
        y = 10,
        w = 60,
        h = 35,
        text = "← 返回",
        font_size = 16,
        stype = {
            bg_color = 0x0f3460,
            text_color = 0x00d4ff
        },
        radius = 8,
        on_click = function() _G.go_back() end
    })

    -- 标题
    airui.label({
        parent = header,
        x = 80,
        y = 12,
        w = 320,
        h = 30,
        text = "串口调试",
        font_size = 24,
        color = 0x00d4ff,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 状态指示器
    status_indicator = airui.container({
        parent = header,
        x = 410,
        y = 17,
        w = 20,
        h = 20,
        color = 0xff4444,
        radius = 10,
    })

    -- 分割线
    airui.container({
        parent = main_container,
        x = 0,
        y = 55,
        w = 480,
        h = 2,
        color = 0x0f3460
    })

    -- 内容区域
    local content = airui.container({
        parent = main_container,
        x = 0,
        y = 57,
        w = 480,
        h = 263,
        color = 0x1a1a2e
    })

    -- 配置区域（紧凑版）
    local config_box = airui.container({
        parent = content,
        x = 8,
        y = 8,
        w = 464,
        h = 60,
        color = 0x0f3460,
        radius = 8
    })

    -- 串口选择
    airui.label({
        parent = config_box,
        x = 10,
        y = 8,
        w = 45,
        h = 20,
        text = "串口:",
        font_size = 14,
        color = 0x00d4ff
    })
    uart_dropdown = airui.dropdown({
        parent = config_box,
        x = 55,
        y = 6,
        w = 85,
        h = 26,
        options = { "UART1", "UART2", "UART3" },
        font_size = 12
    })
    log.info("uart_page", "【UI创建】串口下拉框创建完成")

    -- 波特率
    airui.label({
        parent = config_box,
        x = 150,
        y = 8,
        w = 55,
        h = 20,
        text = "波特率:",
        font_size = 14,
        color = 0x00d4ff
    })
    baud_dropdown = airui.dropdown({
        parent = config_box,
        x = 205,
        y = 6,
        w = 85,
        h = 26,
        options = { "9600", "115200", "460800" },
        font_size = 12
    })
    log.info("uart_page", "【UI创建】波特率下拉框创建完成")

    -- 连接按钮
    connect_btn = airui.button({
        parent = config_box,
        x = 300,
        y = 6,
        w = 150,
        h = 26,
        text = "连接",
        font_size = 14,
        stype = {
            bg_color = 0x00ff88,
            text_color = 0x1a1a2e
        },
        radius = 6,
        on_click = handle_connect
    })

    -- 十六进制模式开关
    hex_mode_switch = airui.switch({
        parent = config_box,
        x = 10,
        y = 38,
        checked = false,
        on_change = function(self)
            hex_mode = not hex_mode
            log.info("uart_page", "十六进制模式", hex_mode)
        end
    })

    airui.label({
        parent = config_box,
        x = 40,
        y = 38,
        w = 80,
        h = 18,
        text = "十六进制",
        font_size = 12,
        color = 0xaaaaaa
    })

    -- 初始化并创建虚拟键盘
    log.info("uart_page", "【UI创建】初始化并创建虚拟键盘")
    virtual_keyboard.create(main_container, 8, 245, 464, 72)
    log.info("uart_page", "【UI创建】串口页面UI创建完成")
    
    -- 发送区域（紧凑版）
    local send_box = airui.container({
        parent = content,
        x = 8,
        y = 75,
        w = 464,
        h = 60,
        color = 0x0f3460,
        radius = 8
    })

    airui.label({
        parent = send_box,
        x = 10,
        y = 6,
        w = 40,
        h = 18,
        text = "发送:",
        font_size = 14,
        color = 0x00d4ff
    })

    send_input = airui.textarea({
        parent = send_box,
        x = 10,
        y = 26,
        w = 380,
        h = 28,
        placeholder = "点击输入",
        font_size = 12,
        on_click = function()
            virtual_keyboard.show(send_input, send_input:get_text())
        end
    })

    send_btn = airui.button({
        parent = send_box,
        x = 398,
        y = 6,
        w = 55,
        h = 48,
        text = "发送",
        font_size = 14,
        stype = {
            bg_color = 0xe94560,
            text_color = 0xffffff
        },
        radius = 4,
        on_click = handle_send
    })

    -- 接收区域（扩展版）
    local receive_box = airui.container({
        parent = content,
        x = 8,
        y = 145,
        w = 464,
        h = 100,
        color = 0x0f3460,
        radius = 8
    })

    count_label = airui.label({
        parent = receive_box,
        x = 10,
        y = 6,
        w = 180,
        h = 18,
        text = string.format("接收 Rx:%d Tx:%d", receive_count, send_count),
        font_size = 12,
        color = 0x00d4ff
    })

    receive_area = airui.label({
        parent = receive_box,
        x = 10,
        y = 26,
        w = 444,
        h = 80,
        text = "等待接收数据...",
        font_size = 12,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_TOP_LEFT
    })

    clear_btn = airui.button({
        parent = receive_box,
        x = 384,
        y = 6,
        w = 75,
        h = 22,
        text = "清空",
        font_size = 14,
        stype = {
            bg_color = 0x666666,
            text_color = 0xffffff
        },
        radius = 4,
        on_click = handle_clear
    })
end

-- 处理串口接收数据
local function handle_uart_receive(uart_id, data)
    if active then
        log.info("uart_page", "【接收数据】串口ID:" .. tostring(uart_id) .. " 数据长度:" .. (#data or 0))
        add_to_receive(data)
    else
        log.debug("uart_page", "【接收数据】页面未激活，忽略数据")
    end
end

-- 页面初始化
function uart_page.init()
    log.info("uart_page", "【页面初始化】开始初始化串口页面")
    active = true

    uart_page.create_ui()

    -- 订阅串口接收事件
    log.info("uart_page", "【页面初始化】订阅串口接收事件")
    sys.subscribe("uart_data", handle_uart_receive)

    -- 初始化显示
    update_receive_display()
    update_status()

    log.info("uart_page", "串口页面初始化完成")
end

-- 状态变量
local active = false
local status_blink_timer = nil

-- 状态指示器闪烁效果
local function status_blink()
    if not active or not status_indicator then return end
    
    local current_color = status_indicator:get_color() or 0
    if current_color == 0x00ff88 then
        status_indicator:set_color(0x00cc66)
    else
        status_indicator:set_color(0x00ff88)
    end
end

-- 页面清理
function uart_page.cleanup()
    log.info("uart_page", "【页面清理】开始清理串口页面")
    active = false

    -- 停止状态指示器闪烁
    if status_blink_timer then
        sys.timerStop(status_blink_timer)
        status_blink_timer = nil
    end

    -- 取消订阅
    log.info("uart_page", "【页面清理】取消订阅串口接收事件")
    sys.unsubscribe("uart_data", handle_uart_receive)

    -- 关闭串口
    if is_open then
        log.info("uart_page", "【页面清理】关闭打开的串口")
        uart_app.close()
        is_open = false
    end

    -- 销毁虚拟键盘
    log.info("uart_page", "【页面清理】销毁虚拟键盘")
    virtual_keyboard.destroy()

    -- 销毁主容器
    if main_container then
        log.info("uart_page", "【页面清理】销毁主容器")
        main_container:destroy()
        main_container = nil
    end

    -- 清空控件引用
    uart_dropdown = nil
    baud_dropdown = nil
    send_input = nil
    receive_area = nil
    hex_mode_switch = nil
    send_btn = nil
    clear_btn = nil
    connect_btn = nil
    status_indicator = nil

    log.info("uart_page", "串口页面清理完成")
end

return uart_page
