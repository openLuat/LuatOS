-- 自动低功耗, 轻休眠模式
-- Air780E、Air780EP支持uart唤醒和网络数据下发唤醒, 但需要断开USB,或者pm.power(pm.USB, false) 但这样也看不到日志了
-- pm.request(pm.LIGHT)

--根据自己的服务器修改以下参数
local mqtt_host = "lbsmqtt.airm2m.com"
local mqtt_port = 1884
local mqtt_isssl = false
local client1_id = "abc"
local client2_id = "abc2"
local user_name = "user"
local password = "password"
local device_id = mobile.imei()

local mqttc1 = nil
local pub_topic_client = "/luatos/pub/client1/"
local sub_topic_client = "/luatos/sub/client1/"
-- local pub_topic2_client = "/luatos/2"
-- local pub_topic3_client = "/luatos/3"


local mqttc2 = nil
local pub_topic_client2 = "/luatos/pub/client2/"
local sub_topic_client2 = "/luatos/sub/client2/"
-- local pub_topic2_client2 = "/luatos/2"
-- local pub_topic3_client2 = "/luatos/3"
-- 统一联网函数
sys.taskInit(function()
    -- 默认都等到联网成功
    sys.waitUntil("IP_READY")
    sys.publish("net_ready")
end)

sys.taskInit(function()
    -- 等待联网
    
    local ret= sys.waitUntil("net_ready")
    -- 下面的是mqtt的参数均可自行修改
    pub_topic_client = pub_topic_client .. device_id
    sub_topic_client = sub_topic_client .. device_id

    -- 打印一下上报(pub)和下发(sub)的topic名称
    -- 上报: 设备 ---> 服务器
    -- 下发: 设备 <--- 服务器
    -- 可使用mqtt.x等客户端进行调试
    log.info("mqtt", "pub", pub_topic_client)
    log.info("mqtt", "sub", sub_topic_client)

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

    -------------------------------------
    -------- MQTT 演示代码 --------------
    -------------------------------------

    mqttc1 = mqtt.create(nil, mqtt_host, mqtt_port, mqtt_isssl)

    mqttc1:auth(client1_id,user_name,password) -- client_id必填,其余选填
    -- mqttc1:keepalive(240) -- 默认值240s
    mqttc1:autoreconn(true, 3000) -- 自动重连机制

    mqttc1:on(function(mqtt_client, event, data, payload)
        -- 用户自定义代码
        log.info("mqtt", "event", event, mqtt_client, data, payload)
        if event == "conack" then
            -- 联上了
            sys.publish("mqtt_conack")
            mqtt_client:subscribe(sub_topic_client)--单主题订阅
            -- mqtt_client:subscribe({[topic1]=1,[topic2]=1,[topic3]=1})--多主题订阅
        elseif event == "recv" then
            log.info("mqtt", "downlink", "topic", data, "payload", payload)
            sys.publish("mqtt_payload", data, payload)
        elseif event == "sent" then
            -- log.info("mqtt", "sent", "pkgid", data)
        -- elseif event == "disconnect" then
            -- 非自动重连时,按需重启mqttc
            -- mqtt_client:connect()
        end
    end)

    -- mqttc自动处理重连, 除非自行关闭
    mqttc1:connect()
	sys.waitUntil("mqtt_conack")
    while true do
        -- 演示等待其他task发送过来的上报信息
        local ret, topic, data, qos = sys.waitUntil("mqtt_pub", 300000)
        if ret then
            -- 提供关闭本while循环的途径, 不需要可以注释掉
            if topic == "close" then break end
            mqttc1:publish(topic, data, qos)
        end
        -- 如果没有其他task上报, 可以写个空等待
        --sys.wait(60000000)
    end
    mqttc1:close()
    mqttc1 = nil
end)

-- 这里演示在另一个task里上报数据, 会定时上报数据,不需要就注释掉
sys.taskInit(function()
    sys.wait(3000)
	local data = "123,"
	local qos = 1 -- QOS0不带puback, QOS1是带puback的
    while true do
        sys.wait(3000)
        if mqttc1 and mqttc1:ready() then
            local pkgid = mqttc1:publish(pub_topic_client, data .. os.date(), qos)
            -- local pkgid = mqttc1:publish(topic2, data, qos)
            -- local pkgid = mqttc1:publish(topic3, data, qos)
        end
    end
end)


-- mqtt多链接示例
sys.taskInit(function()
    -- 等待联网
    local ret= sys.waitUntil("net_ready")
    -- 下面的是mqtt的参数均可自行修改
    client2_id = device_id.."2"
    pub_topic_client2 = pub_topic_client2 .. device_id
    sub_topic_client2 = sub_topic_client2 .. device_id

    -- 打印一下上报(pub)和下发(sub)的topic名称
    -- 上报: 设备 ---> 服务器
    -- 下发: 设备 <--- 服务器
    -- 可使用mqtt.x等客户端进行调试
    log.info("mqtt", "pub", pub_topic_client2)
    log.info("mqtt", "sub", sub_topic_client2)

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

    -------------------------------------
    -------- MQTT 演示代码 --------------
    -------------------------------------

    mqttc2 = mqtt.create(nil, mqtt_host, mqtt_port, mqtt_isssl)

    mqttc2:auth(client2_id,user_name,password) -- client_id必填,其余选填
    -- mqttc2:keepalive(240) -- 默认值240s
    mqttc2:autoreconn(true, 3000) -- 自动重连机制

    mqttc2:on(function(mqtt_client, event, data, payload)
        -- 用户自定义代码
        log.info("mqtt", "event", event, mqtt_client, data, payload)
        if event == "conack" then
            -- 联上了
            sys.publish("mqtt_conack")
            mqtt_client:subscribe(sub_topic_client2)--单主题订阅
            -- mqtt_client:subscribe({[topic1]=1,[topic2]=1,[topic3]=1})--多主题订阅
        elseif event == "recv" then
            log.info("mqtt", "downlink", "topic", data, "payload", payload)
            sys.publish("mqtt_payload", data, payload)
        elseif event == "sent" then
            log.info("mqtt", "sent", "pkgid", data)
        elseif event == "disconnect" then
            -- 非自动重连时,按需重启mqttc
            mqtt_client:connect()
        end
    end)

    -- mqttc自动处理重连, 除非自行关闭
    mqttc2:connect()
	sys.waitUntil("mqtt_conack")
    while true do
        -- 演示等待其他task发送过来的上报信息
        local ret, topic, data, qos = sys.waitUntil("mqtt_pub", 300000)
        if ret then
            -- 提供关闭本while循环的途径, 不需要可以注释掉
            if topic == "close" then break end
            mqttc2:publish(topic, data, qos)
        end
        -- 如果没有其他task上报, 可以写个空等待
        --sys.wait(60000000)
    end
    mqttc2:close()
    mqttc2 = nil
end)


-- 这里演示在另一个task里上报数据, 会定时上报数据,不需要就注释掉
sys.taskInit(function()
    sys.wait(3000)
	local data = "123,"
	local qos = 1 -- QOS0不带puback, QOS1是带puback的
    while true do
        sys.wait(3000)
        if mqttc2 and mqttc2:ready() then
            local pkgid = mqttc2:publish(pub_topic_client2, data .. os.date(), qos)
            -- local pkgid = mqttc2:publish(topic2, data, qos)
            -- local pkgid = mqttc2:publish(topic3, data, qos)
        end
    end
end)


sys.taskInit(function ()
    while true do
        sys.wait(3000)
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
