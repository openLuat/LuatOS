
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "aliyun_demo"
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

-- 低功耗sleep2模式下依然能输出电平的AON系列GPIO,电平1.8v
-- AON_GPIO2 --> GPIO21
-- AON_GPIO3 --> GPIO23

-- ADC相关---------------------------------------
-- 通道 0-内部温度, 1-供电电压, 2 外部ADC管脚
-- adc.open(2)
-- adc.read(2)
-- adc.close(2)

local aliyun_msgid = 1
local vPowerSwitch = 1
function aliyun_params_post()
--[[
{
  "id": "123",
  "version": "1.0",
  "params": {
    "Power": {
      "value": "on",
      "time": 1524448722000
    },
    "WF": {
      "value": 23.6,
      "time": 1524448722000
    }
  },
  "method": "thing.event.property.post"
}
]]
    aliyun_msgid = aliyun_msgid + 1
    local re = {
        id = tostring(aliyun_msgid),
        version = "1.0",
        params = {
            PowerSwitch = {
                value = vPowerSwitch,
                time = os.time() * 1000
            }
            -- ,RSSI = {
            --     value = nbiot.rssi(),
            --     time = os.time() * 1000
            -- },
        },
        method = "thing.event.property.post"
    }
    return json.encode(re)
end

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
    local topic_post = string.format("/sys/%s/%s/thing/event/property/post", productKey, deviceName)
    local topic_post_reply = string.format("/sys/%s/%s/thing/event/property/post_reply", productKey, deviceName)
    local topic_set = string.format("/sys/%s/%s/thing/service/property/set", productKey, deviceName)
    local topic_user_get = string.format("/%s/%s/user/get", productKey, deviceName)
    log.info("mqtt", "topic_post", topic_post)
    log.info("mqtt", "topic_set", topic_set)
    log.info("mqtt", "topic_user_get", topic_user_get)
    while true do
        -- 等待联网成功
        while not socket.isReady() do 
            log.info("net", "wait for network ready")
            sys.waitUntil("NET_READY", 1000)
        end
        log.info("main", "net is ready!!")
        sys.wait(1000) -- 稍等一会

        -- 开始连接到阿里云物联网
        local mqttc = mqtt.client(mqttClientId, 240, mqttUsername, mqttPassword)
        -- 等待底层tcp连接完成
        while not mqttc:connect(host, port) do sys.wait(15000) end
        -- 连接成功, 开始订阅
        log.info("mqttc", "mqtt seem ok", "try subscribe", topic_set)
        if mqttc:subscribe(topic_set) then
            mqttc:subscribe(topic_post_reply)
            mqttc:subscribe(topic_user_get)
            -- 订阅完成, 发布业务数据
            log.info("mqttc", "mqtt subscribe ok", "try publish", topic_post)
            if mqttc:publish(topic_post, aliyun_params_post(), 1) then
                -- 发布也ok了, 等待数据下发或数据上传
                while true do
                    log.info("mqttc", "wait for new msg")
                    local r, data, param = mqttc:receive(120000, "pub_msg")
                    log.info("mqttc", "mqttc:receive", r, data, param)
                    if r then -- 有下发的数据
                        log.info("mqttc", "get message from server", data.payload or "nil", data.topic)
                        local tjsondata,result,errinfo = json.decode(data.payload)
                        if result then
                            log.info("mqtt", tjsondata.id, tjsondata.method)
                            if tjsondata.method == "thing.service.property.set" and tjsondata.params then
                                vPowerSwitch = tjsondata.params.PowerSwitch
                                log.info("mqtt", "vPowerSwitch", "set as", vPowerSwitch)
                            end
                        else
                            log.info("mqtt", "json.decode error",errinfo)
                        end
                    elseif data == "pub_msg" then -- 需要上报数据
                        log.info("mqttc", "send message to server", data, param)
                        mqttc:publish(topic_post, param, 1)
                    elseif data == "timeout" then -- 无交互,发个定时report也行
                        log.info("mqttc", "wait timeout, send custom report")
                        mqttc:publish(topic_post, aliyun_params_post(), 1)
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
