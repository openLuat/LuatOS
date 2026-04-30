--[[
@module  websocket_app
@summary WebSocket应用功能模块（真机稳定版，修正心跳定时器）
@version 1.0
@date    2026.04.10
]]

-- ============================================================================
-- network_watchdog
-- ============================================================================
local function network_watchdog_task_func()
    while true do
        if not sys.waitUntil("FEED_NETWORK_WATCHDOG", 180000) then
            log.error("network_watchdog_task_func timeout")
            sys.wait(3000)
            rtos.reboot()
        end
    end
end
sys.taskInit(network_watchdog_task_func)

-- ============================================================================
-- websocket_receiver
-- ============================================================================
local recv_data_buff = ""

local function websocket_receiver_proc(data, fin, opcode)
    log.info("WebSocket接收处理", "收到数据", data, "是否结束", fin, "操作码", opcode)
    sys.publish("FEED_NETWORK_WATCHDOG")
    recv_data_buff = recv_data_buff .. data

    if fin == 1 and #recv_data_buff > 0 then
        local processed_data = recv_data_buff
        recv_data_buff = ""
        local ok, json_data = pcall(json.decode, processed_data)
        if ok and json_data and type(json_data) == "table" then
            log.info("WebSocket接收处理", "收到JSON格式数据")
        else
            if not ok then
                log.warn("WebSocket接收处理", "JSON解析失败，原始数据:", processed_data)
            else
                log.info("WebSocket接收处理", "收到非JSON格式数据")
            end
        end
        sys.publish("RECV_DATA_FROM_SERVER", "收到WebSocket服务器数据: ", processed_data)
        local log_content = "收到服务器数据: " .. processed_data:sub(1, 30)
        if #processed_data > 30 then log_content = log_content .. "..." end
        sys.publish("WEBSOCKET_LOG_ADD", "debug", log_content)
    end
end

-- ============================================================================
-- websocket_sender
-- ============================================================================
local send_queue = {}
local TASK_NAME_PREFIX = "websocket_"
local SENDER_TASK_NAME = TASK_NAME_PREFIX.."sender"

local function send_data_req_proc_func(tag, data, cb)
    local data_str = tostring(data)
    if data_str == '"echo"' then
        local response = json.encode({ action = "echo", msg = os.date("%a %Y-%m-%d %H:%M:%S") })
        table.insert(send_queue, {data=response, cb=cb})
    else
        if tag == "timer" then
            log.info("发送心跳", "长度", #data_str)
        else
            log.info("准备发送数据到服务器", "长度", #data_str)
        end
        table.insert(send_queue, {data=data_str, cb=cb})
    end
    sys.sendMsg(SENDER_TASK_NAME, "WEBSOCKET_EVENT", "SEND_REQ")
end

local function send_item(ws_client)
    while #send_queue > 0 do
        local item = table.remove(send_queue, 1)
        if not ws_client or not ws_client:ready() then
            if item.cb and item.cb.func then item.cb.func(false, item.cb.para) end
            sys.sendMsg(SENDER_TASK_NAME, "WEBSOCKET_EVENT", "DISCONNECTED")
            return nil
        end
        local result = ws_client:send(item.data)
        if result then
            if item.data:match("^%d+$") then
                log.info("wbs_sender", "发送心跳成功", "长度", #item.data)
                sys.publish("WEBSOCKET_LOG_ADD", "debug", "发送心跳: " .. item.data)
            else
                log.info("wbs_sender", "发送成功", "长度", #item.data)
                sys.publish("WEBSOCKET_LOG_ADD", "info", "发送数据: " .. item.data:sub(1, 30))
            end
            if item.cb and item.cb.func then item.cb.func(true, item.cb.para) end
            sys.publish("FEED_NETWORK_WATCHDOG")
            return item
        else
            log.warn("wbs_sender", "发送失败")
            sys.publish("WEBSOCKET_LOG_ADD", "error", "发送失败")
            if item.cb and item.cb.func then item.cb.func(false, item.cb.para) end
            sys.sendMsg(SENDER_TASK_NAME, "WEBSOCKET_EVENT", "DISCONNECTED")
            return nil
        end
    end
    return nil
end

local function websocket_client_sender_task_func()
    local ws_client
    while true do
        local msg = sys.waitMsg(SENDER_TASK_NAME, "WEBSOCKET_EVENT")
        if msg[2] == "CONNECT_OK" then
            ws_client = msg[3]
            while #send_queue > 0 do
                if not send_item(ws_client) then break end
            end
        elseif msg[2] == "SEND_REQ" then
            if ws_client then send_item(ws_client) end
        elseif msg[2] == "SEND_OK" then
            if ws_client then send_item(ws_client) end
        elseif msg[2] == "DISCONNECTED" then
            ws_client = nil
            while #send_queue > 0 do
                local item = table.remove(send_queue, 1)
                if item.cb and item.cb.func then item.cb.func(false, item.cb.para) end
            end
        end
    end
end

sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func)
sys.taskInitEx(websocket_client_sender_task_func, SENDER_TASK_NAME)

-- ============================================================================
-- timer_app (修正：确保旧定时器被停止)
-- ============================================================================
local HEARTBEAT_INTERVAL = 30   -- 与 UI 默认值保持一致
local heartbeat_timer = nil
local heartbeat_counter = 1

local function send_heartbeat()
    if not _G.websocket_connected then
        log.info("timer_app", "未连接，跳过心跳")
        return
    end
    local data = heartbeat_counter
    heartbeat_counter = heartbeat_counter + 1
    sys.publish("SEND_DATA_REQ", "timer", data, {
        func = function(result)
            if result then
                log.info("timer_app", "心跳发送成功", data)
                sys.publish("WEBSOCKET_LOG_ADD", "debug", "心跳发送成功: " .. data)
            else
                log.warn("timer_app", "心跳发送失败", data)
                sys.publish("WEBSOCKET_LOG_ADD", "warn", "心跳发送失败: " .. data)
            end
        end
    })
end

local function start_heartbeat(interval)
    if heartbeat_timer then
        sys.timerStop(heartbeat_timer)
        heartbeat_timer = nil
        log.info("timer_app", "已停止旧心跳定时器")
    end
    heartbeat_timer = sys.timerLoopStart(send_heartbeat, interval * 1000)
    log.info("timer_app", "心跳定时器已启动，间隔：" .. interval .. "秒")
end

start_heartbeat(HEARTBEAT_INTERVAL)

local function on_config_updated(new_config)
    if new_config and new_config.heartbeat_interval then
        local new_interval = tonumber(new_config.heartbeat_interval) or 60
        if new_interval ~= HEARTBEAT_INTERVAL then
            log.info("timer_app", "心跳间隔从 " .. HEARTBEAT_INTERVAL .. " 秒更新为 " .. new_interval .. " 秒")
            HEARTBEAT_INTERVAL = new_interval
            start_heartbeat(HEARTBEAT_INTERVAL)
        else
            log.info("timer_app", "心跳间隔未变化，保持：" .. HEARTBEAT_INTERVAL)
        end
    end
end
sys.subscribe("WS_CONFIG_UPDATED", on_config_updated)

-- ============================================================================
-- websocket_main (保持之前的长延时重连版本，不主动close)
-- ============================================================================
local ws_config = {
    server_url = "wss://echo.airtun.air32.cn/ws/echo",
    reconnect_interval = 5,
    max_reconnect = 5,
    heartbeat_interval = 60,
    connect_timeout = 10,
    response_timeout = 5
}
local MAIN_TASK_NAME = TASK_NAME_PREFIX.."main"
local reconnect_requested = false
local current_reconnect_count = 0

local function add_log(log_type, content)
    if type(content) ~= "string" then content = tostring(content) or "" end
    if #content > 100 then content = string.sub(content, 1, 97) .. "..." end
    sys.publish("WEBSOCKET_LOG_ADD", log_type, content)
end

local function on_config_updated_main(new_config)
    if new_config then
        if new_config.server_url then ws_config.server_url = new_config.server_url end
        if new_config.reconnect_interval then ws_config.reconnect_interval = new_config.reconnect_interval end
        if new_config.max_reconnect then ws_config.max_reconnect = new_config.max_reconnect end
        if new_config.heartbeat_interval then ws_config.heartbeat_interval = new_config.heartbeat_interval end
        if new_config.connect_timeout then ws_config.connect_timeout = new_config.connect_timeout end
        if new_config.response_timeout then ws_config.response_timeout = new_config.response_timeout end
        reconnect_requested = true
        sys.sendMsg(MAIN_TASK_NAME, "WEBSOCKET_EVENT", "CLOSE")
    end
end

local function websocket_client_event_cbfunc(ws_client, event, data, fin, opcode)
    if event == "conack" then
        log.info("WebSocket事件回调", "连接成功")
        sys.sendMsg(MAIN_TASK_NAME, "WEBSOCKET_EVENT", "CONNECT", true)
        sys.publish("WEBSOCKET_EVENT", "CONNECT", true)
        _G.websocket_connected = true
        current_reconnect_count = 0
        add_log("info", "WebSocket连接成功")
    elseif event == "recv" then
        websocket_receiver_proc(data, fin, opcode)
        add_log("debug", "收到服务器数据: " .. tostring(data):sub(1, 30))
    elseif event == "sent" then
        sys.sendMsg(SENDER_TASK_NAME, "WEBSOCKET_EVENT", "SEND_OK", data)
    elseif event == "disconnect" then
        log.info("WebSocket事件回调", "服务器断开连接")
        sys.sendMsg(MAIN_TASK_NAME, "WEBSOCKET_EVENT", "DISCONNECTED", false)
        sys.publish("WEBSOCKET_EVENT", "DISCONNECTED", false)
        _G.websocket_connected = false
        add_log("warn", "WebSocket连接断开")
    elseif event == "error" then
        log.error("WebSocket错误", "错误类型:", data)
        _G.websocket_connected = false
        add_log("error", "WebSocket错误: " .. tostring(data))
        sys.sendMsg(MAIN_TASK_NAME, "WEBSOCKET_EVENT", "ERROR")
        sys.publish("WEBSOCKET_EVENT", "ERROR")
    end
end

local function websocket_client_main_task_func()
    local ws_client

    while true do
        while not socket.adapter(socket.dft()) do
            sys.waitUntil("IP_READY", 1000)
        end

        sys.cleanMsg(MAIN_TASK_NAME)

        ws_client = websocket.create(nil, ws_config.server_url)
        if not ws_client then
            log.error("WebSocket主任务", "创建失败")
            goto reconnect
        end

        ws_client:on(websocket_client_event_cbfunc)
        if not ws_client:connect() then
            log.error("WebSocket主任务", "连接失败")
            goto reconnect
        end

        while true do
            local msg = sys.waitMsg(MAIN_TASK_NAME, "WEBSOCKET_EVENT")
            if msg[2] == "CONNECT" then
                if msg[3] then
                    log.info("WebSocket主任务", "连接成功")
                    sys.sendMsg(SENDER_TASK_NAME, "WEBSOCKET_EVENT", "CONNECT_OK", ws_client)
                else
                    break
                end
            elseif msg[2] == "CLOSE" then
                log.info("WebSocket主任务", "收到CLOSE指令，等待旧连接释放")
                -- 取消回调，防止关闭过程中触发事件
                if ws_client then
                    pcall(ws_client.on, ws_client, nil)
                end
                sys.wait(3000)
                break
            elseif msg[2] == "DISCONNECTED" or msg[2] == "ERROR" then
                break
            end
        end

        ::reconnect::
        sys.cleanMsg(MAIN_TASK_NAME)
        sys.sendMsg(SENDER_TASK_NAME, "WEBSOCKET_EVENT", "DISCONNECTED")
        if ws_client then
            ws_client = nil
            sys.wait(2000)
        end

        local wait_time = ws_config.reconnect_interval * 1000
        if reconnect_requested then
            wait_time = math.max(wait_time, 5000)
            reconnect_requested = false
            current_reconnect_count = 0
            log.info("WebSocket主任务", "配置更新，等待" .. (wait_time/1000) .. "秒后重连")
        else
            current_reconnect_count = current_reconnect_count + 1
            if current_reconnect_count >= ws_config.max_reconnect then
                log.error("WebSocket主任务", "达到最大重连次数，等待配置更新")
                add_log("error", "达到最大重连次数，停止重连")
                sys.publish("WEBSOCKET_EVENT", "CONNECT", false)
                while not reconnect_requested do
                    sys.waitUntil("WS_CONFIG_UPDATED", 5000)
                end
                current_reconnect_count = 0
                reconnect_requested = false
            end
        end

        local seconds = math.ceil(wait_time / 1000)
        for i = 1, seconds do
            sys.wait(1000)
            sys.publish("FEED_NETWORK_WATCHDOG")
        end
    end
end

sys.subscribe("WS_CONFIG_UPDATED", on_config_updated_main)
sys.taskInitEx(websocket_client_main_task_func, MAIN_TASK_NAME)

log.info("websocket_app", "模块已加载（心跳定时器修正版）")