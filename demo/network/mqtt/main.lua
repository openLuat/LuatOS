
-- 这是个概念设计的demo, 未实用

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "mqttdemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")

sys.taskInit(function()
    mqttc = mqtt.create(ip, port, ca_file)
    mqttc:auth(client_id, user, password)
    mqttc:keepalive(240) -- 默认值也是240
    mqttc:topics({abc=1, bdf=2}) -- 连接+鉴权ok后,自动订阅这些topic
    mqttc:on(function(event, data, data2)
        -- 用户自定义代码
        log.info("mqtt", "event", event)
        if event == "conack" then
            -- 连接+鉴权ok, 如果还需要订阅别的, 就继续调用
            --mqttc:subscribe(sub_topic, sub_qos)
        elseif event == "recv" then
            log.info("mqtt", "downlink", "topic", data, "payload", data2)
        end
    end)
    while true do
        local ret, topic, data, qos = sys.waitUntil("mqtt_pub", 3000)
        if ret then
            if topic == "close" then break end
            mqttc:publish(topic, data, qos)
        else
            mqttc:ping()
        end
    end
    mqttc:close()
    mqttc = nil
end)

sys.taskInit(function()
    while true do
        sys.wait(30000)
        -- 其他task可以拿mqttc对象直接publish
        mqttc:publish(topic, data, qos)
        -- 也可以通过sys.publish发布到指定task去
        sys.publish("mqtt_pub", topic, data, qos)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
