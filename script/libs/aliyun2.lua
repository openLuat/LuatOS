--[[
@module aliyun2
@summary 阿里云物联网平台(开发中)
@version 1.0
@date    2024.05.18
@author  wendal
@demo    aliyun2
@usage
-- 请查阅demo

-- 本库基于阿里云物联网重新设计, 与aliyun.lua库不兼容
-- 本库尚属开发测试阶段, API随时可能变化, 也可能不变^_^
]]
_G.sys = require("sys")

local aliyun2 = {}
local g_id = 1

--[[
初始化一个aliyun示例
@api aliyun.create(opts)
@table 参数表
@return aliyun实例
@usage
-- 初始化一个aliyun示例
local ali = aliyun.create(opts)
if ali and aliyun2.start(ali) then
    while 1 do
        local result, tip, params = sys.waitUntil(ali.topic, 30000)
        if result then
            log.info("aliyun", "event", tip, params)
        end
    end
else
    log.error("aliyun", "初始化失败")
end
]]
function aliyun2.create(opts)
    if not opts then
        log.error("aliyun2", "配置参数表不能是空")
        return
    end
    -- 检查最基本的参数
    if not opts.productKey or not opts.deviceName then
        log.error("aliyun2", "缺失配置参数productKey")
        return
    end
    if not opts.deviceName then
        if mobile then
            opts.deviceName = mobile.imei()
        elseif wlan and wlan.getMac then
            opts.deviceName = wlan.getMac()
        else
            opts.deviceName = mcu.unique_id():toHex()
        end
        log.info("aliyun2", "deviceName未指定,自动分配", opts.deviceName)
    end
    if opts.productSecret and #opts.productSecret == 0 then
        opts.productSecret = nil
    end
    if opts.deviceSecret and #opts.deviceSecret == 0 then
        opts.deviceSecret = nil
    end
    if not opts.store_key then
        opts.store_key = opts.productKey .. "_" .. opts.deviceName
    end
    if opts.productSecret and not opts.deviceSecret then
        -- 从本地存储读取设备密钥
        local payload = nil
        if fskv then
            payload = fskv.get(opts.store_key)
        end
        if not payload or #payload < 16 then
            payload = io.readFile(opts.store_key)
        end
        if payload then
            local jdata = json.decode(payload)
            if jdata then
                opts.deviceSecret = jdata["deviceSecret"]
                opts.deviceToken = jdata["deviceToken"]
                opts.clientId = jdata["clientId"]
            end
        end
    end

    if not opts.productSecret and not opts.deviceSecret and not opts.deviceToken then
        log.error("aliyun2", "请指定productSecret或deviceSecret")
        return
    end
    local ctx = opts
    -- 计算mqtt的host和port
    if not ctx.mqtt_host then
        -- ctx.mqtt_host = "iot-as-mqtt." .. ctx.productKey .. ".aliyuncs.com"
        if ctx.instanceId then
            ctx.mqtt_host = ctx.instanceId .. ".mqtt.iothub.aliyuncs.com"
        else
            ctx.mqtt_host = ctx.productKey .. ".iot-as-mqtt." .. (opts.regionId or "cn-shanghai") ..".aliyuncs.com"
        end
    end
    if not ctx.mqtt_port then
        ctx.mqtt_port = 1883
    end
    ctx.device_retry = 0
    ctx.topic = "aliyun2_" .. g_id
    g_id = g_id + 1

    -- 生成mqtt的topic
    if ctx.auto_topic == nil or ctx.auto_topic then
        if not ctx.sub_topics then
            ctx.sub_topics = {}
        end
        if not ctx.pub_topics then
            ctx.pub_topics = {}
        end
        local topics = ctx.sub_topics
        -- 订阅必要的topic
        local dn = ctx.productKey .. "/" .. ctx.deviceName
        -- 首先是OTA的topic
        topics.ota = "/ota/device/upgrade/" .. dn
        -- 配置更新信息
        topics.config_push = "/sys/" .. dn .. "/thing/config/push"
        -- 广播信息
        topics.broadcast = "/broadcast/" .. ctx.productKey .. "/#"
        -- NTP信息
        topics.ntp = "/ext/ntp/" .. dn .. "/response"

        -- 物模型, 透传信息
        topics.raw_reply = "/sys/" .. dn .. "/thing/model/up_raw_reply"
        topics.raw_down = "/sys/" .. dn .. "/thing/model/down_raw"
        -- 非透传
        topics.property_set = "/sys/".. dn .. "/thing/service/property/set"

        -- 上行常用的topic
        topics = ctx.pub_topics
        topics.inform = "/ota/device/inform/".. dn
        topics.ntp = "/ext/ntp/".. dn .. "/request"
        topics.raw_up = "/sys/".. dn .. "/thing/model/up_raw"
    end

    if ctx.instanceId then
        log.info("aliyun2", "instanceId", ctx.instanceId)
    end
    log.info("aliyun2", "deviceName", ctx.deviceName)
    log.info("aliyun2", "mqtt_host", ctx.mqtt_host)
    log.info("aliyun2", "mqtt_port", ctx.mqtt_port)
    return ctx
end

local function aliyun_do_reg(ctx)
    local mqttc = mqtt.create(ctx.adapter, ctx.mqtt_host, 443, true)
    if not mqttc then
        log.error("aliyun2", "创建mqtt实例失败")
        return
    end
    -- 计算自动注册所需要的密钥
    local tm = tostring(os.time())
    local client_id = string.format("%s|securemode=%s,authType=%s,random=%s,signmethod=hmacsha1%s|", ctx.deviceName, ctx.regnwl and -2 or 2, ctx.regnwl and "regnwl" or "register", tm, (ctx.instanceId and ",instanceId=" .. ctx.instanceId or ""))
    log.info("aliyun2", "开始注册流程", client_id)
    local user_name = ctx.deviceName .. "&"..ctx.productKey
    local content = "deviceName"..ctx.deviceName.."productKey"..ctx.productKey.."random" .. tm
    local password = crypto.hmac_sha1(content, ctx.productSecret)
    log.info("aliyun2", "尝试注册", client_id, user_name, password)
    mqttc:auth(client_id, user_name, password)
    mqttc:keepalive(240) -- 实际上会忽略该属性
    -- mqttc:debug(true)
    mqttc:autoreconn(false, 3000) -- 不需要自动重连
    local regok = false -- 记录注册成功与否
    mqttc:on(function(mqtt_client, event, data, payload)
        log.info("aliyun2", "event", event, data, payload)
        if event == "recv" then
            log.info("aliyun", "downlink", "topic", data, "payload", payload)
            if payload then
                local jdata,res = json.decode(payload) -- TODO 搞个alijson库进行封装
                if jdata and (jdata["deviceSecret"] or jdata["deviceToken"]) then
                    log.info("aliyun2", "获取到设备密钥")
                    regok = true
                    ctx.deviceSecret = jdata["deviceSecret"]
                    ctx.deviceToken = jdata["deviceToken"]
                    ctx.clientId = jdata["clientId"]
                    sys.publish(tm, "reg", "ok")
                    if fskv then
                        log.info("aliyun2", "密钥信息存入fskv", ctx.store_key)
                        fskv.set(ctx.store_key, payload)
                    end
                    log.info("aliyun2", "密钥信息存入文件系统", ctx.store_key)
                    io.writeFile(ctx.store_key, payload)
                else
                    sys.publish(tm, "reg", "fail")
                    return
                end
            end
        elseif event == "close" then
            sys.publish(tm, "close")
        end
    end)
    mqttc:connect()
    sys.waitUntil(tm, 5000)
    sys.wait(100)
    mqttc:close()
    if regok then
        log.info("aliyun2", "自动注册成功,密钥信息已获取")
    else
        log.info("alyun2", "自动注册失败,延迟30秒后重试")
        sys.wait(30000)
    end
end

local function aliyun_task_once(ctx)
    -- 几个条件: 有设备密钥, 有产品密钥, 登陆失败的次数
    -- 情况1: 只有设备密钥, 没有产品密钥, 那就固定是一机一密
    -- 情况2: 只有产品密钥, 没有设备密钥, 那就是一机一密
    -- 情况3: 有产品密钥, 有设备密钥, 登录失败次数少于设定值(默认3次),那继续用一机一密去尝试登陆
    -- 情况4: 有产品密钥, 有设备密钥, 登录失败次数大于设定值(默认3次), 使用一型一密去尝试注册一次

    if ctx.productSecret then
        if ctx.deviceSecret or ctx.deviceToken then
            if ctx.device_retry < 3 then
                -- 失败次数还不多,先尝试用一机一密
            else
                log.info("aliyun2", "设备密钥已存在,但已经连续失败3次,尝试重新注册")
                aliyun_do_reg(ctx)
                ctx.device_retry = 0
            end
        else
            aliyun_do_reg(ctx)
        end
    end

    if not ctx.deviceSecret and not ctx.deviceToken then
        log.info("aliyun2", "未能获取到设备密钥,等待重试")
        return
    end

    local mqttc = mqtt.create(ctx.adapter, ctx.mqtt_host, ctx.mqtt_port, ctx.mqtt_isssl, ctx.ca_file)
    if not mqttc then
        log.error("aliyun2", "创建mqtt实例失败")
        return
    end
    if ctx.deviceSecret then
        local client_id,user_name, password = iotauth.aliyun(ctx.productKey, ctx.deviceName, ctx.deviceSecret)
        log.info("aliyun2", "密钥模式", client_id,user_name, password)
        mqttc:auth(client_id, user_name, password)
    else
        local client_id = ctx.clientId .. "|securemode=-2,authType=connwl|"
        local user_name = ctx.deviceName.."&"..ctx.productKey
        log.info("aliyun2", "token模式", client_id, user_name, ctx.deviceToken)
        mqttc:auth(client_id, user_name, ctx.deviceToken)
    end
    mqttc:keepalive(ctx.mqtt_keepalive or 240)
    -- mqttc:debug(true)
    mqttc:autoreconn(false, 3000) -- 不需要自动重连
    mqttc:on(function(mqtt_client, event, data, payload)
        log.info("aliyun2", "event", event, data, payload)
        if event == "conack" then
            log.info("aliyun2", "连接成功,鉴权完成")
            ctx.device_retry = 0

            -- 需要订阅的topic
            if ctx.sub_topics then
                for k, v in pairs(ctx.sub_topics) do
                    log.info("aliyun2", "订阅topic", v, "别名", k)
                    mqttc:subscribe(v)
                end
            end

            -- 上报一些基础信息
            -- 版本信息
            if ctx.pub_topics and ctx.pub_topics.inform then
                local info = ctx.inform_data or {version=_G.VERSION, module=rtos.bsp():upper()}
                info = json.encode({id="123", params=info})
                log.info("aliyun2", "上报版本信息", ctx.pub_topics.inform, info)
                mqttc:publish(ctx.pub_topics.inform, info, 1)
            end
            
            sys.publish(ctx.topic, "conack")
        elseif event == "recv" then
            -- 收到消息
            log.info("aliyun2", "收到下行信息", "topic", data, "payload前128字节", payload and payload:sub(1, 128))
            sys.publish(ctx.topic, "recv", data, payload)
            -- TODO 支持FOTA/OTA
            if ctx.sub_topics and ctx.sub_topics.ota == data then
                log.info("aliyun2", "收到ota信息", payload)
                local jdata = json.decode(payload)
                if jdata and jdata.data and jdata.data.url then
                    log.info("aliyun2", "获取到OTA所需要的URL", jdata.data.url)
                    sys.publish(ctx.topic, "ota", jdata.data)
                end
            end
        end
    end)
    mqttc:connect()
    sys.waitUntil(ctx.topic, 5000)
    if mqttc:ready() then
        ctx.mqttc = mqttc
        ctx.device_retry = 0
        while mqttc:ready() and ctx.running do
            sys.waitUntil(ctx.topic, 5000)
        end
    else
        ctx.device_retry = ctx.device_retry + 1
    end
    mqttc:close()
    log.info("aliyun2", "单次任务结束")
    ctx.mqttc = nil
end

local function aliyun_task (ctx)
    -- 准备好参数

    -- 开始主循环
    while ctx.running do
        aliyun_task_once(ctx)
        sys.wait(2000)
    end
    log.info("aliyun2", "阿里云任务结束")
end

--[[
启动aliyun实例
@api aliyun2.start(ali)
@return 成功返回true,失败返回false
]]
function aliyun2.start(ali)
    ali.running = true
    ali.c_task = sys.taskInit(aliyun_task, ali)
    return ali.c_task ~= nil
end

--[[
关闭aliyun实例
@api aliyun2.stop(ali)
@return boolean 成功返回true,失败返回false
]]
function aliyun2.stop(ali)
    if ali.c_task then
        ali.running = nil
        sys.publish(ali.topic, "stop")
    end
end

--[[
是否已经连接上
@api aliyun2.ready(ali)
@return boolean 已经成功返回true,否则一概返回false
]]
function aliyun2.ready(ali)
    if ali and ali.mqttc and ali.mqttc:ready() then
        return true
    end
end

--[[
订阅自定义的topic
@api aliyun2.subscribe(ali, topic)
@return 成功返回true,失败返回false或者nil
]]
function aliyun2.subscribe(ali, topic, qos)
    if not aliyun2.ready(ali) then
        log.warn("aliyun2", "还没连上服务器,不能订阅", topic)
        return
    end
    ali.mqttc:subscribe(topic, qos or 1)
    return true
end

--[[
上报消息,上行数据
@api aliyun2.publish(ali, topic, payload, qos, retain)
@return 成功返回true,失败返回false或者nil
]]
function aliyun2.publish(ali, topic, payload, qos, retain)
    if not aliyun2.ready(ali) then
        log.warn("aliyun2", "还没连上服务器,不能上报", topic)
        return
    end
    ali.mqttc:public(topic, payload, qos or 1, retain or 0)
    return true
end

-- TODO
-- 1. alijson库
-- 2. 对物模型做一些封装
-- 3. 对透传进行一些封装

return aliyun2
