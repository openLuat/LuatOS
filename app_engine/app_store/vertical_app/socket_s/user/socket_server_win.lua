--[[
@module  socket_server_win
@summary Socket Server管理页面模块
@version 1.0
@date    2026.04.08
@usage
支持TCP/UDP服务器管理，数据收发及日志显示功能。
参考 socket/server demo 架构重写，使用正确的 socket 接收方式。
]]

-- ==================== 窗口级资源句柄 ====================
local win_id = nil
local main_container = nil
local content_container = nil
local tab_bar_container = nil

-- ==================== 加载依赖模块 ====================
local exwin = require "exwin"
local libnet = require "libnet"
local udpsrv = require "udpsrv"

-- ==================== 运行时状态 ====================
local current_tab = "dashboard"
local selected_conn = "tcp"

-- Tab配置
local TABS = {
    { key = "dashboard", name = "仪表盘", icon = "D" },
    { key = "detail",    name = "详情",   icon = "I" },
    { key = "settings",  name = "设置",   icon = "S" },
    { key = "logs",      name = "日志",   icon = "L" }
}

-- Server配置
local server_config = {
    tcp = {
        enabled = true,
        ip = "192.168.1.19",
        port = 50003,
        running = false,
        send_bytes = 0,
        recv_bytes = 0,
        client_count = 0,
        retry_count = 0
    },
    udp = {
        enabled = true,
        ip = "192.168.1.19",
        port = 50004,
        running = false,
        send_bytes = 0,
        recv_bytes = 0,
        client_count = 0,
        retry_count = 0
    }
}

-- 发送队列
local send_queues = {
    tcp = {},
    udp = {}
}

-- 任务退出标志
local task_exit_flags = {
    tcp = false,
    udp = false
}

-- 重启标志
local restart_flags = {
    tcp = false,
    udp = false
}

-- 日志数据
local log_entries = {}
local max_logs = 200
local log_scroll_offset = 0
local logs_per_page = 8

-- 网卡信息
local netcard_info = {
    name = "WiFi 网卡",
    connected = true,
    ip = "192.168.1.19"
}

-- 获取实际IP地址的函数
local function update_netcard_info()
    -- 尝试使用 wlan.getIP() 获取WiFi IP地址
    if wlan and wlan.getIP then
        local ip = wlan.getIP()
        if ip and ip ~= "0.0.0.0" then
            netcard_info.ip = ip
            netcard_info.connected = true
            -- 同步更新服务器配置的IP
            server_config.tcp.ip = ip
            server_config.udp.ip = ip
            return ip
        end
    end
    
    -- 如果无法获取IP，保持默认IP但标记为未连接
    netcard_info.connected = false
    return netcard_info.ip
end

-- 订阅 IP_READY 消息，获取网络就绪时的IP地址
sys.subscribe("IP_READY", function(ip, adapter)
    if ip and ip ~= "0.0.0.0" then
        log.info("socket_server", "IP_READY 收到IP:", ip)
        netcard_info.ip = ip
        netcard_info.connected = true
        -- 同步更新服务器配置的IP
        server_config.tcp.ip = ip
        server_config.udp.ip = ip
    end
end)

-- 订阅 IP_LOSE 消息，处理网络断开
sys.subscribe("IP_LOSE", function()
    log.warn("socket_server", "IP_LOSE 网络断开")
    netcard_info.connected = false
end)

-- 设置页面输入框引用
local settings_inputs = {
    tcp = { ip = nil, port = nil },
    udp = { ip = nil, port = nil }
}

-- 键盘对象
local text_keyboard = nil
local numeric_keyboard = nil

-- ==================== 工具函数 ====================

-- 初始化键盘
local function init_keyboards()
    log.info("socket_server_win", "初始化键盘")
    text_keyboard = airui.keyboard({
        mode = "text",
        auto_hide = true,
        preview = true,
        preview_height = 40,
        w = 480,
        h = 200,
        on_commit = function(self)
            log.info("socket_server_win", "text keyboard commit")
            self:hide()
        end
    })

    numeric_keyboard = airui.keyboard({
        mode = "numeric",
        auto_hide = true,
        preview = true,
        preview_height = 40,
        w = 480,
        h = 200,
        on_commit = function(self)
            log.info("socket_server_win", "numeric keyboard commit")
            self:hide()
        end
    })
end

-- 字节转KB
local function bytes_to_kb(bytes)
    return string.format("%.1f", bytes / 1024)
end

-- 添加日志
local function add_log(tag, type, content)
    local entry = {
        time = os.date("%H:%M:%S"),
        tag = tag,
        type = type,
        content = content
    }
    table.insert(log_entries, 1, entry)
    if #log_entries > max_logs then
        table.remove(log_entries)
    end
    
    -- 如果当前在日志页面，自动刷新显示
    if current_tab == "logs" and content_container then
        refresh_content()
    end
end

-- ==================== Socket Server 任务 ====================
-- 完全参考 socket/server demo 架构实现

-- 用户消息定义（参考 demo 的 readme.md）
-- "SEND_DATA_REQ"：UI层发布此消息，通知 server 发送数据
-- "RECV_DATA_FROM_CLIENT"：server 收到数据后发布此消息，通知 UI 层

-- TCP Server 任务（参考 demo tcp_server_main.lua + tcp_server_sender.lua + tcp_server_receiver.lua）
local function tcp_server_task()
    log.info("tcp_server", "========== TCP任务启动 ==========")
    local task_name = "tcp_server_task"
    local netc = nil
    local result, param
    
    -- socket 接收缓冲区（参考 demo 的 tcp_server_receiver）
    local recv_buff = nil
    
    -- TCP 发送队列处理函数（参考 demo 的 tcp_server_sender.proc）
    local function tcp_process_send_queue()
        while #send_queues.tcp > 0 do
            local item = table.remove(send_queues.tcp, 1)
            if not item or not item.data then
                log.error("tcp_server", "队列项无效，跳过")
                goto continue_tcp_send
            end
            
            local data = item.data
            log.info("tcp_server", "准备发送数据，长度:", #data)
            result = libnet.tx(task_name, 15000, netc, data)
            
            if not result then
                log.error("tcp_server", "发送失败，放回队列")
                table.insert(send_queues.tcp, 1, item)
                return false  -- 发送失败，退出处理
            end
            
            server_config.tcp.send_bytes = server_config.tcp.send_bytes + #data
            log.info("tcp_server", "发送成功")
            
            ::continue_tcp_send::
        end
        return true
    end
    
    -- TCP 接收数据函数（参考 demo 的 tcp_server_receiver.proc）
    local function tcp_receive_data()
        if recv_buff == nil then
            recv_buff = zbuff.create(1024)
        end
        
        local rx_count = 0
        while true do
            local succ, rx_param = socket.rx(netc, recv_buff)
            
            if not succ then
                log.info("tcp_server", "socket.rx 错误，连接断开")
                return false
            end
            
            if recv_buff:used() > 0 then
                rx_count = rx_count + 1
                local data = recv_buff:query()
                server_config.tcp.recv_bytes = server_config.tcp.recv_bytes + #data
                add_log("TCP", "RECV", data)
                log.info("tcp_server", "收到数据[", rx_count, "]，长度:", #data)
                recv_buff:del()
            else
                if rx_count > 0 then
                    log.info("tcp_server", "数据接收完成，共", rx_count, "条")
                end
                break
            end
        end
        return true
    end
    
    log.info("tcp_server", "进入主循环")
    while not task_exit_flags.tcp do
        local config = server_config.tcp
        
        if not config.enabled then
            sys.wait(1000)
            goto tcp_continue
        end
        
        -- 等待网络就绪
        while not socket.adapter(socket.dft()) do
            log.warn("tcp_server", "等待网络就绪...")
            sys.waitUntil("IP_READY", 1000)
            if task_exit_flags.tcp then return end
        end
        
        -- 创建 socket
        netc = socket.create(socket.dft(), task_name)
        if not netc then
            log.error("tcp_server", "socket.create 失败")
            config.retry_count = config.retry_count + 1
            sys.wait(5000)
            goto tcp_continue
        end
        
        -- 配置 socket
        result = socket.config(netc, config.port, nil, nil, 300, 10, 3)
        if not result then
            log.error("tcp_server", "socket.config 失败")
            goto TCP_EXCEPTION
        end
        
        -- 开始监听
        log.info("tcp_server", "开始监听端口:", config.port)
        result = libnet.listen(task_name, 0, netc)
        if not result then
            log.error("tcp_server", "libnet.listen 失败")
            goto TCP_EXCEPTION
        end
        
        config.running = true
        add_log("TCP", "INFO", "服务器启动在 " .. config.ip .. ":" .. config.port)
        log.info("tcp_server", "客户端已连接")
        
        -- 发送欢迎消息
        libnet.tx(task_name, 0, netc, "TCP server is UP!")
        config.client_count = 1
        add_log("TCP", "CONN", "客户端连接")
        
        -- 数据收发主循环（参考 demo 架构）
        while config.running and config.enabled and not task_exit_flags.tcp do
            -- 检查重启标志
            if restart_flags.tcp then
                restart_flags.tcp = false
                break
            end
            
            -- 1. 接收数据
            if not tcp_receive_data() then
                log.info("tcp_server", "接收数据失败，连接断开")
                break
            end
            
            -- 2. 发送数据（处理队列）
            if not tcp_process_send_queue() then
                log.info("tcp_server", "发送数据失败，连接异常")
                break
            end
            
            -- 3. 等待事件（15秒超时）
            result, param = libnet.wait(task_name, 15000, netc)
            if not result then
                log.info("tcp_server", "客户端断开")
                break
            end
        end
        
        ::TCP_EXCEPTION::
        
        -- 清空发送队列
        send_queues.tcp = {}
        
        if netc then
            libnet.close(task_name, 5000, netc)
            socket.release(netc)
            netc = nil
        end
        
        config.running = false
        config.client_count = 0
        add_log("TCP", "DISC", "客户端断开")
        
        if not config.enabled or task_exit_flags.tcp then
            log.info("tcp_server", "服务器停止")
            break
        end
        
        sys.wait(5000)
        
        ::tcp_continue::
    end
    
    if recv_buff then
        recv_buff:free()
        recv_buff = nil
    end
    
    log.info("tcp_server", "任务退出")
end

-- UDP Server 任务（参考 demo udp_server_main.lua + udp_server_sender.lua + udp_server_receiver.lua）
local function udp_server_task()
    log.info("udp_server", "========== UDP任务启动 ==========")
    local task_name = "udp_server_task"
    local udp_server = nil
    local ret, data, remote_ip, remote_port
    
    -- 客户端信息（记录发送方的 IP 和端口）
    local client_info = {}
    
    -- UDP 发送队列处理函数（参考 demo 的 udp_server_sender.proc）
    local function udp_process_send_queue()
        if not udp_server then
            log.error("udp_server", "udp_server 不存在")
            return false
        end
        
        local queue_len = #send_queues.udp
        if queue_len == 0 then
            return true
        end
        
        log.info("udp_server", "处理发送队列，长度:", queue_len)
        
        while #send_queues.udp > 0 do
            local item = table.remove(send_queues.udp, 1)
            
            -- 检查 item 有效性
            if not item then
                log.error("udp_server", "队列项为 nil，跳过")
                goto continue_udp_send
            end
            
            local send_data = item.data
            if not send_data then
                log.error("udp_server", "队列项 data 为 nil，跳过")
                goto continue_udp_send
            end
            
            -- 确定目标地址
            local target_ip = item.ip or client_info.ip
            local target_port = item.port or client_info.port
            
            if not target_ip or not target_port then
                log.error("udp_server", "没有目标地址，无法发送")
                -- 将数据放回队列，等待获取客户端地址
                table.insert(send_queues.udp, 1, item)
                return false
            end
            
            log.info("udp_server", "准备发送数据到", target_ip .. ":" .. target_port)
            local result = udp_server:send(send_data, target_ip, target_port)
            
            if result then
                log.info("udp_server", "发送成功")
                server_config.udp.send_bytes = server_config.udp.send_bytes + #send_data
            else
                log.error("udp_server", "发送失败，放回队列")
                table.insert(send_queues.udp, 1, item)
                return false
            end
            
            ::continue_udp_send::
        end
        return true
    end
    
    log.info("udp_server", "进入主循环")
    while not task_exit_flags.udp do
        local config = server_config.udp
        
        if not config.enabled then
            sys.wait(1000)
            goto udp_continue
        end
        
        -- 等待网络就绪
        while not socket.adapter(socket.dft()) do
            log.warn("udp_server", "等待网络就绪...")
            sys.waitUntil("IP_READY", 1000)
            if task_exit_flags.udp then return end
        end
        
        -- 创建 UDP 服务器
        udp_server = udpsrv.create(config.port, task_name, socket.dft())
        if not udp_server then
            log.error("udp_server", "udpsrv.create 失败")
            config.retry_count = config.retry_count + 1
            sys.wait(5000)
            goto udp_continue
        end
        
        config.running = true
        add_log("UDP", "INFO", "服务器启动在 " .. config.ip .. ":" .. config.port)
        log.info("udp_server", "UDP服务器启动成功，端口:", config.port)
        
        -- 发送广播消息通知客户端
        udp_server:send("UDP Server is UP", "255.255.255.255", 50000)
        
        -- 数据收发主循环（参考 demo 架构）
        while config.running and config.enabled and not task_exit_flags.udp do
            -- 检查重启标志
            if restart_flags.udp then
                restart_flags.udp = false
                break
            end
            
            -- 1. 先处理发送队列（不依赖接收事件）
            udp_process_send_queue()
            
            -- 2. 等待接收数据事件（15秒超时）
            ret, data, remote_ip, remote_port = sys.waitUntil(task_name, 15000)
            
            if ret then
                -- 判断事件类型
                if data == "SEND_READY" and remote_ip == nil then
                    -- 发送就绪事件，已经在上面处理过队列了
                    log.info("udp_server", "发送就绪事件")
                    
                elseif data == "SOCKET_CLOSED" then
                    log.error("udp_server", "SOCKET_CLOSED")
                    goto UDP_EXCEPTION
                    
                elseif type(data) == "string" and remote_ip and remote_port then
                    -- 真实接收到的数据
                    log.info("udp_server", "收到数据，长度:", #data)
                    config.recv_bytes = config.recv_bytes + #data
                    
                    -- 记录客户端信息
                    client_info.ip = remote_ip
                    client_info.port = remote_port
                    config.client_count = 1
                    
                    local msg = string.format("来自 %s:%d - %s", remote_ip, remote_port, data)
                    add_log("UDP", "RECV", msg)
                    
                    -- 收到数据后再次处理发送队列（可能在等待期间有数据要发送）
                    udp_process_send_queue()
                else
                    log.warn("udp_server", "未知事件")
                end
            else
                -- 超时，发送心跳广播
                log.info("udp_server", "超时，发送心跳广播")
                udp_server:send("UDP Server Heartbeat", "255.255.255.255", 50000)
            end
        end
        
        ::UDP_EXCEPTION::
        
        -- 清空发送队列
        send_queues.udp = {}
        
        if udp_server then
            udp_server:close()
            udp_server = nil
        end
        
        config.running = false
        config.client_count = 0
        client_info = {}
        
        if not config.enabled or task_exit_flags.udp then
            log.info("udp_server", "服务器停止")
            break
        end
        
        sys.wait(5000)
        
        ::udp_continue::
    end
    
    log.info("udp_server", "任务退出")
end

-- ==================== UI构建函数 ====================

-- 创建Tab按钮
local function create_tab_button(parent, x, width, tab)
    local is_active = current_tab == tab.key
    local bg_color = is_active and 0xe94560 or 0x0f3460
    local text_color = is_active and 0xffffff or 0x888888
    
    local btn = airui.container({
        parent = parent,
        x = x,
        y = 5,
        w = width,
        h = 40,
        color = bg_color,
        radius = 6,
        on_click = function()
            if current_tab ~= tab.key then
                current_tab = tab.key
                refresh_tab_bar()
                refresh_content()
            end
        end
    })
    
    airui.label({
        parent = btn,
        x = 0,
        y = 8,
        w = width,
        h = 24,
        text = tab.name,
        font_size = 14,
        color = text_color,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    return btn
end

-- 刷新Tab导航栏
function refresh_tab_bar()
    if tab_bar_container then
        tab_bar_container:destroy()
        tab_bar_container = nil
    end

    tab_bar_container = airui.container({
        parent = main_container,
        x = 0,
        y = 60,
        w = 480,
        h = 50,
        color = 0x0f3460
    })

    local tab_width = 100
    local start_x = 20
    local gap = 10

    for i, tab in ipairs(TABS) do
        create_tab_button(tab_bar_container, start_x + (i-1) * (tab_width + gap), tab_width, tab)
    end
end

-- 创建仪表盘页面
local function create_dashboard_page()
    content_container = airui.container({
        parent = main_container,
        x = 0,
        y = 110,
        w = 480,
        h = 690,
        color = 0x16213e
    })

    -- 更新网卡信息
    update_netcard_info()

    -- 网卡状态卡片
    local netcard_card = airui.container({
        parent = content_container,
        x = 10,
        y = 10,
        w = 460,
        h = 100,
        color = 0x1a1a2e,
        radius = 10
    })

    airui.label({
        parent = netcard_card,
        x = 15,
        y = 10,
        w = 100,
        h = 20,
        text = "网卡信息",
        font_size = 14,
        color = 0xe94560
    })

    airui.label({
        parent = netcard_card,
        x = 15,
        y = 35,
        w = 200,
        h = 20,
        text = netcard_info.name,
        font_size = 16,
        color = 0xffffff
    })

    -- 显示IP地址
    airui.label({
        parent = netcard_card,
        x = 15,
        y = 58,
        w = 300,
        h = 18,
        text = "IP: " .. netcard_info.ip,
        font_size = 14,
        color = 0x00d26a
    })

    -- 连接状态
    local status_text = netcard_info.connected and "● 已连接" or "● 未连接"
    local status_color = netcard_info.connected and 0x00d26a or 0xff4757
    airui.label({
        parent = netcard_card,
        x = 350,
        y = 58,
        w = 100,
        h = 18,
        text = status_text,
        font_size = 12,
        color = status_color
    })

    -- 数据统计卡片
    local stats_card = airui.container({
        parent = content_container,
        x = 10,
        y = 120,
        w = 460,
        h = 140,
        color = 0x1a1a2e,
        radius = 10
    })

    airui.label({
        parent = stats_card,
        x = 15,
        y = 10,
        w = 100,
        h = 20,
        text = "数据统计",
        font_size = 14,
        color = 0xe94560
    })

    -- 统计项
    local total_send = 0
    local total_recv = 0
    for _, data in pairs(server_config) do
        total_send = total_send + data.send_bytes
        total_recv = total_recv + data.recv_bytes
    end

    local stats = {
        { label = "发送 (KB)", value = bytes_to_kb(total_send), x = 30 },
        { label = "接收 (KB)", value = bytes_to_kb(total_recv), x = 250 },
        { label = "重连次数", value = tostring(server_config.tcp.retry_count + server_config.udp.retry_count), x = 30, y = 80 },
        { label = "日志条数", value = tostring(#log_entries), x = 250, y = 80 }
    }

    for _, stat in ipairs(stats) do
        local y_pos = stat.y or 40
        
        airui.label({
            parent = stats_card,
            x = stat.x,
            y = y_pos,
            w = 100,
            h = 30,
            text = stat.value,
            font_size = 24,
            color = 0xe94560,
            align = airui.TEXT_ALIGN_CENTER
        })

        airui.label({
            parent = stats_card,
            x = stat.x,
            y = y_pos + 30,
            w = 100,
            h = 20,
            text = stat.label,
            font_size = 12,
            color = 0x888888,
            align = airui.TEXT_ALIGN_CENTER
        })
    end

    -- 连接状态卡片
    local conn_card = airui.container({
        parent = content_container,
        x = 10,
        y = 270,
        w = 460,
        h = 180,
        color = 0x1a1a2e,
        radius = 10
    })

    airui.label({
        parent = conn_card,
        x = 15,
        y = 10,
        w = 100,
        h = 20,
        text = "连接状态",
        font_size = 14,
        color = 0xe94560
    })

    local conn_types = {
        { key = "tcp", name = "TCP Server", color = 0x2196F3 },
        { key = "udp", name = "UDP Server", color = 0x9C27B0 }
    }

    for i, conn in ipairs(conn_types) do
        local config = server_config[conn.key]
        local y_pos = 40 + (i-1) * 70

        local conn_item = airui.container({
            parent = conn_card,
            x = 15,
            y = y_pos,
            w = 430,
            h = 60,
            color = 0x0f3460,
            radius = 8,
            on_click = function()
                selected_conn = conn.key
                current_tab = "detail"
                refresh_tab_bar()
                refresh_content()
            end
        })

        -- 类型指示点
        airui.container({
            parent = conn_item,
            x = 15,
            y = 20,
            w = 12,
            h = 12,
            color = conn.color,
            radius = 6
        })

        airui.label({
            parent = conn_item,
            x = 35,
            y = 10,
            w = 150,
            h = 20,
            text = conn.name,
            font_size = 16,
            color = 0xffffff
        })

        airui.label({
            parent = conn_item,
            x = 35,
            y = 32,
            w = 200,
            h = 18,
            text = config.ip .. ":" .. config.port,
            font_size = 12,
            color = 0x888888
        })

        -- 状态标签
        local status_color = config.running and 0x00d26a or 0xff4757
        local status_text = config.running and "运行中" or "已停止"
        
        airui.container({
            parent = conn_item,
            x = 350,
            y = 15,
            w = 70,
            h = 24,
            color = status_color,
            radius = 12
        })

        airui.label({
            parent = conn_item,
            x = 350,
            y = 18,
            w = 70,
            h = 18,
            text = status_text,
            font_size = 11,
            color = 0xffffff,
            align = airui.TEXT_ALIGN_CENTER
        })
    end
end

-- 创建详情页面
local function create_detail_page()
    content_container = airui.container({
        parent = main_container,
        x = 0,
        y = 110,
        w = 480,
        h = 690,
        color = 0x16213e
    })

    local config = server_config[selected_conn]
    local colors = { tcp = 0x2196F3, udp = 0x9C27B0 }

    -- 连接选择器
    for i, conn_type in ipairs({"tcp", "udp"}) do
        local btn_color = selected_conn == conn_type and 0xe94560 or 0x333333
        
        local btn = airui.container({
            parent = content_container,
            x = 15 + (i-1) * 110,
            y = 10,
            w = 100,
            h = 36,
            color = btn_color,
            radius = 18,
            on_click = function()
                selected_conn = conn_type
                refresh_content()
            end
        })

        airui.container({
            parent = btn,
            x = 12,
            y = 12,
            w = 8,
            h = 8,
            color = colors[conn_type],
            radius = 4
        })

        airui.label({
            parent = btn,
            x = 28,
            y = 8,
            w = 60,
            h = 20,
            text = conn_type:upper(),
            font_size = 13,
            color = 0xffffff
        })
    end

    -- 连接信息卡片
    local info_card = airui.container({
        parent = content_container,
        x = 10,
        y = 60,
        w = 460,
        h = 240,
        color = 0x1a1a2e,
        radius = 10
    })

    airui.label({
        parent = info_card,
        x = 15,
        y = 10,
        w = 100,
        h = 20,
        text = "连接信息",
        font_size = 14,
        color = 0xe94560
    })

    local info_items = {
        { "类型", config.type or (selected_conn:upper() .. " Server") },
        { "状态", config.running and "运行中" or "已停止" },
        { "监听地址", config.ip },
        { "监听端口", tostring(config.port) },
        { "已发送", bytes_to_kb(config.send_bytes) .. " KB" },
        { "已接收", bytes_to_kb(config.recv_bytes) .. " KB" },
        { "客户端数", tostring(config.client_count) }
    }

    for i, item in ipairs(info_items) do
        local y_pos = 40 + (i-1) * 28

        airui.label({
            parent = info_card,
            x = 20,
            y = y_pos,
            w = 100,
            h = 24,
            text = item[1],
            font_size = 13,
            color = 0x888888
        })

        airui.label({
            parent = info_card,
            x = 150,
            y = y_pos,
            w = 200,
            h = 24,
            text = item[2],
            font_size = 13,
            color = 0xffffff
        })
    end

    -- 发送区域
    local send_card = airui.container({
        parent = content_container,
        x = 10,
        y = 310,
        w = 460,
        h = 100,
        color = 0x1a1a2e,
        radius = 10
    })

    airui.label({
        parent = send_card,
        x = 15,
        y = 10,
        w = 100,
        h = 20,
        text = "发送数据",
        font_size = 14,
        color = 0xe94560
    })

    -- 输入框
    local input = airui.textarea({
        parent = send_card,
        x = 15,
        y = 40,
        w = 340,
        h = 40,
        text = "",
        font_size = 14,
        color = 0xffffff,
        bg_color = 0x0f3460,
        keyboard = text_keyboard
    })

    -- 发送按钮
    airui.container({
        parent = send_card,
        x = 365,
        y = 40,
        w = 80,
        h = 40,
        color = 0x00d26a,
        radius = 8,
        on_click = function()
            -- 安全获取输入文本
            local ok, data = pcall(function() return input:get_text() end)
            if not ok or not data then
                log.error("socket_server", "获取输入失败")
                return
            end
            
            data = tostring(data):match("^%s*(.-)%s*$")  -- 去除前后空格
            
            if #data == 0 then
                log.warn("socket_server", "输入为空，不发送")
                return
            end
            
            -- 根据选择的连接类型发送
            if selected_conn == "tcp" then
                -- TCP: 加入队列并唤醒任务（参考 demo tcp_server_sender）
                table.insert(send_queues.tcp, {data = data})
                -- 使用 sys.sendMsg 唤醒 TCP 任务
                sys.sendMsg("tcp_server_task", socket.EVENT, 0)
                log.info("socket_server", "TCP数据已加入队列并唤醒任务，长度:", #data)
            else
                -- UDP: 加入队列并唤醒任务（参考 demo udp_server_sender）
                table.insert(send_queues.udp, {data = data, ip = nil, port = nil})
                -- 使用 sys.publish 唤醒 UDP 任务
                sys.publish("udp_server_task", "SEND_READY", nil, nil)
                log.info("socket_server", "UDP数据已加入队列并唤醒任务，长度:", #data)
            end
            
            -- 更新统计和日志
            config.send_bytes = config.send_bytes + #data
            add_log(selected_conn:upper(), "SEND", data)
            input:set_text("")
        end
    })

    airui.label({
        parent = send_card,
        x = 365,
        y = 48,
        w = 80,
        h = 24,
        text = "发送",
        font_size = 14,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
end

-- 创建设置页面
local function create_settings_page()
    content_container = airui.container({
        parent = main_container,
        x = 0,
        y = 110,
        w = 480,
        h = 690,
        color = 0x16213e
    })

    local y_pos = 10

    for _, conn_type in ipairs({"tcp", "udp"}) do
        local config = server_config[conn_type]

        -- 设置组
        local group = airui.container({
            parent = content_container,
            x = 10,
            y = y_pos,
            w = 460,
            h = 160,
            color = 0x1a1a2e,
            radius = 10
        })

        airui.label({
            parent = group,
            x = 15,
            y = 10,
            w = 200,
            h = 20,
            text = conn_type:upper() .. "服务器设置",
            font_size = 14,
            color = 0xe94560
        })

        -- IP地址输入
        airui.label({
            parent = group,
            x = 20,
            y = 40,
            w = 100,
            h = 20,
            text = "监听地址",
            font_size = 12,
            color = 0x888888
        })

        settings_inputs[conn_type].ip = airui.textarea({
            parent = group,
            x = 20,
            y = 65,
            w = 420,
            h = 36,
            text = config.ip,
            font_size = 14,
            color = 0xffffff,
            bg_color = 0x0f3460,
            single_line = true,
            keyboard = text_keyboard
        })

        -- 端口输入
        airui.label({
            parent = group,
            x = 20,
            y = 105,
            w = 100,
            h = 20,
            text = "监听端口",
            font_size = 12,
            color = 0x888888
        })

        settings_inputs[conn_type].port = airui.textarea({
            parent = group,
            x = 20,
            y = 125,
            w = 420,
            h = 36,
            text = tostring(config.port),
            font_size = 14,
            color = 0xffffff,
            bg_color = 0x0f3460,
            single_line = true,
            keyboard = numeric_keyboard
        })

        y_pos = y_pos + 170
    end

    -- 保存按钮
    airui.container({
        parent = content_container,
        x = 10,
        y = y_pos,
        w = 460,
        h = 50,
        color = 0xe94560,
        radius = 10,
        on_click = function()
            -- 安全获取输入框文本的辅助函数
            local function safe_get_text(input_obj, default_value)
                if input_obj == nil then
                    return default_value
                end
                if input_obj.get_text == nil then
                    return default_value
                end
                local ok, result = pcall(function() return input_obj:get_text() end)
                if ok and result and #tostring(result) > 0 then
                    return tostring(result)
                end
                return default_value
            end
            
            -- 保存TCP设置
            local tcp_ip = safe_get_text(settings_inputs.tcp.ip, server_config.tcp.ip)
            local tcp_port = tonumber(safe_get_text(settings_inputs.tcp.port, tostring(server_config.tcp.port)))
            if tcp_ip and tcp_port then
                server_config.tcp.ip = tcp_ip
                server_config.tcp.port = tcp_port
            end
            
            -- 保存UDP设置
            local udp_ip = safe_get_text(settings_inputs.udp.ip, server_config.udp.ip)
            local udp_port = tonumber(safe_get_text(settings_inputs.udp.port, tostring(server_config.udp.port)))
            if udp_ip and udp_port then
                server_config.udp.ip = udp_ip
                server_config.udp.port = udp_port
            end
            
            add_log("SYS", "INFO", "设置已保存")
            log.info("socket_server", "设置已保存")
            
            -- 重启服务器使新设置生效
            add_log("SYS", "INFO", "正在重启服务器...")
            log.info("socket_server", "重启服务器以应用新设置")
            
            -- 停止服务器
            server_config.tcp.enabled = false
            server_config.udp.enabled = false
            
            -- 设置重启标志，让任务检测到后主动退出
            restart_flags.tcp = true
            restart_flags.udp = true
            
            -- 强制设置退出标志，让TCP任务立即退出（即使卡在libnet.listen）
            task_exit_flags.tcp = true
            task_exit_flags.udp = true
            
            -- 使用定时器延迟重新启用服务器（避免在回调中使用 sys.wait）
            sys.timerStart(function()
                -- 清除退出标志
                task_exit_flags.tcp = false
                task_exit_flags.udp = false
                restart_flags.tcp = false
                restart_flags.udp = false
                
                log.info("socket_server", "退出标志已清除，准备重启服务器...")
                log.info("socket_server", "task_exit_flags.tcp:", task_exit_flags.tcp)
                
                -- 重新启用服务器
                server_config.tcp.enabled = true
                server_config.udp.enabled = true
                
                -- 重新启动TCP/UDP任务
                log.info("socket_server", "重新启动TCP/UDP任务...")
                sys.taskInitEx(tcp_server_task, "tcp_server_task")
                sys.taskInitEx(udp_server_task, "udp_server_task")
                
                add_log("SYS", "INFO", "服务器已重启，TCP端口:" .. server_config.tcp.port .. " UDP端口:" .. server_config.udp.port)
                log.info("socket_server", "服务器重启完成，TCP端口:", server_config.tcp.port, "UDP端口:", server_config.udp.port)
            end, 3000)
        end
    })

    airui.label({
        parent = content_container,
        x = 10,
        y = y_pos + 15,
        w = 460,
        h = 20,
        text = "保存设置",
        font_size = 16,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
end

-- 创建日志页面
local function create_logs_page()
    content_container = airui.container({
        parent = main_container,
        x = 0,
        y = 110,
        w = 480,
        h = 690,
        color = 0x16213e
    })

    -- 工具栏
    local toolbar = airui.container({
        parent = content_container,
        x = 10,
        y = 10,
        w = 400,
        h = 40,
        color = 0x1a1a2e,
        radius = 6
    })

    airui.label({
        parent = toolbar,
        x = 15,
        y = 10,
        w = 150,
        h = 20,
        text = "共 " .. #log_entries .. " 条日志",
        font_size = 13,
        color = 0x888888
    })

    -- 清除按钮
    local clear_btn = airui.container({
        parent = toolbar,
        x = 300,
        y = 5,
        w = 85,
        h = 30,
        color = 0xff4757,
        radius = 6,
        on_click = function()
            log_entries = {}
            log_scroll_offset = 0
            refresh_content()
            log.info("socket_server", "日志已清除")
        end
    })

    airui.label({
        parent = clear_btn,
        x = 0,
        y = 6,
        w = 85,
        h = 18,
        text = "清除",
        font_size = 13,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 日志列表区域
    local log_list_panel = airui.container({
        parent = content_container,
        x = 10,
        y = 60,
        w = 400,
        h = 620,
        color = 0x0a0a0a,
        radius = 8
    })

    -- 计算滚动参数
    local total_logs = #log_entries
    local max_offset = math.max(0, total_logs - logs_per_page)
    log_scroll_offset = math.min(log_scroll_offset, max_offset)

    -- 如果没有日志，显示提示
    if total_logs == 0 then
        airui.label({
            parent = log_list_panel,
            x = 0,
            y = 280,
            w = 400,
            h = 30,
            text = "暂无日志数据",
            font_size = 16,
            color = 0x666666,
            align = airui.TEXT_ALIGN_CENTER
        })
    else
        local log_y = 10
        local start_idx = log_scroll_offset + 1
        local end_idx = math.min(start_idx + logs_per_page - 1, total_logs)

        for i = start_idx, end_idx do
            local entry = log_entries[i]
            if entry then
                local tag_colors = { TCP = 0xe94560, UDP = 0x7950f2, SYS = 0xffa502, SEND = 0x00d26a, RECV = 0x2196F3, CONN = 0x9C27B0, DISC = 0xff4757, INFO = 0x888888 }
                local tag_color = tag_colors[entry.tag] or 0x888888
                local type_color = tag_colors[entry.type] or 0x888888

                -- 时间
                airui.label({
                    parent = log_list_panel,
                    x = 10,
                    y = log_y,
                    w = 55,
                    h = 16,
                    text = entry.time,
                    font_size = 11,
                    color = 0x999999,
                    align = airui.TEXT_ALIGN_LEFT
                })

                -- 标签背景
                local tag_badge = airui.container({
                    parent = log_list_panel,
                    x = 70,
                    y = log_y,
                    w = 35,
                    h = 18,
                    color = tag_color,
                    radius = 2
                })

                airui.label({
                    parent = tag_badge,
                    x = 0,
                    y = 2,
                    w = 35,
                    h = 14,
                    text = entry.tag,
                    font_size = 10,
                    color = 0xffffff,
                    align = airui.TEXT_ALIGN_CENTER
                })

                -- 类型
                local type_badge = airui.container({
                    parent = log_list_panel,
                    x = 110,
                    y = log_y,
                    w = 40,
                    h = 18,
                    color = 0x1a1a2e,
                    radius = 2
                })

                airui.label({
                    parent = type_badge,
                    x = 0,
                    y = 2,
                    w = 40,
                    h = 14,
                    text = entry.type,
                    font_size = 10,
                    color = type_color,
                    align = airui.TEXT_ALIGN_CENTER
                })

                -- 内容
                local content_text = entry.content
                if #content_text > 35 then
                    content_text = string.sub(content_text, 1, 32) .. "..."
                end

                airui.label({
                    parent = log_list_panel,
                    x = 10,
                    y = log_y + 22,
                    w = 380,
                    h = 20,
                    text = content_text,
                    font_size = 12,
                    color = 0xcccccc,
                    align = airui.TEXT_ALIGN_LEFT
                })

                log_y = log_y + 70
            end
        end
    end

    -- 滑动条区域
    local scrollbar_bg = airui.container({
        parent = content_container,
        x = 420,
        y = 60,
        w = 50,
        h = 620,
        color = 0x1a1a2e,
        radius = 4
    })

    -- 向上滚动按钮
    local scroll_up_btn = airui.container({
        parent = scrollbar_bg,
        x = 5,
        y = 10,
        w = 40,
        h = 50,
        color = (total_logs > logs_per_page and log_scroll_offset > 0) and 0xe94560 or 0x333333,
        radius = 4,
        on_click = function()
            if log_scroll_offset > 0 then
                log_scroll_offset = log_scroll_offset - 1
                refresh_content()
            end
        end
    })

    airui.label({
        parent = scroll_up_btn,
        x = 0,
        y = 15,
        w = 40,
        h = 20,
        text = "▲",
        font_size = 16,
        color = (total_logs > logs_per_page and log_scroll_offset > 0) and 0xffffff or 0x666666,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 向下滚动按钮
    local scroll_down_btn = airui.container({
        parent = scrollbar_bg,
        x = 5,
        y = 560,
        w = 40,
        h = 50,
        color = (total_logs > logs_per_page and log_scroll_offset < max_offset) and 0xe94560 or 0x333333,
        radius = 4,
        on_click = function()
            if log_scroll_offset < max_offset then
                log_scroll_offset = log_scroll_offset + 1
                refresh_content()
            end
        end
    })

    airui.label({
        parent = scroll_down_btn,
        x = 0,
        y = 15,
        w = 40,
        h = 20,
        text = "▼",
        font_size = 16,
        color = (total_logs > logs_per_page and log_scroll_offset < max_offset) and 0xffffff or 0x666666,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 页码显示
    if total_logs > 0 then
        airui.label({
            parent = scrollbar_bg,
            x = 5,
            y = 295,
            w = 40,
            h = 30,
            text = tostring(log_scroll_offset + 1) .. "/" .. tostring(max_offset + 1),
            font_size = 12,
            color = 0x888888,
            align = airui.TEXT_ALIGN_CENTER
        })
    end
end

-- 刷新内容区域
function refresh_content()
    -- 先隐藏键盘，确保键盘不再引用输入框
    if text_keyboard then
        text_keyboard:hide()
    end
    if numeric_keyboard then
        numeric_keyboard:hide()
    end

    -- 清理设置页面的输入框引用
    settings_inputs.tcp.ip = nil
    settings_inputs.tcp.port = nil
    settings_inputs.udp.ip = nil
    settings_inputs.udp.port = nil

    -- 直接创建新页面
    if current_tab == "dashboard" then
        create_dashboard_page()
    elseif current_tab == "detail" then
        create_detail_page()
    elseif current_tab == "settings" then
        create_settings_page()
    elseif current_tab == "logs" then
        create_logs_page()
    end
end

-- ==================== exwin 窗口生命周期回调 ====================

-- 停止所有 Socket 服务器业务
local function stop_all_servers()
    log.info("socket_server", "停止所有服务器业务")
    
    -- 停止 TCP 服务器
    server_config.tcp.enabled = false
    server_config.tcp.running = false
    add_log("TCP", "INFO", "服务器已停止")
    
    -- 停止 UDP 服务器
    server_config.udp.enabled = false
    server_config.udp.running = false
    add_log("UDP", "INFO", "服务器已停止")
    
    -- 清空发送队列
    send_queues.tcp = {}
    send_queues.udp = {}
    
    log.info("socket_server", "所有服务器业务已停止")
end

-- 启动所有 Socket 服务器业务
local function start_all_servers()
    log.info("socket_server", "启动所有服务器业务")
    
    -- 启动 TCP 服务器
    server_config.tcp.enabled = true
    add_log("TCP", "INFO", "服务器已启用")
    
    -- 启动 UDP 服务器
    server_config.udp.enabled = true
    add_log("UDP", "INFO", "服务器已启用")
    
    log.info("socket_server", "所有服务器业务已启动")
end

-- 创建主UI
local function build_ui()
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = 0x16213e
    })

    -- 初始化键盘
    init_keyboards()

    -- 标题栏
    local header = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 480,
        h = 60,
        color = 0x0f3460
    })

    -- 返回按钮
    local back_btn = airui.container({
        parent = header,
        x = 10,
        y = 10,
        w = 50,
        h = 40,
        color = 0x333333,
        radius = 6,
        on_click = function()
            log.info("socket_server", "点击返回按钮")
            if win_id then
                exwin.close(win_id)
            end
        end
    })

    -- 返回箭头图标
    airui.label({
        parent = back_btn,
        x = 0,
        y = 5,
        w = 50,
        h = 30,
        text = "<",
        font_size = 24,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })

    airui.label({
        parent = header,
        x = 70,
        y = 15,
        w = 200,
        h = 30,
        text = "Socket Server",
        font_size = 24,
        color = 0xe94560,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 状态指示
    airui.container({
        parent = header,
        x = 420,
        y = 22,
        w = 8,
        h = 8,
        color = 0x00d26a,
        radius = 4
    })

    airui.label({
        parent = header,
        x = 435,
        y = 18,
        w = 60,
        h = 24,
        text = "运行中",
        font_size = 12,
        color = 0x00d26a
    })

    refresh_tab_bar()
    refresh_content()
end

-- 窗口创建回调
local function on_create()
    log.info("socket_server", "on_create 窗口创建")
    
    -- 重置退出标志
    task_exit_flags.tcp = false
    task_exit_flags.udp = false
    
    -- 重置服务器配置
    server_config.tcp.running = false
    server_config.tcp.enabled = true
    server_config.udp.running = false
    server_config.udp.enabled = true
    
    -- 构建UI
    build_ui()
    
    -- 启动服务器业务
    start_all_servers()
    
    -- 启动TCP/UDP任务
    log.info("socket_server", "准备启动TCP任务...")
    local tcp_task = sys.taskInitEx(tcp_server_task, "tcp_server_task")
    log.info("socket_server", "TCP任务启动结果:", tcp_task)
    
    log.info("socket_server", "准备启动UDP任务...")
    local udp_task = sys.taskInitEx(udp_server_task, "udp_server_task")
    log.info("socket_server", "UDP任务启动结果:", udp_task)
    
    -- 添加初始日志
    add_log("SYS", "INFO", "系统启动成功")
    add_log("TCP", "INFO", "TCP服务器配置完成")
    add_log("UDP", "INFO", "UDP服务器配置完成")
    
    log.info("socket_server", "on_create 完成，TCP/UDP任务已启动")
end

-- 窗口销毁回调
local function on_destroy()
    log.info("socket_server", "on_destroy 窗口销毁")

    -- 设置任务退出标志
    task_exit_flags.tcp = true
    task_exit_flags.udp = true
    log.info("socket_server", "设置任务退出标志")

    -- 停止服务器业务
    stop_all_servers()

    -- 清理日志数据
    for i = #log_entries, 1, -1 do
        log_entries[i] = nil
    end

    -- 清理设置页面的输入框引用
    settings_inputs.tcp.ip = nil
    settings_inputs.tcp.port = nil
    settings_inputs.udp.ip = nil
    settings_inputs.udp.port = nil

    -- 隐藏并销毁键盘
    if text_keyboard then
        text_keyboard:hide()
        text_keyboard:destroy()
        text_keyboard = nil
    end
    if numeric_keyboard then
        numeric_keyboard:hide()
        numeric_keyboard:destroy()
        numeric_keyboard = nil
    end

    -- 销毁主容器
    if main_container then
        main_container:destroy()
        main_container = nil
    end

    -- 清理引用
    win_id = nil
    tab_bar_container = nil
    content_container = nil

    -- 通知exapp应用已关闭
    log.info("socket_server", "调用 exapp.close()")
    if exapp and exapp.close then
        exapp.close()
    end

    log.info("socket_server", "on_destroy 完成")
end

-- 窗口获得焦点回调
local function on_get_focus()
    refresh_content()
end

-- 窗口失去焦点回调
local function on_lose_focus()
    -- 隐藏键盘
    if text_keyboard then
        text_keyboard:hide()
    end
    if numeric_keyboard then
        numeric_keyboard:hide()
    end
end

-- ==================== 模块接口 ====================

-- 订阅打开Socket Server页面的消息
local function open_handler()
    -- 使用 exwin.is_active 检查窗口是否真正激活
    if not exwin.is_active(win_id) then
        log.info("socket_server", "打开新窗口")
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus,
        })
        log.info("socket_server", "窗口打开，ID:", win_id)
    else
        log.info("socket_server", "窗口已激活，无需重复打开")
    end
end

-- 订阅打开窗口消息
sys.subscribe("OPEN_SOCKET_WIN", open_handler)

log.info("socket_server", "模块加载完成，等待 OPEN_SOCKET_WIN 事件")

-- 模块导出接口
local socket_server_win = {}

function socket_server_win.open()
    open_handler()
end

function socket_server_win.close()
    if win_id then
        exwin.close(win_id)
    end
end

function socket_server_win.is_open()
    return exwin.is_active(win_id)
end

return socket_server_win
