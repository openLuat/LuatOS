--[[
这个代码对应公众号文档 https://mp.weixin.qq.com/s/ST_8Uej8R7qLUsikfh3Xtw

针对的硬件是 ESP32系列
]]

PROJECT = "qcloud100"
VERSION = "1.0.0"

--测试支持硬件：ESP32C3/Air105/Air780E

local sys = require "sys"
require("sysplus")

sys.taskInit(function()
    -- 统一联网函数
    if rtos.bsp():startsWith("ESP32") then -- ESP32系列, C3/S3都可以
        LED = gpio.setup(12, 0, gpio.PULLUP) -- 控制的灯对应的GPIO号
        wlan.init()
        --
        -- ESP32系列, 这里要填wifi的名称和密码. 只支持2.4G频段
        --
        local ssid, password = "wifi的名字", "wifi的密码"
        wlan.setMode(wlan.STATION)
        wlan.connect(ssid, password, 1)
        local result, data = sys.waitUntil("IP_READY")
        log.info("wlan", "IP_READY", result, data)
    elseif rtos.bsp() == "AIR105" then -- Air105走网卡,W5500
        w5500.init(spi.HSPI_0, 24000000, pin.PC14, pin.PC01, pin.PC00)
        w5500.config() --默认是DHCP模式
        w5500.bind(socket.ETH0)
        LED = gpio.setup(62, 0, gpio.PULLUP)
        sys.wait(1000)
    elseif rtos.bsp() == "EC618" then -- Air780E,走4G一堆网络
        -- mobile.simid(2) -- 自动选卡, 如果不清楚在哪个卡槽,就取消注释
        LED = gpio.setup(27, 0, gpio.PULLUP)
        sys.waitUntil("IP_READY") -- 等联网就行,要插卡的
        log.info("mobile", "IP_READY", mobile.imei(), mobile.iccid())
    else
        while 1 do 
            sys.wait(1000)
            log.info("bsp", "未支持的模块", rtos.bsp())
        end
    end

    -- 往下就是连接到腾讯云了, 下面3个参数要改成自己的值, 到腾讯云上建项目建设备才有的
    local product_key = "产品id" -- 一串英文字母,填前面的双引号以内
    local device_id = "设备名称" -- 一定要改成自己的数据
    local device_secret = "设备密钥" -- 设备密钥
    local client_id, user_name, password = iotauth.qcloud(product_key, device_id, device_secret, "sha1", 1700561166)
    log.info("mqtt参数", client_id, user_name, password)

    -- MQTT参数准备好了,开始连接,并监听数据下发
    local mqttc = mqtt.create(nil, product_key .. ".iotcloud.tencentdevices.com", 1883)
    mqttc:auth(client_id, user_name, password)
    mqttc:keepalive(240) -- 默认值240s
    mqttc:autoreconn(true, 3000) -- 自动重连机制
    mqttc:on(
        function(mqtt_client, event, data, payload)
            if event == "conack"then
                -- 连上了,鉴权也ok
                sys.publish("mqtt_conack")
                log.info("mqtt", "mqtt已连接")
                mqtt_client:subscribe("$thing/down/property/" .. product_key .. "/".. device_id)
            elseif event == "recv" then
                log.info("mqtt", "收到消息", data, payload)
                local json = json.decode(payload)
                if json.method == "control" then
                    if json.params.power_switch == 1 then
                        LED(1)
                    elseif json.params.power_switch == 0 then
                        LED(0)
                    end
                end
            elseif event == "sent"then
                log.info("mqtt", "sent", "pkgid", data)
            end
        end
    )
    mqttc:connect()
    --sys.wait(1000)
    sys.waitUntil("mqtt_conack")
    while true do
        local ret, topic, data, qos = sys.waitUntil("mqtt_pub", 30000)    
        if ret then
            if topic == "close" then
                break
            end
            mqttc:publish(topic, data, qos)
        end
    end
    mqttc:close()
    mqttc = nil
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
