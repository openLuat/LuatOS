-- 自动低功耗, 轻休眠模式
-- Air780E支持uart唤醒和网络数据下发唤醒, 但需要断开USB,或者pm.power(pm.USB, false) 但这样也看不到日志了
-- pm.request(pm.LIGHT)
-- 根据自己的服务器修改以下参数
local mqtt_host = "lbsmqtt.airm2m.com"
local mqtt_port = 1884
local mqtt_isssl = false
local client_id = "abc"
local user_name = "user"
local password = "password"

local mqttc = nil

local device_id = mobile.imei()
local pub_topic = "/luatos/pub/" .. device_id
local sub_topic = "/luatos/sub/" .. device_id

sys.taskInit(function()
    -- 等待联网
    sys.waitUntil("CH390_IP_READY")
    log.info("CH390 联网成功，开始测试")
    socket.dft(socket.LWIP_ETH)--配置默认网卡为CH390

    -- 如果自带的DNS不好用，可以用下面的公用DNS,但是一定是要在CH390联网成功后使用
    -- socket.setDNS(socket.LWIP_ETH,1,"223.5.5.5")	
    -- socket.setDNS(nil,1,"114.114.114.114")

    -- 下面的是mqtt的参数均可自行修改
    client_id = device_id


    -- 打印一下上报(pub)和下发(sub)的topic名称
    -- 上报: 设备 ---> 服务器
    -- 下发: 设备 <--- 服务器
    -- 可使用mqtt.x等客户端进行调试
    log.info("mqtt", "pub", pub_topic)
    log.info("mqtt", "sub", sub_topic)

    if mqtt == nil then
        while 1 do
            sys.wait(1000)
            log.info("bsp", "本bsp未适配mqtt库, 请查证")
        end
    end

    -------------------------------------
    -------- MQTT 演示代码 --------------
    -------------------------------------

    mqttc = mqtt.create(nil, mqtt_host, mqtt_port, mqtt_isssl)

    mqttc:auth(client_id, user_name, password) -- client_id必填,其余选填
    -- mqttc:keepalive(240) -- 默认值240s
    mqttc:autoreconn(true, 3000) -- 自动重连机制

    mqttc:on(function(mqtt_client, event, data, payload)
        -- 用户自定义代码
        log.info("mqtt", "event", event, mqtt_client, data, payload)
        if event == "conack" then
            -- 联上了
            sys.publish("mqtt_conack")
            mqtt_client:subscribe(sub_topic) -- 单主题订阅
            -- mqtt_client:subscribe({[topic1]=1,[topic2]=1,[topic3]=1})--多主题订阅
        elseif event == "recv" then
            log.info("mqtt", "downlink", "topic", data, "payload", payload)
            sys.publish("mqtt_payload", data, payload)
        elseif event == "sent" then
            -- log.info("mqtt", "sent", "pkgid", data)
            -- elseif event == "disconnect" then
            -- 非自动重连时,按需重启mqttc
            -- mqtt_client:connect()
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
            if topic == "close" then
                break
            end
            mqttc:publish(topic, data, qos)
        end
        -- 如果没有其他task上报, 可以写个空等待
        -- sys.wait(60000000)
    end
    mqttc:close()
    mqttc = nil
end)

-- 这里演示在另一个task里上报数据, 会定时上报数据,不需要就注释掉
sys.taskInit(function()
    sys.wait(3000)
    local data = "123,"
    local qos = 1 -- QOS0不带puback, QOS1是带puback的
    while true do
        sys.wait(3000)
        if mqttc and mqttc:ready() then
            local pkgid = mqttc:publish(pub_topic, data .. os.date(), qos)
            -- local pkgid = mqttc:publish(topic2, data, qos)
            -- local pkgid = mqttc:publish(topic3, data, qos)
        end
    end
end)

-- 以下是演示与uart结合, 简单的mqtt-uart透传实现,不需要就注释掉
local uart_id = 1
uart.setup(uart_id, 9600)
uart.on(uart_id, "receive", function(id, len)
    local data = ""
    while 1 do
        local tmp = uart.read(uart_id)
        if not tmp or #tmp == 0 then
            break
        end
        data = data .. tmp
    end
    log.info("uart", "uart收到数据长度", #data)
    sys.publish("mqtt_pub", pub_topic, data)
end)
sys.subscribe("mqtt_payload", function(topic, payload)
    log.info("uart", "uart发送数据长度", #payload)
    uart.write(1, payload)
end)

sys.taskInit(function()
    while true do
        sys.wait(3000)
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
    end
end)
