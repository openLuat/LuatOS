--[[
@module  mqtt_sender
@summary MQTT发送队列模块（双队列：实时+补传）
@version 1.0
@date    2026.09.04
@author  江访
@usage
本模块为MQTT发送队列模块，负责：
1、接收其他模块的发送请求，存入发送队列
2、在MQTT连接成功后按顺序发送队列中的数据
3、断开连接时保留队列（不清空），复网后自动补发
4、采用双队列机制：实时队列 + 补传队列，实时优先

断网瞬间：realtime_queue 数据全部移到 hist_queue
断网期间：新数据存入 hist_queue
复网后：先发 realtime_queue（新数据），再发 hist_queue（历史数据）
]]

local mqtt_sender = {}

-- 模块名称标识
mqtt_sender.TASK_NAME = "mqtt_sender"

-- 双队列：实时队列 + 补传队列
local realtime_queue = {}
local hist_queue = {}

-- 队列上限
local MAX_QUEUE_SIZE = 500

-- 当前正在发送的数据项
local sending_item = nil

-- MQTT客户端引用
local mqtt_client = nil

-- MQTT在线状态标记
local is_online = false

--[[
@function publish_item
@summary 发送队列中的一项数据（实时优先）
@param client userdata MQTT客户端对象
@return table|nil 发送的数据项
]]
local function publish_item(client)
    -- 先发高优先级队列（实时数据）
    while #realtime_queue > 0 do
        local item = table.remove(realtime_queue, 1)
        log.info(mqtt_sender.TASK_NAME, "send realtime", "q:", #realtime_queue, "topic:", item.topic)
        local result = client:publish(item.topic, item.payload, item.qos or 0)
        if result then
            sending_item = item
            return item
        else
            log.warn(mqtt_sender.TASK_NAME, "publish failed, notify")
            if item.cb and item.cb.func then
                item.cb.func(false, item.cb.para)
            end
        end
    end

    -- 高优先级发完，发低优先级队列（补传数据）
    while #hist_queue > 0 do
        local item = table.remove(hist_queue, 1)
        log.info(mqtt_sender.TASK_NAME, "send hist", "q:", #hist_queue, "topic:", item.topic)
        local result = client:publish(item.topic, item.payload, item.qos or 0)
        if result then
            sending_item = item
            return item
        else
            log.warn(mqtt_sender.TASK_NAME, "publish failed, notify")
            if item.cb and item.cb.func then
                item.cb.func(false, item.cb.para)
            end
        end
    end
end

--[[
@function notify_result
@summary 通知发送结果
@param item table 发送数据项
@param result boolean 发送结果
@return nil
]]
local function notify_result(item, result)
    if item and item.cb and item.cb.func then
        item.cb.func(result, item.cb.para)
    end
end

--[[
@function mqtt_sender_task
@summary MQTT发送任务
@return nil
]]
local function mqtt_sender_task()
    local msg
    while true do
        msg = sys.waitMsg(mqtt_sender.TASK_NAME, "MQTT_EVENT")
        if msg then
            if msg[2] == "CONNECT_OK" then
                mqtt_client = msg[3]
                is_online = true
                log.info(mqtt_sender.TASK_NAME, "CONNECT_OK, start sending",
                    "realtime:", #realtime_queue, "hist:", #hist_queue)
                publish_item(mqtt_client)
            elseif msg[2] == "PUBLISH_REQ" then
                if mqtt_client and not sending_item then
                    publish_item(mqtt_client)
                end
            elseif msg[2] == "PUBLISH_OK" then
                log.info(mqtt_sender.TASK_NAME, "PUBLISH_OK")
                notify_result(sending_item, true)
                sending_item = nil
                publish_item(mqtt_client)
            elseif msg[2] == "DISCONNECTED" then
                mqtt_client = nil
                is_online = false
                notify_result(sending_item, false)
                sending_item = nil
                log.info(mqtt_sender.TASK_NAME, "DISCONNECTED, queue preserved",
                    "realtime:", #realtime_queue, "hist:", #hist_queue)
            elseif msg[2] == "MOVE_TO_HIST" then
                -- 断网瞬间，把 realtime_queue 全部移到 hist_queue
                while #realtime_queue > 0 do
                    local item = table.remove(realtime_queue, 1)
                    table.insert(hist_queue, item)
                end
                log.info(mqtt_sender.TASK_NAME, "MOVE_TO_HIST done",
                    "realtime:", #realtime_queue, "hist:", #hist_queue)
            end
        end
    end
end

--[[
@function send_data_req_proc
@summary 处理发送请求
@param tag string 发送来源标识
@param topic string 主题
@param payload string 负载数据
@param qos number QoS等级
@param cb table 回调函数 {func=function, para=any}
@return nil
]]
local function send_data_req_proc(tag, topic, payload, qos, cb)
    log.info(mqtt_sender.TASK_NAME, "send_req:", tag, topic)

    local item = {
        topic = topic,
        payload = payload,
        qos = qos or 0,
        cb = cb
    }

    -- 根据在线状态决定加入哪个队列
    if is_online then
        table.insert(realtime_queue, item)
        log.info(mqtt_sender.TASK_NAME, "enqueued to realtime",
            "realtime:", #realtime_queue, "hist:", #hist_queue)
    else
        table.insert(hist_queue, item)
        log.info(mqtt_sender.TASK_NAME, "enqueued to hist",
            "realtime:", #realtime_queue, "hist:", #hist_queue)
    end

    -- 队列超限，删除最旧数据（FIFO）
    while #realtime_queue + #hist_queue > MAX_QUEUE_SIZE do
        if #realtime_queue > 0 then
            table.remove(realtime_queue, 1)
            log.warn(mqtt_sender.TASK_NAME, "queue full, drop oldest realtime")
        else
            table.remove(hist_queue, 1)
            log.warn(mqtt_sender.TASK_NAME, "queue full, drop oldest hist")
        end
    end

    -- 触发发送
    sys.sendMsg(mqtt_sender.TASK_NAME, "MQTT_EVENT", "PUBLISH_REQ")
end

-- 订阅发送请求事件
sys.subscribe("SEND_DATA_REQ", send_data_req_proc)

-- 启动发送任务
sys.taskInitEx(mqtt_sender_task, mqtt_sender.TASK_NAME)

return mqtt_sender
