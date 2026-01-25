local tcp_page = {}

local container, chat_display, status_label
local host_input, port_input, connect_btn, message_input, send_btn
local keyboard

local default_host = "112.125.89.8"
local default_port = 34458

local connected = false
local current_host
local current_port
local chat_lines = {}

local libnet = require "libnet"
local net_task_name = "tcp_page_net_task"
local net_task_running = false
local stop_request = false
local send_queue = {}

local function append_chat(prefix, text)
    if not text or #text == 0 then
        return
    end
    local entry = (prefix or "") .. text
    table.insert(chat_lines, entry)
    if #chat_lines > 64 then
        table.remove(chat_lines, 1)
    end
    if chat_display then
        chat_display:set_text(table.concat(chat_lines, "\n"))
    end
end

local function update_status(text)
    if status_label then
        status_label:set_text(text or "")
    end
end

local function set_connect_btn_label(text)
    if connect_btn then
        connect_btn:set_text(text)
    end
end

local function reset_state()
    connected = false
    current_host = nil
    current_port = nil
    set_connect_btn_label("连接远程服务器")
end

local function cleanup_connection()
    if net_task_running then
        stop_request = true
        sys.sendMsg(net_task_name, socket.EVENT, 0)
    end
    send_queue = {}
    reset_state()
end

local function get_host_port()
    local host = host_input and (host_input:get_text() or "")
    if host == "" then
        host = default_host
    end
    local port_str = port_input and (port_input:get_text() or "")
    local port = tonumber(port_str)
    if not port then
        port = default_port
    end
    return host, port
end

-- 连接到服务器
local function wait_for_adapter_ready()
    while not stop_request and not socket.adapter(socket.dft()) do
        update_status("等待ip网络就绪...")
        sys.waitUntil("IP_READY", 1000)
    end
    return not stop_request
end

local function process_send_queue(socket_client)
    while #send_queue > 0 and not stop_request do
        local send_item = table.remove(send_queue, 1)
        local result, buff_full = libnet.tx(net_task_name, 15000, socket_client, send_item.data)
        if not result then
            table.insert(send_queue, 1, send_item)
            return false
        end
        if buff_full then
            table.insert(send_queue, 1, send_item)
            update_status("发送队列已满，等待重试")
            return true
        end
        append_chat("发送信息：", send_item.data)
        update_status("已发送 " .. tostring(#send_item.data) .. " 字节")
    end
    return true
end

-- 尝试连接到服务器
local function try_connect(host, port, rx_buff)
    -- 创建socket client
    local socket_client = socket.create(nil, net_task_name)
    -- 如果创建失败，则记录错误并退出
    if not socket_client then
        append_chat(nil, "创建 socket 失败")
        update_status("创建 socket 失败")
        sys.wait(2000)
        return true
    end
    -- 配置socket client
    socket.config(socket_client, nil, false, false)
    -- 连接到服务器
    if not libnet.connect(net_task_name, 15000, socket_client, host, port) then
        append_chat(nil, "连接失败: " .. host .. ":" .. tostring(port))
        update_status("连接失败")
        socket.release(socket_client)
        sys.wait(5000)
        return true
    end

    -- 设置连接状态
    connected = true
    current_host = host
    current_port = port
    append_chat(nil, "连接建立成功")
    update_status("已连接: " .. host .. ":" .. tostring(port))
    set_connect_btn_label("断开连接")

    -- 循环处理发送队列和接收数据
    while not stop_request do
        if not process_send_queue(socket_client) then
            append_chat(nil, "发送失败，重连中")
            break
        end
        if not libnet.wait(net_task_name, 15000, socket_client) then
            append_chat(nil, "连接异常")
            update_status("连接断开，等待重连")
            break
        end
        local succ, read_len = socket.rx(socket_client, rx_buff)
        if not succ then
            append_chat(nil, "数据接收失败")
            break
        end
        if read_len and read_len > 0 then
            local payload = rx_buff:toStr(0, read_len)
            rx_buff:clear()
            append_chat("收到信息：", payload)
            update_status("收到 " .. tostring(#payload) .. " 字节")
        end
    end

    connected = false
    current_host = nil
    current_port = nil
    reset_state()

    if socket_client then
        libnet.close(net_task_name, 5000, socket_client)
        socket.release(socket_client)
    end

    append_chat(nil, "连接已断开")
    if stop_request then
        return false
    end
    sys.wait(5000)
    return true
end

-- 网络任务
local function network_task(host, port)
    -- 创建接收缓冲区
    local rx_buff = zbuff.create(1024)
    -- 如果创建失败，则创建一个更大的缓冲区
    if not rx_buff then
        rx_buff = zbuff.create(1024)
    end
    -- 如果创建失败，则记录错误并退出
    if not rx_buff then
        log.error("tcp_page", "zbuff create failed")
        net_task_running = false
        stop_request = false
        return
    end
    -- 循环等待网络就绪
    while not stop_request do
        -- 等待网络就绪
        if not wait_for_adapter_ready() then
            break
        end
        log.info("tcp_page", "网络就绪，尝试连接到服务器")
        -- 尝试连接到服务器
        if not try_connect(host, port, rx_buff) then
            break
        end
    end
    if rx_buff then
        rx_buff:clear()
    end
    net_task_running = false
    stop_request = false
    reset_state()
end

-- 连接到服务器
local function connect_to_server()
    -- 先断开连接
    if net_task_running then
        stop_request = true
        sys.sendMsg(net_task_name, socket.EVENT, 0)
        update_status("正在断开连接...")
        set_connect_btn_label("连接远程服务器")
        return
    end
    -- 获取服务器地址和端口
    local host, port = get_host_port()
    -- 设置当前服务器地址和端口
    current_host = host
    current_port = port
    stop_request = false
    send_queue = {}
    connected = false
    -- 更新状态
    update_status("连接中...")
    append_chat(nil, "正在连接：" .. host .. ":" .. tostring(port))
    set_connect_btn_label("取消连接")
    -- 启动网络任务
    net_task_running = true
    sys.taskInitEx(network_task, net_task_name, nil, host, port)
end

local function send_message()
    if not net_task_running then
        update_status("请先建立连接")
        return
    end
    if not connected then
        update_status("连接尚未建立")
        return
    end
    if not message_input then
        return
    end
    local text = message_input:get_text() or ""
    if #text == 0 then
        return
    end
    if #send_queue >= 64 then
        update_status("发送队列已满")
        return
    end
    table.insert(send_queue, {data = text})
    sys.sendMsg(net_task_name, socket.EVENT, 0)
    message_input:set_text("")
end

function tcp_page.create_page()
    if container then
        return container
    end

    container = airui.container({
        x = 0, y = 0, w = 320, h = 600,
        color = 0xffffff,
    })

    airui.label({
        parent = container,
        text = "TCP 远程通信",
        x = 20, y = 10, w = 280, h = 32,
        font_size = 24,
    })

    status_label = airui.label({
        parent = container,
        text = "等待连接",
        x = 20, y = 50, w = 280, h = 24,
    })
    host_input = airui.textarea({
        parent = container,
        x = 20, y = 80, w = 180, h = 45,
        placeholder = "服务器地址",
        text = default_host,
        max_len = 128,
    })

    port_input = airui.textarea({
        parent = container,
        x = 210, y = 80, w = 90, h = 45,
        placeholder = "端口",
        text = tostring(default_port),
    })

    connect_btn = airui.button({
        parent = container,
        text = "连接远程服务器",
        x = 60, y = 140, w = 200, h = 40,
        on_click = connect_to_server,
    })

    airui.button({
        parent = container,
        text = "清空记录",
        x = 20, y = 280, w = 120, h = 30,
        on_click = function()
            chat_lines = {}
            if chat_display then
                chat_display:set_text("通信记录")
            end
        end,
    })

    chat_display = airui.textarea({
        parent = container,
        x = 20, y = 190, w = 280, h = 120,
        read_only = true,
        auto_line_feed = true,
        text = "通信记录",
    })

    message_input = airui.textarea({
        parent = container,
        x = 20, y = 320, w = 180, h = 40,
        placeholder = "输入消息",
        max_len = 128,
    })

    send_btn = airui.button({
        parent = container,
        text = "发送",
        x = 210, y = 320, w = 90, h = 40,
        on_click = send_message,
    })

    keyboard = airui.keyboard({
        parent = container,
        x = 0, y = 40, w = 320, h = 200,
        target = message_input,
        mode = "text",
        auto_hide = true,
        target = message_input,
    })

    airui.button({
        parent = container,
        text = "返回",
        x = 250, y = 20, w = 50, h = 30,
        on_click = function()
            cleanup_connection()
            container:hide()
        end,
    })

    container:hide()
    return container
end

function tcp_page.show_page()
    if not container then
        tcp_page.create_page()
    end
    container:open()
end

return tcp_page

