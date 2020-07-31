
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air640w_aliyun_autoreg_demo"
VERSION = "1.0.0"

--[[
本demo 为 "一型一密' 的替代方案:
1. 通过regproxy服务获取阿里云物联网平台的设备密钥,并保存到文件
2. 使用mqtt连接到阿里云物联网平台

regproxy服务的源码 https://gitee.com/openLuat/iot-regproxy
]]

-- 引入必要的库文件(lua编写), 内部库不需要require
local sys = require "sys"
local mqtt = require "mqtt"


log.info("version", _VERSION, VERSION)

wlan.connect("uiot", "12345678")

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
    while not socket.isReady() do 
        log.info("net", "wait for network ready")
        sys.waitUntil("NET_READY", 1000)
    end
    
    -- 阿里云物联网的设备信息
    -- https://help.aliyun.com/document_detail/73742.html?spm=a2c4g.11186623.6.593.11a22cf0rGX1bC
    -- deviceName 是imei
    local productKey,deviceName,deviceSecret = "a1UTvQkICk9",wlan.getMac(), nil
    -- 从文件读取设备密钥
    local f = io.open("aliyun_secret.txt")
    if f then
        -- 读取全部数据,应该是32字节
        deviceSecret = f:read("*a")
        f:close()
    end
    -- 判断一下deviceSecret是否合法
    if deviceSecret == nil or deviceSecret == "" or #deviceSecret ~= 32 then
        deviceSecret = nil
        log.info("aliyun", "miss deviceSecret")
        local c = 3
        -- 通过http请求regproxy
        -- regproxy服务的源码 https://gitee.com/openLuat/iot-regproxy
        -- ============================================================================================================
        while c > 0 and deviceSecret == nil do
            sys.wait(2000) -- 稍等一会
            c = c - 1
            local tmpl = "http://regproxy.vue2.cn:8384/reg/aliyun?dev=%s&key=%s&sign=%s"
            local url = string.format(tmpl, deviceName,productKey, crypto.md5(deviceName .. productKey .. "123"))
            http.get(url, nil, function(code,headers,body)
                log.info("http", code, body)
                if code == 200 then
                    local jdata,result = json.decode(body)
                    if jdata and jdata.secret then
                        log.info("aliyun", "GOT secret", jdata.secret)
                        local f_aliyun_secret = io.open("aliyun_secret.txt", "wb")
                        f_aliyun_secret:write(jdata.secret)
                        f_aliyun_secret:close()
                        deviceSecret = jdata.secret
                    end
                end
                sys.publish("HTTP_RESP")
            end)
            sys.waitUntil("HTTP_RESP", 120000) -- 等服务器响应
        end
        -- ============================================================================================================
    end
    -- 往下的代码, 与demo/aliyun一致
    local host, port, selfid = productKey .. ".iot-as-mqtt.cn-shanghai.aliyuncs.com", 1883, deviceName
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
