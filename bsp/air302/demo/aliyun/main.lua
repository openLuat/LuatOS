
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air302_aliyun_demo"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
local sys = require "sys"
local mqtt = require "mqtt"


log.info("version", _VERSION, VERSION)

--- UART 相关------------------------------
-- 配置uart2, 115200 8 N 1
uart.on(2, "receive", function(id, len)
     log.info("uart", "receive", uart.read(id, 1024))
end)
uart.setup(2, 115200)

-- GPIO 和 PWM 相关 -------------------------------
-- 网络灯 GPIO19/PWM5
gpio.setup(19, 0)     -- 初始化GPIO19, 并设置为低电平
gpio.set(19, 1)       -- 设置为高电平
-- pwm.open(5, 1000, 50) -- 初始化PWM5, 频率1000hz, 占空比50%

-- GPIO18/PWM4
-- GPIO17/PWM3

-- 低功耗sleep2模式下依然能输出电平的AON系列GPIO
-- AON_GPIO2 --> GPIO22
-- AON_GPIO3 --> GPIO23

-- ADC相关---------------------------------------
-- 通道 0-内部温度, 1-供电电压, 2-5 外部ADC管脚
-- adc.open(5)
-- adc.read(5)
-- adc.close(5)

-- 连接到阿里云物联网的Task
sys.taskInit(function()
    sys.wait(2000)
    -- 阿里云物联网的设备信息
    -- https://help.aliyun.com/document_detail/73742.html?spm=a2c4g.11186623.6.593.11a22cf0rGX1bC
    -- deviceName 可以是imei, 也可以自定义, 填写正确才能连接上
    local productKey,deviceName,deviceSecret = "a1YFuY6OC1e","azNhIbNNTdsVwY2mhZno","5iRxTePbEMguOuZqltZrJBR0JjWJSdA7" 
    local host, port, selfid = productKey .. ".iot-as-mqtt.cn-shanghai.aliyuncs.com", 1883, nbiot.imei()
    local mqttClientId = selfid  .. "|securemode=3,signmethod=hmacsha1,timestamp=132323232|"
    local mqttUsername = deviceName .. "&" .. productKey
    local signstr = "clientId"..selfid.."deviceName"..deviceName.."productKey"..productKey.."timestamp".."132323232"
    local mqttPassword = crypto.hmac_sha1(signstr, deviceSecret)
    --log.info("aliiot", "mqttClientId", mqttClientId)
    --log.info("aliiot", "mqttUsername", mqttUsername)
    --log.info("aliiot", "signstr", signstr)
    --log.info("aliiot", "mqttPassword", mqttPassword)
    local topic_get = string.format("/%s/%s/user/get", productKey, deviceName)
    local topic_update = string.format("/%s/%s/user/update", productKey, deviceName)
    while true do
        -- 等待联网成功
        while not socket.isReady() do 
            log.info("net", "wait for network ready")
            sys.waitUntil("NET_READY", 1000)
        end
        log.info("main", "net is ready!!")
        sys.wait(1000) -- 稍等一会
        
        -- 清理内存, 啊啊啊啊
        collectgarbage("collect")
        collectgarbage("collect")

        -- 开始连接到阿里云物联网
        local mqttc = mqtt.client(mqttClientId, 240, mqttUsername, mqttPassword)
        -- 等待底层tcp连接完成
        while not mqttc:connect(host, port) do sys.wait(15000) end
        -- 连接成功, 开始订阅
        log.info("mqttc", "mqtt seem ok", "try subscribe", topic_get)
        if mqttc:subscribe(topic_get) then
            -- 订阅完成, 发布业务数据
            log.info("mqttc", "mqtt subscribe ok", "try publish")
            if mqttc:publish(topic_update, "test publish " .. selfid, 1) then
                -- 发布也ok了, 等待数据下发或数据上传
                while true do
                    log.info("mqttc", "wait for new msg")
                    local r, data, param = mqttc:receive(120000, "pub_msg")
                    log.info("mqttc", "mqttc:receive", r, data, param)
                    if r then -- 有下发的数据
                        log.info("mqttc", "get message from server", data.payload or "nil", data.topic)
                    elseif data == "pub_msg" then -- 需要上报数据
                        log.info("mqttc", "send message to server", data, param)
                        mqttc:publish(topic_update, "response " .. param, 1)
                    elseif data == "timeout" then -- 无交互,发个定时report也行
                        log.info("mqttc", "wait timeout, send custom report")
                        mqttc:publish(topic_update, "test publish " .. os.date() .. nbiot.imei())
                    else -- 其他情况不太可能,退出连接吧
                        log.info("mqttc", "ok, something happen", "close connetion")
                        break
                    end
                end
            end
        end
        -- 关掉连接,清理资源
        mqttc:disconnect()
        -- 避免频繁重连, 必须加延时
        sys.wait(30000)
    end

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
