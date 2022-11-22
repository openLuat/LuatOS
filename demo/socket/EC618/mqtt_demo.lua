local libnet = require "libnet"

--根据自己的服务器修改以下参数
local mqtt_host = "lbsmqtt.airm2m.com"
local mqtt_port = 1884
local mqtt_isssl = false
local client_id = "abc"
local user_name = "user"
local password = "password"

local mqttc = nil

-- function recv(topic, payload)
--     local tjson, r = json.decode(payload)
--     log.info("result", r, ",tjson", tjson)
--     if r then
--         log.info("topic", topic)
--         for k, v in pairs(tjson) do
--             log.info("key & value", k, v)
--         end
--     end
-- end

sys.taskInit(function()
	sys.wait(3000)

    mqttc = mqtt.create(nil,mqtt_host, mqtt_port,mqtt_isssl)  --mqtt客户端创建

    mqttc:auth(client_id,user_name,password) --mqtt三元组配置
    mqttc:keepalive(30) -- 默认值240s
    mqttc:autoreconn(true, 3000) -- 自动重连机制

    mqttc:on(function(mqtt_client, event, data, payload)  --mqtt回调注册
        -- 用户自定义代码
        log.info("mqtt", "event", event, mqtt_client, data, payload)
        if event == "conack" then
            sys.publish("mqtt_conack")
            mqtt_client:subscribe("/luatos/123456")
        elseif event == "recv" then
            log.info("mqtt", "downlink", "topic", data, "payload", payload)
        elseif event == "sent" then
            log.info("mqtt", "sent", "pkgid", data)
        end
    end)

    mqttc:connect()
    log.info("mqtt连接成功")
	sys.waitUntil("mqtt_conack")
    while true do
        -- mqttc自动处理重连
        local ret, topic, data, qos = sys.waitUntil("mqtt_pub", 30000)
        if ret then
            if topic == "close" then break end
            mqttc:publish(topic, data, qos)
        end
    end
    mqttc:close()
    mqttc = nil
end)

sys.taskInit(function()
	local topic = "/luatos/123456"
	local payload = "123"
	local qos = 1
    while true do
        sys.wait(5000)
        if mqttc and mqttc:ready() then
            log.info("mqtt的topic",topic,payload,qos)
            local pkgid = mqttc:publish(topic, payload, qos) --发送一条消息
        end
    end
end)
 