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
        -- 用户自定义代码，按event处理
        log.info("mqtt", "event", event, mqtt_client, data, payload)
        if event == "conack" then -- mqtt成功完成鉴权后的消息
            sys.publish("mqtt_conack") -- 小写字母的topic均为自定义topic
            -- 订阅不是必须的，但一般会有
            mqtt_client:subscribe("/luatos/123456")
        elseif event == "recv" then -- 服务器下发的数据
            log.info("mqtt", "downlink", "topic", data, "payload", payload)
            -- 这里继续加自定义的业务处理逻辑
        elseif event == "sent" then -- publish成功后的事件
            log.info("mqtt", "sent", "pkgid", data)
        end
    end)

    -- 发起连接之后，mqtt库会自动维护链接，若连接断开，默认会自动重连
    mqttc:connect()
	sys.waitUntil("mqtt_conack")
    log.info("mqtt连接成功")
    while true do
        -- 业务演示。等待其他task发过来的待上报数据
        -- 这里的mqtt_pub字符串是自定义的，与mqtt库没有直接联系
        -- 若不需要异步关闭mqtt链接，while内的代码可以替换成sys.wait(13000
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
 