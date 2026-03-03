
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "mqttdemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用mqtt库需要下列语句]]
_G.sysplus = require("sysplus")

-- Air780E的AT固件默认会为开机键防抖, 导致部分用户刷机很麻烦
if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then
    pm.power(pm.PWK_MODE, false)
end

--根据自己的服务器修改以下参数
local mqtt_host = "lbsmqtt.airm2m.com"
local mqtt_port = 1884
local mqtt_isssl = false
local client_id = "mqttx_b55c41b7"
local user_name = "user"
local password = "password"

local mqttc = nil

sys.taskInit(function()
    -- 等待联网
    sys.waitUntil("IP_READY")
    -- 获取设备的imei号
    local device_id = mcu.unique_id():toHex()
    -- 下面的是mqtt的参数均可自行修改
    client_id = device_id
    pub_topic = "/luatos/pub/" .. device_id
    sub_topic = "/luatos/sub/" .. device_id

    -- 打印一下上报(pub)和下发(sub)的topic名称
    log.info("mqtt", "pub", pub_topic)
    log.info("mqtt", "sub", sub_topic)

    --[[
        @param1 适配器序号,不填会选择平台自带的
        @param2 服务器地址，域名或ip都可
        @param3 端口号
        @param4 是否为ssl加密连接
        @param5 是否为ipv6
    ]]
    mqttc = mqtt.create(nil, mqtt_host, mqtt_port, mqtt_isssl, ca_file)

    --[[配置mqtt连接服务器的参数
        @param1 设备id
        @param2 账号[可选]
        @param3 密码[可选]
        @param4 清除session，默认true[可选]
    ]]
    mqttc:auth(client_id,user_name,password) -- client_id必填,其余选填
    --设置心跳
    -- mqttc:keepalive(240) -- 默认值240s

    --[[
        @param1 是否自动重连
        @param2 自动重连机制，单位ms
    ]]
    mqttc:autoreconn(true, 3000) -- 自动重连机制

    --[[mqtt事件回调函数，其中事件包括
        conack：连接成功事件。
        recv：接收服务器下发数据的事件
        sent：发送完成事件
        disconnect：断开连接事件
        ]]
    --[[回调函数参数：@param1 mqtt的句柄
        @param2 事件
        @param3 
    ]]
    mqttc:on(function(mqtt_client, event, data, payload)
        -- 用户自定义代码
        log.info("mqtt", "event", event, mqtt_client, data, payload)
        if event == "conack" then
            -- mqtt连接上服务器后，发布一条消息。订阅一个mqtt主题
            sys.publish("mqtt_conack")
            mqtt_client:subscribe(sub_topic)--单主题订阅
            -- mqtt_client:subscribe({[topic1]=1,[topic2]=1,[topic3]=1})--多主题订阅
        elseif event == "recv" then
            log.info("mqtt", "downlink", "topic", data, "payload", payload)
        elseif event == "sent" then
        end
    end)

    -- mqttc自动处理重连, 除非自行关闭
    mqttc:connect()
    --等待连接成功
	sys.waitUntil("mqtt_conack")
    while true do
        -- 演示等待其他task发送过来的上报信息
        local ret, topic, data, qos = sys.waitUntil("mqtt_pub", 300000)
        if ret then
            -- 当接收到的tpoic是字符串close时，就跳出等待其他task发过来的上报消息的循环
            if topic == "close" then break end
            mqttc:publish(topic, data, qos)
        end
    end
    --跳出等待上报消息的循环后，就关闭close
    mqttc:close()
    --删除创建的mqtt实例
    mqttc = nil
end)

-- 定时上报数据演示
sys.taskInit(function()
    sys.wait(3000)
	local data = "123test,"
	local qos = 0 -- QOS0不带puback, QOS1是带puback的
    while true do
        sys.wait(3000)
        --如果mqttc实例存在，并且mqtt客户端就绪
        if mqttc and mqttc:ready() then
            --发布一个mqtt消息，这个消息的订阅，在mqtt服务器上
            local pkgid = mqttc:publish(pub_topic, data .. os.date(), qos)
        end
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
