--[[
@module  mqtt_ipv6
@summary mqtt client使用IPv6连接服务器示例
@version 1.0
@date    2026.08.27
@author  拓毅恒
@usage

注意：
服务器使用合宙官方MQTT测试服务器lbsmqtt.airm2m.com:1884，仅用于测试，如需商用更换为自己的服务器地址和端口

本文件为mqtt client优先使用IPv6连接服务器的应用功能模块，核心业务逻辑为：
1、等待ipv6_info发布IPV6_READY消息后，创建mqtt client
2、连接服务器，成功后自动订阅下行主题mobile.imei().."/down"
3、定时器每5秒向mobile.imei().."/timer/up"发布一条 "Hello world"
4、收到服务器下发的数据（发到mobile.imei().."/down"）时打印日志
5、连接断开或异常后自动重连（5秒）

本文件没有对外接口，直接在main.lua中require "mqtt_ipv6"就可以加载运行；
]]

-- mqtt 服务器地址和端口
local SERVER_ADDR = "lbsmqtt.airm2m.com"
local SERVER_PORT = 1884

-- mqtt 任务名前缀和 main task 的任务名
local mqtt_sender = {}
mqtt_sender.TASK_NAME_PREFIX = "mqtt_"
mqtt_sender.TASK_NAME = mqtt_sender.TASK_NAME_PREFIX.."sender"
local TASK_NAME = mqtt_sender.TASK_NAME_PREFIX.."main"

-- mqtt 主题的前缀：IMEI 号
local TOPIC_PREFIX = mobile.imei()

-- ============================ 数据发送 ============================
local send_queue = {}

-- 订阅"SEND_DATA_REQ"消息，将其他模块需要发送的数据加入发送队列
local function send_data_req_proc_func(tag, topic, payload, qos, cb)
    table.insert(send_queue, {topic=topic, payload="send from "..tag..": "..payload, qos=qos or 0, cb=cb})
    sys.sendMsg(mqtt_sender.TASK_NAME, "MQTT_EVENT", "PUBLISH_REQ")
end

-- 依次发送发送队列中的数据，返回当前正在发送的数据项；publish 失败则通知回调后继续下一条
local function publish_item(mqtt_client)
    local item
    while #send_queue>0 do
        item = table.remove(send_queue, 1)
        result = mqtt_client:publish(item.topic, item.payload, item.qos)
        if result then
            return item
        else
            if item.cb and item.cb.func then
                item.cb.func(false, item.cb.para)
            end
        end
    end
end

local function publish_item_cbfunc(item, result)
    if item then
        if item.cb and item.cb.func then
            item.cb.func(result, item.cb.para)
        end
    end
end

-- mqtt sender task：按事件驱动发送队列中的数据
local function mqtt_client_sender_task_func()
    local mqtt_client
    local send_item
    local result, msg

    while true do
        msg = sys.waitMsg(mqtt_sender.TASK_NAME, "MQTT_EVENT")
        if msg[2] == "CONNECT_OK" then
            mqtt_client = msg[3]
            send_item = publish_item(mqtt_client)
        elseif msg[2] == "PUBLISH_REQ" then
            if mqtt_client and not send_item then
                send_item = publish_item(mqtt_client)
            end
        elseif msg[2] == "PUBLISH_OK" then
            publish_item_cbfunc(send_item, true)
            -- 网络环境检测看门狗喂狗（看门狗已屏蔽）
            -- sys.publish("FEED_NETWORK_WATCHDOG")
            send_item = publish_item(mqtt_client)
        elseif msg[2] == "DISCONNECTED" then
            mqtt_client = nil
            publish_item_cbfunc(send_item, false)
            while #send_queue>0 do
                send_item = table.remove(send_queue,1)
                publish_item_cbfunc(send_item, false)
            end
            send_item = nil
        end
    end
end

sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func)
sys.taskInitEx(mqtt_client_sender_task_func, mqtt_sender.TASK_NAME)

-- ============================ 数据接收 ============================
local mqtt_receiver = {}

function mqtt_receiver.proc(topic, payload, metas)
    -- 打印收到服务器下发的数据
    log.info("mqtt_receiver.data", topic, payload)
    -- 网络环境检测看门狗喂狗（看门狗已屏蔽）
    -- sys.publish("FEED_NETWORK_WATCHDOG")
end

-- ============================ 定时器应用 ============================
-- 每 5 秒向 mobile.imei().."/timer/up" 发布一条 "Hello world"
local send_data_req_timer_cbfunc

local function send_data_cbfunc(result, para)
    log.info("send_data_cbfunc", result, para)
    sys.timerStart(send_data_req_timer_cbfunc, 5000)
end

send_data_req_timer_cbfunc = function()
    sys.publish("SEND_DATA_REQ", "timer", mobile.imei().."/timer/up", "Hello world", 0, {func=send_data_cbfunc, para="timer_helloworld"})
end

sys.timerStart(send_data_req_timer_cbfunc, 5000)

-- ============================ mqtt 连接主逻辑 ============================
local function mqtt_client_event_cbfunc(mqtt_client, event, data, payload, metas)
    log.info("mqtt_client_event_cbfunc", mqtt_client, event, data, payload, json.encode(metas))

    if event == "conack" then
        -- 连接成功，通知 main task，并订阅下行主题
        sys.sendMsg(TASK_NAME, "MQTT_EVENT", "CONNECT", true)
        if not mqtt_client:subscribe(TOPIC_PREFIX .. "/down") then
            sys.sendMsg(TASK_NAME, "MQTT_EVENT", "SUBSCRIBE", false, -1)
        end
    elseif event == "suback" then
        sys.sendMsg(TASK_NAME, "MQTT_EVENT", "SUBSCRIBE", data, payload)
    elseif event == "unsuback" then
        sys.sendMsg(TASK_NAME, "MQTT_EVENT", "UNSUBSCRIBE", true)
    elseif event == "recv" then
        -- 处理服务器下发的 publish 数据
        mqtt_receiver.proc(data, payload, metas)
    elseif event == "sent" then
        sys.sendMsg(mqtt_sender.TASK_NAME, "MQTT_EVENT", "PUBLISH_OK", data)
    elseif event == "disconnect" then
        sys.sendMsg(TASK_NAME, "MQTT_EVENT", "DISCONNECTED", false)
    elseif event == "pong" then
        -- 网络环境检测看门狗喂狗（看门狗已屏蔽）
        -- sys.publish("FEED_NETWORK_WATCHDOG")
    elseif event == "error" then
        if data == "connect" or data == "conack" then
            sys.sendMsg(TASK_NAME, "MQTT_EVENT", "CONNECT", false)
        elseif data == "other" or data == "tx" then
            sys.sendMsg(TASK_NAME, "MQTT_EVENT", "ERROR")
        end
    end
end

local function mqtt_client_main_task_func()
    local mqtt_client
    local result, msg

    -- 等待 IPv6 就绪（ipv6_info 发布 IPV6_READY），确保 IPv6 地址已分配后再连接服务器
    sys.waitUntil("IPV6_READY")
    log.info("mqtt_client_main_task_func", "收到 IPV6_READY，准备进行 IPv6 MQTT 连接")

    while true do
        -- 等待默认网卡连接成功
        while not socket.adapter(socket.dft()) do
            log.warn("mqtt_client_main_task_func", "wait IP_READY", socket.dft())
            sys.waitUntil("IP_READY", 1000)
        end
        log.info("mqtt_client_main_task_func", "recv IP_READY", socket.dft())

        -- 清空此 task 绑定的消息队列
        sys.cleanMsg(TASK_NAME)

        -- 创建 mqtt client 对象（ipv6 = true 优先使用 IPv6 地址连接服务器）
        mqtt_client = mqtt.create(nil, SERVER_ADDR, SERVER_PORT, nil, {ipv6 = true})
        if not mqtt_client then
            log.error("mqtt_client_main_task_func", "mqtt.create error")
            goto EXCEPTION_PROC
        end

        -- 配置 client id
        result = mqtt_client:auth(TASK_NAME..mobile.imei(), "", "", true)
        if not result then
            log.error("mqtt_client_main_task_func", "mqtt_client:auth error")
            goto EXCEPTION_PROC
        end

        -- 注册事件回调函数
        mqtt_client:on(mqtt_client_event_cbfunc)

        -- 连接服务器
        result = mqtt_client:connect()
        if not result then
            log.error("mqtt_client_main_task_func", "mqtt_client:connect error")
            goto EXCEPTION_PROC
        end

        -- 连接、订阅、断开、异常等事件处理
        while true do
            msg = sys.waitMsg(TASK_NAME, "MQTT_EVENT")
            log.info("mqtt_client_main_task_func waitMsg", msg[2], msg[3], msg[4])

            if msg[2] == "CONNECT" then
                if msg[3] then
                    log.info("mqtt_client_main_task_func", "connect success")
                    -- 通知 sender task 可以发送数据了
                    sys.sendMsg(mqtt_sender.TASK_NAME, "MQTT_EVENT", "CONNECT_OK", mqtt_client)
                else
                    log.info("mqtt_client_main_task_func", "connect error")
                    break
                end
            elseif msg[2] == "SUBSCRIBE" then
                if msg[3] then
                    log.info("mqtt_client_main_task_func", "subscribe success", "qos: "..(msg[4] or "nil"))
                else
                    log.error("mqtt_client_main_task_func", "subscribe error", "code", msg[4])
                    mqtt_client:disconnect()
                    sys.wait(1000)
                    break
                end
            elseif msg[2] == "UNSUBSCRIBE" then
                log.info("mqtt_client_main_task_func", "unsubscribe success")
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

        ::EXCEPTION_PROC::

        -- 清空消息队列，通知 sender task 连接已断开
        sys.cleanMsg(TASK_NAME)
        sys.sendMsg(mqtt_sender.TASK_NAME, "MQTT_EVENT", "DISCONNECTED")

        if mqtt_client then
            mqtt_client:close()
            mqtt_client = nil
        end

        -- 5 秒后重连
        sys.wait(5000)
    end
end

-- 创建并启动 mqtt main task
sys.taskInitEx(mqtt_client_main_task_func, TASK_NAME)
