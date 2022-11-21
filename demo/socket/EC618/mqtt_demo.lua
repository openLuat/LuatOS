local libnet = require "libnet"


local mqtt_host = "lbsmqtt.airm2m.com"
local mqtt_port = 1883
local client_id = "123456"
local user_name = "username"
local password = "password"

local mqttc = nil


function recv(topic, payload)
    local tjson, r = json.decode(payload)
    log.info("result", r, ",tjson", tjson)
    if r then
        log.info("topic", topic)
        for k, v in pairs(tjson) do
            log.info("key & value", k, v)
        end
    end
end

sys.taskInit(function()
	sys.wait(3000)
    mqttc = mqtt.create(nil,mqtt_host, mqtt_port,false)

    mqttc:auth(client_id,user_name,password)    -- mqtt三元组配置
    mqttc:keepalive(30)     -- 默认值240s
    mqttc:autoreconn(true, 3000)    -- 自动重连机制

    mqttc:on(function(mqtt_client, event, topic, payload)
        -- 用户自定义代码
        log.info("mqtt", "event", event, mqtt_client, topic, payload)
        if event == "conack" then       -- 连接事件
            sys.publish("mqtt_conack")
            mqtt_client:subscribe("/luatos/123456")
        elseif event == "recv" then     -- 接收事件
            recv(topic, payload)
            log.info("mqtt", "downlink", "topic", topic, "payload", payload)
        elseif event == "sent" then     -- 发送事件
            log.info("mqtt", "sent", "pkgid", topic)
        end
    end)

    mqttc:connect()

	sys.waitUntil("mqtt_conack")
    while true do
        -- mqttc自动处理重连
        local ret, topic, data, qos = sys.waitUntil("mqtt_pub", 30000)
        if ret then
            log.info("mqtt-topic_data_qos",ret, topic, data, qos)
            if topic == "close" then break end
            mqttc:publish(topic, data, qos)
        end
    end
    mqttc:close()
    mqttc = nil
end)

-- publish消息
sys.taskInit(function()
	local topic = "/luatos/123456"
	local payload = "{\"cn\": \"合宙\", \" luatos\": \"yyds\"}"
	local qos = 1
    while true do
        sys.wait(5000)
        if mqttc and mqttc:ready() then
            local pkgid = mqttc:publish(topic, payload, qos)
        end
    end
end)
