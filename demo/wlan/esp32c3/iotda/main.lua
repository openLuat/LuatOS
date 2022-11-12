PROJECT = "gpiodemo"
VERSION = "1.0.0"

-- 一定要添加sys.lua !!!!
local sys = require "sys"
require("sysplus")
log.info("main", "iotda demo")


local device_id     = ""    --改为你自己的设备id
local device_secret = ""    --改为你自己的设备密钥

local mqttc = nil

sys.taskInit(function()
    log.info("wlan", "wlan_init:", wlan.init())
    wlan.setMode(wlan.STATION)
    wlan.connect("CMCC_EDU", "88995500", 1)
    local result, data = sys.waitUntil("IP_READY")
    log.info("wlan", "IP_READY", result, data)
    
    local client_id,user_name,password = iotauth.iotda(device_id,device_secret)
    log.info("iotda",client_id,user_name,password)
    
    mqttc = mqtt.create(nil,"a16203e7a0.iot-mqtts.cn-north-4.myhuaweicloud.com", 1883)

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

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
