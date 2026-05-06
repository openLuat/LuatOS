--[[
@module  socket_win
@summary Socket管理页面模块
@version 3.5
@date    2026.04.09
@author  LuatOS
@usage
整合socket_app.lua和socket_win.lua为一个文件，支持TCP/UDP/SSL连接管理。
重构为exwin窗口生命周期管理模式，参考airplane_battle架构。
]]

-- ==================== 窗口级资源句柄 ====================
-- win_id 用于主动关闭窗口，main_container 是挂在 airui.screen 下的根容器
local win_id = nil
local main_container = nil
local content_container = nil
local tab_bar_container = nil

-- ==================== 加载依赖模块 ====================
local exwin = require "exwin"
local libnet = require "libnet"

-- ==================== 运行时状态 ====================
local current_tab = "dashboard"
local selected_conn = "tcp"

-- Socket配置
local socket_config = {
    tcp = {
        enabled = true,
        server = "115.120.239.161",
        port = 24862,
        connected = false,
        send_bytes = 0,
        recv_bytes = 0,
        retry_count = 0
    },
    udp = {
        enabled = true,
        server = "115.120.239.161",
        port = 25975,
        connected = false,
        send_bytes = 0,
        recv_bytes = 0,
        retry_count = 0
    },
    ssl = {
        enabled = true,
        server = "115.120.239.161",
        port = 22214,
        connected = false,
        send_bytes = 0,
        recv_bytes = 0,
        retry_count = 0
    }
}

-- Socket客户端对象
local socket_clients = {}

-- 发送队列
local send_queues = {
    tcp = {},
    udp = {},
    ssl = {}
}

-- 接收缓冲区
local recv_buffs = {
    tcp = nil,
    udp = nil,
    ssl = nil
}

-- 任务名称
local TASK_NAMES = {
    tcp = "tcp_socket_task",
    udp = "udp_socket_task",
    ssl = "ssl_socket_task"
}

-- 任务句柄（用于关闭任务）
local task_handles = {
    tcp = nil,
    udp = nil,
    ssl = nil
}

-- 任务退出标志（用于优雅地停止任务）
local task_exit_flags = {
    tcp = false,
    udp = false,
    ssl = false
}

-- Socket连接状态（UI显示用）
local socket_status = {}

-- 日志数据（最多保存200条）
local log_entries = {}
local max_logs = 200
local log_scroll_offset = 0
local logs_per_page = 6

-- 网卡信息
local netcard_info = {
    name = "WiFi 网卡",
    connected = true
}

-- 设置参数
local settings_data = {
    tcp = { server = "115.120.239.161", port = "24862", enabled = true },
    udp = { server = "115.120.239.161", port = "25975", enabled = true },
    ssl = { server = "115.120.239.161", port = "22214", enabled = true }
}

-- Tab配置
local TABS = {
    { key = "dashboard", name = "仪表盘", icon = "D" },
    { key = "detail",    name = "详情",   icon = "I" },
    { key = "settings",  name = "设置",   icon = "S" },
    { key = "logs",      name = "日志",   icon = "L" }
}

-- 连接类型配置
local CONN_TYPES = {
    { key = "tcp", name = "TCP", icon = "T", color = 0x2196F3 },
    { key = "udp", name = "UDP", icon = "U", color = 0x9C27B0 },
    { key = "ssl", name = "SSL", icon = "S", color = 0x4CAF50 }
}

-- 键盘对象
local text_keyboard = nil
local numeric_keyboard = nil

-- 刷新控制标志
local refresh_in_progress = false
local send_in_progress = false
local refresh_pending = false
local last_refresh_time = 0
local refresh_interval = 500

-- ==================== 基础工具函数 ====================

-- 发布Socket状态更新事件
local function publish_status_update(conn_type)
    local config = socket_config[conn_type]
    sys.publish("SOCKET_STATUS_UPDATE", conn_type, {
        connected = config.connected,
        server = config.server,
        port = config.port,
        send = config.send_bytes,
        recv = config.recv_bytes,
        retry = config.retry_count
    })
end

-- 添加日志
local function add_log(conn_type, log_type, content)
    if type(content) ~= "string" then
        content = tostring(content) or ""
    end
    if #content > 50 then
        content = string.sub(content, 1, 50) .. "..."
    end
    sys.publish("SOCKET_LOG_ADD", conn_type, log_type, content)
end

-- 更新Socket配置
local function set_socket_config(conn_type, config)
    if not socket_config[conn_type] then
        log.error("socket_app", "set_config", conn_type, "not found")
        return
    end

    local old_server = socket_config[conn_type].server
    local old_port = socket_config[conn_type].port
    local server_changed = config.server and config.server ~= old_server
    local port_changed = config.port and config.port ~= old_port
    local need_reconnect = server_changed or port_changed

    for k, v in pairs(config) do
        if v ~= nil then
            socket_config[conn_type][k] = v
        end
    end

    if socket_config[conn_type].enabled == nil then
        socket_config[conn_type].enabled = true
    end

    publish_status_update(conn_type)

    if config.enabled == false and socket_clients[conn_type] then
        sys.publish("SOCKET_CLOSE_" .. string.upper(conn_type))
    end

    if need_reconnect then
        if socket_clients[conn_type] then
            sys.publish("SOCKET_CLOSE_" .. string.upper(conn_type))
        end
        sys.taskInit(function()
            sys.wait(500)
            sys.publish("SOCKET_RECONNECT_" .. string.upper(conn_type))
        end)
    elseif config.enabled == true and not socket_clients[conn_type] then
        sys.publish("SOCKET_RECONNECT_" .. string.upper(conn_type))
    end
end

-- 清空发送队列
local function clear_send_queue(conn_type)
    send_queues[conn_type] = {}
end

-- 发送数据处理
local function process_send_queue(conn_type, task_name, socket_client)
    local send_queue = send_queues[conn_type]
    local config = socket_config[conn_type]
    local max_retry = 3
    local retry_count = 0

    while #send_queue > 0 do
        local item = table.remove(send_queue, 1)
        local ok, result, buff_full = pcall(libnet.tx, task_name, 5000, socket_client, item.data)

        if not ok then
            log.error(task_name, "libnet.tx error:", result)
            add_log(conn_type, "ERROR", "发送调用失败")
            return false
        end

        if not result then
            log.error(task_name, "libnet.tx failed")
            add_log(conn_type, "ERROR", "发送失败")
            return false
        end

        if buff_full then
            retry_count = retry_count + 1
            if retry_count > max_retry then
                log.error(task_name, "buffer full max retry")
                add_log(conn_type, "ERROR", "发送缓冲区满")
                return false
            end
            table.insert(send_queue, item)
            sys.wait(50)
            return true
        end

        config.send_bytes = config.send_bytes + #item.data
        publish_status_update(conn_type)
        retry_count = 0
    end

    return true
end

-- 接收数据处理
local function process_recv_data(conn_type, socket_client)
    local config = socket_config[conn_type]
    local TASK_NAME = TASK_NAMES[conn_type]

    if not recv_buffs[conn_type] then
        recv_buffs[conn_type] = zbuff.create(1024, 0, zbuff.HEAP_SRAM)
    end
    local recv_buff = recv_buffs[conn_type]

    local success = true
    local max_reads = 10
    local read_count = 0

    while read_count < max_reads do
        read_count = read_count + 1
        recv_buff:del()
        local result = socket.rx(socket_client, recv_buff)

        if not result then
            log.error(TASK_NAME, "socket.rx error")
            success = false
            break
        end

        if recv_buff:used() > 0 then
            local data_len = recv_buff:used()
            config.recv_bytes = config.recv_bytes + data_len
            publish_status_update(conn_type)

            local display_len = math.min(data_len, 50)
            local data_str = recv_buff:query(0, display_len)
            if data_str and #data_str > 0 then
                data_str = "" .. data_str
                add_log(conn_type, "RECV", data_str)
                sys.publish("SOCKET_DATA_RECEIVED", conn_type, data_str)
            end
        else
            break
        end

        sys.wait(1)
    end

    return success
end

-- 发送数据（供外部调用）
local function send_socket_data(conn_type, data, tag)
    tag = tag or "app"
    local config = socket_config[conn_type]

    if not config then
        log.error("socket_app", "send_data: invalid conn_type:", conn_type)
        return false
    end

    if config.enabled == false then
        log.warn("socket_app", "send_data:", conn_type, "not enabled")
        return false
    end

    if not config.connected then
        log.warn("socket_app", "send_data:", conn_type, "not connected")
        return false
    end

    if not socket_clients[conn_type] then
        log.warn("socket_app", "send_data:", conn_type, "socket not ready")
        return false
    end

    if #send_queues[conn_type] >= 10 then
        log.warn("socket_app", conn_type, "send queue full")
        add_log(conn_type, "WARN", "发送队列已满")
        return false
    end

    table.insert(send_queues[conn_type], {
        data = "send from " .. tag .. ": " .. data,
        timestamp = os.time()
    })

    sys.sendMsg(TASK_NAMES[conn_type], socket.EVENT, 0)
    add_log(conn_type, "SEND", data)

    return true
end

-- 获取所有Socket状态
local function get_all_socket_status()
    local status = {}
    for conn_type, config in pairs(socket_config) do
        status[conn_type] = {
            connected = config.connected,
            server = config.server,
            port = config.port,
            send = config.send_bytes,
            recv = config.recv_bytes,
            retry = config.retry_count
        }
    end
    return status
end

-- ==================== Socket任务函数 ====================

-- TCP Socket任务
local function tcp_socket_task_func()
    local conn_type = "tcp"
    local config = socket_config[conn_type]
    local TASK_NAME = TASK_NAMES[conn_type]
    local socket_client
    local result, para1, para2

    while not task_exit_flags[conn_type] do
        if config.enabled == false then
            sys.waitUntil({"SOCKET_RECONNECT_TCP", "SOCKET_EXIT_TCP"}, 5000)
            if task_exit_flags[conn_type] then break end
            goto CONTINUE
        end

        if config.enabled == nil then
            config.enabled = true
        end

        while not socket.adapter(socket.dft()) do
            sys.waitUntil({"IP_READY", "SOCKET_EXIT_TCP"}, 1000)
            if task_exit_flags[conn_type] then break end
        end
        if task_exit_flags[conn_type] then break end

        log.info(TASK_NAME, "connecting to", config.server, config.port)

        socket_client = socket.create(nil, TASK_NAME)
        if not socket_client then
            log.error(TASK_NAME, "socket.create error")
            goto EXCEPTION_PROC
        end

        if not socket.config(socket_client, nil, nil, nil, 300, 10, 3) then
            log.error(TASK_NAME, "socket.config error")
            goto EXCEPTION_PROC
        end

        if not libnet.connect(TASK_NAME, 30000, socket_client, config.server, config.port) then
            log.error(TASK_NAME, "libnet.connect error")
            config.retry_count = config.retry_count + 1
            add_log(conn_type, "ERROR", "连接失败，重试: " .. config.retry_count)
            goto EXCEPTION_PROC
        end

        log.info(TASK_NAME, "connected")
        config.connected = true
        socket_clients[conn_type] = socket_client
        publish_status_update(conn_type)
        add_log(conn_type, "INFO", "连接成功")

        while not task_exit_flags[conn_type] do
            if not process_recv_data(conn_type, socket_client) then
                log.error(TASK_NAME, "recv error")
                break
            end

            if not process_send_queue(conn_type, TASK_NAME, socket_client) then
                log.error(TASK_NAME, "send error")
                break
            end

            result, para1, para2 = libnet.wait(TASK_NAME, 15000, socket_client)

            if not result then
                log.warn(TASK_NAME, "connection exception")
                break
            end
        end

        ::EXCEPTION_PROC::
        config.connected = false
        socket_clients[conn_type] = nil
        publish_status_update(conn_type)
        add_log(conn_type, "INFO", "连接断开")

        clear_send_queue(conn_type)

        if socket_client then
            libnet.close(TASK_NAME, 5000, socket_client)
            socket.release(socket_client)
            socket_client = nil
        end

        if task_exit_flags[conn_type] then break end

        if config.enabled then
            sys.wait(5000)
        end

        ::CONTINUE::
    end
    
    -- 任务退出时清理句柄
    task_handles[conn_type] = nil
    log.info(TASK_NAME, "任务已退出")
end

-- UDP Socket任务
local function udp_socket_task_func()
    local conn_type = "udp"
    local config = socket_config[conn_type]
    local TASK_NAME = TASK_NAMES[conn_type]
    local socket_client
    local result, para1, para2
    local ok, tx_result

    local need_break = false
    local close_flag = { false }
    local reconnect_flag = { false }

    local function on_socket_close()
        return function()
            close_flag[1] = true
        end
    end

    local function on_socket_reconnect()
        return function()
            reconnect_flag[1] = true
        end
    end

    while not task_exit_flags[conn_type] do
        close_flag[1] = false
        reconnect_flag[1] = false

        if config.enabled == false then
            sys.waitUntil({"SOCKET_RECONNECT_UDP", "SOCKET_EXIT_UDP"}, 5000)
            if task_exit_flags[conn_type] then break end
            goto CONTINUE
        end

        if config.enabled == nil then
            config.enabled = true
        end

        while not socket.adapter(socket.dft()) do
            sys.waitUntil({"IP_READY", "SOCKET_EXIT_UDP"}, 1000)
            if task_exit_flags[conn_type] then break end
        end
        if task_exit_flags[conn_type] then break end

        log.info(TASK_NAME, "connecting to", config.server, config.port)

        socket_client = socket.create(nil, TASK_NAME)
        if not socket_client then
            log.error(TASK_NAME, "socket.create error")
            goto EXCEPTION_PROC
        end

        if not socket.config(socket_client, nil, true) then
            log.error(TASK_NAME, "socket.config error")
            goto EXCEPTION_PROC
        end

        if not libnet.connect(TASK_NAME, 30000, socket_client, config.server, config.port) then
            log.error(TASK_NAME, "libnet.connect error")
            config.retry_count = config.retry_count + 1
            goto EXCEPTION_PROC
        end

        log.info(TASK_NAME, "connected")
        config.connected = true
        socket_clients[conn_type] = socket_client
        publish_status_update(conn_type)
        add_log(conn_type, "INFO", "连接成功")

        ok, tx_result = pcall(libnet.tx, TASK_NAME, 5000, socket_client, "UDP_HEARTBEAT")
        if ok and tx_result then
            config.send_bytes = config.send_bytes + 13
            publish_status_update(conn_type)
        end

        if not _G["SOCKET_SUBSCRIBED_" .. string.upper(conn_type)] then
            sys.subscribe("SOCKET_CLOSE_" .. string.upper(conn_type), on_socket_close())
            sys.subscribe("SOCKET_RECONNECT_" .. string.upper(conn_type), on_socket_reconnect())
            _G["SOCKET_SUBSCRIBED_" .. string.upper(conn_type)] = true
        end
        
        need_break = false
        while not need_break and not task_exit_flags[conn_type] do
            if close_flag[1] then
                close_flag[1] = false
                need_break = true
            elseif reconnect_flag[1] then
                reconnect_flag[1] = false
                need_break = true
            elseif not process_recv_data(conn_type, socket_client) then
                log.error(TASK_NAME, "recv error")
                need_break = true
            elseif not process_send_queue(conn_type, TASK_NAME, socket_client) then
                log.error(TASK_NAME, "send error")
                need_break = true
            else
                result, para1, para2 = libnet.wait(TASK_NAME, 1000, socket_client)
                if not result then
                    need_break = true
                end
            end
        end

        ::EXCEPTION_PROC::
        config.connected = false
        socket_clients[conn_type] = nil
        publish_status_update(conn_type)
        add_log(conn_type, "INFO", "连接断开")

        clear_send_queue(conn_type)

        if socket_client then
            libnet.close(TASK_NAME, 5000, socket_client)
            socket.release(socket_client)
            socket_client = nil
        end

        if task_exit_flags[conn_type] then break end

        if socket_config[conn_type].enabled then
            sys.wait(5000)
        end

        ::CONTINUE::
    end
    
    -- 任务退出时清理句柄
    task_handles[conn_type] = nil
    log.info(TASK_NAME, "任务已退出")
end

-- SSL Socket任务
local function ssl_socket_task_func()
    local conn_type = "ssl"
    local config = socket_config[conn_type]
    local TASK_NAME = TASK_NAMES[conn_type]
    local socket_client
    local result, para1, para2

    while not task_exit_flags[conn_type] do
        if config.enabled == false then
            sys.waitUntil({"SOCKET_RECONNECT_SSL", "SOCKET_EXIT_SSL"}, 5000)
            if task_exit_flags[conn_type] then break end
            goto CONTINUE
        end

        if config.enabled == nil then
            config.enabled = true
        end

        while not socket.adapter(socket.dft()) do
            sys.waitUntil({"IP_READY", "SOCKET_EXIT_SSL"}, 1000)
            if task_exit_flags[conn_type] then break end
        end
        if task_exit_flags[conn_type] then break end

        log.info(TASK_NAME, "connecting to", config.server, config.port)

        socket_client = socket.create(nil, TASK_NAME)
        if not socket_client then
            log.error(TASK_NAME, "socket.create error")
            goto EXCEPTION_PROC
        end

        if not socket.config(socket_client, nil, nil, true, 300, 10, 3) then
            log.error(TASK_NAME, "socket.config error")
            goto EXCEPTION_PROC
        end

        if not libnet.connect(TASK_NAME, 30000, socket_client, config.server, config.port) then
            log.error(TASK_NAME, "libnet.connect error")
            config.retry_count = config.retry_count + 1
            add_log(conn_type, "ERROR", "SSL连接失败，重试: " .. config.retry_count)
            goto EXCEPTION_PROC
        end

        log.info(TASK_NAME, "connected")
        config.connected = true
        socket_clients[conn_type] = socket_client
        publish_status_update(conn_type)
        add_log(conn_type, "INFO", "SSL连接成功")

        while not task_exit_flags[conn_type] do
            if not process_recv_data(conn_type, socket_client) then
                log.error(TASK_NAME, "recv error")
                break
            end

            if not process_send_queue(conn_type, TASK_NAME, socket_client) then
                log.error(TASK_NAME, "send error")
                break
            end

            result, para1, para2 = libnet.wait(TASK_NAME, 15000, socket_client)

            if not result then
                log.warn(TASK_NAME, "connection exception")
                break
            end
        end

        ::EXCEPTION_PROC::
        config.connected = false
        socket_clients[conn_type] = nil
        publish_status_update(conn_type)
        add_log(conn_type, "INFO", "SSL连接断开")

        clear_send_queue(conn_type)

        if socket_client then
            libnet.close(TASK_NAME, 5000, socket_client)
            socket.release(socket_client)
            socket_client = nil
        end

        if task_exit_flags[conn_type] then break end

        if config.enabled then
            sys.wait(5000)
        end

        ::CONTINUE::
    end
    
    -- 任务退出时清理句柄
    task_handles[conn_type] = nil
    log.info(TASK_NAME, "任务已退出")
end

-- ==================== UI工具函数 ====================

-- 初始化键盘
local function init_keyboards()
    log.info("init_keyboards","初始化键盘")
    text_keyboard = airui.keyboard({
        mode = "text",
        auto_hide = true,
        preview = true,
        preview_height = 40,
        w = 480,
        h = 200,
        on_commit = function(self)
            log.info("socket_win", "text keyboard commit")
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
            log.info("socket_win", "numeric keyboard commit")
            self:hide()
        end
    })
end

-- 更新Socket状态
local function update_socket_status()
    socket_status = get_all_socket_status()
end

-- 添加日志条目
local function add_log_entry(tag, log_type, content)
    local safe_content = content
    if type(content) == "string" and #content > 100 then
        safe_content = string.sub(content, 1, 97) .. "..."
    elseif type(content) ~= "string" then
        safe_content = tostring(content or "")
    end

    local t = os.time()
    local dt = os.date("*t", t)
    local time_str = string.format("%02d:%02d:%02d", dt.hour, dt.min, dt.sec)
    table.insert(log_entries, 1, {
        time = time_str,
        tag = tag,
        type = log_type,
        content = safe_content
    })
    while #log_entries > max_logs do
        table.remove(log_entries)
    end
    log_scroll_offset = 0
end

-- 处理Socket状态更新事件
local function on_socket_status_update(conn_type, status)
    socket_status[conn_type] = status

    local current_time = os.time() * 1000 + (os.clock() * 1000 % 1000)
    local need_refresh = false

    if current_tab == "detail" and selected_conn == conn_type then
        need_refresh = true
    elseif current_tab == "dashboard" then
        need_refresh = true
    end

    if need_refresh and (current_time - last_refresh_time > refresh_interval) then
        last_refresh_time = current_time
        sys.taskInit(function()
            sys.wait(100)
            if current_tab == "detail" and selected_conn == conn_type then
                refresh_content()
            elseif current_tab == "dashboard" then
                refresh_content()
            end
        end)
    end
end

-- 处理Socket日志添加事件
local function on_socket_log_add(conn_type, log_type, content)
    add_log_entry(conn_type, log_type, content)
    if current_tab == "logs" and not refresh_in_progress then
        sys.taskInit(function()
            sys.wait(50)
            if current_tab == "logs" then
                refresh_in_progress = true
                refresh_content()
                refresh_in_progress = false
            end
        end)
    end
end

-- 处理详情页面刷新请求
local function on_socket_detail_refresh()
    if refresh_pending then
        return
    end
    refresh_pending = true
    sys.taskInit(function()
        sys.wait(50)
        if current_tab == "detail" and not refresh_in_progress then
            refresh_in_progress = true
            refresh_content()
            refresh_in_progress = false
        end
        refresh_pending = false
    end)
end

-- 创建Tab按钮
local function create_tab_button(parent, x, w, tab_config)
    local is_active = (current_tab == tab_config.key)
    local btn = airui.container({
        parent = parent,
        x = x,
        y = 5,
        w = w,
        h = 40,
        color = is_active and 0xE94560 or 0x5C6BC0,
        radius = 4,
        on_click = function()
            if current_tab ~= tab_config.key then
                current_tab = tab_config.key
                sys.taskInit(function()
                    sys.wait(50)
                    refresh_content()
                    refresh_tab_bar()
                end)
            end
        end
    })

    airui.label({
        parent = btn,
        x = 0,
        y = 10,
        w = w,
        h = 20,
        text = tab_config.icon .. " " .. tab_config.name,
        font_size = 14,
        color = 0xffffff,
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
        color = 0x3F51B5
    })

    local tab_width = 100
    local start_x = 20
    local gap = 10

    for i, tab in ipairs(TABS) do
        create_tab_button(tab_bar_container, start_x + (i-1) * (tab_width + gap), tab_width, tab)
    end
end

-- ==================== 页面创建函数 ====================

-- 创建仪表盘页面
local function create_dashboard_page()
    content_container = airui.container({
        parent = main_container,
        x = 0,
        y = 110,
        w = 480,
        h = 690,
        color = 0xF3F4F6
    })

    -- 网卡状态卡片
    local netcard_card = airui.container({
        parent = content_container,
        x = 10,
        y = 10,
        w = 460,
        h = 80,
        color = 0xffffff,
        radius = 8
    })

    airui.label({
        parent = netcard_card,
        x = 15,
        y = 10,
        w = 100,
        h = 20,
        text = "当前网卡",
        font_size = 14,
        color = 0x666666,
        align = airui.TEXT_ALIGN_LEFT
    })

    airui.label({
        parent = netcard_card,
        x = 15,
        y = 35,
        w = 200,
        h = 30,
        text = "📱 " .. netcard_info.name,
        font_size = 20,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    airui.container({
        parent = netcard_card,
        x = 380,
        y = 25,
        w = 12,
        h = 12,
        color = 0x00D26A,
        radius = 6
    })

    airui.label({
        parent = netcard_card,
        x = 400,
        y = 22,
        w = 50,
        h = 20,
        text = "已连接",
        font_size = 14,
        color = 0x00D26A,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 统计数据
    local total_send = 0
    local total_recv = 0
    local total_retry = 0
    for _, status in pairs(socket_status) do
        total_send = total_send + (status.send or 0)
        total_recv = total_recv + (status.recv or 0)
        total_retry = total_retry + (status.retry or 0)
    end

    local stats = {
        { label = "发送", value = string.format("%.1fK", total_send / 1024) },
        { label = "接收", value = string.format("%.1fK", total_recv / 1024) },
        { label = "重连", value = tostring(total_retry) },
        { label = "日志", value = tostring(#log_entries) }
    }

    airui.label({
        parent = content_container,
        x = 10,
        y = 105,
        w = 200,
        h = 20,
        text = "数据统计",
        font_size = 14,
        color = 0x666666,
        align = airui.TEXT_ALIGN_LEFT
    })

    local stats_container = airui.container({
        parent = content_container,
        x = 10,
        y = 130,
        w = 460,
        h = 80,
        color = 0xffffff,
        radius = 8
    })

    for i, stat in ipairs(stats) do
        local stat_x = 10 + (i-1) * 115
        local stat_card = airui.container({
            parent = stats_container,
            x = stat_x,
            y = 10,
            w = 100,
            h = 60,
            color = 0xFFEBEE,
            radius = 4
        })

        airui.label({
            parent = stat_card,
            x = 0,
            y = 8,
            w = 100,
            h = 28,
            text = stat.value,
            font_size = 22,
            color = 0xE94560,
            align = airui.TEXT_ALIGN_CENTER
        })

        airui.label({
            parent = stat_card,
            x = 0,
            y = 38,
            w = 100,
            h = 18,
            text = stat.label,
            font_size = 12,
            color = 0x666666,
            align = airui.TEXT_ALIGN_CENTER
        })
    end

    -- 连接状态卡片
    airui.label({
        parent = content_container,
        x = 10,
        y = 225,
        w = 200,
        h = 20,
        text = "连接状态",
        font_size = 14,
        color = 0x666666,
        align = airui.TEXT_ALIGN_LEFT
    })

    local conn_container = airui.container({
        parent = content_container,
        x = 10,
        y = 250,
        w = 460,
        h = 320,
        color = 0xffffff,
        radius = 8
    })

    for i, conn in ipairs(CONN_TYPES) do
        local row = math.floor((i-1) / 2)
        local col = (i-1) % 2
        local card_x = 10 + col * 225
        local card_y = 10 + row * 155

        local status = socket_status[conn.key] or {}
        local is_connected = status.connected or false
        local status_color = is_connected and 0x00D26A or (conn.key == "ssl" and 0xFFA502 or 0xFF4757)
        local status_text = is_connected and "已连接" or (conn.key == "ssl" and "连接中" or "未连接")

        local conn_card = airui.container({
            parent = conn_container,
            x = card_x,
            y = card_y,
            w = 215,
            h = 145,
            color = 0xF5F5F5,
            radius = 6,
            on_click = function()
                selected_conn = conn.key
                current_tab = "detail"
                sys.taskInit(function()
                    sys.wait(50)
                    refresh_content()
                    refresh_tab_bar()
                end)
            end
        })

        airui.container({
            parent = conn_card,
            x = 0,
            y = 0,
            w = 6,
            h = 145,
            color = status_color,
            radius = 3
        })

        airui.label({
            parent = conn_card,
            x = 15,
            y = 10,
            w = 80,
            h = 24,
            text = conn.name,
            font_size = 18,
            color = 0x333333,
            align = airui.TEXT_ALIGN_LEFT
        })

        local status_badge = airui.container({
            parent = conn_card,
            x = 120,
            y = 10,
            w = 80,
            h = 24,
            color = is_connected and 0xE8F5E9 or 0xFFEBEE,
            radius = 12
        })

        airui.label({
            parent = status_badge,
            x = 0,
            y = 4,
            w = 80,
            h = 16,
            text = status_text,
            font_size = 12,
            color = status_color,
            align = airui.TEXT_ALIGN_CENTER
        })

        local server_text = (status.server or "--") .. ":" .. (status.port or "--")
        airui.label({
            parent = conn_card,
            x = 15,
            y = 45,
            w = 190,
            h = 18,
            text = server_text,
            font_size = 13,
            color = 0x666666,
            align = airui.TEXT_ALIGN_LEFT
        })

        local bottom_text
        if is_connected then
            bottom_text = "↑" .. string.format("%.1fK", (status.send or 0) / 1024) .. " ↓" .. string.format("%.1fK", (status.recv or 0) / 1024)
        else
            bottom_text = "重连:" .. (status.retry or 0) .. "次"
        end

        airui.label({
            parent = conn_card,
            x = 15,
            y = 75,
            w = 180,
            h = 18,
            text = bottom_text,
            font_size = 13,
            color = 0x999999,
            align = airui.TEXT_ALIGN_LEFT
        })

        local detail_btn = airui.container({
            parent = conn_card,
            x = 15,
            y = 105,
            w = 185,
            h = 30,
            color = 0xE94560,
            radius = 4
        })

        airui.label({
            parent = detail_btn,
            x = 0,
            y = 6,
            w = 185,
            h = 18,
            text = "查看详情",
            font_size = 13,
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
        color = 0xF3F4F6
    })

    -- 连接选择器
    local conn_selector = airui.container({
        parent = content_container,
        x = 10,
        y = 10,
        w = 460,
        h = 60,
        color = 0xffffff,
        radius = 8
    })

    local btn_width = (460 - 40) / 3
    for i, conn in ipairs(CONN_TYPES) do
        local status = socket_status[conn.key] or {}
        local is_connected = status.connected or false
        local status_color = is_connected and 0x00D26A or (conn.key == "ssl" and 0xFFA502 or 0xFF4757)
        local is_selected = (selected_conn == conn.key)

        local btn = airui.container({
            parent = conn_selector,
            x = 10 + (i-1) * (btn_width + 10),
            y = 10,
            w = btn_width,
            h = 40,
            color = is_selected and 0xE94560 or 0xF5F5F5,
            radius = 4,
            on_click = function()
                if selected_conn ~= conn.key then
                    selected_conn = conn.key
                    sys.taskInit(function()
                        sys.wait(100)
                        refresh_content()
                    end)
                end
            end
        })

        airui.container({
            parent = btn,
            x = 10,
            y = 16,
            w = 8,
            h = 8,
            color = status_color,
            radius = 4
        })

        airui.label({
            parent = btn,
            x = 22,
            y = 10,
            w = btn_width - 30,
            h = 20,
            text = conn.name,
            font_size = 15,
            color = is_selected and 0xffffff or 0x333333,
            align = airui.TEXT_ALIGN_CENTER
        })
    end

    -- 信息面板
    local info_panel = airui.container({
        parent = content_container,
        x = 10,
        y = 80,
        w = 460,
        h = 200,
        color = 0xffffff,
        radius = 8
    })

    airui.label({
        parent = info_panel,
        x = 15,
        y = 10,
        w = 200,
        h = 20,
        text = "连接信息",
        font_size = 16,
        color = 0xE94560,
        align = airui.TEXT_ALIGN_LEFT
    })

    local status = socket_status[selected_conn] or {}
    local is_connected = status.connected or false
    local status_color = is_connected and 0x00D26A or 0xFF4757
    local status_text = is_connected and "已连接" or "未连接"

    local info_items = {
        { label = "类型",   value = string.upper(selected_conn) .. " Client" },
        { label = "状态",   value = status_text, value_color = status_color },
        { label = "服务器", value = status.server or "--" },
        { label = "端口",   value = tostring(status.port or "--") },
        { label = "发送",   value = string.format("%.2f KB", (status.send or 0) / 1024) },
        { label = "接收",   value = string.format("%.2f KB", (status.recv or 0) / 1024) }
    }

    for i, item in ipairs(info_items) do
        local row = math.floor((i-1) / 2)
        local col = (i-1) % 2
        local x_pos = 15 + col * 220
        local y_pos = 45 + row * 45

        airui.label({
            parent = info_panel,
            x = x_pos,
            y = y_pos,
            w = 60,
            h = 18,
            text = item.label,
            font_size = 13,
            color = 0x666666,
            align = airui.TEXT_ALIGN_LEFT
        })

        airui.label({
            parent = info_panel,
            x = x_pos + 65,
            y = y_pos,
            w = 140,
            h = 18,
            text = item.value,
            font_size = 14,
            color = item.value_color or 0x333333,
            align = airui.TEXT_ALIGN_LEFT
        })
    end

    -- 日志面板
    local log_panel = airui.container({
        parent = content_container,
        x = 10,
        y = 290,
        w = 460,
        h = 280,
        color = 0xffffff,
        radius = 8
    })

    airui.label({
        parent = log_panel,
        x = 15,
        y = 10,
        w = 200,
        h = 18,
        text = "连接日志",
        font_size = 16,
        color = 0xE94560,
        align = airui.TEXT_ALIGN_LEFT
    })

    local log_y = 40
    local log_count = 0
    for i = 1, #log_entries do
        local log_entry = log_entries[i]
        if log_entry and log_entry.tag == selected_conn and log_count < 6 then
            local log_color = (log_entry.type == "SEND") and 0x00D26A or
                              ((log_entry.type == "RECV") and 0x2196F3 or 0xFFA502)

            airui.label({
                parent = log_panel,
                x = 15,
                y = log_y,
                w = 50,
                h = 16,
                text = log_entry.time,
                font_size = 11,
                color = 0x999999,
                align = airui.TEXT_ALIGN_LEFT
            })

            local type_badge = airui.container({
                parent = log_panel,
                x = 70,
                y = log_y,
                w = 40,
                h = 18,
                color = log_color,
                radius = 2
            })

            airui.label({
                parent = type_badge,
                x = 2,
                y = 2,
                w = 36,
                h = 14,
                text = log_entry.type,
                font_size = 10,
                color = 0xffffff,
                align = airui.TEXT_ALIGN_CENTER
            })

            local content_text = log_entry.content
            if #content_text > 35 then
                content_text = string.sub(content_text, 1, 35) .. "..."
            end

            airui.label({
                parent = log_panel,
                x = 115,
                y = log_y,
                w = 330,
                h = 18,
                text = content_text,
                font_size = 12,
                color = 0x333333,
                align = airui.TEXT_ALIGN_LEFT
            })

            log_y = log_y + 38
            log_count = log_count + 1
        end
    end

    if log_count == 0 then
        airui.label({
            parent = log_panel,
            x = 15,
            y = 120,
            w = 430,
            h = 24,
            text = "暂无日志",
            font_size = 14,
            color = 0x999999,
            align = airui.TEXT_ALIGN_CENTER
        })
    end

    -- 发送面板
    local send_panel = airui.container({
        parent = content_container,
        x = 10,
        y = 580,
        w = 460,
        h = 100,
        color = 0xffffff,
        radius = 8
    })

    airui.label({
        parent = send_panel,
        x = 15,
        y = 8,
        w = 100,
        h = 16,
        text = "发送数据",
        font_size = 14,
        color = 0xE94560,
        align = airui.TEXT_ALIGN_LEFT
    })

    if not text_keyboard then
        init_keyboards()
    end

    local send_input = airui.textarea({
        parent = send_panel,
        x = 15,
        y = 30,
        w = 320,
        h = 50,
        text = "",
        placeholder = "输入要发送的数据...",
        font_size = 14,
        color = 0x333333,
        bg_color = 0xF5F5F5,
        keyboard = text_keyboard
    })

    local send_btn = airui.container({
        parent = send_panel,
        x = 345,
        y = 30,
        w = 100,
        h = 50,
        color = is_connected and 0x00D26A or 0xCCCCCC,
        radius = 6,
        on_click = function()
            if send_in_progress then
                return
            end

            update_socket_status()
            local current_status = socket_status[selected_conn] or {}
            local currently_connected = current_status.connected or false

            local data = send_input:get_text()
            if not data or #data == 0 then
                return
            end

            send_in_progress = true

            send_input:set_text("")

            local conn_type = selected_conn
            local send_data = data

            sys.taskInit(function()
                local success, err = pcall(function()
                    sys.wait(200)
                    send_socket_data(conn_type, send_data, "ui")
                end)
                if not success then
                    log.error("socket_win", "send error:", err)
                end
                sys.wait(100)
                send_in_progress = false
            end)
        end
    })

    airui.label({
        parent = send_btn,
        x = 0,
        y = 15,
        w = 100,
        h = 20,
        text = "发送",
        font_size = 16,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
end

-- 创建设置页面
local function create_settings_page()
    if not text_keyboard then
        init_keyboards()
    end

    content_container = airui.container({
        parent = main_container,
        x = 0,
        y = 110,
        w = 480,
        h = 690,
        color = 0xF3F4F6
    })

    local settings_panel = airui.container({
        parent = content_container,
        x = 10,
        y = 10,
        w = 460,
        h = 580,
        color = 0xffffff,
        radius = 8
    })

    -- TCP服务器设置
    airui.label({
        parent = settings_panel,
        x = 15,
        y = 15,
        w = 200,
        h = 22,
        text = "TCP服务器",
        font_size = 16,
        color = 0xE94560,
        align = airui.TEXT_ALIGN_LEFT
    })

    airui.label({
        parent = settings_panel,
        x = 15,
        y = 45,
        w = 50,
        h = 20,
        text = "地址",
        font_size = 14,
        color = 0x666666,
        align = airui.TEXT_ALIGN_LEFT
    })

    local tcp_server_input = airui.textarea({
        parent = settings_panel,
        x = 70,
        y = 42,
        w = 200,
        h = 36,
        text = settings_data.tcp.server,
        font_size = 14,
        color = 0x333333,
        bg_color = 0xF5F5F5,
        keyboard = text_keyboard,
        scrollbar = false,
        single_line = true
    })

    airui.label({
        parent = settings_panel,
        x = 285,
        y = 45,
        w = 40,
        h = 20,
        text = "端口",
        font_size = 14,
        color = 0x666666,
        align = airui.TEXT_ALIGN_LEFT
    })

    local tcp_port_input = airui.textarea({
        parent = settings_panel,
        x = 330,
        y = 42,
        w = 110,
        h = 36,
        text = settings_data.tcp.port,
        font_size = 14,
        color = 0x333333,
        bg_color = 0xF5F5F5,
        keyboard = numeric_keyboard,
        scrollbar = false,
        single_line = true
    })

    -- UDP服务器设置
    airui.label({
        parent = settings_panel,
        x = 15,
        y = 95,
        w = 200,
        h = 22,
        text = "UDP服务器",
        font_size = 16,
        color = 0xE94560,
        align = airui.TEXT_ALIGN_LEFT
    })

    airui.label({
        parent = settings_panel,
        x = 15,
        y = 125,
        w = 50,
        h = 20,
        text = "地址",
        font_size = 14,
        color = 0x666666,
        align = airui.TEXT_ALIGN_LEFT
    })

    local udp_server_input = airui.textarea({
        parent = settings_panel,
        x = 70,
        y = 122,
        w = 200,
        h = 36,
        text = settings_data.udp.server,
        font_size = 14,
        color = 0x333333,
        bg_color = 0xF5F5F5,
        keyboard = text_keyboard,
        scrollbar = false,
        single_line = true
    })

    airui.label({
        parent = settings_panel,
        x = 285,
        y = 125,
        w = 40,
        h = 20,
        text = "端口",
        font_size = 14,
        color = 0x666666,
        align = airui.TEXT_ALIGN_LEFT
    })

    local udp_port_input = airui.textarea({
        parent = settings_panel,
        x = 330,
        y = 122,
        w = 110,
        h = 36,
        text = settings_data.udp.port,
        font_size = 14,
        color = 0x333333,
        bg_color = 0xF5F5F5,
        keyboard = numeric_keyboard,
        scrollbar = false,
        single_line = true
    })

    -- SSL服务器设置
    airui.label({
        parent = settings_panel,
        x = 15,
        y = 175,
        w = 200,
        h = 22,
        text = "SSL服务器",
        font_size = 16,
        color = 0xE94560,
        align = airui.TEXT_ALIGN_LEFT
    })

    airui.label({
        parent = settings_panel,
        x = 15,
        y = 205,
        w = 50,
        h = 20,
        text = "地址",
        font_size = 14,
        color = 0x666666,
        align = airui.TEXT_ALIGN_LEFT
    })

    local ssl_server_input = airui.textarea({
        parent = settings_panel,
        x = 70,
        y = 202,
        w = 200,
        h = 36,
        text = settings_data.ssl.server,
        font_size = 14,
        color = 0x333333,
        bg_color = 0xF5F5F5,
        keyboard = text_keyboard,
        scrollbar = false,
        single_line = true
    })

    airui.label({
        parent = settings_panel,
        x = 285,
        y = 205,
        w = 40,
        h = 20,
        text = "端口",
        font_size = 14,
        color = 0x666666,
        align = airui.TEXT_ALIGN_LEFT
    })

    local ssl_port_input = airui.textarea({
        parent = settings_panel,
        x = 330,
        y = 202,
        w = 110,
        h = 36,
        text = settings_data.ssl.port,
        font_size = 14,
        color = 0x333333,
        bg_color = 0xF5F5F5,
        keyboard = numeric_keyboard,
        scrollbar = false,
        single_line = true
    })

    -- 保存按钮
    local save_btn = airui.container({
        parent = settings_panel,
        x = 150,
        y = 280,
        w = 160,
        h = 45,
        color = 0xE94560,
        radius = 6,
        on_click = function()
            local function safe_get_text(input_obj, default_value)
                if input_obj == nil then
                    log.warn("socket_win", "输入框对象为nil")
                    return default_value
                end
                if input_obj.get_text == nil then
                    log.warn("socket_win", "输入框没有get_text方法")
                    return default_value
                end
                local ok, result = pcall(function() return input_obj:get_text() end)
                if ok and result and #tostring(result) > 0 then
                    return tostring(result)
                end
                return default_value
            end

            settings_data.tcp.server = safe_get_text(tcp_server_input, settings_data.tcp.server)
            settings_data.tcp.port = safe_get_text(tcp_port_input, settings_data.tcp.port)
            settings_data.udp.server = safe_get_text(udp_server_input, settings_data.udp.server)
            settings_data.udp.port = safe_get_text(udp_port_input, settings_data.udp.port)
            settings_data.ssl.server = safe_get_text(ssl_server_input, settings_data.ssl.server)
            settings_data.ssl.port = safe_get_text(ssl_port_input, settings_data.ssl.port)

            add_log_entry("sys", "INFO", "设置已保存")

            sys.taskInit(function()
                sys.wait(200)
                local tcp_port = tonumber(settings_data.tcp.port) or settings_data.tcp.port
                local udp_port = tonumber(settings_data.udp.port) or settings_data.udp.port
                local ssl_port = tonumber(settings_data.ssl.port) or settings_data.ssl.port

                set_socket_config("tcp", { server = settings_data.tcp.server, port = tcp_port })
                set_socket_config("udp", { server = settings_data.udp.server, port = udp_port })
                set_socket_config("ssl", { server = settings_data.ssl.server, port = ssl_port })
            end)
        end
    })

    airui.label({
        parent = save_btn,
        x = 0,
        y = 12,
        w = 160,
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
        color = 0xF3F4F6
    })

    local log_list_panel = airui.container({
        parent = content_container,
        x = 10,
        y = 10,
        w = 400,
        h = 670,
        color = 0xffffff,
        radius = 8
    })

    local log_header = airui.container({
        parent = log_list_panel,
        x = 0,
        y = 0,
        w = 400,
        h = 40,
        color = 0xFFEBEE,
        radius = 8
    })

    airui.label({
        parent = log_header,
        x = 15,
        y = 10,
        w = 120,
        h = 20,
        text = "系统日志",
        font_size = 16,
        color = 0xE94560,
        align = airui.TEXT_ALIGN_LEFT
    })

    airui.label({
        parent = log_header,
        x = 200,
        y = 12,
        w = 80,
        h = 16,
        text = #log_entries .. " 条",
        font_size = 13,
        color = 0x666666,
        align = airui.TEXT_ALIGN_RIGHT
    })

    local clear_btn = airui.container({
        parent = log_header,
        x = 300,
        y = 8,
        w = 85,
        h = 24,
        color = 0xE94560,
        radius = 4,
        on_click = function()
            log_entries = {}
            log_scroll_offset = 0
            sys.taskInit(function()
                sys.wait(100)
                if current_tab == "logs" then
                    refresh_content()
                end
            end)
        end
    })

    airui.label({
        parent = clear_btn,
        x = 0,
        y = 4,
        w = 85,
        h = 16,
        text = "清除",
        font_size = 13,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })

    local total_logs = #log_entries
    local max_offset = math.max(0, total_logs - logs_per_page)
    log_scroll_offset = math.min(log_scroll_offset, max_offset)

    local log_y = 50
    local start_idx = log_scroll_offset + 1
    local end_idx = math.min(start_idx + logs_per_page - 1, total_logs)

    for i = start_idx, end_idx do
        local log_item = log_entries[i]
        if log_item then
            local tag_colors = {
                tcp = 0xE94560,
                udp = 0x7950F2,
                ssl = 0x00D26A,
                sys = 0xFFA502,
                err = 0xFF4757
            }
            local tag_color = tag_colors[log_item.tag] or 0x666666

            airui.label({
                parent = log_list_panel,
                x = 10,
                y = log_y,
                w = 55,
                h = 16,
                text = log_item.time,
                font_size = 11,
                color = 0x999999,
                align = airui.TEXT_ALIGN_LEFT
            })

            local tag_badge = airui.container({
                parent = log_list_panel,
                x = 70,
                y = log_y,
                w = 50,
                h = 20,
                color = tag_color,
                radius = 3
            })

            airui.label({
                parent = tag_badge,
                x = 2,
                y = 3,
                w = 46,
                h = 14,
                text = string.upper(log_item.tag),
                font_size = 11,
                color = 0xffffff,
                align = airui.TEXT_ALIGN_CENTER
            })

            local type_badge = airui.container({
                parent = log_list_panel,
                x = 125,
                y = log_y,
                w = 45,
                h = 20,
                color = 0xF5F5F5,
                radius = 3
            })

            airui.label({
                parent = type_badge,
                x = 2,
                y = 3,
                w = 41,
                h = 14,
                text = log_item.type,
                font_size = 11,
                color = 0x666666,
                align = airui.TEXT_ALIGN_CENTER
            })

            local content_text = log_item.content
            if #content_text > 30 then
                content_text = string.sub(content_text, 1, 30) .. "..."
            end

            airui.label({
                parent = log_list_panel,
                x = 10,
                y = log_y + 24,
                w = 380,
                h = 20,
                text = content_text,
                font_size = 12,
                color = 0x333333,
                align = airui.TEXT_ALIGN_LEFT
            })

            log_y = log_y + 55
        end
    end

    if total_logs == 0 then
        airui.label({
            parent = log_list_panel,
            x = 10,
            y = 300,
            w = 380,
            h = 24,
            text = "暂无日志记录",
            font_size = 16,
            color = 0x999999,
            align = airui.TEXT_ALIGN_CENTER
        })
    end

    -- 滑动条区域
    local scrollbar_bg = airui.container({
        parent = content_container,
        x = 420,
        y = 10,
        w = 50,
        h = 670,
        color = 0xE0E0E0,
        radius = 4
    })

    local scroll_up_btn = airui.container({
        parent = scrollbar_bg,
        x = 5,
        y = 10,
        w = 40,
        h = 50,
        color = (total_logs > logs_per_page and log_scroll_offset > 0) and 0xE94560 or 0xF5F5F5,
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
        color = (total_logs > logs_per_page and log_scroll_offset > 0) and 0xFFFFFF or 0x666666,
        align = airui.TEXT_ALIGN_CENTER
    })

    local scroll_down_btn = airui.container({
        parent = scrollbar_bg,
        x = 5,
        y = 610,
        w = 40,
        h = 50,
        color = (total_logs > logs_per_page and log_scroll_offset < max_offset) and 0xE94560 or 0xF5F5F5,
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
        color = (total_logs > logs_per_page and log_scroll_offset < max_offset) and 0xFFFFFF or 0x666666,
        align = airui.TEXT_ALIGN_CENTER
    })

    airui.label({
        parent = scrollbar_bg,
        x = 5,
        y = 320,
        w = 40,
        h = 30,
        text = tostring(log_scroll_offset + 1) .. "/" .. tostring(max_offset + 1),
        font_size = 14,
        color = 0x666666,
        align = airui.TEXT_ALIGN_CENTER
    })
end

-- 刷新内容区域
function refresh_content()
    sys.taskInit(function()
        if current_tab == "dashboard" then
            create_dashboard_page()
        elseif current_tab == "detail" then
            create_detail_page()
        elseif current_tab == "settings" then
            create_settings_page()
        elseif current_tab == "logs" then
            create_logs_page()
        end
    end)
end

-- ==================== exwin 窗口生命周期回调 ====================

-- 主动关闭当前 exwin 窗口
local function close_window()
    if win_id then
        exwin.close(win_id)
    end
end

-- 启动所有Socket任务
local function start_socket_tasks()
    log.info("socket_win", "启动所有Socket任务")
    
    -- 确保之前的任务已经完全停止
    local wait_count = 0
    while (task_handles.tcp or task_handles.udp or task_handles.ssl) and wait_count < 50 do
        sys.wait(10)
        wait_count = wait_count + 1
    end
    if wait_count >= 50 then
        log.warn("socket_win", "等待旧任务退出超时，强制清理")
        -- 强制清理残留的任务句柄
        for conn_type, handle in pairs(task_handles) do
            if handle then
                sys.taskDel(handle)
                task_handles[conn_type] = nil
            end
        end
    end
    
    -- 重置退出标志
    for conn_type in pairs(task_exit_flags) do
        task_exit_flags[conn_type] = false
    end
    
    -- 重置连接状态
    for conn_type, config in pairs(socket_config) do
        config.connected = false
        config.send_bytes = 0
        config.recv_bytes = 0
        config.retry_count = 0
    end
    
    -- 启动任务
    task_handles.tcp = sys.taskInitEx(tcp_socket_task_func, TASK_NAMES.tcp, function(msg) log.info("tcp_cb", msg[1], msg[2], msg[3], msg[4]) end)
    task_handles.udp = sys.taskInitEx(udp_socket_task_func, TASK_NAMES.udp, function(msg) log.info("udp_cb", msg[1], msg[2], msg[3], msg[4]) end)
    task_handles.ssl = sys.taskInitEx(ssl_socket_task_func, TASK_NAMES.ssl, function(msg) log.info("ssl_cb", msg[1], msg[2], msg[3], msg[4]) end)
end

-- 停止所有Socket任务
local function stop_socket_tasks_async()
    log.info("socket_win", "停止所有Socket任务")
    
    -- 设置退出标志，让任务主动退出
    for conn_type in pairs(task_exit_flags) do
        task_exit_flags[conn_type] = true
    end
    
    -- 发布退出事件，唤醒等待中的任务
    sys.publish("SOCKET_EXIT_TCP")
    sys.publish("SOCKET_EXIT_UDP")
    sys.publish("SOCKET_EXIT_SSL")
    
    -- 发布关闭事件断开所有socket连接
    for conn_type, client in pairs(socket_clients) do
        if client then
            sys.publish("SOCKET_CLOSE_" .. string.upper(conn_type))
        end
    end
    
    -- 在协程中等待任务退出
    sys.taskInit(function()
        -- 等待任务真正退出
        local wait_count = 0
        while (task_handles.tcp or task_handles.udp or task_handles.ssl) and wait_count < 100 do
            sys.wait(10)
            wait_count = wait_count + 1
        end
        
        -- 如果超时，强制删除
        if wait_count >= 100 then
            -- log.warn("socket_win", "等待任务退出超时，强制删除")
            for conn_type, handle in pairs(task_handles) do
                if handle then
                    sys.taskDel(handle)
                    task_handles[conn_type] = nil
                end
            end
        end
        
        -- 清理所有socket客户端引用
        for conn_type in pairs(socket_clients) do
            socket_clients[conn_type] = nil
        end
        
        -- 重置所有连接状态
        for conn_type, config in pairs(socket_config) do
            config.connected = false
            config.send_bytes = 0
            config.recv_bytes = 0
            config.retry_count = 0
        end
        
        -- 清空发送队列
        for conn_type in pairs(send_queues) do
            send_queues[conn_type] = {}
        end
        
        -- 清空接收缓冲区
        for conn_type in pairs(recv_buffs) do
            if recv_buffs[conn_type] then
                recv_buffs[conn_type]:del()
            end
        end
        
        log.info("socket_win", "所有Socket任务已停止，资源已清理")
    end)
end

-- 创建主UI
local function build_ui()
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = 0xF8F9FA
    })

    init_keyboards()

    local header = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 480,
        h = 60,
        color = 0x3F51B5
    })

    airui.label({
        parent = header,
        x = 15,
        y = 15,
        w = 150,
        h = 30,
        text = "Socket工具",
        font_size = 24,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_LEFT
    })

    local back_btn = airui.container({
        parent = header,
        x = 380,
        y = 10,
        w = 90,
        h = 40,
        color = 0x2195F6,
        radius = 6,
        on_click = function()
            close_window()
        end
    })

    airui.label({
        parent = back_btn,
        x = 0,
        y = 8,
        w = 90,
        h = 24,
        text = "返回",
        font_size = 18,
        color = 0xfefefe,
        align = airui.TEXT_ALIGN_CENTER
    })

    refresh_tab_bar()
    refresh_content()
end

-- 窗口创建回调
local function on_create()
    -- 启动Socket任务（窗口打开时才启动）
    start_socket_tasks()
    
    update_socket_status()
    
    -- 订阅事件
    sys.subscribe("SOCKET_STATUS_UPDATE", on_socket_status_update)
    sys.subscribe("SOCKET_LOG_ADD", on_socket_log_add)
    sys.subscribe("SOCKET_DETAIL_REFRESH", on_socket_detail_refresh)
    
    -- 构建UI
    build_ui()
end

-- 窗口销毁回调
local function on_destroy()
    -- 停止Socket任务（窗口关闭时停止）- 异步版本在协程中执行
    stop_socket_tasks_async()
    
    -- 取消事件订阅
    sys.unsubscribe("SOCKET_STATUS_UPDATE", on_socket_status_update)
    sys.unsubscribe("SOCKET_LOG_ADD", on_socket_log_add)
    sys.unsubscribe("SOCKET_DETAIL_REFRESH", on_socket_detail_refresh)

    -- 隐藏键盘
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

    -- 销毁主容器（连带所有子组件）
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    
    -- 清理引用
    win_id = nil
    tab_bar_container = nil
    content_container = nil
    
    -- 通知exapp关闭应用，触发sandbox_cleanup
    -- 这是关键：让exapp知道应用已经退出，可以重新打开
    if exapp and exapp.close then
        log.info("socket_win", "calling exapp.close() to notify app exit")
        exapp.close()
    end
end

-- 窗口获得焦点回调
local function on_get_focus()
    update_socket_status()
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

-- 打开窗口处理函数 - 参考 airplane_win.lua 的实现
local function open_handler()
    -- 如果窗口已经存在，将其置顶而不是重新创建
    if win_id then
        exwin.to_top(win_id)
        return
    end
    
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

-- Socket任务不再在模块加载时启动，而是在窗口打开时启动
-- 参考 airplane_win.lua 的生命周期管理模式

log.info("socket_app", "module loaded, waiting for window open")

-- 订阅打开窗口消息
sys.subscribe("OPEN_SOCKET_WIN", open_handler)

-- 模块导出接口
local socket_win = {}

function socket_win.open()
    open_handler()
end

function socket_win.close()
    close_window()
end

function socket_win.is_open()
    return win_id ~= nil
end

return socket_win
