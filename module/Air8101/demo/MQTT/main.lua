-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "mqttdemo"
VERSION = "1.0.0"

--[[
本demo需要mqtt库,
mqtt也是内置库, 无需require
]]

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用mqtt库需要下列语句]]
_G.sysplus = require("sysplus")

--根据自己的服务器修改以下参数
local mqtt_host = "lbsmqtt.airm2m.com"
local mqtt_port = 1884
local mqtt_isssl = false
local ca_file = false

local client_id = "mqttx_b55c41b7"
local user_name = "user"
local password = "password"

local pub_topic = ""-- .. (mcu.unique_id():toHex())
local sub_topic = ""-- .. (mcu.unique_id():toHex())

local mqttc = nil



sys.taskInit(function()
    -----------------------------
    -- 统一联网函数, 可自行删减
    ----------------------------
    if wlan and wlan.connect then
        -- wifi 联网, Air8101系列均支持
        local ssid = "Xiaomi_1100"
        local password = "1234567890"
        log.info("wifi", ssid, password)

        wlan.init()
        wlan.setMode(wlan.STATION)
        wlan.connect(ssid, password, 1)
        --等待WIFI联网结果，WIFI联网成功后，内核固件会产生一个"IP_READY"消息
        local result, data = sys.waitUntil("IP_READY")
        log.info("wlan", "IP_READY", result, data)
        device_id = wlan.getMac()

    else
         -- 其他不认识的bsp, 循环提示一下吧
         while 1 do
            sys.wait(1000)
            log.info("bsp", "本bsp可能未适配网络层, 请查证")
        end
    end
    log.info("已联网")


    sys.publish("net_ready")
end)

sys.taskInit(function()
    -- 等待联网
    sys.waitUntil("net_ready")
    local device_id = "1001001"

    client_id = device_id
    pub_topic = device_id .. "/up"  -- 设备发布的主题，开发者可自行修改
    sub_topic = device_id .. "/down" -- 设备订阅的主题，开发者可自行修改

    -- 打印一下上报(pub)和下发(sub)的topic名称
    -- 上报: 设备 ---> 服务器
    -- 下发: 设备 <--- 服务器
    -- 可使用mqtt.x等客户端进行调试
    log.info("mqtt", "pub", pub_topic)
    log.info("mqtt", "sub", sub_topic)

    -- 打印一下支持的加密套件, 通常来说, 固件已包含常见的99%的加密套件
    -- if crypto.cipher_suites then
    --     log.info("cipher", "suites", json.encode(crypto.cipher_suites()))
    -- end
    if mqtt == nil then
        while 1 do
            sys.wait(1000)
            log.info("bsp", "本bsp未适配mqtt库, 请查证")
        end
    end

    -------------------------------------
    -------- MQTT 演示代码 --------------
    -------------------------------------

    mqttc = mqtt.create(nil, mqtt_host, mqtt_port, mqtt_isssl, ca_file)

    mqttc:auth(client_id,user_name,password) -- client_id必填,其余选填
    -- mqttc:keepalive(240) -- 默认值240s
    mqttc:autoreconn(true, 3000) -- 自动重连机制

    mqttc:on(function(mqtt_client, event, data, payload)
        -- 用户自定义代码
        log.info("mqtt", "event", event, mqtt_client, data, payload)
        if event == "conack" then
            -- 联上了

            sys.publish("mqtt_conack")
            mqtt_client:subscribe(sub_topic)--单主题订阅
            -- mqtt_client:subscribe({[topic1]=1,[topic2]=1,[topic3]=1})--多主题订阅
        elseif event == "recv" then
            log.info("mqtt", "downlink", "topic", data, "payload:", payload)
            log.info("mqtt", "uplink", "topic", pub_topic, "payload:", payload)
            sys.publish("mqtt_pub", pub_topic, payload)  --将收到的数据，通过发布主题目，进行发送
        elseif event == "sent" then
            log.info("mqtt", "sent", "pkgid", data)
        elseif event == "disconnect" then

            -- 非自动重连时,按需重启mqttc
            -- mqtt_client:connect()
            log.info("mqtt", "disconnect")
        end
    end)

    -- mqttc自动处理重连, 除非自行关闭
    mqttc:connect()
    sys.waitUntil("mqtt_conack")
    while true do
        -- 演示等待其他task发送过来的上报信息
        local ret, topic, data, qos = sys.waitUntil("mqtt_pub", 300000)
        if ret then
            -- 提供关闭本while循环的途径, 不需要可以注释掉
            if topic == "close" then break end
            mqttc:publish(topic, data, qos)
        end

        -- 如果没有其他task上报, 可以写个空等待
        --sys.wait(6000)
    end
    mqttc:close()
    mqttc = nil
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
