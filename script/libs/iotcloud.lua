



local iotcloud = {}
--云平台
iotcloud.TENCENT = "tencent"
--认证方式
iotcloud.certificate = "certificate"
iotcloud.key = "key"
-- event
iotcloud.connect = "connect"


local cloudc_table = {}

local cloudc = {}
cloudc.__index = cloudc

--云平台连接成功处理函数,此处可订阅一些主题或者上报版本等默认操作
local function iotcloud_connect(iotcloudc)
    -- mqtt_client:subscribe(sub_topic)--单主题订阅
    -- mqtt_client:subscribe({[topic1]=1,[topic2]=1,[topic3]=1})--多主题订阅
end

--mqtt回调函数
local function iotcloud_mqtt_callback(mqtt_client, event, data, payload)
    local iotcloudc = nil
    for k, v in pairs(cloudc_table) do
        if v.mqttc == mqtt_client then
            iotcloudc = v
        end
    end

    -- 用户自定义代码
    log.info("mqtt", "event", event, mqtt_client, data, payload)
    if event == "conack" then                   --连接成功
        iotcloud_connect(iotcloudc)
        sys.publish("iotcloud",iotcloudc,iotcloud.connect, data, payload)
    elseif event == "recv" then
        log.info("mqtt", "downlink", "topic", data, "payload", payload)
        sys.publish("mqtt_payload", data, payload)
    elseif event == "sent" then
        log.info("mqtt", "sent", "pkgid", data)
    elseif event == "disconnect" then
        -- mqtt_client:connect()
    end
end


--自动注册
local function iotcloud_auto_enrol(iotcloudc)
    if iotcloudc.cloud == iotcloud.TENCENT then           --此为腾讯云
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
        log.info("cloud_body_json", cloud_body_json)
        local code, headers, body = http.request("POST","https://ap-guangzhou.gateway.tencentdevices.com/register/dev", 
                {["Content-Type"]="application/json; charset=UTF-8"},
                cloud_body_json
        ).wait()
        log.info("http.post", code, headers, body)
        if code == 200 then
            local dat, result, errinfo = json.decode(body)
            if result then
                if dat.code==0 then
                    local payload = crypto.cipher_decrypt("AES-128-CBC","ZERO",crypto.base64_decode(dat.payload),string.sub(iotcloudc.product_secret,1,16),"0000000000000000")
                    local payload = json.decode(payload)
                    fskv.set("iotcloud_tencent", payload)
                    if payload.encryptionType == 1 then     -- 证书认证
                        iotcloudc.authentication = iotcloud.certificate
                    elseif payload.encryptionType == 2 then -- 密钥认证
                        iotcloudc.authentication = iotcloud.key
                    end
                    return true
                else
                    return false
                end
            end
        else
            return false
        end
    end
end

function iotcloud.new(cloud,iot_config,connect_config)
    local iotcloudc = setmetatable({
        cloud = nil,                    -- 云平台
        host = nil,                     -- host
        ip = nil,                       -- ip
        mqttc = nil,                    -- mqtt对象
        produt_id = nil,                -- 产品id
        device_name = nil,              -- 设备名
        product_secret = nil,           -- 产品秘钥
        client_id = nil,                -- 设备id
        user_name = nil,                -- mqtt用户名
        password = nil,                 -- mqtt密码
        authentication = nil,           -- 认证方式:密钥认证/证书认证 
    }, cloudc)
    local isssl, ca_file
    if fskv then fskv.init() else return false end
    if iot_config.device_name then                      --设定了就使用指定的device_name
        iotcloudc.device_name = iot_config.device_name
    elseif mobile then                                  --未设定优先使用imei
        iotcloudc.device_name = mobile.imei()
    else                                                --无imei使用unique_id
        iotcloudc.device_name = mcu.unique_id():toHex()
    end
    if cloud == iotcloud.TENCENT or cloud == "qcloud" then --此为腾讯云
        iotcloudc.cloud = iotcloud.TENCENT
        iotcloudc.produt_id = iot_config.produt_id
        if iot_config.product_secret then                   --有product_secret说明是动态注册
            iotcloudc.product_secret = iot_config.product_secret
            if not fskv.get("iotcloud_tencent") then 
                if not iotcloud_auto_enrol(iotcloudc) then return false end
            end
            local data = fskv.get("iotcloud_tencent")
            -- print("payload",data.encryptionType,data.psk,data.clientCert,data.clientKey)
            if data.encryptionType == 1 then                -- 证书认证
                iotcloudc.ip = 8883
                isssl = true
                ca_file = {client_cert = data.clientCert,client_key = data.clientKey}
                iotcloudc.client_id,iotcloudc.user_name = iotauth.qcloud(iotcloudc.produt_id,iotcloudc.device_name,"")
            elseif data.encryptionType == 2 then            -- 密钥认证
                iotcloudc.ip = 1883
                iot_config.key = data.psk
                iotcloudc.client_id,iotcloudc.user_name,iotcloudc.password = iotauth.qcloud(iotcloudc.produt_id,iotcloudc.device_name,iot_config.key,iot_config.method)
            end
        else                                                --否则为非动态注册
            if iot_config.key then                          --密钥认证
                iotcloudc.ip = 1883
                iotcloudc.client_id,iotcloudc.user_name,iotcloudc.password = iotauth.qcloud(iotcloudc.produt_id,iotcloudc.device_name,iot_config.key,iot_config.method)
            elseif connect_config.tls then                  --证书认证
                iotcloudc.ip = 8883
                isssl = true
                ca_file = {client_cert = connect_config.tls.client_cert}
                iotcloudc.client_id,iotcloudc.user_name = iotauth.qcloud(iotcloudc.produt_id,iotcloudc.device_name,"")
            else                                            --密钥证书都没有
                return false
            end
        end
        if connect_config then
            iotcloudc.host = connect_config.host or iotcloudc.produt_id..".iotcloud.tencentdevices.com"
            if connect_config.ip then iotcloudc.ip = connect_config.ip end
        else
            iotcloudc.host = iotcloudc.produt_id..".iotcloud.tencentdevices.com"
        end
    end

    if ca_file then
        if ca_file.client_cert then
            ca_file.client_cert = ca_file.client_cert:gsub("\b", "\n")
        end
        if ca_file.client_key then
            ca_file.client_key = ca_file.client_key:gsub("\b", "\n")
        end
    end

    ca_file.verify = 1

    iotcloudc.mqttc = mqtt.create(nil, iotcloudc.host, iotcloudc.ip, isssl and ca_file or nil)
    iotcloudc.mqttc:auth(iotcloudc.client_id,iotcloudc.user_name,iotcloudc.password)
    iotcloudc.mqttc:keepalive(300)                         -- 默认值240s
    iotcloudc.mqttc:autoreconn(true, 3000)                 -- 自动重连机制
    iotcloudc.mqttc:on(iotcloud_mqtt_callback)
    table.insert(cloudc_table,iotcloudc)
    return iotcloudc,error_code -- 错误返回待处理
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