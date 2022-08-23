
local mqttc = nil
local mqttc2 = nil
local function testTask()
	sys.wait(2000);
    print("testTask")

    mqttc = mqtt.create(nil,"120.55.137.106", 1884, isssl, ca_file) -- host,port必填,其余选填
    mqttc:auth("123456789","username","password") -- client_id必填,其余选填
    mqttc:keepalive(30) -- 默认值240s
    -- mqttc:reconnect(true, 3000) -- 自动重连机制

    mqttc:on(function(mqtt_client, event, data, payload)
        -- 用户自定义代码
        log.info("mqtt", "event", event, mqtt_client, data, payload)
        if event == "conack" then
            sys.publish("mqtt_conack")
            -- 连接+鉴权ok, 如果还需要订阅别的, 就继续调用
            mqttc:subscribe("/luatos/123456",2)
        elseif event == "recv" then
            log.info("mqtt", "downlink", "topic", data, "payload", payload)
        elseif event == "sent" then
            -- data 为 发送结果, true 发送成功, 其余发送失败
            log.info("mqtt", "sent", data, "pkgid", payload)
        -- elseif event == "disconnect" then
            -- 非自动重连时,按需重启mqttc
            -- mqttc:connect()
        end
    end)

    mqttc:connect()
	sys.waitUntil("mqtt_conack")
    while true do
        -- mqttc自动处理重连
        local ret, topic, data, qos = sys.waitUntil("mqtt_pub", 30000)
        if ret then
            if topic == "close" then break end
            mqttc:publish(topic, data, qos)
        else
            mqttc:ping() -- 是否真的发心跳,底层以keepalive时长为准
        end
    end
    mqttc:close()
    mqttc = nil
end
local function testTask2()
	sys.wait(2000);
    print("testTask")

    mqttc2 = mqtt.create(nil,"120.55.137.106", 1884, isssl, ca_file) -- host,port必填,其余选填
    mqttc2:auth("1234567890","username","password") -- client_id必填,其余选填
    mqttc2:keepalive(30) -- 默认值240s
    -- mqttc2:reconnect(true, 3000) -- 自动重连机制

    mqttc2:on(function(mqtt_client, event, data, payload)
        -- 用户自定义代码
        log.info("mqtt2", "event", event, mqtt_client, data, payload)
        if event == "conack" then
            sys.publish("mqtt2_conack")
            -- 连接+鉴权ok, 如果还需要订阅别的, 就继续调用
            mqttc2:subscribe("/luatos/123456",2)
        elseif event == "recv" then
            log.info("mqtt2", "downlink", "topic", data, "payload", payload)
        elseif event == "sent" then
            -- data 为 发送结果, true 发送成功, 其余发送失败
            log.info("mqtt2", "sent", data, "pkgid", payload)
        -- elseif event == "disconnect" then
            -- 非自动重连时,按需重启mqttc
            -- mqttc2:connect()
        end
    end)

    mqttc2:connect()
	sys.waitUntil("mqtt2_conack")
    while true do
        -- mqttc自动处理重连
        local ret, topic, data, qos = sys.waitUntil("mqtt2_pub", 30000)
        if ret then
            if topic == "close" then break end
            mqttc2:publish(topic, data, qos)
        else
            mqttc2:ping() -- 是否真的发心跳,底层以keepalive时长为准
        end
    end
    mqttc2:close()
    mqttc2 = nil
end
function mqttDemo()
	sys.taskInit(testTask)
    sys.taskInit(testTask2)
end

sys.taskInit(function()
	local topic = "/luatos/123456"
	local data = "123"
	local qos = 1
    while true do
        sys.wait(5000)
        -- 其他task可以拿mqttc对象直接publish
        -- mqttc若链接成功,以收到正确的conack为判据
        if mqttc:ready() then
			-- mqttc:subscribe(topic)
            local pkgid = mqttc:publish(topic, data, qos)
            -- 也可以通过sys.publish发布到指定task去
            -- sys.publish("mqtt_pub", topic, data, qos)
        end
    end
end)

sys.taskInit(function()
	local topic = "/luatos/123456"
	local data = "123"
	local qos = 1
    while true do
        sys.wait(5000)
        -- 其他task可以拿mqttc对象直接publish
        -- mqttc若链接成功,以收到正确的conack为判据
        if mqttc2:ready() then
			-- mqttc:subscribe(topic)
            local pkgid = mqttc2:publish(topic, data, qos)
            -- 也可以通过sys.publish发布到指定task去
            -- sys.publish("mqtt2_pub", topic, data, qos)
        end
    end
end)

-- sys.subscribe("MQTT_MSG_PUBLISH",function(mqttc,topic,payload)
--     log.info("MQTT_MSG_PUBLISH","topic",topic,"payload",payload)
-- end)
