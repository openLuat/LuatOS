--[[
@module aliyun
@summary AliYun阿里云物联网平台
@version 1.0
@date    2023.06.07
@author  wendal
@demo    aliyun
@usage
-- 请查阅demo
]]
_G.sys = require("sys")
--[[特别注意, 使用mqtt库需要下列语句]]
_G.sysplus = require("sysplus")
local libfota = require("libfota")

-- 总的库对象
local aliyun = {}
local mqttc = nil

local ClientId,PassWord,UserName,SetClientidFnc,SetDeviceTokenFnc,SetDeviceSecretFnc
local EvtCb = {}
local opts = {}

-------------------------------------------------------
---- FOTA 相关
-------------------------------------------------------
-- fota的回调函数
local function libfota_cb(result)
    log.info("fota", "result", result)
    -- fota成功
    if result == 0 then
        rtos.reboot()
    end
end
--收到云端固件升级通知消息时的回调函数
local function aliyun_upgrade(payload)
    local jsonData, result = json.decode(payload)
    if result and jsonData.data and jsonData.data.url then
        log.info("aliyun", "ota.url", jsonData.data.url)
        libfota.request(EvtCb["ota"] or libfota_cb, jsonData.data.url)
    end
end

-------------------------------------------------------
--- 用户侧的回调处理
-------------------------------------------------------



--底层libMQTT回调函数，上层的回调函数，通过 aliyun.on注册
local function mqtt_cbevent(mqtt_client, event, data, payload,metas)
    log.debug("aliyun", "event", event, "data", data)
    if event == "conack" then
        log.info("aliyun", "conack")
        -- if opts.ProductKey and opts.DeviceName then
        aliyun.subscribe("/ota/device/upgrade/"..opts.ProductKey.."/"..opts.DeviceName,1)
        aliyun.publish("/ota/device/inform/"..opts.ProductKey.."/"..opts.DeviceName,1,"{\"id\":1,\"params\":{\"version\":\"".._G.VERSION.."\"}}")
        -- end
        sys.publish("aliyun_conack")
        if EvtCb["connect"] then
            EvtCb["connect"](true)
        end
    elseif event == "recv" then -- 服务器下发的数据
        log.debug("aliyun", "downlink", "topic", data, "payload", payload)
        --OTA消息
        if data =="/ota/device/upgrade/".. opts.ProductKey.."/".. opts.DeviceName then
            aliyun_upgrade(payload)
        end

        if EvtCb["receive"] then
            EvtCb["receive"](data, payload, metas.qos, metas.retain, metas.dup)
        end
    elseif event == "sent" then
        log.info("aliyun", "sent", data)
        if data then
            sys.publish("aliyun_evt", "sent", data)
            if EvtCb["publish"] then
                EvtCb["publish"](data)
            end
        end
    elseif event == "disconnect" then
        log.info("aliyun", "disconnect")
        if EvtCb["connect"] then
            EvtCb["connect"](false)
        end
    end
end

local function mqtt_task(mqtt_host, mqtt_port, mqtt_isssl, client_id, user_name, password)
    mqttc = mqtt.create(nil,mqtt_host, mqtt_port or 1883, mqtt_isssl)  --mqtt客户端创建
    log.debug("aliyun", "mqtt三元组", client_id,user_name,password)
    mqttc:auth(client_id,user_name,password) --mqtt三元组配置

    mqttc:keepalive(300) -- 默认值240s
    mqttc:autoreconn(true, 20000) -- 自动重连机制
    mqttc:on(mqtt_cbevent)  --mqtt回调注册
    -- mqttc:debug(true)
    mqttc:connect()
end

---------------------------------------------------
---              一型一密
--------------------------------------------------

-- 二次连接, 也就是真正的连接
local function clientDataTask(DeviceName,ProductKey,mqtt_host,mqtt_port,mqtt_isssl,passtoken,Registration)
    sys.taskInit(function()
        if not Registration then -- 预注册
            local client_id,user_name,password = iotauth.aliyun(opts.ProductKey, opts.DeviceName,SetDeviceSecretFnc)
            -- mqttc = mqtt.create(nil,opts.mqtt_host, opts.mqtt_port, opts.mqtt_isssl)  --mqtt客户端创建
            -- mqttc:auth(client_id,user_name,password) --mqtt三元组配置
            mqtt_task(mqtt_host or opts.mqtt_host, mqtt_port or opts.mqtt_port, mqtt_isssl or opts.mqtt_isssl, client_id, user_name, password)
        else -- 免预注册
            -- mqttc = mqtt.create(nil,opts.mqtt_host, opts.mqtt_port, opts.mqtt_isssl)  --mqtt客户端创建
            -- mqttc:auth(opts.DeviceName, opts.ProductKey, passtoken) --mqtt三元组配置
            mqtt_task(mqtt_host or opts.mqtt_host, mqtt_port or opts.mqtt_port, mqtt_isssl or opts.mqtt_isssl, opts.DeviceName, opts.ProductKey, passtoken)
        end
    end)
end

--根据返回的数据进行二次加密
local function directProc(DeviceName,ProductKey,mqtt_host,mqtt_port,mqtt_isssl,Registration)
    if not Registration then
        local ClientId = DeviceName.."|securemode=3,signmethod=hmacmd5,timestamp=789|"
        local UserName = DeviceName.."&"..ProductKey

        local content = "ClientId"..DeviceName.."deviceName"..DeviceName.."productKey"..ProductKey.."timestamp789"
        local signKey= SetDeviceSecretFnc
        PassWord = crypto.hmac_md5(content,signKey)

        clientDataTask(ClientId,UserName,PassWord,mqtt_host,mqtt_port,mqtt_isssl,DeviceName,ProductKey)
    else
        local ClientId = SetClientidFnc.."|securemode=-2,authType=connwl|"
        local UserName = DeviceName.."&"..ProductKey
        local PassWord = SetDeviceTokenFnc

        clientDataTask(ClientId,UserName,mqtt_host,mqtt_port,mqtt_isssl,PassWord,Registration)
    end
end

--获取一型一密的连接参数
local function clientEncryptionTask(Registration,DeviceName,ProductKey,ProductSecret,InstanceId,mqtt_host,mqtt_port,mqtt_isssl)
    sys.taskInit(function()
        --预注册
        if not Registration then
            ClientId = DeviceName.."|securemode=2,authType=register,random=123,signmethod=hmacmd5|"
        --免预注册
        else
            if InstanceId and #InstanceId > 0 then
                ClientId = DeviceName.."|securemode=-2,authType=regnwl,random=123,signmethod=hmacmd5,instanceId="..InstanceId.."|"
            else
                ClientId = DeviceName.."|securemode=-2,authType=regnwl,random=123,signmethod=hmacmd5|"
            end
        end
        local UserName = DeviceName.."&"..ProductKey
        local content = "deviceName"..DeviceName.."productKey"..ProductKey.."random123"
        local PassWord = crypto.hmac_md5(content, ProductSecret)

        local mqttClient = mqtt.create(nil, mqtt_host, mqtt_port, true)  --客户端创建
        if mqttClient == nil then
            log.error("aliyun", "一型一密要求固件支持TLS加密, 当前固件不支持!!!")
            return
        end
        log.debug("aliyun", "一型一密认证三元组", ClientId, UserName, PassWord)
        mqttClient:auth(ClientId,UserName,PassWord) --三元组配置
        mqttClient:autoreconn(true, 30000)
        local flag = true
        mqttClient:on(function(mqtt_client, event, data, payload)  --mqtt回调注册
            if event == "recv" then
                -- 无需订阅topic, 阿里云会主动下发通知
                log.info("aliyun", "downlink", "topic", data, "payload", payload)
                if payload then
                    local tJsonDecode,res = json.decode(payload)
                    if not Registration then
                        --预注册
                        if res and tJsonDecode["deviceName"] and tJsonDecode["deviceSecret"] then
                            SetDeviceSecretFnc = tJsonDecode["deviceSecret"]
                            log.debug("aliyun", "一型一密(预注册)", tJsonDecode["deviceName"], SetDeviceSecretFnc)
                            if EvtCb["reg"] then
                                EvtCb["reg"](tJsonDecode)
                            else
                                aliyun.store(tJsonDecode)
                            end
                            mqttClient:autoreconn(false)
                            mqttClient:disconnect()
                            flag = false
                            clientDataTask(DeviceName,ProductKey,mqtt_host,mqtt_port,mqtt_isssl)
                        end
                    else
                         --免预注册
                        if res and tJsonDecode["deviceName"] and tJsonDecode["deviceToken"] then
                            SetDeviceTokenFnc = tJsonDecode["deviceToken"]
                            SetClientidFnc = tJsonDecode["clientId"]
                            log.debug("aliyun", "一型一密(免预注册)", SetClientidFnc, SetDeviceTokenFnc)
                            if EvtCb["reg"] then
                                EvtCb["reg"](tJsonDecode)
                            else
                                aliyun.store(tJsonDecode)
                            end
                            mqttClient:autoreconn(false)
                            mqttClient:disconnect()
                            flag = false
                            directProc(DeviceName, ProductKey, mqtt_host, mqtt_port, mqtt_isssl, Registration)
                        end
                    end
                end
            end
        end)
        mqttClient:connect()
        while flag do
            sys.wait(1000)
        end
    end)
end

---------------------------------------------
-- 一机一密
---------------------------------------------
local function confiDentialTask()
    sys.taskInit(function()
        local client_id,user_name,password = iotauth.aliyun(opts.ProductKey, opts.DeviceName, opts.DeviceSecret)
        mqtt_task(opts.mqtt_host, opts.mqtt_port, opts.mqtt_isssl, client_id, user_name, password)
    end)
end


--正常连接 预注册一型一密获取DeviceSecret后就是正常的一机一密连接
function aliyun.clientGetDirectDataTask(DeviceName,ProductKey,mqtt_host,mqtt_port,mqtt_isssl,Registration,DeviceSecret,deviceToken,cid)
    sys.taskInit(function()
        if not Registration then
            local client_id,user_name,password = iotauth.aliyun(ProductKey,DeviceName,DeviceSecret)
            -- mqttc = mqtt.create(nil,mqtt_host, mqtt_port,mqtt_isssl)  --mqtt客户端创建
            -- mqttc:auth(client_id,user_name,password) --mqtt三元组配置
            mqtt_task(mqtt_host, mqtt_port,mqtt_isssl, client_id, user_name, password)
        else
            local clientId = cid.."|securemode=-2,authType=connwl|"
            local client_id,user_name,password = iotauth.aliyun(ProductKey,DeviceName,deviceToken)
            -- mqttc = mqtt.create(nil,mqtt_host, mqtt_port,mqtt_isssl)  --mqtt客户端创建
            -- mqttc:auth(clientId, user_name, deviceToken) --mqtt三元组配置
            mqtt_task(mqtt_host, mqtt_port,mqtt_isssl, clientId, user_name, deviceToken)
        end
    end)
end


--[[
订阅主题
@api aliyun.subscribe(topic,qos)
@string 主题内容为UTF8编码
@number qos为number类型(0/1，默认1)
@return nil
@usage
aliyun.subscribe("/b0FMK1Ga5cp/862991234567890/get", 1)
]]
function aliyun.subscribe(topic,qos)
    if mqttc and mqttc:ready() then
        mqttc:subscribe(topic,qos or 1)
    end
end


--[[
发布一条消息
@api aliyun.publish(topic,qos,payload,cbFnc,cbPara)
@string UTF8编码的主题
@number qos质量等级，0/1，默认0
@string payload 负载内容，UTF8编码
@function cbFnc 消息发布结果的回调函数,回调函数的调用形式为：cbFnc(result,cbPara)。result为true表示发布成功，false或者nil表示订阅失败；cbPara为本接口中的第5个参数
@param cbPara 消息发布结果回调函数的回调参数
@return nil
@usage
aliyun.publish("/b0FMK1Ga5cp/862991234567890/update",0,"test")
aliyun.publish("/b0FMK1Ga5cp/862991234567890/update",1,"test",cbFnc,"cbFncPara")
]]
function aliyun.publish(topic,qos,payload,cbFnc,cbPara)
    if mqttc and mqttc:ready() then
        local pkgid = mqttc:publish(topic, payload, qos)
        if cbFnc then
            if pkgid then
                sys.taskInit(function()
                    local timeout = 15000
                    while timeout > 0 do
                        local result, evt, tmp = sys.waitUntil("aliyun_evt", 1000)
                        -- log.debug("aliyun", "等待publish的sent事件", result, evt, tmp)
                        if evt == "sent" and pkgid == tmp then
                            cbFnc(true, cbPara)
                            return
                        end
                        timeout = timeout - 1000
                    end
                    cbFnc(false, cbPara)
                end)
            else
                cbFnc(true, cbPara)
            end
        end
    else
        cbFnc(false, cbPara)
    end
end


--[[
注册事件的处理函数
@api aliyun.on(evt,cbFnc)
@string evt事件，
"connect"表示接入服务器连接结果事件，
"receive"表示接收到接入服务器的消息事件，
"publish"表示发送消息的结果事件
@function cbFnc 事件的处理函数
当evt为"connect"时，cbFnc的调用形式为：cbFnc(result)，result为true表示连接成功，false或者nil表示连接失败，
当evt为"receive"时，cbFnc的调用形式为：cbFnc(topic,payload)，topic为UTF8编码的主题(string类型)，payload为原始编码的负载(string类型)，
当evt为"publish"时，cbFnc的调用形式为：cbFnc(result)，result为true表示发送成功，false或者nil表示发送失败
@return nil
@usage
aliyun.on("connect",cbFnc)
]]
function aliyun.on(evt,cbFnc)
	EvtCb[evt] = cbFnc
end


--[[
@api aliyun.getDeviceSecret()
@return string 预注册一型一密阿里云返回的DeviceSecret
可以在应用层使用kv区来保存该参数并使用判断来避免重启后无法连接
]]
function aliyun.getDeviceSecret()
    return SetDeviceSecretFnc
end

--[[
@api aliyun.getDeviceToken()
@return string 免预注册一型一密阿里云返回的DeviceToken
可以在应用层使用kv区来保存该参数并使用判断来避免重启后无法连接
]]
function aliyun.getDeviceToken()
    return SetDeviceTokenFnc
end

--[[
@api aliyun.getClientid()
@return string 免预注册一型一密阿里云返回的Clientid
可以在应用层使用kv区来保存该参数并使用判断来避免重启后无法连接
]]
function aliyun.getClientid()
    return SetClientidFnc
end



--[[
配置阿里云物联网套件的产品信息和设备信息
@api aliyun.setup(tPara)
@table 阿里云物联网套件的产品信息和设备信息
@return nil
@usage
aliyun.setup(tPara)
-- 参数说明
一机一密认证方案时，ProductSecret参数传入nil
一型一密认证方案时，ProductSecret参数传入真实的产品密钥
Registration 是否是预注册 已预注册为false，未预注册为true
DeviceName 设备名称
ProductKey 产品key
ProductSecret 产品secret，根据此信息判断是一机一密还是一型一密
DeviceSecret 设备secret
InstanceId 如果没有注册需要填写实例id，在实例详情页面
mqtt_port mqtt端口
mqtt_isssl 是否使用ssl加密连接，true为无证书最简单的加密
]]
function aliyun.setup(tPara)
    opts = tPara
    aliyun.opts = opts
    if not opts.mqtt_host then
        if opts.host then
            opts.mqtt_host = opts.host
        elseif tPara.InstanceId and #tPara.InstanceId > 0 then
            opts.mqtt_host = tPara.InstanceId..".mqtt.iothub.aliyuncs.com"
        else
            opts.mqtt_host = tPara.ProductKey .. ".iot-as-mqtt."..tPara.RegionId..".aliyuncs.com"
        end
    end
    -- log.debug("aliyun", "mqtt host", opts.mqtt_host)
    if not tPara.ProductSecret or #tPara.ProductSecret == 0 then
        log.info("aliyun", "一机一密模式")
        confiDentialTask()
    else
        log.info("aliyun", string.format("一型一密(%s)模式 - %s", tPara.Registration and "预注册" or "免预注册", tPara.reginfo and "已获取注册信息" or "开始获取注册信息"))
        if tPara.reginfo then
            aliyun.clientGetDirectDataTask(tPara.DeviceName,tPara.ProductKey, opts.mqtt_host, 1883, tPara.mqtt_isssl,
                tPara.Registration,
                tPara.deviceSecret, tPara.deviceToken, tPara.clientId)
        else
            clientEncryptionTask(tPara.Registration,tPara.DeviceName,tPara.ProductKey,tPara.ProductSecret,tPara.InstanceId, opts.mqtt_host, 1883,tPara.mqtt_isssl)
        end
    end
end

--[[
判断阿里云物联网套件是否已经连接
@api aliyun.ready()
@return boolean 阿里云物联网套件是否已经连接
@usage
-- 本函数于2024.6.17新增
if aliyun.ready() then
    log.info("aliyun", "已连接")
end
]]
function aliyun.ready()
    if mqttc and mqttc:ready() then
        return true
    end
end

--[[
获取或存储注册信息
@api aliyun.store(result)
@table result 注册结果，如果为nil则表示获取注册信息
@return table 注册信息，如果为nil则表示获取失败
@usage
-- 获取注册信息
local store = aliyun.store()
-- 存储注册信息
aliyun.store(result)
]]
function aliyun.store(result)
    if result then
        log.debug("aliyun", "注册结果", json.encode(result))
        if fskv then
            fskv.set("ProductKey", result["productKey"])
            fskv.set("DeviceName",result["deviceName"])
            if result["deviceSecret"] then
                fskv.set("deviceSecret",result["deviceSecret"])
            else
                fskv.set("deviceToken",result["deviceToken"])
                fskv.set("clientId", result["clientId"])
            end
        else
            log.debug("aliyun", "fskv not found, use io/fs")
            io.writeFile("/alireg.json", json.encode(result))
        end
    else
        local store = {}
        if fskv then
            store.deviceName = fskv.get("DeviceName") or fskv.get("deviceName")
            store.productKey = fskv.get("ProductKey") or fskv.get("productKey")
            store.deviceSecret = fskv.get("deviceSecret")
            store.deviceToken = fskv.get("deviceToken")
            store.clientid = fskv.get("clientid")
        else
            local tmp = io.readFile("/alireg.json")
            if tmp then
                store = json.decode(tmp)
                if not store then
                    store = {}
                end
            end
        end
        return store
    end
end

return aliyun
