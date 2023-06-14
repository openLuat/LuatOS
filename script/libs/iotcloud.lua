



local iotcloud = {}
--云平台
iotcloud.TENCENT            = "tencent"
--认证方式
local iotcloud_certificate  = "certificate" -- 秘钥认证
local iotcloud_key          = "key"         -- 证书认证
-- event
iotcloud.CONNECT            = "connect"     -- 连接上服务器
iotcloud.RECEIVE            = "receive"     -- 接收到消息
iotcloud.OTA                = "ota"         -- ota消息
iotcloud.DISCONNECT         = "disconnect"  -- 服务器连接断开

local cloudc_table = {}     -- iotcloudc 对象表

local cloudc = {}
cloudc.__index = cloudc

-- 云平台连接成功处理函数,此处可订阅一些主题或者上报版本等默认操作
local function iotcloud_connect(iotcloudc)
    if iotcloudc.cloud == iotcloud.TENCENT then      -- 腾讯云
        -- 订阅ota主题
        iotcloudc:subscribe("$ota/update/"..iotcloudc.produt_id.."/"..iotcloudc.device_name)    
        -- 上报ota版本信息
        iotcloudc:publish("$ota/report/"..iotcloudc.produt_id.."/"..iotcloudc.device_name,"{\"type\":\"report_version\",\"report\":{\"version\": \"".._G.VERSION.."\"}}")
    end
        -- mqtt_client:subscribe({[topic1]=1,[topic2]=1,[topic3]=1})--多主题订阅
end

local function iotcloud_ota_download(iotcloudc,ota_url,config,version)
    local code, headers, body = http.request("GET", ota_url, nil, nil, config).wait()
    log.info("ota download", code, headers, body) -- 只返回code和headers
    if code == 200 or code == 206 then
        if iotcloudc.cloud == iotcloud.TENCENT then  -- 此为腾讯云
            -- 下载进度     type：消息类型 state：状态为正在下载中 percent：当前下载进度，百分比
            iotcloudc:publish("$ota/report/"..iotcloudc.produt_id.."/"..iotcloudc.device_name,"{\"type\":\"report_progress\",\"report\":{\"progress\":{\"state\": \"downloading\",\"percent\": \"100\",\"result_code\": \"0\",\"result_msg\": \"\"}},\"version\": \""..version.."\"}")
            -- 开始升级     type：消息类型 state：状态为烧制中
            iotcloudc:publish("$ota/report/"..iotcloudc.produt_id.."/"..iotcloudc.device_name,"{\"type\":\"report_progress\",\"report\":{\"progress\":{\"state\": \"burning\",\"result_code\": \"0\",\"result_msg\": \"\"}},\"version\": \""..version.."\"}")
            -- 升级成功     type：消息类型 state：状态为已完成
            iotcloudc:publish("$ota/report/"..iotcloudc.produt_id.."/"..iotcloudc.device_name,"{\"type\":\"report_progress\",\"report\":{\"progress\":{\"state\": \"done\",\"result_code\": \"0\",\"result_msg\": \"\"}},\"version\": \""..version.."\"}")
            
            -- iotcloudc:publish("$ota/report/"..iotcloudc.produt_id.."/"..iotcloudc.device_name,"{\"type\":\"report_version\",\"report\":{\"version\": \"0.0.2\"}}")
        end
    else
        if iotcloudc.cloud == iotcloud.TENCENT then  -- 此为腾讯云
            -- 升级失败     type：消息类型 state：状态为失败 result_code：错误码，-1：下载超时；-2：文件不存在；-3：签名过期；-4:MD5不匹配；-5：更新固件失败 result_msg：错误消息
            iotcloudc:publish("$ota/report/"..iotcloudc.produt_id.."/"..iotcloudc.device_name,"{\"type\":\"report_progress\",\"report\":{\"progress\":{\"state\": \"fail\",\"result_code\": \"-5\",\"result_msg\": \"ota_fail\"}},\"version\": \""..version.."\"}")
        end
    end
end

-- mqtt回调函数
local function iotcloud_mqtt_callback(mqtt_client, event, data, payload)
    local iotcloudc = nil
    -- 遍历出 iotcloudc
    for k, v in pairs(cloudc_table) do
        if v.mqttc == mqtt_client then
            iotcloudc = v
        end
    end

    -- 用户自定义代码
    log.info("mqtt", "event", event, mqtt_client, data, payload)
    if event == "conack" then                               -- 连接上服务器
        iotcloud_connect(iotcloudc)
        sys.publish("iotcloud",iotcloudc,iotcloud.CONNECT, data, payload)
    elseif event == "recv" then                             -- 接收到消息
        if data == "$ota/update/"..iotcloudc.produt_id.."/"..iotcloudc.device_name then
            local ota_payload = json.decode(payload)
            if ota_payload.type == "update_firmware" then
                print("ota url",ota_payload.url)
                local isfota,otadst
                if fota then isfota = true else otadst = "/update.bin" end
                -- otadst = "/update.bin"--test
                sys.taskInit(iotcloud_ota_download,iotcloudc,ota_payload.url,{fota=isfota,dst=otadst,timeout = 120000},ota_payload.version)

            end
        else
            sys.publish("iotcloud", iotcloudc, iotcloud.RECEIVE,data,payload)
        end
    elseif event == "sent" then                             -- ota消息
        log.info("mqtt", "sent", "pkgid", data)
        sys.publish("iotcloud", iotcloudc, iotcloud.OTA)
    elseif event == "disconnect" then                       -- 服务器连接断开
        sys.publish("iotcloud", iotcloudc, iotcloud.DISCONNECT)
    end
end


-- 腾讯云自动注册
local function iotcloud_tencent_autoenrol(iotcloudc)
    local deviceName = iotcloudc.device_name
    local nonce = math.random(1,100)
    local timestamp = os.time()
    local data = "deviceName="..deviceName.."&nonce="..nonce.."&productId="..iotcloudc.produt_id.."&timestamp="..timestamp
    local hmac_sha1_data = crypto.hmac_sha1(data,iotcloudc.product_secret):lower()
    local signature = crypto.base64_encode(hmac_sha1_data)
    local cloud_body = {
        deviceName=deviceName,
        nonce=nonce,
        productId=iotcloudc.produt_id,
        timestamp=timestamp,
        signature=signature,
    }
    local cloud_body_json = json.encode(cloud_body)
    local code, headers, body = http.request("POST","https://ap-guangzhou.gateway.tencentdevices.com/register/dev", 
            {["Content-Type"]="application/json; charset=UTF-8"},
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
    iotcloudc.produt_id = iot_config.produt_id
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
            iotcloudc.client_id,iotcloudc.user_name = iotauth.qcloud(iotcloudc.produt_id,iotcloudc.device_name,"")
        elseif data.encryptionType == 2 then                -- 密钥认证
            iotcloudc.ip = 1883
            iot_config.key = data.psk
            iotcloudc.client_id,iotcloudc.user_name,iotcloudc.password = iotauth.qcloud(iotcloudc.produt_id,iotcloudc.device_name,iot_config.key,iot_config.method)
        end
    else                                                    -- 否则为非动态注册
        if iot_config.key then                              -- 密钥认证
            iotcloudc.ip = 1883
            iotcloudc.client_id,iotcloudc.user_name,iotcloudc.password = iotauth.qcloud(iotcloudc.produt_id,iotcloudc.device_name,iot_config.key,iot_config.method)
        elseif connect_config.tls then                      -- 证书认证
            iotcloudc.ip = 8883
            iotcloudc.isssl = true
            iotcloudc.ca_file = {client_cert = connect_config.tls.client_cert}
            iotcloudc.client_id,iotcloudc.user_name = iotauth.qcloud(iotcloudc.produt_id,iotcloudc.device_name,"")
        else                                                -- 密钥证书都没有
            return false
        end
    end
    if connect_config then
        iotcloudc.host = connect_config.host or iotcloudc.produt_id..".iotcloud.tencentdevices.com"
        if connect_config.ip then iotcloudc.ip = connect_config.ip end
    else
        iotcloudc.host = iotcloudc.produt_id..".iotcloud.tencentdevices.com"
    end
    return true
end

function iotcloud.new(cloud,iot_config,connect_config)
    local iotcloudc = setmetatable({
        cloud = nil,                                        -- 云平台
        host = nil,                                         -- host
        ip = nil,                                           -- ip
        mqttc = nil,                                        -- mqtt对象
        produt_id = nil,                                    -- 产品id
        device_name = nil,                                  -- 设备名
        product_secret = nil,                               -- 产品秘钥
        client_id = nil,                                    -- 设备id
        user_name = nil,                                    -- mqtt用户名
        password = nil,                                     -- mqtt密码
        authentication = nil,                               -- 认证方式:密钥认证/证书认证 
        isssl = nil,                                        -- 是否加密
        ca_file = nil,                                      -- 证书 
    }, cloudc)
    if fskv then fskv.init() else return false end
    if iot_config.device_name then                          -- 设定了就使用指定的device_name
        iotcloudc.device_name = iot_config.device_name
    elseif mobile then                                      -- 未设定优先使用imei
        iotcloudc.device_name = mobile.imei()
    else                                                    -- 无imei使用unique_id
        iotcloudc.device_name = mcu.unique_id():toHex()
    end
    if cloud == iotcloud.TENCENT or cloud == "qcloud" then  -- 此为腾讯云
        if not iotcloud_tencent_config(iotcloudc,iot_config,connect_config) then return false end
    else
        log.error("iotcloud","cloud not support",cloud)
    end

    if iotcloudc.ca_file then iotcloudc.ca_file.verify = 1 end
    iotcloudc.mqttc = mqtt.create(nil, iotcloudc.host, iotcloudc.ip, iotcloudc.isssl and iotcloudc.ca_file or nil)
    iotcloudc.mqttc:auth(iotcloudc.client_id,iotcloudc.user_name,iotcloudc.password)
    iotcloudc.mqttc:keepalive(300)                          -- 默认值240s
    iotcloudc.mqttc:autoreconn(true, 3000)                  -- 自动重连机制
    iotcloudc.mqttc:on(iotcloud_mqtt_callback)              -- mqtt回调
    table.insert(cloudc_table,iotcloudc)                    -- 添加到表里记录
    return iotcloudc,error_code                             -- 错误返回待处理
end 

function cloudc:connect()
    self.mqttc:connect()
end

function cloudc:disconnect()
    self.mqttc:disconnect()
end

function cloudc:subscribe(topic, qos)
    self.mqttc:subscribe(topic, qos)
end

function cloudc:publish(topic,data,qos,retain)
    self.mqttc:publish(topic,data,qos,retain)
end

function cloudc:close()
    self.mqttc:close()
    for k, v in pairs(cloudc_table) do
        if v.mqttc == self.mqttc then
            table.remove(cloudc_table,k)
        end
    end
end

return iotcloud