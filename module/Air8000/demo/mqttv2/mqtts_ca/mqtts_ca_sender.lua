--[[
@module  mqttt_ca_sender
@summary mqtts ca client数据发送应用功能模块 
@version 1.0
@date    2025.07.29
@author  朱天华
@usage
本文件为mqtts ca client 数据发送应用功能模块，核心业务逻辑为：
1、sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func)订阅"SEND_DATA_REQ"消息，将其他应用模块需要发送的数据存储到队列send_queue中；
2、mqtts ca sender task接收"CONNECT OK"、"PUBLISH_REQ"、"PUBLISH OK"三种类型的"MQTT_EVENT"消息，遍历队列send_queue，逐条发送数据到server；
3、mqtts ca sender task接收"DISCONNECTED"类型的"MQTT_EVENT"消息，丢弃掉队列send_queue中未发送的数据；
4、任何一条数据无论发送成功还是失败，只要这条数据有回调函数，都会通过回调函数通知数据发送方；

本文件的对外接口有1个：
1、sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func)：订阅"SEND_DATA_REQ"消息；
   其他应用模块如果需要发送数据，直接sys.publish这个消息即可，将需要发送的topic，payload和qos以及回调函数和回调参数一起publish出去；
   本demo项目中uart_app.lua和timer_app.lua中publish了这个消息；
]]

local mqtts_ca_sender = {}

--[[
数据发送队列，数据结构为：
{
    [1] = {topic="topic1", payload="payload1", qos=0, cb={func=callback_function1, para=callback_para1}},
    [2] = {topic="topic2", payload="payload2", qos=1, cb={func=callback_function2, para=callback_para2}},
    [3] = {topic="topic3", payload="payload3", qos=2, cb={func=callback_function3, para=callback_para3}},
}
topic的内容为publish的主题，string类型，必须存在；
payload的内容为publish的负载数据，string类型，必须存在；
qos的内容为publish的质量等级，number类型，取值范围0,1,2，可选，如果用户没有指定，默认为0；
cb.func的内容为数据发送结果的用户回调函数，可以不存在；
cb.para的内容为数据发送结果的用户回调函数的回调参数，可以不存在；
]]
local send_queue = {}

-- mqtts ca client的任务名前缀
mqtts_ca_sender.TASK_NAME_PREFIX = "mqtts_ca_"

-- mqtts_ca_client_sender的任务名
mqtts_ca_sender.TASK_NAME = mqtts_ca_sender.TASK_NAME_PREFIX.."sender"

-- "SEND_DATA_REQ"消息的处理函数
local function send_data_req_proc_func(tag, topic, payload, qos, cb)
    -- 将原始数据增加前缀，然后插入到发送队列send_queue中
    table.insert(send_queue, {topic=topic, payload="send from "..tag..": "..payload, qos=qos or 0, cb=cb})
    -- 发送消息通知 mqtts ca sender task，有新数据等待发送
    sysplus.sendMsg(mqtts_ca_sender.TASK_NAME, "MQTT_EVENT", "PUBLISH_REQ")
end

-- 按照顺序发送send_queue中的数据
-- 如果调用publish接口成功，则返回当前正在发送的数据项
-- 如果调用publish接口失败，通知回调函数发送失败后，继续发送下一条数据
local function publish_item(mqtt_client)
    local item
    -- 如果发送队列中有数据等待发送
    while #send_queue>0 do
        -- 取出来第一条数据赋值给item
        -- 同时从队列send_queue中删除这一条数据
        item = table.remove(send_queue, 1)

        -- publish数据
        -- result表示调用publish接口的同步结果，返回值有以下几种：
        -- 如果失败，返回nil
        -- 如果成功，number类型，qos为0时直接返回0；qos为1或者2时返回publish报文的message id
        result = mqtt_client:publish(item.topic, item.payload, item.qos)

        -- publish接口调用成功
        if result then
            return item
        -- publish接口调用失败
        else
            -- 如果当前发送的数据有用户回调函数，则执行用户回调函数
            if item.cb and item.cb.func then
                item.cb.func(false, item.cb.para)
            end
        end
    end
end


local function publish_item_cbfunc(item, result)
    if item then
        -- 如果当前发送的数据有用户回调函数，则执行用户回调函数
        if item.cb and item.cb.func then
            item.cb.func(result, item.cb.para)
        end
    end
end

-- mqtts_ca client sender的任务处理函数
local function mqtts_ca_client_sender_task_func() 

    local mqtt_client
    local send_item
    local result, msg

    while true do
        -- 等待"MQTT_EVENT"消息
        msg = sysplus.waitMsg(mqtts_ca_sender.TASK_NAME, "MQTT_EVENT")

        -- mqtt连接成功
        -- msg[3]表示mqtt client对象
        if msg[2] == "CONNECT_OK" then
            mqtt_client = msg[3]
            -- 发送send_queue中的数据
            send_item = publish_item(mqtt_client)
        -- mqtt publish数据请求
        elseif msg[2] == "PUBLISH_REQ" then
            -- 如果mqtt client对象存在，并且没有正在等待发送结果的发送数据项
            if mqtt_client and not send_item then
                -- 发送send_queue中的数据
                send_item = publish_item(mqtt_client)
            end
        -- mqtt publish数据成功
        elseif msg[2] == "PUBLISH_OK" then
            -- publish成功，执行回调函数通知发送方
            publish_item_cbfunc(send_item, true)
            -- publish成功，通知网络环境检测看门狗功能模块进行喂狗
            sys.publish("FEED_NETWORK_WATCHDOG")
            -- 发送send_queue中的数据
            send_item = publish_item(mqtt_client)
        -- mqtt断开连接
        elseif msg[2] == "DISCONNECTED" then
            -- 清空mqtt client对象
            mqtt_client = nil
            -- 如果存在正在等待发送结果的发送项，执行回调函数通知发送方失败
            publish_item_cbfunc(send_item, false)
            -- 如果发送队列中有数据等待发送
            while #send_queue>0 do
                -- 取出来第一条数据赋值给send_item
                -- 同时从队列send_queue中删除这一条数据
                send_item = table.remove(send_queue,1)
                -- 执行回调函数通知发送方失败
                publish_item_cbfunc(send_item, false)
            end
            -- 当前没有正在等待发送结果的发送项
            send_item = nil
        end
    end
end


-- 订阅"SEND_DATA_REQ"消息；
-- 其他应用模块如果需要发送数据，直接sys.publish这个消息即可，将需要发送的数据以及回调函数和回调参数一起publish出去；
-- 本demo项目中uart_app.lua和timer_app.lua中publish了这个消息；
sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func)


--创建并且启动一个task
--运行这个task的处理函数mqtts_ca_client_sender_task_func
sysplus.taskInitEx(mqtts_ca_client_sender_task_func, mqtts_ca_sender.TASK_NAME)

return mqtts_ca_sender
