
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "mqttairm2m"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

local mqtt = require "mqtt"

sys.taskInit(function()
    -- 服务器配置信息
    local host, port, selfid = "lbsmqtt.airm2m.com", 1884, nbiot.imei()
    -- 等待联网成功
    while true do
        while not socket.isReady() do 
            log.info("net", "wait for network ready")
            sys.waitUntil("NET_READY", 1000)
        end
        log.info("main", "Airm2m mqtt loop")
        
        local mqttc = mqtt.client(selfid, nil, nil, false)
        while not mqttc:connect(host, port) do sys.wait(2000) end
        local topic_req = string.format("/device/%s/req", selfid)
        local topic_report = string.format("/device/%s/report", selfid)
        local topic_resp = string.format("/device/%s/resp", selfid)
        log.info("mqttc", "mqtt seem ok", "try subscribe", topic_req)
        if mqttc:subscribe(topic_req) then
            log.info("mqttc", "mqtt subscribe ok", "try publish")
            if mqttc:publish(topic_report, "test publish " .. os.date()  .. crypto.md5("12345"), 1) then
                while true do
                    log.info("mqttc", "wait for new msg")
                    local r, data, param = mqttc:receive(120000, "pub_msg")
                    log.info("mqttc", "mqttc:receive", r, data, param)
                    if r then
                        log.info("mqttc", "get message from server", data.payload or "nil", data.topic)
                    elseif data == "pub_msg" then
                        log.info("mqttc", "send message to server", data, param)
                        mqttc:publish(topic_resp, "response " .. param)
                    elseif data == "timeout" then
                        log.info("mqttc", "wait timeout, send custom report")
                        mqttc:publish(topic_report, "test publish " .. os.date() .. nbiot.imei())
                    else
                        log.info("mqttc", "ok, something happen", "close connetion")
                        break
                    end
                end
            end
        end
        mqttc:disconnect()
        sys.wait(5000) -- 等待一小会, 免得疯狂重连
    end

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
