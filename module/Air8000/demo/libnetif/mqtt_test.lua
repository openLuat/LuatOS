--[[
@module  mqtt_test
@summary mqtt_test mqtt功能测试模块 
@version 1.0
@date    2025.07.15
@author  wjq
@usage
本文件为mqtt功能测试模块，核心业务逻辑为：
1、开启mqtt连接
2、注册网卡驱动的回调函数
3、触发回调后，mqtt重连
本文件没有对外接口，直接在main.lua中require "mqtt_test"就可以加载运行；
]]
--根据自己的服务器修改以下参数
local mqtt_host = "lbsmqtt.airm2m.com"
local mqtt_port = 1884
local mqtt_isssl = false
local ca_file = false

local client_id = "mqttx_b55c41b7"
local user_name = "user"
local password = "password"

local pub_topic = ""-- .. (mcu.unique_id():toHex())
local sub_topic = ""-- .. (mcu.unique_id():toHex())

local mqttc = nil

mqtt_state = false

libnetif.notify_status(function(net_type, adapter)
    log.info("可以使用优先级更高的网络:", net_type, adapter)
    sys.publish("mqtt_pub", "close")  --关闭现在的mqtt链接
end)

-- 这里演示在另一个task里上报数据, 会定时上报数据,不需要就注释掉
sys.taskInit(function()
    sys.wait(3000)
    local data = "hello mqtt"
    local qos = 1 -- QOS0不带puback, QOS1是带puback的
    while true do
        sys.wait(3000)
        if mqttc and mqttc:ready() then
            local pkgid = mqttc:publish(pub_topic, data, qos)
        end
    end
end)


sys.taskInit(function()
        -- 等待联网
    sys.waitUntil("IP_READY")
    local device_id = "1001001"

    client_id = device_id
    pub_topic = device_id .. "/up"  -- 设备发布的主题，开发者可自行修改
    sub_topic = device_id .. "/down" -- 设备订阅的主题，开发者可自行修改

    -- 打印一下上报(pub)和下发(sub)的topic名称
    -- 上报: 设备 ---> 服务器
    -- 下发: 设备 <--- 服务器
    -- 可使用mqtt.x等客户端进行调试
    log.info("mqtt", "pub", pub_topic)
    log.info("mqtt", "sub", sub_topic)

    -- 打印一下支持的加密套件, 通常来说, 固件已包含常见的99%的加密套件
    -- if crypto.cipher_suites then
    --     log.info("cipher", "suites", json.encode(crypto.cipher_suites()))
    -- end
    if mqtt == nil then
        while 1 do
            sys.wait(1000)
            log.info("bsp", "本bsp未适配mqtt库, 请查证")
        end
    end


    while true do
    -------------------------------------
    -------- MQTT 演示代码 --------------
    -------------------------------------
    sys.wait(1000)
    mqttc = mqtt.create(nil, mqtt_host, mqtt_port, mqtt_isssl, ca_file)

    mqttc:auth(client_id,user_name,password) -- client_id必填,其余选填
    -- mqttc:keepalive(240) -- 默认值240s
    mqttc:autoreconn(true, 3000) -- 自动重连机制

    mqttc:on(function(mqtt_client, event, data, payload)
        -- 用户自定义代码
        log.info("mqtt", "event", event, mqtt_client, data, payload)
        if event == "conack" then
            -- 联上了

            sys.publish("mqtt_conack")
            mqtt_client:subscribe(sub_topic)--单主题订阅
            -- mqtt_client:subscribe({[topic1]=1,[topic2]=1,[topic3]=1})--多主题订阅
        elseif event == "recv" then
            log.info("mqtt", "downlink", "topic", data, "payload:", payload)
            log.info("mqtt", "uplink", "topic", pub_topic, "payload:", payload)
            sys.publish("mqtt_pub", pub_topic, payload)  --将收到的数据，通过发布主题目，进行发送
        elseif event == "sent" then
            log.info("mqtt", "sent", "pkgid", data)
        elseif event == "disconnect" then

            -- 非自动重连时,按需重启mqttc
            -- mqtt_client:connect()
            log.info("mqtt", "disconnect")
        end
    end)

    -- mqttc自动处理重连, 除非自行关闭
    mqttc:connect()
    while true do
        -- 演示等待其他task发送过来的上报信息
        local ret, topic, data, qos = sys.waitUntil("mqtt_pub", 300000)
        if ret then
            -- 提供关闭本while循环的途径, 不需要可以注释掉
            if topic == "close" then break end
            mqttc:publish(topic, data, qos)
        end

        -- 如果没有其他task上报, 可以写个空等待
        --sys.wait(6000)
    end
    mqttc:close()
    mqttc = nil
    end
end)
