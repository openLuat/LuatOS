-- PROJECT = "aliyundemo"
-- VERSION = "1.0.0"
-- local sys = require "sys"
-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用mqtt库需要下列语句]]
_G.sysplus = require("sysplus")

aLiyun = {}

local clientId,password,userName,DeviceSecret

local outQueue =
{
    SUBSCRIBE = {},
    PUBLISH = {},
}

local evtCb = {}

local mqttc = nil

--添加
local function insert(type,topic,qos,payload,retain)
    table.insert(outQueue[type],{t=topic,q=qos,p=payload,r=retain})
end

--删除
local function remove(type)
    if #outQueue[type]>0 then return table.remove(outQueue[type],1) end
end

--订阅步骤
local function procSubscribe(client)
    local i
    if #outQueue["SUBSCRIBE"]>0 then
        log.info("订阅表里大于零")
    else 
        log.info("订阅表里没数据")
    end

    for i=1,#outQueue["SUBSCRIBE"] do
        if not client:subscribe(outQueue["SUBSCRIBE"][i].t , outQueue["SUBSCRIBE"][i].q) then
            outQueue["SUBSCRIBE"] = {}
            return false,"procSubscribe"
        end
    end
    outQueue["SUBSCRIBE"] = {}
    return true
end

--接收处理
local function procReceive(client)
    while true do
        log.info("到接受处理方法里了")
        local ret,data,payload,DeviceName,ProductKey = sys.waitUntil("NET_SENT_RDY",30000)
        log.info("接收到消息之后传到处理方法里的数据",ret,data,payload,DeviceName,ProductKey)
        --接收到数据
        if ret then
            log.info("aLiYun.procReceive",data.topic,string.toHex(data.payload))
            --OTA消息
            if payload.topic=="/ota/device/upgrade/"..ProductKey.."/"..DeviceName then
                log.info("进到OTA升级判断里了",payload.topic)
                -- if aLiYunOta and aLiYunOta.upgrade then
                --     aLiYunOta.upgrade(data.payload)
                -- end
            --其他消息
            else    
                if evtCb["receive"] then evtCb["receive"](data.topic,data.qos,data.payload) end
            end
            
            
            --如果有等待发送的数据，则立即退出本循环
            if #outQueue["PUBLISH"]>0 then
                return true,"procReceive"
            end
        end
    end
	
    return data=="timeout" or "procReceive"
end

--发布
local function procSend(client)
    sys.taskInit(function()
        if not procSubscribe(client) then
            return false,"procSubscribe"
        end
        if #outQueue["PUBLISH"]>0 then
            log.info("发布表里大于零")
        else 
            log.info("发布表里没数据")
        end

        while #outQueue["PUBLISH"]>0 do
            local item = table.remove(outQueue["PUBLISH"],1)
            local result = client:publish(item.t,item.p,item.q)
            if item.cb then item.cb(result,item.para) end
            if not result then
                return false,"procSend" 
            end
        end
        return true,"procSend"
    end)
end

--二次连接
local function clientDataTask(clientId,user,password,mqtt_host,mqtt_port,mqtt_isssl,DeviceName,ProductKey)
    sys.taskInit(function()
        if mobile.status() == 0 then
            sys.waitUntil("IP_READY",30000)
        end
        if mobile.status() == 1 then
            local mqttc = mqtt.create(nil,mqtt_host,mqtt_port,mqtt_isssl)  --客户端创建
            mqttc:auth(clientId,user,password) --三元组配置
            mqttc:keepalive(30) -- 默认值240s
            mqttc:autoreconn(true, 3000) -- 自动重连机制
    
            mqttc:on(mqtt_cbevent)  --mqtt回调注册
            if mqttc:connect() then
                while true do
                    procSubscribe(mqttc)
                    procSend(mqttc)
                    sys.wait(1000)
                end
            end
    
    
        else
            --进入飞行模式，20秒之后，退出飞行模式
            mobile.flymode(0,true)
            sys.wait(20000)
            mobile.flymode(0,false)
        end
    end)
end

--根据返回的数据进行二次加密
local function directProc(DeviceName,ProductKey,mqtt_host,mqtt_port,mqtt_isssl,Registration)
    if not Registration then
        local clientId = DeviceName.."|securemode=2,signmethod=hmacmd5,timestamp=789|"
        local userName = DeviceName.."&"..ProductKey
        
        local content = "clientId"..DeviceName.."deviceName"..DeviceName.."productKey"..ProductKey.."timestamp789"
        log.info("content",content)
        local signKey= fskv.kv_get("deviceSecret")
        log.info("signKey",signKey)
        password =crypto.hmac_md5(content,signKey)
        log.info("password",password)

        
        log.info("aLiYun.directProc",clientId,userName,password)
        
        clientDataTask(clientId,userName,password,mqtt_host,mqtt_port,mqtt_isssl,DeviceName,ProductKey)
    else
        local clientid = fskv.kv_get("clientid")
        local deviceToken = fskv.kv_get("deviceToken")
        local clientId = clientid.."|securemode=-2,authType=connwl|"
        local userName = DeviceName.."&"..ProductKey
        local password = deviceToken

        log.info("aLiYun.directProc",clientId,userName,password)
        
        clientDataTask(clientId,userName,password,mqtt_host,mqtt_port,mqtt_isssl,DeviceName,ProductKey)
    end
end

--获取预注册和免预注册一型一密一次连接返回的数据
local function clientEncryptionTask(Registration,DeviceName,ProductKey,ProductSecret,InstanceId,mqtt_host,mqtt_port,mqtt_isssl)
    sys.taskInit(function()
        local tm = os.time()
        --一型一密
            --预注册
            if not Registration then
                clientId = DeviceName.."|securemode=2,authType=register,random="..tm..",signmethod=hmacmd5|"
            --免预注册
            else
                clientId = DeviceName.."|securemode=-2,authType=regnwl,random="..tm..",signmethod=hmacmd5,instanceId="..InstanceId.."|"
            end
            userName = DeviceName.."&"..ProductKey
            local content = "deviceName"..DeviceName.."productKey"..ProductKey.."random"..tm
            password = crypto.hmac_md5(content,ProductSecret)
    
            local mqttClient = mqtt.create(nil,mqtt_host,mqtt_port,mqtt_isssl)  --客户端创建
            mqttClient:auth(clientId,userName,password) --三元组配置
            mqttClient:on(function(mqtt_client, event, data, payload)  --mqtt回调注册
                -- 用户自定义代码
                if event == "conack" then

                elseif event == "recv" then
                    log.info("mqtt", "downlink", "topic", data, "payload", payload)
                    if payload then
                        local tJsonDecode,res = json.decode(payload)
                        if not Registration then
                            --预注册
                            if res and tJsonDecode["deviceName"] and tJsonDecode["deviceSecret"] then
                                --把当前设备的SN号改为设备秘钥
                                fskv.init()
                                fskv.set("deviceSecret", tJsonDecode["deviceSecret"])
                                mqttClient:disconnect()
                                directProc(DeviceName,ProductKey,mqtt_host,mqtt_port,mqtt_isssl,Registration)
                            end
                        else
                             --免预注册
                            if res and tJsonDecode["deviceName"] and tJsonDecode["deviceToken"] then
                                --把当前设备的SN号改为设备秘钥
                                fskv.init()
                                fskv.set("deviceToken", tJsonDecode["deviceToken"])
                                fskv.set("clientid", tJsonDecode["clientId"])
                                -- sys.wait(1000)
                                mqttClient:disconnect()
                                directProc(DeviceName,ProductKey,mqtt_host,mqtt_port,mqtt_isssl,Registration)
                            end
                        end
                        
                    end
                elseif event == "sent" then
                    log.info("mqtt", "sent", "pkgid", data)
                end
            end)
    
            mqttClient:connect()
            log.info("mqtt连接成功")
    end)
end


--底层libMQTT回调函数，上层的回调函数，通过 aLiYun.on注册
local function mqtt_cbevent(mqtt_client, event, data, payload) 
    if event == "conack" then
        evtCb["connect"](true) 
    elseif event == "recv" then -- 服务器下发的数据
        log.info("mqtt", "downlink", "topic", data, "payload", payload)

        if evtCb["receive"] then
            evtCb["receive"](data, payload)
        end
    elseif event == "sent" then
        log.info("mqtt", "sent", "pkgid", data)
    end
end


--正常连接 预注册一型一密获取DeviceSecret后就是正常的一机一密连接
local function clientDirectTask(DeviceName,ProductKey,mqtt_host,mqtt_port,mqtt_isssl)
    sys.taskInit(function()
        if mobile.status() == 0 then
            sys.waitUntil("IP_READY",30000)
        end
        if mobile.status() == 1 then
            if DeviceSecret==nil then
                DeviceSecret = fskv.get("deviceSecret")
            end
            local client_id,user_name,password = iotauth.aliyun(ProductKey,DeviceName,DeviceSecret)
            mqttc = mqtt.create(nil,mqtt_host, mqtt_port,mqtt_isssl)  --mqtt客户端创建
    
            mqttc:auth(client_id,user_name,password) --mqtt三元组配置
            mqttc:keepalive(30) -- 默认值240s
            mqttc:autoreconn(true, 3000) -- 自动重连机制
    
            mqttc:on(mqtt_cbevent)  --mqtt回调注册
            if mqttc:connect() then
                while true do
                    procSubscribe(mqttc)
                    procSend(mqttc)
                    sys.wait(1000)
                end  
            end
            
        else
            --进入飞行模式，20秒之后，退出飞行模式
            mobile.flymode(0,true)
            sys.wait(20000)
            mobile.flymode(0,false)
        end
    end)
end


--正常连接 免预注册一型一密获取deviceToken后就是正常的一机一密连接
local function clientTokenTask(DeviceName,ProductKey,mqtt_host,mqtt_port,mqtt_isssl)
    sys.taskInit(function()
        sys.wait(5000)
        if mobile.status() == 0 then
            sys.waitUntil("IP_READY",30000)
        end
        if mobile.status() == 1 then
            deviceToken = fskv.get("deviceToken")
            local clientid = fskv.kv_get("clientid")
            local clientId = clientid.."|securemode=-2,authType=connwl|"
    
            local client_id,user_name,password = iotauth.aliyun(ProductKey,DeviceName,deviceToken)
            mqttc = mqtt.create(nil,mqtt_host, mqtt_port,mqtt_isssl)  --mqtt客户端创建
    
            mqttc:auth(clientId,user_name,deviceToken) --mqtt三元组配置
            mqttc:keepalive(30) -- 默认值240s
            mqttc:autoreconn(true, 3000) -- 自动重连机制
    
            mqttc:on(mqtt_cbevent)  --mqtt回调注册
            if mqttc:connect() then
                while true do
                    procSubscribe(mqttc)
                    procSend(mqttc)
                    sys.wait(1000)
                end  
            end
    
        else
            --进入飞行模式，20秒之后，退出飞行模式
            mobile.flymode(0,true)
            sys.wait(20000)
            mobile.flymode(0,false)
        end
    end)
end

--根据掉电不消失的kv文件区来储存的deviceSecret，deviceToken来判断是进行正常连接还是
function aLiyun.operation(Registration,DeviceName,ProductKey,ProductSecret,InstanceId,mqtt_host,mqtt_port,mqtt_isssl)
    fskv.init()
    fskv.set("DeviceName",DeviceName)
    local name = fskv.get("DeviceName")
    local used = fskv.get("deviceSecret")
    local total = fskv.get("deviceToken")
    local cid = fskv.get("clientid")
    --判断是否是同一DeviceName，不是的话就重新连接
    if name == DeviceName then
        if not Registration then
            if used == nil then
                clientEncryptionTask(Registration,DeviceName,ProductKey,ProductSecret,InstanceId,mqtt_host,mqtt_port,mqtt_isssl)
            else
                clientDirectTask(DeviceName,ProductKey,mqtt_host,mqtt_port,mqtt_isssl)
            end
        else
            -- fskv.del("deviceToken")
            -- fskv.del("clientid")
            -- log.info("删除deviceToken，clientid")
            if total == nil then
                clientEncryptionTask(Registration,DeviceName,ProductKey,ProductSecret,InstanceId,mqtt_host,mqtt_port,mqtt_isssl)
            else
                clientTokenTask(DeviceName,ProductKey,mqtt_host,mqtt_port,mqtt_isssl)
            end
        end
    else
            fskv.del("deviceToken")
            fskv.del("clientid")
            fskv.del("DeviceName")
            fskv.del("deviceSecret")
            --删除kv区的数据，重新建立连接
            clientEncryptionTask(Registration,DeviceName,ProductKey,ProductSecret,InstanceId,mqtt_host,mqtt_port,mqtt_isssl)
    end
end

--一机一密连接  ConfiDential
function aLiyun.confiDentialTask(DeviceName,ProductKey,DeviceSecret,mqtt_host,mqtt_port,mqtt_isssl)
    sys.taskInit(function()
        sys.wait(5000)
        if mobile.status() == 0 then
            sys.waitUntil("IP_READY",30000)
        end
        if mobile.status() == 1 then
            local client_id,user_name,password = iotauth.aliyun(ProductKey,DeviceName,DeviceSecret)
            mqttc = mqtt.create(nil,mqtt_host, mqtt_port,mqtt_isssl)  --mqtt客户端创建
            mqttc:auth(client_id,user_name,password) --mqtt三元组配置
            mqttc:keepalive(30) -- 默认值240s
            mqttc:autoreconn(true, 3000) -- 自动重连机制

            mqttc:on(mqtt_cbevent)  --mqtt回调注册
            if mqttc:connect() then
                while true do
                    procSubscribe(mqttc)
                    procSend(mqttc)
                    sys.wait(1000)
                end  
            end
            
        else
            --进入飞行模式，20秒之后，退出飞行模式
            mobile.flymode(0,true)
            sys.wait(20000)
            mobile.flymode(0,false)
        end
    end)
end


--- 订阅主题
-- @param topic，string或者table类型，一个主题时为string类型，多个主题时为table类型，主题内容为UTF8编码
-- @param qos，number或者nil，topic为一个主题时，qos为number类型(0/1，默认0)；topic为多个主题时，qos为nil
-- @return nil
-- @usage
-- aLiYun.subscriber("/b0FMK1Ga5cp/862991234567890/get", 0)
-- aLiYun.subscriber({["/b0FMK1Ga5cp/862991234567890/get"] = 0, ["/b0FMK1Ga5cp/862991234567890/get"] = 1})
function aLiyun.subscriber(topic,qos)
    insert("SUBSCRIBE",topic,qos)
    sys.publish("aliyun_publish_ind","send")
end

--- 发布一条消息
-- @string topic，UTF8编码的主题
-- @string payload，负载
-- @number[opt=0] qos，质量等级，0/1，默认0
-- @function[opt=nil] cbFnc，消息发布结果的回调函数
-- 回调函数的调用形式为：cbFnc(result,cbPara)。result为true表示发布成功，false或者nil表示订阅失败；cbPara为本接口中的第5个参数
-- @param[opt=nil] cbPara，消息发布结果回调函数的回调参数
-- @return nil
-- @usage
-- aLiYun.publish("/b0FMK1Ga5cp/862991234567890/update","test",0)
-- aLiYun.publish("/b0FMK1Ga5cp/862991234567890/update","test",1,cbFnc,"cbFncPara")
function aLiyun.publish(topic,qos,payload,retain)
    insert("PUBLISH",topic,qos,payload,retain)
    sys.publish("aliyun_publish_ind","send")
    log.info("aliyun aliyun_publish_ind","publish")
end


--- 注册事件的处理函数
-- @string evt 事件
-- "auth"表示鉴权服务器认证结果事件
-- "connect"表示接入服务器连接结果事件
-- "reconnect"表示重连事件
-- "receive"表示接收到接入服务器的消息事件
-- @function cbFnc 事件的处理函数
-- 当evt为"auth"时，cbFnc的调用形式为：cbFnc(result)，result为true表示认证成功，false或者nil表示认证失败
-- 当evt为"connect"时，cbFnc的调用形式为：cbFnc(result)，result为true表示连接成功，false或者nil表示连接失败
-- 当evt为"receive"时，cbFnc的调用形式为：cbFnc(topic,qos,payload)，topic为UTF8编码的主题(string类型)，qos为质量等级(number类型)，payload为原始编码的负载(string类型)
-- 当evt为"reconnect"时，cbFnc的调用形式为：cbFnc()，表示lib中在自动重连阿里云服务器
-- @return nil
-- @usage
-- aLiYun.on("connect",cbFnc)
function aLiyun.on(evt,cbFnc)
	evtCb[evt] = cbFnc
end









return aLiyun
-- 用户代码已结束---------------------------------------------
