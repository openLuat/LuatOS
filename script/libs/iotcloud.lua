--[[
@module iotcloud
@summary iotcloud 云平台库 (已支持: 腾讯云 阿里云 onenet 华为云 涂鸦云 百度云 Tlink云 其他也会支持,有用到的提issue会加速支持)  
@version 2.1
@date    2024.10.14
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用

    -- 腾讯云 
    -- 动态注册
    -- iotcloudc = iotcloud.new(iotcloud.TENCENT,{produt_id = "xxx" ,product_secret = "xxx"})
    -- 密钥校验
    -- iotcloudc = iotcloud.new(iotcloud.TENCENT,{produt_id = "xxx",device_name = "123456789",device_secret = "xxx=="})
    -- 证书校验
    -- iotcloudc = iotcloud.new(iotcloud.TENCENT,{produt_id = "xxx",device_name = "123456789"},{tls={client_cert=io.readFile("/luadb/client_cert.crt")}})

    -- 阿里云  
    -- 一型一密(免预注册-仅企业版支持)
    -- iotcloudc = iotcloud.new(iotcloud.ALIYUN,{instance_id = "xxx",produt_id = "xxx",product_secret = "xxx"}) -- 企业版公共实例
    -- 一型一密(预注册)
    -- iotcloudc = iotcloud.new(iotcloud.ALIYUN,{produt_id = "xxx",device_name = "xxx",product_secret = "xxx"})                     -- 旧版公共实例
    -- iotcloudc = iotcloud.new(iotcloud.ALIYUN,{instance_id = "xxx",produt_id = "xxx",device_name = "xxx",product_secret = "xxx"}) -- 新版公共实例
    -- 一机一密(预注册)
    -- iotcloudc = iotcloud.new(iotcloud.ALIYUN,{produt_id = "xxx",device_name = "xxx",device_secret = "xxx"})                    -- 旧版公共实例
    -- iotcloudc = iotcloud.new(iotcloud.ALIYUN,{instance_id = "xxx",produt_id = "xxx",device_name = "xxx",device_secret = "xxx"})-- 新版公共实例


    -- ONENET云
    -- 动态注册
    -- iotcloudc = iotcloud.new(iotcloud.ONENET,{produt_id = "xxx",userid = "xxx",userkey = "xxx"})
    -- 一型一密
    -- iotcloudc = iotcloud.new(iotcloud.ONENET,{produt_id = "xxx",product_secret = "xxx"})
    -- 一机一密
    -- iotcloudc = iotcloud.new(iotcloud.ONENET,{produt_id = "xxx",device_name = "xxx",device_secret = "xxx"})

    -- 华为云
    -- 动态注册(免预注册)
    -- iotcloudc = iotcloud.new(iotcloud.HUAWEI,{produt_id = "xxx",project_id = "xxx",endpoint = "xxx",
    --                         iam_username="xxx",iam_password="xxx",iam_domain="xxx"})
    -- 手动注册(预注册)
    -- iotcloudc = iotcloud.new(iotcloud.HUAWEI,{produt_id = "xxx",endpoint = "xxx",device_name = "xxx",device_secret = "xxx"})

    -- 涂鸦云 
    -- iotcloudc = iotcloud.new(iotcloud.TUYA,{device_name = "xxx",device_secret = "xxx"})

    -- 百度云 
    -- iotcloudc = iotcloud.new(iotcloud.BAIDU,{produt_id = "afadjlw",device_name = "test",device_secret = "BBDVsSRGefaknffT"})
    -- iotcloudc = iotcloud.new(iotcloud.BAIDU,{produt_id = "xxx",device_name = "xxx"},{tls={server_cert=io.readFile("/luadb/GlobalSign.cer"),client_cert=io.readFile("/luadb/client_cert"),client_key=io.readFile("/luadb/client_private_key")}})

    -- Tlink云  
    -- iotcloudc = iotcloud.new(iotcloud.TLINK,{produt_id = "xxx",product_secret = "xxx",device_name = "xxx"})
    -- iotcloudc = iotcloud.new(iotcloud.TLINK,{produt_id = "xxx",product_secret = "xxx",device_name = "xxx"},{tls={client_cert=io.readFile("/luadb/client_cert.crt")}})

]]



local iotcloud = {}
--云平台
--//@const TENCENT string 腾讯云
iotcloud.TENCENT            = "tencent"     -- 腾讯云
--//@const ALIYUN string 阿里云
iotcloud.ALIYUN             = "aliyun"      -- 阿里云
--//@const ONENET string ONENET云
iotcloud.ONENET             = "onenet"      -- ONENET云
--//@const HUAWEI string 华为云
iotcloud.HUAWEI             = "huawei"      -- 华为云
--//@const TUYA string 涂鸦云
iotcloud.TUYA               = "tuya"        -- 涂鸦云
--//@const BAIDU string 百度云
iotcloud.BAIDU               = "baidu"      -- 百度云
--//@const TLINK string Tlink云
iotcloud.TLINK               = "tlink"      -- Tlink云

--认证方式
local iotcloud_certificate  = "certificate" -- 秘钥认证
local iotcloud_key          = "key"         -- 证书认证
-- event
--//@const CONNECT string 连接上服务器
iotcloud.CONNECT            = "connect"     -- 连接上服务器
--//@const SEND string 发送消息
iotcloud.SEND               = "SEND"        -- 发送消息
--//@const RECEIVE string 接收到消息
iotcloud.RECEIVE            = "receive"     -- 接收到消息
--//@const DISCONNECT string 服务器连接断开
iotcloud.DISCONNECT         = "disconnect"  -- 服务器连接断开
--//@const OTA string ota消息
iotcloud.OTA                = "ota"         -- ota消息


local cloudc_table = {}     -- iotcloudc 对象表

local cloudc = {}
cloudc.__index = cloudc

-- 云平台连接成功处理函数,此处可订阅一些主题或者上报版本等默认操作
local function iotcloud_connect(iotcloudc)
    -- mqtt_client:subscribe({[topic1]=1,[topic2]=1,[topic3]=1})--多主题订阅
    if iotcloudc.cloud == iotcloud.TENCENT then     -- 腾讯云
        iotcloudc:subscribe("$ota/update/"..iotcloudc.product_id.."/"..iotcloudc.device_name)    -- 订阅ota主题
        iotcloudc:publish("$ota/report/"..iotcloudc.product_id.."/"..iotcloudc.device_name,"{\"type\":\"report_version\",\"report\":{\"version\": \"".._G.VERSION.."\"}}")   -- 上报ota版本信息
    elseif iotcloudc.cloud == iotcloud.ALIYUN then  -- 阿里云
        iotcloudc:subscribe("/ota/device/upgrade/"..iotcloudc.product_id.."/"..iotcloudc.device_name)    -- 订阅ota主题
        iotcloudc:publish("/ota/device/inform/"..iotcloudc.product_id.."/"..iotcloudc.device_name,"{\"id\":1,\"params\":{\"version\":\"".._G.VERSION.."\"}}")   -- 上报ota版本信息
    elseif iotcloudc.cloud == iotcloud.ONENET then  -- 中国移动云
    elseif iotcloudc.cloud == iotcloud.HUAWEI then  -- 华为云
        iotcloudc:subscribe("$oc/devices/"..iotcloudc.device_id.."/sys/events/down")    -- 订阅ota主题
        iotcloudc:publish("$oc/devices/"..iotcloudc.device_id.."/sys/events/up","{\"services\":[{\"service_id\":\"$ota\",\"event_type\":\"version_report\",\"paras\":{\"fw_version\":\"".._G.VERSION.."\"}}]}")   -- 上报ota版本信息
    elseif iotcloudc.cloud == iotcloud.TUYA then  -- 涂鸦云
    elseif iotcloudc.cloud == iotcloud.TLINK then  -- Tlink云
        iotcloudc:subscribe(iotcloudc.device_name.."/+")    -- 订阅主题
        
    end
end

local function http_downloald_callback(content_len,body_len,iotcloudc)
    -- print("http_downloald_callback-------------------",content_len,body_len)
    if iotcloudc.cloud == iotcloud.TENCENT then
        if body_len == 0 then
            -- 开始升级     type：消息类型 state：状态为烧制中
            iotcloudc:publish("$ota/report/"..iotcloudc.product_id.."/"..iotcloudc.device_name,"{\"type\":\"report_progress\",\"report\":{\"progress\":{\"state\": \"burning\",\"result_code\": \"0\",\"result_msg\": \"\"}},\"version\": \""..iotcloudc.ota_version.."\"}")
        else
            -- 下载进度     type：消息类型 state：状态为正在下载中 percent：当前下载进度，百分比
            iotcloudc:publish("$ota/report/"..iotcloudc.product_id.."/"..iotcloudc.device_name,"{\"type\":\"report_progress\",\"report\":{\"progress\":{\"state\": \"downloading\",\"percent\": \""..body_len*100//content_len.."\",\"result_code\": \"0\",\"result_msg\": \"\"}},\"version\": \""..iotcloudc.ota_version.."\"}")
        end
    elseif iotcloudc.cloud == iotcloud.HUAWEI then
        iotcloudc:publish("$oc/devices/"..iotcloudc.device_id.."/sys/events/up","{\"services\":[{\"service_id\":\"$ota\",\"event_type\":\"upgrade_progress_report\",\"paras\":{\"result_code\":\"0\",\"version\":\"".._G.VERSION.."\",\"progress\":\""..(body_len*100//content_len - 1).."\"}}]}")   -- 上报ota版本信息
    end
end 

local function iotcloud_ota_download(iotcloudc,ota_payload,config)
    local ota_url = nil
    local ota_headers = nil
    local body_ota = nil
    config.callback = http_downloald_callback
    config.userdata = iotcloudc

    if iotcloudc.cloud == iotcloud.TENCENT then
        ota_url = ota_payload.url
    elseif iotcloudc.cloud == iotcloud.ALIYUN then
        ota_url = ota_payload.data.url
    elseif iotcloudc.cloud == iotcloud.HUAWEI then
        ota_url = ota_payload.services[1].paras.url
        ota_headers = {["Content-Type"]="application/json;charset=UTF-8",["Authorization"]="Bearer "..ota_payload.services[1].paras.access_token}
    end

    local code, headers, body = http.request("GET", ota_url, ota_headers, body_ota, config).wait()
    -- log.info("ota download", code, headers, body) -- 只返回code和headers
    if code == 200 or code == 206 then
        if iotcloudc.cloud == iotcloud.TENCENT then  -- 此为腾讯云
            -- 升级成功     type：消息类型 state：状态为已完成
            iotcloudc:publish("$ota/report/"..iotcloudc.product_id.."/"..iotcloudc.device_name,"{\"type\":\"report_progress\",\"report\":{\"progress\":{\"state\": \"done\",\"result_code\": \"0\",\"result_msg\": \"\"}},\"version\": \""..iotcloudc.ota_version.."\"}")
        elseif iotcloudc.cloud == iotcloud.ALIYUN then -- 此为阿里云
            
        elseif iotcloudc.cloud == iotcloud.HUAWEI then
            iotcloudc:publish("$oc/devices/"..iotcloudc.device_id.."/sys/events/up","{\"services\":[{\"service_id\":\"$ota\",\"event_type\":\"upgrade_progress_report\",\"paras\":{\"result_code\":\"0\",\"version\":\""..iotcloudc.ota_version.."\",\"progress\":\"100\"}}]}")   -- 上报ota版本信息
        end
    else
        if iotcloudc.cloud == iotcloud.TENCENT then  -- 此为腾讯云
            -- 升级失败     type：消息类型 state：状态为失败 result_code：错误码，-1：下载超时；-2：文件不存在；-3：签名过期；-4:MD5不匹配；-5：更新固件失败 result_msg：错误消息
            iotcloudc:publish("$ota/report/"..iotcloudc.product_id.."/"..iotcloudc.device_name,"{\"type\":\"report_progress\",\"report\":{\"progress\":{\"state\": \"fail\",\"result_code\": \"-5\",\"result_msg\": \"ota_fail\"}},\"version\": \""..iotcloudc.ota_version.."\"}")
        elseif iotcloudc.cloud == iotcloud.ALIYUN then  -- 此为阿里云
            
        elseif iotcloudc.cloud == iotcloud.HUAWEI then
            iotcloudc:publish("$oc/devices/"..iotcloudc.device_id.."/sys/events/up","{\"services\":[{\"service_id\":\"$ota\",\"event_type\":\"upgrade_progress_report\",\"paras\":{\"result_code\":\"255\"}}]}")   -- 上报ota版本信息
        end
    end
    sys.publish("iotcloud", iotcloudc, iotcloud.OTA,code == 200 or code == 206)
end

-- iotcloud mqtt回调函数
local function iotcloud_mqtt_callback(mqtt_client, event, data, payload)
    local iotcloudc = nil
    -- 遍历出 iotcloudc
    for k, v in pairs(cloudc_table) do
        if v.mqttc == mqtt_client then
            iotcloudc = v
        end
    end

    local isfota,otadst
    if fota then isfota = true else otadst = "/update.bin" end
    -- otadst = "/update.bin"--test

    -- print("iotcloud_mqtt_callback",mqtt_client, event, data, payload)
    -- 用户自定义代码
    if event == "conack" then                               -- 连接上服务器
        iotcloud_connect(iotcloudc)
        sys.publish("iotcloud",iotcloudc,iotcloud.CONNECT, data, payload)
    elseif event == "recv" then                             -- 接收到消息
        if iotcloudc.cloud == iotcloud.TENCENT and data == "$ota/update/"..iotcloudc.product_id.."/"..iotcloudc.device_name then -- 腾讯云ota
            local ota_payload = json.decode(payload)
            if ota_payload.type == "update_firmware" then
                iotcloudc.ota_version = ota_payload.version
                sys.taskInit(iotcloud_ota_download,iotcloudc,ota_payload,{fota=isfota,dst=otadst,timeout = 120000})
                
            end
        elseif iotcloudc.cloud == iotcloud.ALIYUN and data == "/ota/device/upgrade/"..iotcloudc.product_id.."/"..iotcloudc.device_name then -- 阿里云ota
            local ota_payload = json.decode(payload)
            if ota_payload.message == "success" then
                iotcloudc.ota_version = ota_payload.version
                sys.taskInit(iotcloud_ota_download,iotcloudc,ota_payload,{fota=isfota,dst=otadst,timeout = 120000})
            end
        elseif iotcloudc.cloud == iotcloud.HUAWEI and data == "$oc/devices/"..iotcloudc.device_id.."/sys/events/down" then -- 华为云ota
            local ota_payload = json.decode(payload)
            if ota_payload.services[1].event_type == "version_query" then
                iotcloudc:publish("$oc/devices/"..iotcloudc.device_id.."/sys/events/up","{\"services\":[{\"service_id\":\"$ota\",\"event_type\":\"version_report\",\"paras\":{\"fw_version\":\"".._G.VERSION.."\"}}]}")   -- 上报ota版本信息
            elseif ota_payload.services[1].event_type == "firmware_upgrade" then
                iotcloudc.ota_version = ota_payload.services[1].paras.version
                sys.taskInit(iotcloud_ota_download,iotcloudc,ota_payload,{fota=isfota,dst=otadst,timeout = 120000})
            end
        else
            sys.publish("iotcloud", iotcloudc, iotcloud.RECEIVE,data,payload)
        end
    elseif event == "sent" then                             -- 发送消息
        sys.publish("iotcloud", iotcloudc, iotcloud.SEND,data,payload)
    elseif event == "disconnect" then                       -- 服务器连接断开
        sys.publish("iotcloud", iotcloudc, iotcloud.DISCONNECT)
    end
end

-- 腾讯云自动注册
local function iotcloud_tencent_autoenrol(iotcloudc)
    local deviceName = iotcloudc.device_name
    local nonce = math.random(1,100)
    local timestamp = os.time()
    local data = "deviceName="..deviceName.."&nonce="..nonce.."&productId="..iotcloudc.product_id.."&timestamp="..timestamp
    local hmac_sha1_data = crypto.hmac_sha1(data,iotcloudc.product_secret):lower()
    local signature = crypto.base64_encode(hmac_sha1_data)
    local cloud_body = {
        deviceName=deviceName,
        nonce=nonce,
        productId=iotcloudc.product_id,
        timestamp=timestamp,
        signature=signature,
    }
    local cloud_body_json = json.encode(cloud_body)
    local code, headers, body = http.request("POST","https://ap-guangzhou.gateway.tencentdevices.com/register/dev", 
            {["Content-Type"]="application/json;charset=UTF-8"},
            cloud_body_json
    ).wait()
    if code == 200 then
        local dat, result, errinfo = json.decode(body)
        if result then
            if dat.code==0 then
                local payload = crypto.cipher_decrypt("AES-128-CBC","ZERO",crypto.base64_decode(dat.payload),string.sub(iotcloudc.product_secret,1,16),"0000000000000000")
                local payload = json.decode(payload)
                fskv.set("iotcloud_tencent", payload)
                if payload.encryptionType == 1 then     -- 证书认证
                    iotcloudc.authentication = iotcloud_certificate
                elseif payload.encryptionType == 2 then -- 密钥认证
                    iotcloudc.authentication = iotcloud_key
                end
                return true
            else
                log.info("http.post", code, headers, body)
                return false
            end
        end
    else
        log.info("http.post", code, headers, body)
        return false
    end
end

-- 腾讯云参数配置逻辑
local function iotcloud_tencent_config(iotcloudc,iot_config,connect_config)
    iotcloudc.cloud = iotcloud.TENCENT
    if iot_config.product_secret then                       -- 有product_secret说明是动态注册
        iotcloudc.product_secret = iot_config.product_secret
        if not fskv.get("iotcloud_tencent") then 
            if not iotcloud_tencent_autoenrol(iotcloudc) then return false end
        end
        local data = fskv.get("iotcloud_tencent")
        -- print("payload",data.encryptionType,data.psk,data.clientCert,data.clientKey)
        if data.encryptionType == 1 then                    -- 证书认证
            iotcloudc.ip = 8883
            iotcloudc.isssl = true
            iotcloudc.ca_file = {client_cert = data.clientCert,client_key = data.clientKey}
            iotcloudc.client_id,iotcloudc.user_name = iotauth.qcloud(iotcloudc.product_id,iotcloudc.device_name,"")
        elseif data.encryptionType == 2 then                -- 密钥认证
            iotcloudc.ip = 1883
            iot_config.device_secret = data.psk
            iotcloudc.client_id,iotcloudc.user_name,iotcloudc.password = iotauth.qcloud(iotcloudc.product_id,iotcloudc.device_name,iot_config.device_secret,iot_config.method)
        end
    else                                                    -- 否则为非动态注册
        if iot_config.device_secret then                    -- 密钥认证
            iotcloudc.ip = 1883
            iotcloudc.client_id,iotcloudc.user_name,iotcloudc.password = iotauth.qcloud(iotcloudc.product_id,iotcloudc.device_name,iot_config.device_secret,iot_config.method)
        elseif connect_config.tls then                      -- 证书认证
            iotcloudc.ip = 8883
            iotcloudc.isssl = true
            iotcloudc.ca_file = {client_cert = connect_config.tls.client_cert}
            iotcloudc.client_id,iotcloudc.user_name = iotauth.qcloud(iotcloudc.product_id,iotcloudc.device_name,"")
        else                                                -- 密钥证书都没有
            return false
        end
    end
    if connect_config then
        iotcloudc.host = connect_config.host or iotcloudc.product_id..".iotcloud.tencentdevices.com"
        if connect_config.ip then iotcloudc.ip = connect_config.ip end
    else
        iotcloudc.host = iotcloudc.product_id..".iotcloud.tencentdevices.com"
    end
    return true
end

local function iotcloud_aliyun_callback(mqtt_client, event, data, payload)
    -- log.info("mqtt", "event", event, mqtt_client, data, payload)
    if data == "/ext/regnwl" or data == "/ext/register" then sys.publish("aliyun_autoenrol", payload) end
    if event == "disconnect" then mqtt_client:close() end
end

-- 阿里云自动注册
local function iotcloud_aliyun_autoenrol(iotcloudc,register)
    local random = math.random(1,999)
    local data = "deviceName"..iotcloudc.device_name.."productKey"..iotcloudc.product_id.."random"..random
    local mqttClientId = iotcloudc.device_name.."|securemode="..(register and "2" or "-2")..",authType="..(register and "register" or "regnwl")..",random="..random..",signmethod=hmacsha1" .. (iotcloudc.instance_id and (",instanceId="..iotcloudc.instance_id) or "").."|"
    local mqttUserName = iotcloudc.device_name.."&"..iotcloudc.product_id
    local mqttPassword = crypto.hmac_sha1(data,iotcloudc.product_secret):lower()
    -- print("iotcloud_aliyun_autoenrol",mqttClientId,mqttUserName,mqttPassword)
    aliyun_mqttc = mqtt.create(nil, iotcloudc.instance_id and (iotcloudc.instance_id..".mqtt.iothub.aliyuncs.com") or iotcloudc.product_id..".iot-as-mqtt.cn-shanghai.aliyuncs.com", 443,true)
    aliyun_mqttc:auth(mqttClientId,mqttUserName,mqttPassword)
    aliyun_mqttc:on(iotcloud_aliyun_callback)
    aliyun_mqttc:connect()
    local result, payload = sys.waitUntil("aliyun_autoenrol", 30000)
    -- print("aliyun_autoenrol",result, payload)
    if result then
        local payload = json.decode(payload)
        fskv.set("iotcloud_aliyun", payload)
        -- print("aliyun_autoenrol payload",payload.clientId, payload.deviceToken,data.deviceSecret)
        return true
    else
        return false
    end
end

-- 阿里云参数配置逻辑
local function iotcloud_aliyun_config(iotcloudc,iot_config,connect_config)
    iotcloudc.cloud = iotcloud.ALIYUN
    iotcloudc.instance_id = iot_config.instance_id
    if iot_config.product_secret then                       -- 有 product_secret 说明是动态注册(一型一密)
        iotcloudc.product_secret = iot_config.product_secret
        if not fskv.get("iotcloud_aliyun") then 
            if not iotcloud_aliyun_autoenrol(iotcloudc,iot_config.device_name and true) then return false end
        end
        local data = fskv.get("iotcloud_aliyun")
        -- print("aliyun_autoenrol payload",data.clientId, data.deviceToken,data.deviceSecret)
        if data.deviceSecret then                           -- 一型一密(预注册)
            iotcloudc.client_id,iotcloudc.user_name,iotcloudc.password = iotauth.aliyun(iotcloudc.product_id,iotcloudc.device_name,data.deviceSecret,iot_config.method)
        else                                                -- 一型一密(免预注册)
            iotcloudc.client_id = data.clientId.."|securemode=-2,authType=connwl|"
            iotcloudc.user_name = iotcloudc.device_name.."&"..iotcloudc.product_id
            iotcloudc.password = data.deviceToken
        end
        iotcloudc.ip = 1883
    else                                                    -- 否则为非动态注册(一机一密)
        if iot_config.device_secret or iot_config.key then                    -- 密钥认证
            iot_config.device_secret = iot_config.device_secret or iot_config.key
            iotcloudc.ip = 1883
            iotcloudc.client_id,iotcloudc.user_name,iotcloudc.password = iotauth.aliyun(iotcloudc.product_id,iotcloudc.device_name,iot_config.device_secret,iot_config.method)
        -- elseif connect_config.tls then                   -- 证书认证
        --     iotcloudc.ip = 443
        --     iotcloudc.isssl = true
        --     iotcloudc.ca_file = {client_cert = connect_config.tls.client_cert}
        --     iotcloudc.client_id,iotcloudc.user_name = iotauth.aliyun(iotcloudc.product_id,iotcloudc.device_name,"",iot_config.method,nil,true)
        else                                                -- 密钥证书都没有
            return false
        end
    end
    if connect_config then
        iotcloudc.host = connect_config.host or (iotcloudc.instance_id and (iotcloudc.instance_id..".mqtt.iothub.aliyuncs.com")) or iotcloudc.product_id..".iot-as-mqtt.cn-shanghai.aliyuncs.com"
        if connect_config.ip then iotcloudc.ip = connect_config.ip end
    else
        iotcloudc.host = iotcloudc.instance_id and (iotcloudc.instance_id..".mqtt.iothub.aliyuncs.com") or (iotcloudc.product_id..".iot-as-mqtt.cn-shanghai.aliyuncs.com")
    end
    return true
end

-- 中国移动云自动注册
local function iotcloud_onenet_autoenrol(iotcloudc)
    local version = '2022-05-01'
    local res = "userid/"..iotcloudc.userid
    local et = '32472115200'
    local method = 'SHA256'
    local key = crypto.base64_decode(iotcloudc.userkey)
    local StringForSignature  = et .. '\n' .. method .. '\n' .. res ..'\n' .. version
    local sign1 = crypto.hmac_sha256(StringForSignature,key)
    local sign2 = sign1:fromHex()
    local sign = crypto.base64_encode(sign2)
    sign = string.urlEncode(sign)
    res = string.urlEncode(res)
    local token = string.format('version=%s&res=%s&et=%s&method=%s&sign=%s',version, res, et, method, sign)
    local code, headers, body = http.request("POST","https://iot-api.heclouds.com/device/create", 
            {["Content-Type"]="application/json;charset=UTF-8",["authorization"]=token},
            "{\"product_id\":\""..iotcloudc.product_id.."\",\"device_name\":\""..iotcloudc.device_name.."\"}"
    ).wait()
    if code == 200 then
        local dat, result, errinfo = json.decode(body)
        if result then
            if dat.code==0 then
                fskv.set("iotcloud_onenet", dat.data.sec_key)
                return true
            else
                log.info("http.post", code, headers, body)
                return false
            end
        end
    else
        log.info("http.post", code, headers, body)
        return false
    end
end

-- 中国移动云参数配置逻辑
local function iotcloud_onenet_config(iotcloudc,iot_config,connect_config)
    iotcloudc.cloud = iotcloud.ONENET
    iotcloudc.host  = "mqtts.heclouds.com"
    iotcloudc.ip    = 1883
    if iot_config.product_secret then                       -- 一型一密
        iotcloudc.product_secret = iot_config.product_secret
        iotcloudc.client_id,iotcloudc.user_name,iotcloudc.password = iotauth.onenet(iotcloudc.product_id, iotcloudc.device_name, iot_config.product_secret, nil, nil, nil, "products/" .. iotcloudc.product_id)
    elseif iot_config.device_secret then                              -- 一机一密
        iotcloudc.client_id,iotcloudc.user_name,iotcloudc.password = iotauth.onenet(iotcloudc.product_id,iotcloudc.device_name,iot_config.device_secret)
    elseif iot_config.userid and iot_config.userkey then    -- 动态注册
        iotcloudc.userid = iot_config.userid
        iotcloudc.userkey = iot_config.userkey
        if not fskv.get("iotcloud_onenet") then 
            if not iotcloud_onenet_autoenrol(iotcloudc) then return false end
        end
        local data = fskv.get("iotcloud_onenet")
        -- print("fskv.get data",data)
        iotcloudc.client_id,iotcloudc.user_name,iotcloudc.password = iotauth.onenet(iotcloudc.product_id,iotcloudc.device_name,data)
    end
    return true
end

-- 华为云自动注册
local function iotcloud_huawei_autoenrol(iotcloudc)
    local token_code, token_headers, token_body = http.request("POST","https://iam."..iotcloudc.region..".myhuaweicloud.com/v3/auth/tokens", 
            {["Content-Type"]="application/json;charset=UTF-8"},
            "{\"auth\":{\"identity\":{\"methods\":[\"password\"],\"password\":{\"user\":{\"domain\":{\"name\":\""..iotcloudc.iam_domain.."\"},\"name\":\""..iotcloudc.iam_username.."\",\"password\":\""..iotcloudc.iam_password.."\"}}},\"scope\":{\"project\":{\"name\":\""..iotcloudc.region.."\"}}}}"
    ).wait()
    -- print("iotcloud_huawei_autoenrol token_code", token_code, token_headers, token_body)
    if token_code ~= 201 then
        log.error("iotcloud_huawei_autoenrol",token_body)
        return false
    end

    local http_url = "https://"..iotcloudc.endpoint..".iotda."..iotcloudc.region..".myhuaweicloud.com/v5/iot/"..iotcloudc.project_id.."/devices"
    local code, headers, body = http.request("POST",http_url, 
            {["Content-Type"]="application/json;charset=UTF-8",["X-Auth-Token"]=token_headers["X-Subject-Token"]},
            "{\"node_id\": \""..iotcloudc.device_name.."\",\"product_id\": \""..iotcloudc.product_id.."\"}"
    ).wait()
    -- print("iotcloud_huawei_autoenrol", code, headers, body)
    if code == 201 then
        local dat, result, errinfo = json.decode(body)
        if result then
            fskv.set("iotcloud_huawei", dat.auth_info.secret)
            return true
        end
    else
        log.error("iotcloud_huawei_autoenrol", code, headers, body)
        return false
    end
end

-- 华为云参数配置逻辑
local function iotcloud_huawei_config(iotcloudc,iot_config,connect_config)
    iotcloudc.cloud = iotcloud.HUAWEI
    iotcloudc.region = iot_config.region or "cn-north-4"
    iotcloudc.endpoint = iot_config.endpoint
    iotcloudc.project_id = iot_config.project_id
    iotcloudc.iam_username = iot_config.iam_username
    iotcloudc.iam_password = iot_config.iam_password
    iotcloudc.iam_domain = iot_config.iam_domain
    iotcloudc.device_id = iot_config.device_id or iotcloudc.product_id.."_"..iotcloudc.device_name
    iotcloudc.device_secret = iot_config.device_secret
    iotcloudc.ip = 8883
    iotcloudc.isssl = true

    if connect_config.host == nil then
        if iotcloudc.endpoint then
            iotcloudc.host = iotcloudc.endpoint..".iotda-device."..iotcloudc.region..".myhuaweicloud.com"
        else
            log.error("iotcloud",iotcloudc.cloud,"endpoint is nil")
            return false
        end
    end

    -- 一型一密(自动注册) 最终会获取设备秘钥
    if iotcloudc.product_id and iotcloudc.project_id and iotcloudc.iam_username and iotcloudc.iam_password and iotcloudc.iam_domain then
        if not fskv.get("iotcloud_huawei") then 
            if not iotcloud_huawei_autoenrol(iotcloudc) then return false end
        end
        iotcloudc.device_secret = fskv.get("iotcloud_huawei")
    end

    if iotcloudc.device_secret then                         -- 一机一密
        iotcloudc.client_id,iotcloudc.user_name,iotcloudc.password = iotauth.iotda(iotcloudc.device_id,iotcloudc.device_secret)
    else
        log.error("iotcloud",iotcloudc.cloud,"device_secret is nil")
        return false
    end
    return true
end

-- 涂鸦云参数配置逻辑
local function iotcloud_tuya_config(iotcloudc,iot_config,connect_config)
    iotcloudc.cloud = iotcloud.TUYA
    iotcloudc.host = "m1.tuyacn.com"
    iotcloudc.ip = 8883
    iotcloudc.isssl = true
    iotcloudc.device_secret = iot_config.device_secret
    if iotcloudc.device_secret then
        iotcloudc.client_id,iotcloudc.user_name,iotcloudc.password = iotauth.tuya(iotcloudc.device_name,iotcloudc.device_secret)
    else
        return false
    end
    return true
end

-- 百度云参数配置逻辑
local function iotcloud_baidu_config(iotcloudc,iot_config,connect_config)
    iotcloudc.cloud = iotcloud.BAIDU
    iotcloudc.region = iot_config.region or "gz"
    iotcloudc.host = iotcloudc.product_id..".iot."..iotcloudc.region..".baidubce.com"
    iotcloudc.ip = 1883
    iotcloudc.device_secret = iot_config.device_secret
    if iotcloudc.device_secret then
        iotcloudc.client_id,iotcloudc.user_name,iotcloudc.password = iotauth.baidu(iotcloudc.product_id,iotcloudc.device_name,iotcloudc.device_secret)
    elseif connect_config.tls then
        iotcloudc.ip = 1884
        iotcloudc.isssl = true
        iotcloudc.client_id=""
        iotcloudc.user_name=""
        iotcloudc.password=""
    else
        return false
    end
    return true
end

-- TLINK云参数配置逻辑
local function iotcloud_tlink_config(iotcloudc,iot_config,connect_config)
    iotcloudc.cloud = iotcloud.TLINK
    iotcloudc.host = "mq.tlink.io"
    iotcloudc.ip = 1883
    iotcloudc.client_id = iotcloudc.device_name
    iotcloudc.user_name = iotcloudc.product_id
    iotcloudc.password = iot_config.product_secret
    if connect_config.tls then                      -- 证书认证
        iotcloudc.ip = 8883
        iotcloudc.isssl = true
        iotcloudc.ca_file = {client_cert = connect_config.tls.client_cert}
    end
    return true
end

--[[
创建云平台对象
@api iotcloud.new(cloud,iot_config,connect_config)
@string 云平台 iotcloud.TENCENT:腾讯云 iotcloud.ALIYUN:阿里云 iotcloud.ONENET:中国移动云 iotcloud.HUAWEI:华为云 iotcloud.TUYA:涂鸦云
@table iot云平台配置, device_name:可选，默认为imei否则为unique_id iot_config.product_id:产品id(阿里云则为产品key) iot_config.product_secret:产品密钥,有此项则为动态注册 iot_config.device_secret:设备秘钥,有此项则为秘钥连接 instance_id:公共实例id,新版阿里云公共实例专用 userid:用户ID,onenet专用,动态注册使用  userkey:用户Accesskey,onenet专用,动态注册使用
@table mqtt配置, host:可选,默认为平台默认host ip:可选,默认为平台默认ip tls:加密,若有此项一般为产品认证 keepalive:心跳时间,单位s 可选,默认240 autoreconn:自动重连,number:重连时间，单位ms /bool 是否重连,默认3000ms 可选，默认不自动重连
@return table 云平台对象
@usage

    -- 腾讯云 
    -- 动态注册
    -- iotcloudc = iotcloud.new(iotcloud.TENCENT,{produt_id = "xxx" ,product_secret = "xxx"})
    -- 密钥校验
    -- iotcloudc = iotcloud.new(iotcloud.TENCENT,{produt_id = "xxx",device_name = "123456789",device_secret = "xxx=="})
    -- 证书校验
    -- iotcloudc = iotcloud.new(iotcloud.TENCENT,{produt_id = "xxx",device_name = "123456789"},{tls={client_cert=io.readFile("/luadb/client_cert.crt")}})

    -- 阿里云  
    -- 一型一密(免预注册-仅企业版支持)
    -- iotcloudc = iotcloud.new(iotcloud.ALIYUN,{instance_id = "xxx",produt_id = "xxx",product_secret = "xxx"}) -- 企业版公共实例
    -- 一型一密(预注册)
    -- iotcloudc = iotcloud.new(iotcloud.ALIYUN,{produt_id = "xxx",device_name = "xxx",product_secret = "xxx"})                     -- 旧版公共实例
    -- iotcloudc = iotcloud.new(iotcloud.ALIYUN,{instance_id = "xxx",produt_id = "xxx",device_name = "xxx",product_secret = "xxx"}) -- 新版公共实例
    -- 一机一密 (预注册)
    -- iotcloudc = iotcloud.new(iotcloud.ALIYUN,{produt_id = "xxx",device_name = "xxx",device_secret = "xxx"})                    -- 旧版公共实例
    -- iotcloudc = iotcloud.new(iotcloud.ALIYUN,{instance_id = "xxx",produt_id = "xxx",device_name = "xxx",device_secret = "xxx"})-- 新版公共实例

    -- ONENET云
    -- 动态注册
    -- iotcloudc = iotcloud.new(iotcloud.ONENET,{produt_id = "xxx",userid = "xxx",userkey = "xxx"})
    -- 一型一密
    -- iotcloudc = iotcloud.new(iotcloud.ONENET,{produt_id = "xxx",product_secret = "xxx"})
    -- 一机一密
    -- iotcloudc = iotcloud.new(iotcloud.ONENET,{produt_id = "xxx",device_name = "xxx",device_secret = "xxx"})

    -- 华为云
    -- 动态注册(免预注册)
    -- iotcloudc = iotcloud.new(iotcloud.HUAWEI,{produt_id = "xxx",project_id = "xxx",endpoint = "xxx",
    --                         iam_username="xxx",iam_password="xxx",iam_domain="xxx"})
    -- 密钥校验 (预注册)
    -- iotcloudc = iotcloud.new(iotcloud.HUAWEI,{produt_id = "xxx",endpoint = "xxx",device_name = "xxx",device_secret = "xxx"})

    -- 涂鸦云 
    -- iotcloudc = iotcloud.new(iotcloud.TUYA,{device_name = "xxx",device_secret = "xxx"})

    -- 百度云 
    -- iotcloudc = iotcloud.new(iotcloud.BAIDU,{produt_id = "afadjlw",device_name = "test",device_secret = "BBDVsSRGefaknffT"})
    -- iotcloudc = iotcloud.new(iotcloud.BAIDU,{produt_id = "xxx",device_name = "xxx"},{tls={server_cert=io.readFile("/luadb/GlobalSign.cer"),client_cert=io.readFile("/luadb/client_cert"),client_key=io.readFile("/luadb/client_private_key")}})

    -- Tlink云  
    -- iotcloudc = iotcloud.new(iotcloud.TLINK,{produt_id = "xxx",product_secret = "xxx",device_name = "xxx"})
    -- iotcloudc = iotcloud.new(iotcloud.TLINK,{produt_id = "xxx",product_secret = "xxx",device_name = "xxx"},{tls={client_cert=io.readFile("/luadb/client_cert.crt")}})

]]
function iotcloud.new(cloud,iot_config,connect_config)
    if not connect_config then connect_config = {} end
    local mqtt_ssl = nil
    local iotcloudc = setmetatable({
        cloud = nil,                                        -- 云平台
        host = nil,                                         -- host
        ip = nil,                                           -- ip
        mqttc = nil,                                        -- mqtt对象
        device_name = nil,                                  -- 设备名(一般为设备id)
        product_id = nil,                                   -- 产品id
        product_secret = nil,                               -- 产品秘钥
        device_id = nil,                                    -- 设备id(一般为设备名)
        device_secret = nil,                                -- 设备秘钥
        region = nil,                                       -- 云区域
        client_id = nil,                                    -- mqtt客户端id
        user_name = nil,                                    -- mqtt用户名
        password = nil,                                     -- mqtt密码
        authentication = nil,                               -- 认证方式:密钥认证/证书认证 
        isssl = nil,                                        -- 是否加密
        ca_file = nil,                                      -- 证书 
        ota_version = nil,                                  -- ota时目标版本
        instance_id = nil,                                  -- aliyun API专用 实例ID
        userid = nil,                                       -- onenet API专用
        userkey = nil,                                      -- onenet API专用
        iam_username = nil,                                 -- 华为云 API专用 IAM用户名
        iam_password = nil,                                 -- 华为云 API专用 华为云密码
        iam_domain = nil,                                   -- 华为云 API专用 账号名
        endpoint = nil,                                     -- 华为云 API专用
        project_id = nil,                                   -- 华为云 API专用
        
    }, cloudc)
    if fskv then fskv.init() else log.error("iotcloud","iotcloud need fskv",cloud) return false end
    if iot_config.produt_id then
        iotcloudc.product_id = iot_config.produt_id
    end
    if iot_config.device_name then                          -- 设定了就使用指定的device_name
        iotcloudc.device_name = iot_config.device_name
    elseif mobile then                                      -- 未设定优先使用imei
        iotcloudc.device_name = mobile.imei()
    else                                                    -- 无imei使用unique_id
        iotcloudc.device_name = mcu.unique_id():toHex()
    end
    if cloud == iotcloud.TENCENT or cloud == "qcloud" then  -- 此为腾讯云
        if not iotcloud_tencent_config(iotcloudc,iot_config,connect_config) then return false end
    elseif cloud == iotcloud.ALIYUN then
        if not iotcloud_aliyun_config(iotcloudc,iot_config,connect_config) then return false end
    elseif cloud == iotcloud.ONENET then
        if not iotcloud_onenet_config(iotcloudc,iot_config,connect_config) then return false end
    elseif cloud == iotcloud.HUAWEI then
        if not iotcloud_huawei_config(iotcloudc,iot_config,connect_config) then return false end
    elseif cloud == iotcloud.TUYA then
        if not iotcloud_tuya_config(iotcloudc,iot_config,connect_config) then return false end
    elseif cloud == iotcloud.BAIDU then
        if not iotcloud_baidu_config(iotcloudc,iot_config,connect_config) then return false end
    elseif cloud == iotcloud.TLINK then
        if not iotcloud_tlink_config(iotcloudc,iot_config,connect_config) then return false end
    else
        log.error("iotcloud","cloud not support",cloud)
        return false
    end
    -- print("iotauth.mqtt",iotcloudc.host,iotcloudc.ip,iotcloudc.isssl)
    -- print("iotauth.auth",iotcloudc.client_id,iotcloudc.user_name,iotcloudc.password)
    if iotcloudc.ca_file then
        iotcloudc.ca_file.verify = 1
        mqtt_ssl = iotcloudc.ca_file
    elseif iotcloudc.isssl then
        mqtt_ssl = iotcloudc.isssl
    end
    iotcloudc.mqttc = mqtt.create(nil, connect_config.host or iotcloudc.host, connect_config.ip or iotcloudc.ip, connect_config.tls or mqtt_ssl)
    if not iotcloudc.mqttc then return false end

    -- iotcloudc.mqttc:debug(true)

    iotcloudc.mqttc:auth(iotcloudc.client_id,iotcloudc.user_name,iotcloudc.password)
    iotcloudc.mqttc:keepalive(connect_config.keepalive or 240)
    iotcloudc.mqttc:autoreconn(connect_config.autoreconn and true, (type(connect_config.autoreconn) == "number") or connect_config.autoreconn)-- 自动重连机制
    iotcloudc.mqttc:on(iotcloud_mqtt_callback)              -- mqtt回调
    table.insert(cloudc_table,iotcloudc)                    -- 添加到表里记录
    return iotcloudc,error_code                             -- 错误返回待处理
end 

--[[
云平台连接
@api cloudc:connect()
@usage
iotcloudc:connect()
]]
function cloudc:connect()
    self.mqttc:connect()
end

--[[
云平台断开
@api cloudc:disconnect()
@usage
iotcloudc:disconnect()
]]
function cloudc:disconnect()
    self.mqttc:disconnect()
end

--[[
云平台订阅
@api cloudc:subscribe(topic, qos)
@string/table 主题
@number topic为string时生效 0/1/2 默认0
]]
function cloudc:subscribe(topic, qos)
    self.mqttc:subscribe(topic, qos)
end

--[[
云平台取消订阅
@api cloudc:unsubscribe(topic)
@string/table 主题
]]
function cloudc:unsubscribe(topic)
    self.mqttc:unsubscribe(topic)
end

--[[
云平台发布
@api cloudc:publish(topic,data,qos,retain)
@string/table 主题
@string 消息,必填,但长度可以是0
@number 消息级别 0/1 默认0
@number 是否存档, 0/1,默认0
]]
function cloudc:publish(topic,data,qos,retain)
    self.mqttc:publish(topic,data,qos,retain)
end

--[[
云平台关闭
@api cloudc:close()
@usage
iotcloudc:close()
]]
function cloudc:close()
    self.mqttc:close()
    for k, v in pairs(cloudc_table) do
        if v.mqttc == self.mqttc then
            table.remove(cloudc_table,k)
        end
    end
end

return iotcloud