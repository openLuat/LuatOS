
-- 这是个概念设计的demo, 未实用

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "mqttdemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")

sys.taskInit(function()
    mqttc = mqtt.create(host, port, isssl, ca_file) -- host,port必填,其余选填
    mqttc:auth(client_id, user, password) -- client_id必填,其余选填
    --mqttc:keepalive(30) -- 默认值240s
    --mqttc:topics({abc=1, bdf=2}) -- 连接+鉴权ok后,自动订阅这些topic
    --mqttc:qos2auto(true) -- 是否自动处理qos2流程,自动上报pubrel, 默认true
    --mqttc:reconnect(true, 3000) -- 自动重连机制
    mqttc:on(function(mqttc, event, data, payload)
        -- 用户自定义代码
        log.info("mqtt", "event", event)
        if event == "conack" then
            -- 连接+鉴权ok, 如果还需要订阅别的, 就继续调用
            --mqttc:subscribe(sub_topic, sub_qos)
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
    while true do
        -- mqttc自动处理重连
        local ret, topic, data, qos = sys.waitUntil("mqtt_pub", 3000)
        if ret then
            if topic == "close" then break end
            mqttc:publish(topic, data, qos)
        else
            mqttc:ping() -- 是否真的发心跳,底层以keepalive时长为准
        end
    end
    mqttc:close()
    mqttc = nil
end)

sys.taskInit(function()
    while true do
        sys.wait(30000)
        -- 其他task可以拿mqttc对象直接publish
        -- mqttc若链接成功,以收到正确的conack为判据
        if mqttc:ready() then
            local pkgid = mqttc:publish(topic, data, qos)
            -- 也可以通过sys.publish发布到指定task去
            sys.publish("mqtt_pub", topic, data, qos)
        end
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
