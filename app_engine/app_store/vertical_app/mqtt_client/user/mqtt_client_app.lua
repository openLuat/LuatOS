--[[
@module  mqtt_client_app
@summary MQTT 多客户端管理器 业务逻辑模块
@version 1.0.0
@date    2026.05.19
@usage
本模块负责 MQTT 连接管理、发布队列、接收分发。
]]
-- ========================================
-- 常量定义
-- ========================================
local MAX_RECONNECT_DELAY = 5000       -- 重连间隔 5 秒

-- ========================================
-- 模块级变量
-- ========================================
local clients = {}                     -- { [index]={connected, mqtt_obj, task_id} }
local subs = {}                        -- { [index]={{topic="/t1", qos=0}, ...} }
local send_queues = {}                 -- { [index]={{topic, payload, qos, cb}, ...} }
local pending_items = {}               -- { [index]=item } 当前正在发送的项

-- ========================================
-- A. 接收数据处理
-- ========================================
local function proc_recv(index, topic, payload)
    -- 写入日志到 UI
    sys.publish("MQTT_LOG", {
        index = index,
        log_type = "receive",
        text = "RECV <- " .. topic .. ": " .. (payload or "")
    })
    -- 分发数据给其他模块
    sys.publish("MQTT_RECV_DATA", {index = index, topic = topic, payload = payload})
end

-- ========================================
-- B. 发送队列管理
-- ========================================
local function publish_item(mqtt_client, index)
    local queue = send_queues[index]
    if not queue then return nil end

    local item
    while #queue > 0 do
        item = table.remove(queue, 1)
        local result = mqtt_client:publish(item.topic, item.payload, item.qos)
        if result then
            return item
        else
            -- 发布失败，执行回调通知
            if item.cb and item.cb.func then
                item.cb.func(false, item.cb.para)
            end
        end
    end
    return nil
end

-- 发送任务函数
local function sender_task_func(task_name, index)
    local mqtt_client
    local send_item
    local result, msg

    while true do
        msg = sys.waitMsg(task_name, "MQTT_EVENT")
        if not msg then
            sys.wait(100)
        elseif msg[2] == "CONNECT_OK" then
            mqtt_client = msg[3]
            send_item = publish_item(mqtt_client, index)
        elseif msg[2] == "PUBLISH_REQ" then
            if mqtt_client and not send_item then
                send_item = publish_item(mqtt_client, index)
            end
        elseif msg[2] == "PUBLISH_OK" then
            if send_item and send_item.cb and send_item.cb.func then
                send_item.cb.func(true, send_item.cb.para)
            end
            send_item = publish_item(mqtt_client, index)
        elseif msg[2] == "DISCONNECTED" then
            mqtt_client = nil
            -- 清理待发送队列
            local queue = send_queues[index]
            if queue then
                while #queue > 0 do
                    local i = table.remove(queue, 1)
                    if i.cb and i.cb.func then
                        i.cb.func(false, i.cb.para)
                    end
                end
            end
            send_item = nil
        end
    end
end

-- ========================================
-- C. 事件回调工厂
-- ========================================
local function make_event_callback(client_index)
    local task_name = "mqtt_main_" .. client_index
    local sender_task_name = "mqtt_sender_" .. client_index

    return function(mqtt_client, event, data, payload, metas)
        -- conack: 连接成功
        if event == "conack" then
            sys.sendMsg(task_name, "MQTT_EVENT", "CONNECT", true)
            -- 自动重订阅
            local client_subs = subs[client_index] or {}
            if #client_subs > 0 then
                local subs_table = {}
                for i = 1, #client_subs do
                    local s = client_subs[i]
                    subs_table[s.topic] = s.qos
                end
                mqtt_client:subscribe(subs_table)
            end
        -- suback: 订阅结果
        elseif event == "suback" then
            sys.sendMsg(task_name, "MQTT_EVENT", "SUBSCRIBE", data, payload)
        -- recv: 接收数据
        elseif event == "recv" then
            proc_recv(client_index, data, payload)
        -- sent: 发布成功
        elseif event == "sent" then
            sys.sendMsg(sender_task_name, "MQTT_EVENT", "PUBLISH_OK", data)
        -- disconnect: 服务器断开
        elseif event == "disconnect" then
            sys.sendMsg(task_name, "MQTT_EVENT", "DISCONNECTED", false)
        -- pong: 心跳应答
        elseif event == "pong" then
            sys.publish("MQTT_LOG", {
                index = client_index,
                log_type = "system",
                text = "PONG (keepalive)"
            })
        -- error: 异常
        elseif event == "error" then
            if data == "connect" or data == "conack" then
                sys.sendMsg(task_name, "MQTT_EVENT", "CONNECT", false)
            else
                sys.sendMsg(task_name, "MQTT_EVENT", "ERROR")
            end
        end
    end
end

-- ========================================
-- D. 客户端主任务
-- ========================================
local function client_task_func(index)
    local task_name = "mqtt_main_" .. index
    local sender_task_name = "mqtt_sender_" .. index
    local client = clients[index]
    local mqtt_client
    local result, msg

    while true do
        -- 等待网络就绪
        while not socket.adapter(socket.dft()) do
            sys.waitUntil("IP_READY", 1000)
        end
        sys.cleanMsg(task_name)

        -- 创建 mqtt 对象
        mqtt_client = mqtt.create(nil, client.host, tonumber(client.port))
        if not mqtt_client then
            sys.publish("MQTT_LOG", {index = index, log_type = "error", text = "mqtt.create 失败"})
            goto EXCEPTION
        end

        -- 认证
        result = mqtt_client:auth(client.client_id, client.user, client.password, true)
        if not result then
            sys.publish("MQTT_LOG", {index = index, log_type = "error", text = "mqtt:auth 失败"})
            goto EXCEPTION
        end

        -- 遗嘱消息（主题非空时设置）
        if client.will_topic and client.will_topic ~= "" then
            mqtt_client:will(client.will_topic, client.will_payload,
                tonumber(client.will_qos) or 0,
                client.will_retain or false)
        end

        -- 注册回调
        mqtt_client:on(make_event_callback(index))

        -- 设置心跳间隔（单位：秒）
        mqtt_client:keepalive(tonumber(client.keepalive) or 240)

        -- 连接
        result = mqtt_client:connect()
        if not result then
            sys.publish("MQTT_LOG", {index = index, log_type = "error", text = "mqtt:connect 失败"})
            goto EXCEPTION
        end

        -- 连接成功通知
        client.connected = true
        client.mqtt_obj = mqtt_client
        sys.publish("MQTT_STATUS", {index = index, connected = true})
        sys.publish("MQTT_LOG", {index = index, log_type = "system", text = "连接成功 " .. client.host .. ":" .. client.port})

        -- 通知 sender 连接就绪
        sys.sendMsg(sender_task_name, "MQTT_EVENT", "CONNECT_OK", mqtt_client)

        -- 事件循环
        while true do
            msg = sys.waitMsg(task_name, "MQTT_EVENT")
            if not msg then
                sys.wait(100)
            elseif msg[2] == "CONNECT" then
                if not msg[3] then break end
            elseif msg[2] == "SUBSCRIBE" then
                if not msg[3] then
                    mqtt_client:disconnect()
                    sys.wait(1000)
                    break
                end
            elseif msg[2] == "CLOSE" then
                mqtt_client:disconnect()
                sys.wait(1000)
                break
            elseif msg[2] == "DISCONNECTED" then
                break
            elseif msg[2] == "ERROR" then
                break
            end
        end

        ::EXCEPTION::
        client.connected = false
        client.mqtt_obj = nil
        sys.publish("MQTT_STATUS", {index = index, connected = false})
        sys.cleanMsg(task_name)
        sys.sendMsg(sender_task_name, "MQTT_EVENT", "DISCONNECTED")

        if mqtt_client then
            mqtt_client:close()
            mqtt_client = nil
        end

        -- 检查是否自动重连（手动断开时 auto_reconnect = false）
        if not client.auto_reconnect then
            -- 手动断开，退出重连循环
            break
        end
        -- 自动重连，等待后继续
        sys.wait(MAX_RECONNECT_DELAY)
    end
end

-- ========================================
-- E. 启动客户端
-- ========================================
local function start_client(index)
    -- 启动 sender 协程
    local sender_task_name = "mqtt_sender_" .. index
    sys.taskInitEx(function() sender_task_func(sender_task_name, index) end, sender_task_name)
    -- 启动 main 协程
    local main_task_name = "mqtt_main_" .. index
    sys.taskInitEx(function() client_task_func(index) end, main_task_name)
end

-- ========================================
-- F. 事件订阅
-- ========================================
sys.subscribe("MQTT_CONNECT", function(data)
    local index = data.index
    if not clients[index] then return end
    if clients[index].connected then
        sys.publish("MQTT_LOG", {index = index, log_type = "error", text = "已在连接状态"})
        return
    end
    -- 重置为自动重连模式
    clients[index].auto_reconnect = true
    start_client(index)
end)

sys.subscribe("MQTT_DISCONNECT", function(data)
    local index = data.index
    if not clients[index] then return end
    -- 标记为手动断开，不自动重连
    clients[index].auto_reconnect = false
    sys.sendMsg("mqtt_main_" .. index, "MQTT_EVENT", "CLOSE")
end)

sys.subscribe("MQTT_PUBLISH", function(data)
    local index = data.index
    if not clients[index] then return end
    if not send_queues[index] then
        send_queues[index] = {}
    end
    table.insert(send_queues[index], {
        topic = data.topic,
        payload = data.payload,
        qos = data.qos or 0,
        cb = data.cb
    })
    sys.sendMsg("mqtt_sender_" .. index, "MQTT_EVENT", "PUBLISH_REQ")
    sys.publish("MQTT_LOG", {
        index = index,
        log_type = "send",
        text = "SEND -> " .. data.topic .. " Q" .. (data.qos or 0) .. ": " .. (data.payload or "")
    })
end)

sys.subscribe("MQTT_SUBSCRIBE", function(data)
    local index = data.index
    local client_subs = subs[index]
    if not client_subs then
        client_subs = {}
        subs[index] = client_subs
    end
    -- 去重
    for i = 1, #client_subs do
        if client_subs[i].topic == data.topic then
            sys.publish("MQTT_LOG", {index = index, log_type = "error", text = "订阅失败: 主题 " .. data.topic .. " 已存在"})
            return
        end
    end
    table.insert(client_subs, {topic = data.topic, qos = data.qos or 0})
    -- 如果已连接，立即发送 subscribe
    if clients[index] and clients[index].connected and clients[index].mqtt_obj then
        clients[index].mqtt_obj:subscribe(data.topic, data.qos or 0)
    end
    sys.publish("MQTT_SUB_LIST_CHANGE", {index = index, subs = client_subs})
    sys.publish("MQTT_LOG", {index = index, log_type = "system", text = "订阅: " .. data.topic .. " (Q" .. (data.qos or 0) .. ")"})
end)

sys.subscribe("MQTT_UNSUBSCRIBE", function(data)
    local index = data.index
    local client_subs = subs[index]
    if not client_subs then return end
    for i = 1, #client_subs do
        if client_subs[i].topic == data.topic then
            table.remove(client_subs, i)
            if clients[index] and clients[index].connected and clients[index].mqtt_obj then
                clients[index].mqtt_obj:unsubscribe(data.topic)
            end
            sys.publish("MQTT_SUB_LIST_CHANGE", {index = index, subs = client_subs})
            sys.publish("MQTT_LOG", {index = index, log_type = "system", text = "取消订阅: " .. data.topic})
            break
        end
    end
end)

sys.subscribe("MQTT_NEW_CLIENT", function(data)
    local index = data.index
    clients[index] = {
        connected = false,
        mqtt_obj = nil,
        auto_reconnect = true,  -- 自动重连模式
        host = data.host or "",
        port = data.port or 1884,
        client_id = data.client_id or "",
        user = data.user or "",
        password = data.password or "",
        will_topic = data.will_topic or "",
        will_payload = data.will_payload or "",
        will_qos = data.will_qos or 0,
        will_retain = data.will_retain or false,
        keepalive = data.keepalive or 240
    }
    subs[index] = {}
    send_queues[index] = {}
end)

sys.subscribe("MQTT_DEL_CLIENT", function(data)
    local index = data.index
    if clients[index] and clients[index].connected then
        sys.sendMsg("mqtt_main_" .. index, "MQTT_EVENT", "CLOSE")
    end
    clients[index] = nil
    subs[index] = nil
    send_queues[index] = nil
end)

-- 同步客户端配置（win 保存配置时调用）
sys.subscribe("MQTT_SYNC_CLIENT", function(data)
    local index = data.index
    if not clients[index] then return end
    clients[index].host = data.host or ""
    clients[index].port = data.port or 1884
    clients[index].client_id = data.client_id or ""
    clients[index].user = data.user or ""
    clients[index].password = data.password or ""
    clients[index].will_topic = data.will_topic or ""
    clients[index].will_payload = data.will_payload or ""
    clients[index].will_qos = data.will_qos or 0
    clients[index].will_retain = data.will_retain or false
    clients[index].keepalive = data.keepalive or 240
end)

log.info("mqtt_client_app", "模块加载完成")
