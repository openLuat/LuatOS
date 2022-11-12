local libnet = require "libnet"


local mqtt_host = "www.dozingfiretruck.com.cn"
local mqtt_port = 8883
local client_id = "123456"
local user_name = ""
local password = ""

local mqttc = nil

sys.taskInit(function()
	sys.wait(3000)
    mqttc = mqtt.create(nil,mqtt_host, mqtt_port)

    mqttc:auth(client_id,user_name,password)
    mqttc:keepalive(30) -- 默认值240s
    mqttc:autoreconn(true, 3000) -- 自动重连机制

    mqttc:on(function(mqtt_client, event, data, payload)
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
    sys.wait(10000)
    mqttc:subscribe("/luatos/123456")
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
    local result, data = sys.waitUntil("IP_READY")
    while true do
        sys.wait(5000)
        if mqttc and mqttc:ready() then
            local pkgid = mqttc:publish(topic, payload, qos)
        end
    end
end)
