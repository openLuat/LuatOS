--[[
@module  websocket_win
@summary WebSocket UI模块（无持久化，适配480x800，键盘优化）
@version 1.0
@date    2026.04.10
]]

-- ============================================================================
-- websocket_win: WebSocket主页面模块
-- ============================================================================

local main_win_id = nil
local main_container, connection_status_icon, connection_status_text
local receive_count_text, receive_bytes_text, send_count_text, send_bytes_text
local ws_status = false
local network_status_label
local stats = {
    receive_count = 0,
    receive_bytes = 0,
    send_count = 0,
    send_bytes = 0
}

-- 默认配置（与 socket_app 类似，直接写在代码中）
local default_config = {
    server_url = "wss://echo.airtun.air32.cn/ws/echo",
    reconnect_interval = 5,
    max_reconnect = 5,
    heartbeat_interval = 30,
    connect_timeout = 10,
    response_timeout = 5
}

-- 使用全局配置对象（每次启动都是默认值）
_G.websocket_config = {
    server_url = default_config.server_url,
    reconnect_interval = default_config.reconnect_interval,
    max_reconnect = default_config.max_reconnect,
    heartbeat_interval = default_config.heartbeat_interval,
    connect_timeout = default_config.connect_timeout,
    response_timeout = default_config.response_timeout
}

local function create_main_ui()
    main_container = airui.container({ x = 0, y = 0, w = 480, h = 800, color = 0xF8F9FA, parent = airui.screen })
    
    local status_bar = airui.container({ parent = main_container, x = 0, y = 0, w = 480, h = 60, color = 0x3F51B5 })
    airui.label({ parent = status_bar, x = 90, y = 12, w = 300, h = 36, text = "WebSocket管理", font_size = 24, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    local back_btn = airui.container({ parent = status_bar, x = 400, y = 12, w = 70, h = 36, color = 0x2195F6, radius = 5,
        on_click = function()
            if main_win_id then
                exwin.close(main_win_id)
            end
        end
    })
    airui.label({ parent = back_btn, x = 10, y = 8, w = 50, h = 20, text = "返回", font_size = 16, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    
    local content = airui.container({ parent = main_container, x = 0, y = 60, w = 480, h = 740, color = 0xF3F4F6 })
    
    -- 网络状态卡片
    local network_card = airui.container({ parent = content, x = 20, y = 10, w = 215, h = 95, color = 0xFFFFFF, radius = 8, border_color = 0xE0E0E0, border_width = 1 })
    airui.label({ parent = network_card, x = 10, y = 10, w = 200, h = 20, text = "网络状态", font_size = 18, color = 0x333333 })
    network_status_label = airui.label({ parent = network_card, x = 10, y = 40, w = 200, h = 20, text = "当前网络: 未知", font_size = 14, color = 0x666666 })
    
    -- WebSocket状态卡片
    local ws_card = airui.container({ parent = content, x = 245, y = 10, w = 215, h = 95, color = 0xFFFFFF, radius = 8, border_color = 0xE0E0E0, border_width = 1 })
    airui.label({ parent = ws_card, x = 10, y = 10, w = 200, h = 20, text = "WebSocket状态", font_size = 18, color = 0x333333 })
    connection_status_icon = airui.label({ parent = ws_card, x = 10, y = 40, w = 20, h = 20, text = "●", font_size = 20, color = 0xCCCCCC })
    connection_status_text = airui.label({ parent = ws_card, x = 40, y = 40, w = 165, h = 20, text = "已断开", font_size = 14, color = 0x666666 })
    
    -- 接收统计卡片
    local receive_card = airui.container({ parent = content, x = 20, y = 115, w = 215, h = 95, color = 0xFFFFFF, radius = 8, border_color = 0xE0E0E0, border_width = 1 })
    airui.label({ parent = receive_card, x = 10, y = 10, w = 200, h = 20, text = "接收统计", font_size = 18, color = 0x333333 })
    receive_count_text = airui.label({ parent = receive_card, x = 10, y = 40, w = 200, h = 20, text = "总条数: 0", font_size = 14, color = 0x666666 })
    receive_bytes_text = airui.label({ parent = receive_card, x = 10, y = 65, w = 200, h = 20, text = "字节总数: 0", font_size = 14, color = 0x666666 })
    
    -- 发送统计卡片
    local send_card = airui.container({ parent = content, x = 245, y = 115, w = 215, h = 95, color = 0xFFFFFF, radius = 8, border_color = 0xE0E0E0, border_width = 1 })
    airui.label({ parent = send_card, x = 10, y = 10, w = 200, h = 20, text = "发送统计", font_size = 18, color = 0x333333 })
    send_count_text = airui.label({ parent = send_card, x = 10, y = 40, w = 200, h = 20, text = "总条数: 0", font_size = 14, color = 0x666666 })
    send_bytes_text = airui.label({ parent = send_card, x = 10, y = 65, w = 200, h = 20, text = "字节总数: 0", font_size = 14, color = 0x666666 })
    
    -- 底部按钮
    local bottom_y = 260
    local btn_width = 140
    local btn_height = 50
    local gap = (480 - 3 * btn_width) / 4
    local btn_left = airui.container({ parent = content, x = gap, y = bottom_y, w = btn_width, h = btn_height, color = 0x2195F6, radius = 8, on_click = function()
        sys.publish("OPEN_WS_CONNECTION_WIN")
    end })
    airui.label({ parent = btn_left, x = 0, y = 15, w = btn_width, h = 20, text = "连接管理", font_size = 18, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    
    local btn_mid = airui.container({ parent = content, x = 2 * gap + btn_width, y = bottom_y, w = btn_width, h = btn_height, color = 0x4CAF50, radius = 8, on_click = function()
        sys.publish("OPEN_WS_DATA_WIN")
    end })
    airui.label({ parent = btn_mid, x = 0, y = 15, w = btn_width, h = 20, text = "数据管理", font_size = 18, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    
    local btn_right = airui.container({ parent = content, x = 3 * gap + 2 * btn_width, y = bottom_y, w = btn_width, h = btn_height, color = 0xFF9800, radius = 8, on_click = function()
        sys.publish("OPEN_WS_LOGS_WIN")
    end })
    airui.label({ parent = btn_right, x = 0, y = 15, w = btn_width, h = 20, text = "日志", font_size = 18, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })
end

local function update_ws_status(status)
    if not connection_status_icon or not connection_status_text then return end
    if status then
        connection_status_icon:set_color(0x27AE60)
        connection_status_text:set_text("WebSocket连接成功")
        connection_status_text:set_color(0x27AE60)
    else
        connection_status_icon:set_color(0xE74C3C)
        connection_status_text:set_text("未连接")
        connection_status_text:set_color(0xE74C3C)
    end
    ws_status = status
end

local function update_network_status()
    if not network_status_label then return end
    local net_ok = socket.adapter(socket.dft())
    if net_ok then
        network_status_label:set_text("当前网络: 已连接")
        network_status_label:set_color(0x27AE60)
    else
        network_status_label:set_text("当前网络: 无网络")
        network_status_label:set_color(0xE74C3C)
    end
end

local function update_stats()
    if not receive_count_text or not receive_bytes_text or not send_count_text or not send_bytes_text then return end
    receive_count_text:set_text("总条数: " .. tostring(stats.receive_count))
    receive_bytes_text:set_text("字节总数: " .. tostring(stats.receive_bytes))
    send_count_text:set_text("总条数: " .. tostring(stats.send_count))
    send_bytes_text:set_text("字节总数: " .. tostring(stats.send_bytes))
end

local function on_websocket_event(event_type, event_data)
    log.info("WebSocket UI事件", "类型:", event_type, "数据:", event_data)
    if event_type == "CONNECT" then
        update_ws_status(event_data == true)
    elseif event_type == "DISCONNECTED" then
        update_ws_status(false)
    elseif event_type == "ERROR" then
        update_ws_status(false)
    end
end

local function on_websocket_data(tag, data)
    if data then
        stats.receive_count = stats.receive_count + 1
        stats.receive_bytes = stats.receive_bytes + #data
        update_stats()
    end
end

local function on_websocket_send(tag, data, cb)
    local data_str = tostring(data)
    if data then
        stats.send_count = stats.send_count + 1
        stats.send_bytes = stats.send_bytes + #data_str
        update_stats()
    end
end

local function on_main_create()
    create_main_ui()
    local current_ws_status = _G.websocket_connected or false
    update_ws_status(current_ws_status)
    update_network_status()
    update_stats()
    sys.subscribe("WEBSOCKET_EVENT", on_websocket_event)
    sys.subscribe("RECV_DATA_FROM_SERVER", on_websocket_data)
    sys.subscribe("SEND_DATA_REQ", on_websocket_send)
    sys.timerLoopStart(update_network_status, 5000)
end

local function on_main_destroy()
    sys.unsubscribe("WEBSOCKET_EVENT", on_websocket_event)
    sys.unsubscribe("RECV_DATA_FROM_SERVER", on_websocket_data)
    sys.unsubscribe("SEND_DATA_REQ", on_websocket_send)
    sys.timerStop(update_network_status)
    if main_container then main_container:destroy() end
    connection_status_icon, connection_status_text = nil, nil
    receive_count_text, receive_bytes_text, send_count_text, send_bytes_text = nil, nil, nil, nil
    network_status_label = nil
end

local function on_main_get_focus()
    update_network_status()
    update_ws_status(ws_status)
    update_stats()
end

local function open_main_handler()
    main_win_id = exwin.open({
        on_create = on_main_create,
        on_destroy = on_main_destroy,
        on_lose_focus = function() end,
        on_get_focus = on_main_get_focus,
    })
end
sys.subscribe("OPEN_WEBSOCKET_WIN", open_main_handler)

-- ============================================================================
-- ws_connection: WebSocket连接管理页面模块（键盘优化）
-- ============================================================================

local connection_win_id = nil
local connection_container, connection_content
local server_address_input
local reconnect_interval_input, max_reconnect_input
local heartbeat_interval_input
local connect_timeout_input, response_timeout_input
local keyboard_numeric, keyboard_text
local connection_status_label, connection_count_label
local msgbox_ref = nil
local msgbox_timer = nil

-- 使用全局配置对象（内存中）
local ws_config = _G.websocket_config
local connection_stats = { is_connected = false, connect_count = 0 }
local waiting_for_connect = false

local function close_msgbox()
    if msgbox_timer then sys.timerStop(msgbox_timer); msgbox_timer = nil end
    if msgbox_ref then msgbox_ref:hide(); msgbox_ref = nil end
end

local function show_msgbox(title, text, auto_close_ms)
    close_msgbox()
    msgbox_ref = airui.msgbox({
        title = title,
        text = text,
        buttons = { "确定" },
        on_action = function(self, label)
            if label == "确定" then self:hide(); msgbox_ref = nil end
        end
    })
    if auto_close_ms and auto_close_ms > 0 then
        msgbox_timer = sys.timerStart(close_msgbox, auto_close_ms)
    end
end

local function update_connection_status()
    if not connection_status_label or not connection_count_label then return end
    if connection_stats.is_connected then
        connection_status_label:set_text("已连接")
        connection_status_label:set_color(0x27AE60)
    else
        connection_status_label:set_text("已断开")
        connection_status_label:set_color(0xE74C3C)
    end
    connection_count_label:set_text("连接次数: " .. tostring(connection_stats.connect_count))
end

local function on_connection_websocket_event(event_type, event_data)
    if event_type == "CONNECT" then
        if event_data == true then
            connection_stats.is_connected = true
            connection_stats.connect_count = connection_stats.connect_count + 1
            update_connection_status()
            if waiting_for_connect then
                waiting_for_connect = false
                show_msgbox("连接状态", "连接成功", 5000)
            end
        else
            connection_stats.is_connected = false
            update_connection_status()
            if waiting_for_connect then
                waiting_for_connect = false
                show_msgbox("连接状态", "连接失败", 5000)
            end
        end
    elseif event_type == "DISCONNECTED" then
        connection_stats.is_connected = false
        update_connection_status()
        waiting_for_connect = false
    elseif event_type == "ERROR" then
        connection_stats.is_connected = false
        update_connection_status()
        if waiting_for_connect then
            waiting_for_connect = false
            show_msgbox("连接状态", "连接失败", 5000)
        end
    end
end

local function save_settings()
    local server_url = server_address_input and server_address_input:get_text() or ws_config.server_url
    local reconnect_interval = tonumber(reconnect_interval_input and reconnect_interval_input:get_text() or "5") or 5
    local max_reconnect = tonumber(max_reconnect_input and max_reconnect_input:get_text() or "5") or 5
    local heartbeat_interval = tonumber(heartbeat_interval_input and heartbeat_interval_input:get_text() or "60") or 60
    local connect_timeout = tonumber(connect_timeout_input and connect_timeout_input:get_text() or "10") or 10
    local response_timeout = tonumber(response_timeout_input and response_timeout_input:get_text() or "5") or 5
    
    local config_changed = (
        server_url ~= ws_config.server_url or
        reconnect_interval ~= ws_config.reconnect_interval or
        max_reconnect ~= ws_config.max_reconnect or
        heartbeat_interval ~= ws_config.heartbeat_interval or
        connect_timeout ~= ws_config.connect_timeout or
        response_timeout ~= ws_config.response_timeout
    )
    
    ws_config.server_url = server_url
    ws_config.reconnect_interval = reconnect_interval
    ws_config.max_reconnect = max_reconnect
    ws_config.heartbeat_interval = heartbeat_interval
    ws_config.connect_timeout = connect_timeout
    ws_config.response_timeout = response_timeout
    
    if not config_changed then
        show_msgbox("保存结果", "保存成功", 3000)
        return true
    end
    
    waiting_for_connect = true
    sys.publish("WS_CONFIG_UPDATED", ws_config)
    show_msgbox("保存结果", "保存成功，正在重连...", 0)
    sys.timerStart(function()
        if waiting_for_connect then waiting_for_connect = false; close_msgbox() end
    end, 10000)
    return true
end

local function create_connection_ui()
    connection_container = airui.container({ x = 0, y = 0, w = 480, h = 800, color = 0xF8F9FA, parent = airui.screen })
    local status_bar = airui.container({ parent = connection_container, x = 0, y = 0, w = 480, h = 60, color = 0x3F51B5 })
    local back_btn = airui.container({ parent = status_bar, x = 10, y = 12, w = 36, h = 36, color = 0x3F51B5, on_click = function()
        if connection_win_id then exwin.close(connection_win_id) end
    end })
    airui.label({ parent = back_btn, x = 0, y = 0, w = 36, h = 36, text = "←", font_size = 28, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    airui.label({ parent = status_bar, x = 160, y = 12, w = 160, h = 36, text = "连接管理", font_size = 22, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    
    connection_content = airui.container({ parent = connection_container, x = 0, y = 60, w = 480, h = 740, color = 0xF3F4F6 })
    
    -- 优化键盘：向上移动30像素，高度增加至160
    keyboard_numeric = airui.keyboard({
        mode = "numeric",
        auto_hide = true,
        preview = true,
        preview_height = 35,
        w = 480,
        h = 160,
        y = -30,
        parent = airui.screen
    })
    keyboard_text = airui.keyboard({
        mode = "text",
        auto_hide = true,
        preview = true,
        preview_height = 35,
        w = 480,
        h = 160,
        y = -30,
        parent = airui.screen
    })
    
    -- 连接状态
    local status_panel = airui.container({ parent = connection_content, x = 10, y = 10, w = 460, h = 55, color = 0xFFFFFF, radius = 8, border_color = 0xE0E0E0, border_width = 1 })
    airui.label({ parent = status_panel, x = 2, y = 12, w = 100, h = 30, text = "连接状态", font_size = 18, color = 0x333333, align = airui.TEXT_ALIGN_CENTER, valign = airui.TEXT_VALIGN_CENTER })
    connection_status_label = airui.label({ parent = status_panel, x = 102, y = 12, w = 150, h = 30, text = "已断开", font_size = 16, color = 0xE74C3C, align = airui.TEXT_ALIGN_CENTER, valign = airui.TEXT_VALIGN_CENTER })
    connection_count_label = airui.label({ parent = status_panel, x = 262, y = 12, w = 150, h = 30, text = "连接次数: 0", font_size = 16, color = 0x666666, align = airui.TEXT_ALIGN_CENTER, valign = airui.TEXT_VALIGN_CENTER })
    
    -- 服务器地址（增大输入框高度和字体）
    local addr_panel = airui.container({ parent = connection_content, x = 10, y = 75, w = 460, h = 60, color = 0xFFFFFF, radius = 8, border_color = 0xE0E0E0, border_width = 1 })
    airui.label({ parent = addr_panel, x = 2, y = 15, w = 100, h = 30, text = "服务器地址", font_size = 18, color = 0x333333, align = airui.TEXT_ALIGN_CENTER, valign = airui.TEXT_VALIGN_CENTER })
    server_address_input = airui.textarea({
        parent = addr_panel,
        x = 102,
        y = 12,
        w = 350,
        h = 36,
        placeholder = "wss://echo.airtun.air32.cn/ws/echo",
        text = ws_config.server_url,
        max_len = 100,
        font_size = 16,
        keyboard = keyboard_text,
        border_color = nil
    })
    
    -- 重连设置（增大输入框高度和字体）
    local reconnect_panel = airui.container({ parent = connection_content, x = 10, y = 145, w = 460, h = 60, color = 0xFFFFFF, radius = 8, border_color = 0xE0E0E0, border_width = 1 })
    airui.label({ parent = reconnect_panel, x = 2, y = 15, w = 100, h = 30, text = "重连间隔", font_size = 18, color = 0x333333, align = airui.TEXT_ALIGN_CENTER, valign = airui.TEXT_VALIGN_CENTER })
    reconnect_interval_input = airui.textarea({
        parent = reconnect_panel,
        x = 102,
        y = 12,
        w = 80,
        h = 36,
        placeholder = "5",
        text = tostring(ws_config.reconnect_interval),
        max_len = 5,
        font_size = 16,
        keyboard = keyboard_numeric,
        border_color = nil
    })
    airui.label({ parent = reconnect_panel, x = 185, y = 15, w = 30, h = 30, text = "秒", font_size = 16, color = 0x666666, align = airui.TEXT_ALIGN_CENTER, valign = airui.TEXT_VALIGN_CENTER })
    airui.label({ parent = reconnect_panel, x = 220, y = 15, w = 100, h = 30, text = "最大重连", font_size = 18, color = 0x333333, align = airui.TEXT_ALIGN_CENTER, valign = airui.TEXT_VALIGN_CENTER })
    max_reconnect_input = airui.textarea({
        parent = reconnect_panel,
        x = 320,
        y = 12,
        w = 80,
        h = 36,
        placeholder = "5",
        text = tostring(ws_config.max_reconnect),
        max_len = 5,
        font_size = 16,
        keyboard = keyboard_numeric,
        border_color = nil
    })
    airui.label({ parent = reconnect_panel, x = 405, y = 15, w = 30, h = 30, text = "次", font_size = 16, color = 0x666666, align = airui.TEXT_ALIGN_CENTER, valign = airui.TEXT_VALIGN_CENTER })
    
    -- 心跳设置
    local heartbeat_panel = airui.container({ parent = connection_content, x = 10, y = 215, w = 460, h = 60, color = 0xFFFFFF, radius = 8, border_color = 0xE0E0E0, border_width = 1 })
    airui.label({ parent = heartbeat_panel, x = 2, y = 15, w = 100, h = 30, text = "心跳间隔", font_size = 18, color = 0x333333, align = airui.TEXT_ALIGN_CENTER, valign = airui.TEXT_VALIGN_CENTER })
    heartbeat_interval_input = airui.textarea({
        parent = heartbeat_panel,
        x = 102,
        y = 12,
        w = 80,
        h = 36,
        placeholder = "60",
        text = tostring(ws_config.heartbeat_interval),
        max_len = 5,
        font_size = 16,
        keyboard = keyboard_numeric,
        border_color = nil
    })
    airui.label({ parent = heartbeat_panel, x = 185, y = 15, w = 150, h = 30, text = "秒 (默认30秒)", font_size = 16, color = 0x666666, align = airui.TEXT_ALIGN_CENTER, valign = airui.TEXT_VALIGN_CENTER })
    
    -- 超时设置
    local timeout_panel = airui.container({ parent = connection_content, x = 10, y = 285, w = 460, h = 60, color = 0xFFFFFF, radius = 8, border_color = 0xE0E0E0, border_width = 1 })
    airui.label({ parent = timeout_panel, x = 2, y = 15, w = 100, h = 30, text = "连接超时", font_size = 18, color = 0x333333, align = airui.TEXT_ALIGN_CENTER, valign = airui.TEXT_VALIGN_CENTER })
    connect_timeout_input = airui.textarea({
        parent = timeout_panel,
        x = 102,
        y = 12,
        w = 80,
        h = 36,
        placeholder = "10",
        text = tostring(ws_config.connect_timeout),
        max_len = 5,
        font_size = 16,
        keyboard = keyboard_numeric,
        border_color = nil
    })
    airui.label({ parent = timeout_panel, x = 185, y = 15, w = 30, h = 30, text = "秒", font_size = 16, color = 0x666666, align = airui.TEXT_ALIGN_CENTER, valign = airui.TEXT_VALIGN_CENTER })
    airui.label({ parent = timeout_panel, x = 220, y = 15, w = 100, h = 30, text = "响应超时", font_size = 18, color = 0x333333, align = airui.TEXT_ALIGN_CENTER, valign = airui.TEXT_VALIGN_CENTER })
    response_timeout_input = airui.textarea({
        parent = timeout_panel,
        x = 320,
        y = 12,
        w = 80,
        h = 36,
        placeholder = "5",
        text = tostring(ws_config.response_timeout),
        max_len = 5,
        font_size = 16,
        keyboard = keyboard_numeric,
        border_color = nil
    })
    airui.label({ parent = timeout_panel, x = 405, y = 15, w = 30, h = 30, text = "秒", font_size = 16, color = 0x666666, align = airui.TEXT_ALIGN_CENTER, valign = airui.TEXT_VALIGN_CENTER })
    
    -- 保存按钮
local save_btn = airui.container({ parent = connection_content, x = 10, y = 365, w = 460, h = 55, color = 0x3498DB, radius = 8, on_click = save_settings })
airui.label({ parent = save_btn, x = 180, y = 14, w = 100, h = 27, text = "保存设置", font_size = 20, color = 0xFFFFFF, align = airui.TEXT_ALIGN_CENTER })
end

local function on_connection_create()
    create_connection_ui()
    waiting_for_connect = false
    connection_stats.is_connected = _G.websocket_connected or false
    update_connection_status()
    sys.subscribe("WEBSOCKET_EVENT", on_connection_websocket_event)
end

local function on_connection_destroy()
    sys.unsubscribe("WEBSOCKET_EVENT", on_connection_websocket_event)
    close_msgbox()
    if keyboard_numeric then keyboard_numeric:destroy() end
    if keyboard_text then keyboard_text:destroy() end
    if connection_container then connection_container:destroy() end
    connection_status_label, connection_count_label = nil, nil
    server_address_input = nil
end

local function on_connection_get_focus()
    connection_stats.is_connected = _G.websocket_connected or false
    update_connection_status()
end

local function open_connection_handler()
    connection_win_id = exwin.open({
        on_create = on_connection_create,
        on_destroy = on_connection_destroy,
        on_lose_focus = function() end,
        on_get_focus = on_connection_get_focus,
    })
end
sys.subscribe("OPEN_WS_CONNECTION_WIN", open_connection_handler)

-- ============================================================================
-- ws_data: WebSocket数据管理页面模块 (480x800，键盘优化)
-- ============================================================================

local data_win_id = nil
local data_container, send_textarea, receive_textarea, history_textarea
local send_btn, clear_btn
local tabview
local keyboard
local send_in_progress = false
local send_msgbox_ref, send_msgbox_timer = nil, nil
local send_history = "暂无发送历史"
local receive_history = ""

local function close_send_msgbox()
    if send_msgbox_timer then sys.timerStop(send_msgbox_timer); send_msgbox_timer = nil end
    if send_msgbox_ref then send_msgbox_ref:hide(); send_msgbox_ref = nil end
end

local function show_send_msgbox(text, auto_close_ms)
    close_send_msgbox()
    send_msgbox_ref = airui.msgbox({
        title = "发送结果",
        text = text,
        buttons = { "确定" },
        on_action = function(self, label)
            if label == "确定" then self:hide(); send_msgbox_ref = nil end
        end
    })
    if auto_close_ms and auto_close_ms > 0 then
        send_msgbox_timer = sys.timerStart(close_send_msgbox, auto_close_ms)
    end
end

local function update_send_btn_color()
    if not send_btn then return end
    local connected = _G.websocket_connected or false
    send_btn:set_color(connected and 0x3498DB or 0xCCCCCC)
end

local function on_data_websocket_event(event_type, event_data)
    if event_type == "CONNECT" or event_type == "DISCONNECTED" then update_send_btn_color() end
end

local function on_data_recv_data(prefix, data)
    local display_data = data or ""
    local timestamp = os.date("%H:%M")
    local new_entry = "[" .. timestamp .. "] " .. tostring(display_data)
    if receive_history == "" then
        receive_history = new_entry
    else
        receive_history = receive_history .. "\n" .. new_entry
    end
    if receive_textarea then receive_textarea:set_text(receive_history) end
end

local function create_data_ui()
    data_container = airui.container({ x = 0, y = 0, w = 480, h = 800, color = 0xF8F9FA, parent = airui.screen })
    local status_bar = airui.container({ parent = data_container, x = 0, y = 0, w = 480, h = 60, color = 0x3F51B5 })
    local back_btn = airui.container({ parent = status_bar, x = 10, y = 12, w = 36, h = 36, color = 0x3F51B5, on_click = function()
        if data_win_id then exwin.close(data_win_id) end
    end })
    airui.label({ parent = back_btn, x = 0, y = 0, w = 36, h = 36, text = "←", font_size = 28, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    airui.label({ parent = status_bar, x = 160, y = 12, w = 160, h = 36, text = "数据管理", font_size = 22, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    
    -- 优化键盘：向上移动30像素，高度增加至160
    keyboard = airui.keyboard({
        mode = "text",
        auto_hide = true,
        preview = true,
        preview_height = 35,
        w = 480,
        h = 160,
        y = -30,
        parent = airui.screen
    })
    
    tabview = airui.tabview({
        parent = data_container,
        x = 0,
        y = 60,
        w = 480,
        h = 740,
        tabs = { "发送", "接收" },
        active = 0,
        switch_mode = "jump",
        page_style = { tabbar_size = 44, pad = { method = airui.TABVIEW_PAD_ALL, value = 0 }, bg_opa = 0 }
    })
    
    local send_content = tabview:get_content(0)
    -- 发送数据卡片：增大高度
    local card_input = airui.container({ parent = send_content, x = 10, y = 10, w = 460, h = 260, color = 0xffffff, radius = 8 })
    airui.label({ parent = card_input, x = 10, y = 8, w = 80, h = 24, text = "数据输入", font_size = 18, color = 0x333333 })
    send_btn = airui.container({ parent = card_input, x = 365, y = 6, w = 85, h = 28, color = 0x3498DB, radius = 4, on_click = function()
        if send_in_progress then return end
        local connected = _G.websocket_connected or false
        if not connected then
            airui.msgbox({ title = "提示", text = "WebSocket未连接，请先连接", buttons = { "确定" } })
            return
        end
        local data = send_textarea:get_text()
        if not data or data == "" then
            airui.msgbox({ title = "提示", text = "请输入要发送的数据", buttons = { "确定" } })
            return
        end
        send_in_progress = true
        if keyboard then keyboard:hide() end
        local send_data = data
        sys.taskInit(function()
            pcall(function()
                sys.wait(200)
                sys.publish("SEND_DATA_REQ", "ui", send_data, {
                    func = function(result, para)
                        if result then
                            send_textarea:set_text("")
                            if send_history == "暂无发送历史" or send_history == "" then
                                send_history = send_data
                            else
                                send_history = send_history .. "\n" .. send_data
                            end
                            history_textarea:set_text(send_history)
                            show_send_msgbox("发送成功", 5000)
                        else
                            send_textarea:set_text(send_data)
                            show_send_msgbox("发送失败", 5000)
                        end
                    end,
                    para = nil
                })
            end)
            sys.wait(100)
            send_in_progress = false
        end)
    end })
    airui.label({ parent = send_btn, x = 5, y = 4, w = 75, h = 20, text = "发送数据", font_size = 16, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    -- 增大发送输入框高度
    send_textarea = airui.textarea({
        parent = card_input,
        x = 10,
        y = 38,
        w = 440,
        h = 210,
        text = "",
        max_len = 512,
        font_size = 16,
        placeholder = "请输入要发送的文本数据...",
        keyboard = keyboard,
        border_color = nil
    })
    
    -- 发送历史卡片
    local card_history = airui.container({ parent = send_content, x = 10, y = 280, w = 460, h = 400, color = 0xffffff, radius = 8 })
    airui.label({ parent = card_history, x = 10, y = 8, w = 80, h = 24, text = "发送历史", font_size = 18, color = 0x333333 })
    local clear_history_btn = airui.container({ parent = card_history, x = 365, y = 6, w = 85, h = 28, color = 0xE0E0E0, radius = 4, on_click = function()
        send_history = "暂无发送历史"
        history_textarea:set_text(send_history)
    end })
    airui.label({ parent = clear_history_btn, x = 5, y = 4, w = 75, h = 20, text = "清空", font_size = 16, color = 0x333333, align = airui.TEXT_ALIGN_CENTER })
    history_textarea = airui.textarea({
        parent = card_history,
        x = 10,
        y = 38,
        w = 440,
        h = 352,
        text = send_history,
        max_len = 1024,
        font_size = 14,
        readonly = true
    })
    
    -- 接收页面
    local receive_content = tabview:get_content(1)
    local card_receive = airui.container({ parent = receive_content, x = 10, y = 10, w = 460, h = 670, color = 0xffffff, radius = 8 })
    airui.label({ parent = card_receive, x = 10, y = 8, w = 80, h = 24, text = "接收数据", font_size = 18, color = 0x333333 })
    clear_btn = airui.container({ parent = card_receive, x = 380, y = 6, w = 70, h = 28, color = 0xFF9A27, radius = 4, on_click = function()
        receive_history = ""
        receive_textarea:set_text(receive_history)
    end })
    airui.label({ parent = clear_btn, x = 5, y = 4, w = 60, h = 20, text = "清空", font_size = 14, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    receive_textarea = airui.textarea({
        parent = card_receive,
        x = 10,
        y = 38,
        w = 440,
        h = 622,
        text = receive_history,
        max_len = 2048,
        font_size = 14,
        placeholder = "接收到的数据将显示在这里...",
        readonly = true
    })
    
    update_send_btn_color()
end

local function on_data_create()
    create_data_ui()
    sys.subscribe("WEBSOCKET_EVENT", on_data_websocket_event)
end

local function on_data_destroy()
    close_send_msgbox()
    sys.unsubscribe("WEBSOCKET_EVENT", on_data_websocket_event)
    if data_container then data_container:destroy() end
    tabview = nil
    keyboard = nil
    send_textarea, receive_textarea, history_textarea = nil, nil, nil
    send_btn, clear_btn = nil, nil
end

local function on_data_get_focus()
    update_send_btn_color()
end

local function open_data_handler()
    data_win_id = exwin.open({
        on_create = on_data_create,
        on_destroy = on_data_destroy,
        on_lose_focus = function() end,
        on_get_focus = on_data_get_focus,
    })
end
sys.subscribe("OPEN_WS_DATA_WIN", open_data_handler)
sys.subscribe("RECV_DATA_FROM_SERVER", on_data_recv_data)

-- ============================================================================
-- ws_logs: WebSocket日志页面模块 (480x800)
-- ============================================================================

local logs_win_id = nil
local logs_container, log_textarea
local clear_btn, export_btn
local search_input, search_btn
local filter_info, filter_warn, filter_error, filter_debug, filter_all
local current_filter = "all"
local logs_keyboard
local all_logs = {}

local function update_filter_buttons()
    if not filter_all then return end
    filter_all:set_color(0x2195F6)
    filter_info:set_color(0xE0E0E0)
    filter_warn:set_color(0xE0E0E0)
    filter_error:set_color(0xE0E0E0)
    filter_debug:set_color(0xE0E0E0)
    if current_filter == "all" then filter_all:set_color(0x2195F6)
    elseif current_filter == "info" then filter_info:set_color(0x2195F6)
    elseif current_filter == "warn" then filter_warn:set_color(0xFF9800)
    elseif current_filter == "error" then filter_error:set_color(0xF44336)
    elseif current_filter == "debug" then filter_debug:set_color(0x9E9E9E)
    end
end

local function display_logs()
    if not log_textarea then return end
    local filtered = {}
    for _, log in ipairs(all_logs) do
        if current_filter == "all" or log.level == current_filter then
            table.insert(filtered, log)
        end
    end
    if #filtered == 0 then
        log_textarea:set_text("暂无日志记录")
        return
    end
    local text = ""
    for _, log in ipairs(filtered) do
        local level_str = log.level == "info" and "[信息]" or
                          log.level == "warn" and "[警告]" or
                          log.level == "error" and "[错误]" or "[调试]"
        text = text .. log.time .. " " .. level_str .. " " .. log.content .. "\n"
    end
    log_textarea:set_text(text)
end

local function set_filter(level)
    current_filter = level
    update_filter_buttons()
    display_logs()
end

local function clear_all_logs()
    all_logs = {}
    display_logs()
    airui.msgbox({
        title = "提示",
        text = "日志已清空",
        buttons = { "确定" },
        timeout = 5000,  -- 5秒后自动关闭
        on_action = function(self, label)
            self:hide()
        end
    })
end

local function export_logs()
    local path = "/websocket_logs_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
    local file, err = io.open(path, "w")
    if file then
        file:write("WebSocket日志导出 - " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n====================================\n")
        for _, log in ipairs(all_logs) do
            local level_str = log.level == "info" and "[信息]" or
                              log.level == "warn" and "[警告]" or
                              log.level == "error" and "[错误]" or "[调试]"
            file:write(log.time .. " " .. level_str .. " " .. log.content .. "\n")
        end
        file:write("====================================\n共 " .. #all_logs .. " 条日志\n")
        file:close()
        airui.msgbox({
            title = "导出成功",
            text = "日志已导出到:\n" .. path,
            buttons = { "确定" },
            timeout = 5000,
            on_action = function(self, label)
                self:hide()
            end
        })
    else
        airui.msgbox({
            title = "导出失败",
            text = "日志导出失败: " .. (err or "未知错误"),
            buttons = { "确定" },
            timeout = 5000,
            on_action = function(self, label)
                self:hide()
            end
        })
    end
end

local function search_logs()
    local keyword = search_input and search_input:get_text()
    if not keyword or keyword == "" then
        display_logs()
        return
    end
    local results = {}
    for _, log in ipairs(all_logs) do
        if (current_filter == "all" or log.level == current_filter) and
           (string.find(log.content, keyword) or string.find(log.time, keyword)) then
            table.insert(results, log)
        end
    end
    if #results == 0 then
        log_textarea:set_text("未找到匹配的日志")
        return
    end
    local text = ""
    for _, log in ipairs(results) do
        local level_str = log.level == "info" and "[信息]" or
                          log.level == "warn" and "[警告]" or
                          log.level == "error" and "[错误]" or "[调试]"
        text = text .. log.time .. " " .. level_str .. " " .. log.content .. "\n"
    end
    log_textarea:set_text(text)
end

local function create_logs_ui()
    logs_container = airui.container({ x = 0, y = 0, w = 480, h = 800, color = 0xF8F9FA, parent = airui.screen })
    logs_keyboard = airui.keyboard({ mode = "text", auto_hide = true, preview = true, preview_height = 35, w = 480, h = 120, parent = airui.screen })
    
    local status_bar = airui.container({ parent = logs_container, x = 0, y = 0, w = 480, h = 60, color = 0x3F51B5 })
    local back_btn = airui.container({ parent = status_bar, x = 10, y = 12, w = 36, h = 36, color = 0x3F51B5, on_click = function()
        if logs_win_id then exwin.close(logs_win_id) end
    end })
    airui.label({ parent = back_btn, x = 0, y = 0, w = 36, h = 36, text = "←", font_size = 28, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    airui.label({ parent = status_bar, x = 160, y = 12, w = 160, h = 36, text = "日志", font_size = 22, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    
    local content = airui.container({ parent = logs_container, x = 0, y = 60, w = 480, h = 740, color = 0xF3F4F6 })
    local card = airui.container({ parent = content, x = 10, y = 10, w = 460, h = 720, color = 0xffffff, radius = 8 })
    
    -- 过滤栏
    local filter_bar = airui.container({ parent = card, x = 10, y = 5, w = 440, h = 44, color = 0xF3F4F6, radius = 4 })
    airui.label({ parent = filter_bar, x = 0, y = 12, w = 70, h = 20, text = "日志过滤", font_size = 16, color = 0x333333 })
    local btn_h = 32
    filter_all = airui.container({ parent = filter_bar, x = 80, y = 6, w = 70, h = btn_h, color = 0x2195F6, radius = 4, on_click = function() set_filter("all") end })
    airui.label({ parent = filter_all, x = 5, y = 5, w = 60, h = 22, text = "全部", font_size = 15, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    filter_info = airui.container({ parent = filter_bar, x = 155, y = 6, w = 55, h = btn_h, color = 0xE0E0E0, radius = 4, on_click = function() set_filter("info") end })
    airui.label({ parent = filter_info, x = 5, y = 5, w = 45, h = 22, text = "信息", font_size = 15, color = 0x000000, align = airui.TEXT_ALIGN_CENTER })
    filter_warn = airui.container({ parent = filter_bar, x = 215, y = 6, w = 55, h = btn_h, color = 0xE0E0E0, radius = 4, on_click = function() set_filter("warn") end })
    airui.label({ parent = filter_warn, x = 5, y = 5, w = 45, h = 22, text = "警告", font_size = 15, color = 0x000000, align = airui.TEXT_ALIGN_CENTER })
    filter_error = airui.container({ parent = filter_bar, x = 275, y = 6, w = 55, h = btn_h, color = 0xE0E0E0, radius = 4, on_click = function() set_filter("error") end })
    airui.label({ parent = filter_error, x = 5, y = 5, w = 45, h = 22, text = "错误", font_size = 15, color = 0x000000, align = airui.TEXT_ALIGN_CENTER })
    filter_debug = airui.container({ parent = filter_bar, x = 335, y = 6, w = 55, h = btn_h, color = 0xE0E0E0, radius = 4, on_click = function() set_filter("debug") end })
    airui.label({ parent = filter_debug, x = 5, y = 5, w = 45, h = 22, text = "调试", font_size = 15, color = 0x000000, align = airui.TEXT_ALIGN_CENTER })
    
    -- 搜索栏
    local search_bar = airui.container({ parent = card, x = 10, y = 54, w = 440, h = 45, color = 0xF3F4F6, radius = 4 })
    search_input = airui.textarea({ parent = search_bar, x = 0, y = 5, w = 370, h = 35, text = "", max_len = 100, font_size = 14, placeholder = "搜索日志...", keyboard = logs_keyboard })
    search_btn = airui.container({ parent = search_bar, x = 375, y = 5, w = 60, h = 35, color = 0x2195F6, radius = 4, on_click = search_logs })
    airui.label({ parent = search_btn, x = 5, y = 8, w = 50, h = 20, text = "搜索", font_size = 14, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    
    -- 日志内容
    log_textarea = airui.textarea({ parent = card, x = 10, y = 104, w = 440, h = 510, text = "WebSocket日志系统启动...\n等待连接...\n", max_len = 4096, font_size = 12, placeholder = "日志将显示在这里..." })
    
    -- 底部按钮
    local bottom_bar = airui.container({ parent = card, x = 10, y = 620, w = 440, h = 90, color = 0xF3F4F6, radius = 4 })
    clear_btn = airui.container({ parent = bottom_bar, x = 0, y = 25, w = 100, h = 40, color = 0xF44336, radius = 6, on_click = clear_all_logs })
    airui.label({ parent = clear_btn, x = 5, y = 10, w = 90, h = 20, text = "清空日志", font_size = 16, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    export_btn = airui.container({ parent = bottom_bar, x = 340, y = 25, w = 100, h = 40, color = 0x2195F6, radius = 6, on_click = export_logs })
    airui.label({ parent = export_btn, x = 5, y = 10, w = 90, h = 20, text = "导出日志", font_size = 16, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })
end

local function on_websocket_log_add(log_type, content)
    local t = os.time()
    local dt = os.date("*t", t)
    local time_str = string.format("%02d:%02d:%02d", dt.hour, dt.min, dt.sec)
    table.insert(all_logs, { level = log_type, time = time_str, content = content })
    while #all_logs > 200 do table.remove(all_logs, 1) end
    if log_textarea then display_logs() end
end

sys.subscribe("WEBSOCKET_LOG_ADD", on_websocket_log_add)

local function on_logs_create()
    create_logs_ui()
    display_logs()
end

local function on_logs_destroy()
    if logs_container then logs_container:destroy() end
    log_textarea, clear_btn, export_btn = nil, nil, nil
    search_input, search_btn = nil, nil, nil
    filter_all, filter_info, filter_warn, filter_error, filter_debug = nil, nil, nil, nil, nil
    logs_keyboard = nil
end

local function on_logs_get_focus()
    display_logs()
end

local function open_logs_handler()
    logs_win_id = exwin.open({
        on_create = on_logs_create,
        on_destroy = on_logs_destroy,
        on_lose_focus = function() end,
        on_get_focus = on_logs_get_focus,
    })
end
sys.subscribe("OPEN_WS_LOGS_WIN", open_logs_handler)

log.info("websocket_win", "模块已加载（键盘优化版）")