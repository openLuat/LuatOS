-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "txiot_demo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用mqtt库需要下列语句]]
_G.sysplus = require("sysplus")


-- 产品ID和产品动态注册秘钥
local ProductId = "SU83PBK5YF"
local ProductSecret = "DliTrlLmab4zo2FiZFNOyLsQ"
local mqttc
local mqtt_isssl = false

--[[
函数名：getDeviceName
功能  ：获取设备名称
参数  ：无
返回值：设备名称
]]
local function getDeviceName()
    --默认使用设备的IMEI作为设备名称，用户可以根据项目需求自行修改
    return mobile.imei()
end



function device_enrol()
    local deviceName = getDeviceName()
    local nonce = math.random(1, 100)
    local timestamp = os.time()
    local data = "deviceName=" .. deviceName .. "&nonce=" .. nonce .. "&productId=" ..
        ProductId .. "&timestamp=" .. timestamp
    local hmac_sha1_data = crypto.hmac_sha1(data, ProductSecret):lower()
    local signature = crypto.base64_encode(hmac_sha1_data)
    local tx_body = {
        productId = ProductId,
        deviceName = deviceName,
        nonce = nonce,
        timestamp = timestamp,
        signature = signature,
    }
    local tx_body_json = json.encode(tx_body)
    local code, headers, body = http.request("POST", "https://ap-guangzhou.gateway.tencentdevices.com/register/dev",
        {
            ["Content-Type"] = "application/json; charset=UTF-8",
            ["X-TC-Version"] = "2019-04-23",
            ["X-TC-Region"] = "ap-guangzhou"
        }, tx_body_json, { timeout = 30000 }).wait()
    log.info("http.post", code, headers, body)
    if code == 200 then
        local m, result, err = json.decode(body)
        log.info(" m,result,err", m, result, err)
        if result == 0 then
            log.info("json解析失败", err)
            device_enrol()
        end
        if m.message == "success" then
            log.info("腾讯云注册设备成功:", body)
            log.info("http.body.message", m.message)
            local result = io.writeFile("/txiot.dat", body)
            log.info("密钥写入结果", result)
        else
            log.info("腾讯云注册设备失败:失败原因", m.message)
        end
    else
        log.info("http请求失败:", body)
    end
end

sys.subscribe("MQTT_SIGN_AUTH", function(clientid, username, password)
    sys.taskInit(function()
        log.info("clientid,username,password", result, clientid, username, password, payload)

        local mqtt_host = ProductId .. ".iotcloud.tencentdevices.com"
        mqttc = mqtt.create(nil, mqtt_host, 1883, mqtt_isssl)
        mqttc:auth(clientid, username, password, false) -- client_id必填,其余选填
        mqttc:keepalive(300)                            -- 默认300s
        mqttc:autoreconn(true, 3000)                    -- 自动重连机制
        mqttc:on(function(mqtt_client, event, data, payload)
            -- 用户自定义代码
            log.info("mqtt", "event", event, mqtt_client, data, payload)
            if event == "conack" then
                log.info("mqtt", "sent", "pkgid", data)
                --连上了
                sys.publish("mqtt_conack")
                local txiot_subscribetopic = {
                    ["$thing/down/property/" .. ProductId .. "/" .. getDeviceName()] = 0
                }
                mqtt_client:subscribe(txiot_subscribetopic)
            elseif event == "recv" then
                log.info("mqtt", "downlink", "topic", data, "payload", payload)
                --TODO：根据需求自行处理data.payload
                --sys.publish("mqtt_payload", data, payload)
                mqttc:publish("$thing/up/property/" .. ProductId .. "/" .. getDeviceName(),
                    "publish from luat mqtt client",
                    0)
            elseif event == "sent" then
                log.info("mqtt", "sent", "pkgid", data)
            elseif event == "disconnect" then
                log.info("连接失败")
                --     --非自动重连时,按需重启mqttc
                --     mqtt_client:connect()
            end
        end)
        mqttc:connect()
        sys.waitUntil("mqtt_conack")
        while true do
            -- 如果没有其他task上报, 可以写个空等待
            sys.wait(60000000)
        end
    end)
end)


sys.subscribe("MQTT_CERT_AUTH", function() ---证书认证连接
    sys.taskInit(function()
        local clientid = ProductId .. getDeviceName()
        local connid = math.random(10000, 99999)
        log.info("connid类型", type(connid))
        local expiry = "32472115200"
        local username = string.format("%s;12010126;%s;%s", clientid, connid, expiry) --生成 MQTT 的 username 部分, 格式为 ${clientid};${sdkappid};${connid};${expiry}
        local password = 123                                                          --证书认证不会验证password
        log.info("clientid1,username1,password1", clientid, username, password)
        local mqtt_host = ProductId .. ".iotcloud.tencentdevices.com"
        mqttc = mqtt.create(nil, mqtt_host, 8883,
        { server_cert = io.readFile("/luadb/ca.crt"),
        client_cert = io.readFile("/client.crt"),
        client_key = io.readFile("/client.key") })
        mqttc:auth(clientid, username, password) -- client_id必填,其余选填
        mqttc:keepalive(300)                     -- 默认值300s
        mqttc:autoreconn(true, 20000)            -- 自动重连机制


        mqttc:on(function(mqtt_client, event, data, payload)
            -- 用户自定义代码
            log.info("mqtt", "event", event, mqtt_client, data, payload)
            if event == "conack" then
                log.info("mqtt", "sent", "pkgid", data)
                --连上了
                sys.publish("mqtt_conack")
                local txiot_subscribetopic = {
                    ["$thing/down/property/" .. ProductId .. "/" .. getDeviceName()] = 0
                }
                mqtt_client:subscribe(txiot_subscribetopic)
            elseif event == "recv" then
                log.info("mqtt", "downlink", "topic", data, "payload", payload)
                --TODO：根据需求自行处理data.payload
                --sys.publish("mqtt_payload", data, payload)
                mqttc:publish("$thing/up/property/" .. ProductId .. "/" .. getDeviceName(),
                    "publish from luat mqtt client",
                    0)
            elseif event == "sent" then
                log.info("mqtt", "sent", "pkgid", data)
            elseif event == "disconnect" then
                log.info("连接失败")
                --     --非自动重连时,按需重启mqttc
                --     mqtt_client:connect()
            end
        end)
        local result = mqttc:connect()
        log.info("connect.result", result)
        sys.waitUntil("mqtt_conack")

        while true do
            -- 如果没有其他task上报, 可以写个空等待
            sys.wait(60000000)
        end
    end)
end)

sys.taskInit(function()
    if mobile.status() ~= 1 and not sys.waitUntil("IP_READY", 600000) then
        log.info("网络初始化失败！")
    end
    log.info("io.exists", io.exists("/txiot.dat"))
    if not io.exists("/txiot.dat") then
        device_enrol()
    end
    local dat, result, err = json.decode(io.readFile("/txiot.dat"))
    log.info("dat,result,err", dat, result, err)
    if result == 0 then
        log.info("json解码失败", err)
        device_enrol() --解析失败重新下载文件
        local dat, result, err = json.decode(io.readFile("/txiot.dat"))
    end
    local payload = json.decode(crypto.cipher_decrypt("AES-128-CBC", "ZERO", crypto.base64_decode(dat.payload),
        string.sub(ProductSecret, 1, 16), "0000000000000000"))
    log.info("payload[encryptionType]", payload.encryptionType)
    log.info("payload[psk]", payload.psk)
    if payload.encryptionType == 2 then
        local clientid, username, password = iotauth.qcloud(ProductId, getDeviceName(), payload.psk)
        sys.publish("MQTT_SIGN_AUTH", clientid, username, password) --签名认证
    elseif payload.encryptionType == 1 then
        log.info("payload date ", payload.encryptionType, payload.psk, payload.clientCert, payload.clientKey)
        io.writeFile("/client.crt", payload.clientCert)
        io.writeFile("/client.key", payload.clientKey)
        sys.publish("MQTT_CERT_AUTH") --证书认证
    end
end)




-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
