
--根据自己的服务器修改以下参数
local mqtt_host = "lbsmqtt.airm2m.com"
local mqtt_port = 1884
local mqtt_isssl = false
local client_id = "abc"
local user_name = "user"
local password = "password"

local mqttc = nil

local function testTask()
    print("testTask")
    mqttc = mqtt.create(nil,mqtt_host, mqtt_port, mqtt_isssl, ca_file)

    mqttc:auth(client_id,user_name,password) -- client_id必填,其余选填
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
        -- elseif event == "disconnect" then
            -- 非自动重连时,按需重启mqttc
            -- mqtt_client:connect()
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
        end
    end
    mqttc:close()
    mqttc = nil
end

function mqttDemo()
	sys.taskInit(testTask)
end

sys.taskInit(function()
	local topic = "/luatos/123456"
	local data = "123"
	local qos = 1
    while true do
        sys.wait(5000)
        if mqttc:ready() then
			-- mqttc:subscribe(topic)
            local pkgid = mqttc:publish(topic, data, qos)
            -- 也可以通过sys.publish发布到指定task去
            -- sys.publish("mqtt_pub", topic, data, qos)
        end
    end
end)
