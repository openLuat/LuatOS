--[[
@module  aircloud
@summary 合宙IoT平台(excloud) + MQTT 双通道数据上报模块
@version 1.0
@date    2026.07.23
@author  江访
@usage
本文件为合宙IoT平台(excloud)和MQTT双通道数据上报功能模块，核心业务逻辑为：
1、excloud初始化、连接认证、心跳维护
2、通过excloud上报传感器数据和FOTA信息
3、通过MQTT短连接上报JSON格式完整数据

本文件的对外接口有5个：
1、aircloud.init(cfg)：初始化excloud并等待连接/认证完成
2、aircloud.report_excloud(sensor_data, fota_info)：通过excloud上报数据
3、aircloud.report_fota_status(status_text, sensor_data)：通过excloud上报FOTA状态
4、aircloud.report_mqtt(topic, payload, broker, port)：通过MQTT短连接上报JSON数据
5、aircloud.build_mqtt_payload(sensor_data, fota_info)：构建MQTT上报payload
]]

-- ==================== 加载扩展库 ====================

-- excloud: 合宙IoT平台通信扩展库，基于自有TLV协议
-- 支持TCP和MQTT两种传输方式，本模块使用TCP方式
local excloud = require "excloud"

-- ==================== 模块表 ====================

-- aircloud 为模块对外接口表，所有对外函数注册在此表上
local aircloud = {}

-- ==================== 内部状态 ====================

-- g_mqtt_publish_done: MQTT发布是否已完成（成功或失败）
-- g_mqtt_publish_success: MQTT发布是否成功
-- 这两个变量用于MQTT短连接模式下的同步等待
local g_mqtt_publish_done = false
local g_mqtt_publish_success = false

-- ==================== MQTT事件回调 ====================

--[[
MQTT客户端事件回调处理函数

本回调注册到 mqtt_client:on()，处理以下事件：
    conack     — MQTT连接成功（broker确认）
    sent       — 数据发布成功
    disconnect — MQTT连接断开（正常或异常）
    error      — MQTT通信错误

@param userdata mqtt_client MQTT客户端对象（由mqtt.create返回）
@param string event 事件类型
    "conack"     — TCP连接成功且收到broker的CONNACK
    "sent"       — PUBLISH报文已发送完成
    "disconnect" — 连接断开（包括主动disconnect和被动断开）
    "error"      — 通信过程发生错误
@param any data 事件附加数据
    conack事件: nil
    sent事件: 报文标识符
    disconnect事件: 断开原因码
    error事件: 错误描述字符串
@param string payload 收到的消息负载（仅message事件有值，本模块未使用）
@param table metas 消息元数据（仅message事件有值，本模块未使用）
]]
local function mqtt_event_callback(mqtt_client, event, data, payload, metas)
    log.info("aircloud", "MQTT事件:", event, data)

    if event == "conack" then
        -- MQTT连接成功：发布MQTT_CONNECT_OK消息，携带客户端对象
        -- 上层等待MQTT_CONNECT_OK后获取connected_client进行publish
        log.info("aircloud", "MQTT连接成功")
        sys.publish("MQTT_CONNECT_OK", mqtt_client)

    elseif event == "sent" then
        -- 数据发送成功：标记发布完成并发布MQTT_SENT_OK
        log.info("aircloud", "MQTT数据发送成功")
        g_mqtt_publish_done = true
        g_mqtt_publish_success = true
        sys.publish("MQTT_SENT_OK")

    elseif event == "disconnect" then
        -- 连接断开：标记发布完成（未成功），防止上层永久等待
        log.warn("aircloud", "MQTT断开")
        g_mqtt_publish_done = true
        sys.publish("MQTT_SENT_OK")

    elseif event == "error" then
        -- 通信错误：标记发布完成（未成功）
        log.warn("aircloud", "MQTT错误:", data)
        g_mqtt_publish_done = true
        sys.publish("MQTT_SENT_OK")
    end
end

-- ==================== excloud事件回调 ====================

--[[
excloud平台事件回调处理函数

本回调注册到 excloud.on()，处理以下事件：
    connect_result — TCP连接结果
    auth_result    — 设备认证结果
    disconnect     — 与服务器断开连接
    send_result    — 数据发送结果

@param string event 事件类型
    "connect_result" — 与excloud服务器的TCP连接结果
    "auth_result"    — 通过auth_key认证的结果
    "disconnect"     — 与服务器断开连接
    "send_result"    — TLV数据发送结果
@param table data 事件数据
    connect_result: {success=boolean, error=string}
    auth_result: {success=boolean, message=string}
    disconnect: 空table
    send_result: {success=boolean, sequence_num=number, error_msg=string}
]]
local function excloud_event_callback(event, data)
    if event == "connect_result" then
        -- TCP连接结果
        -- data.success=true 表示TCP三次握手成功
        -- 后续会进行auth认证
        if data.success then
            log.info("aircloud", "excloud连接成功")
        else
            log.warn("aircloud", "excloud连接失败:", data.error or "未知")
        end

    elseif event == "auth_result" then
        -- 设备认证结果
        -- data.success=true 表示通过auth_key认证通过
        -- 认证通过后发布EXCLOUD_READY，通知上层可以开始数据交互
        if data.success then
            log.info("aircloud", "excloud认证成功")
            sys.publish("EXCLOUD_READY")
        else
            log.warn("aircloud", "excloud认证失败:", data.message)
        end

    elseif event == "disconnect" then
        -- 与服务器断开连接
        log.warn("aircloud", "excloud断开连接")

    elseif event == "send_result" then
        -- TLV数据发送结果
        -- data.sequence_num 为消息流水号，用于日志追踪
        if data.success then
            log.info("aircloud", "excloud发送成功, 流水号:", data.sequence_num)
        else
            log.warn("aircloud", "excloud发送失败:", data.error_msg)
        end
    end
end

-- ==================== API：初始化excloud ====================

--[[
初始化excloud连接并等待认证完成

aircloud.init(cfg)

本函数完成以下工作：
1、注册事件回调 excloud_event_callback
2、调用 excloud.setup 配置传输参数
3、调用 excloud.open 开启服务
4、启动自动心跳（间隔300秒）
5、等待认证完成（最长20秒）

注意：
1、本函数内部有 sys.waitUntil()，必须在协程中调用
2、如果超时（20秒未认证成功），认为初始化失败
3、excloud.setup 已不再需要主动配置 use_getip 和 device_type 参数

@param table cfg
含义：excloud配置参数表
是否必选：必选
cfg包含字段：
    transport         : string, 传输协议类型, 默认"tcp"
        "tcp"  — TCP长连接，适合频繁上报场景
        "mqtt" — MQTT协议，适合标准MQTT生态
    auto_reconnect    : boolean, 是否自动重连, 默认true
        true  — 断开后自动尝试重连
        false — 断开后不自动重连
    reconnect_interval: number, 重连间隔(秒), 默认10
        取值范围：5~300
    max_reconnect     : number, 最大重连次数, 默认3
        达到最大次数后不再重连
    mtn_log_enabled   : boolean, 是否启用运维日志上传, 默认false

@return boolean
含义：初始化是否成功（含TCP连接和认证）
true  — excloud已就绪，可进行数据上报
false — 初始化失败，可能是网络问题或PRODUCT_KEY无效

@usage
local ok = aircloud.init({
    transport = "tcp",
    auto_reconnect = true,
    reconnect_interval = 10,
    max_reconnect = 3,
})
if not ok then
    log.error("aircloud", "初始化失败，跳过excloud上报")
end
]]
function aircloud.init(cfg)
    log.info("aircloud", "正在初始化excloud...")

    -- 第一步：注册事件回调
    -- excloud扩展库内部维护此回调，收到平台事件时回调本函数
    excloud.on(excloud_event_callback)

    -- 第二步：配置excloud参数
    -- excloud.setup会自动通过PRODUCT_KEY获取服务器地址和端口
    -- 不再需要手动指定host和port
    local ok, err_msg = excloud.setup({
        transport = cfg.transport or "tcp",
        auto_reconnect = (cfg.auto_reconnect ~= false),
        reconnect_interval = cfg.reconnect_interval or 10,
        max_reconnect = cfg.max_reconnect or 3,
        mtn_log_enabled = cfg.mtn_log_enabled or false,
    })
    if not ok then
        log.error("aircloud", "excloud.setup失败:", err_msg)
        return false
    end

    -- 第三步：开启excloud服务
    -- open()会发起TCP连接到服务器
    ok, err_msg = excloud.open()
    if not ok then
        log.error("aircloud", "excloud.open失败:", err_msg)
        return false
    end

    -- 第四步：启动自动心跳
    -- 默认间隔300秒，保持TCP长连接活跃
    excloud.start_heartbeat()

    -- 第五步：等待认证完成，最长20秒
    -- EXCLOUD_READY由excloud_event_callback在auth_result成功时发布
    sys.waitUntil("EXCLOUD_READY", 20000)
    return true
end

-- ==================== API：excloud数据上报 ====================

--[[
通过excloud平台上报传感器数据和FOTA信息

aircloud.report_excloud(sensor_data, fota_info)

本函数构建TLV列表并通过excloud.send上报服务器。
TLV字段使用 CONTROL_RESPONSE（自定义数据）类型。

@param table sensor_data
含义：传感器数据表（由sensor_vl53l1x.collect_data返回）
是否必选：可选
传入nil表示不上报传感器数据
当传入非nil时，上报 sensor_data.avg_distance 作为TEXT类型值

@param string fota_info
含义：FOTA升级信息描述字符串
是否必选：可选
传入nil表示不上报FOTA信息
示例值：
    "FOTA升级成功: 升级前: VERSION=001.999.000 ; 升级后: VERSION=001.999.001"
    "FOTA升级包下载成功, 升级前版本: 001.999.000"

@return boolean
含义：上报是否成功
true  — 数据已通过TCP发送到服务器
false — excloud未连接或发送失败

@usage
-- 上报传感器数据
aircloud.report_excloud(sensor_data, nil)

-- 上报传感器数据+FOTA信息
aircloud.report_excloud(sensor_data, "FOTA升级成功: xxx")

-- 仅上报FOTA信息
aircloud.report_excloud(nil, "FOTA升级包下载成功")
]]
function aircloud.report_excloud(sensor_data, fota_info)
    -- 检查excloud连接状态
    local status = excloud.status()
    if not status or not status.is_connected then
        log.warn("aircloud", "excloud未连接，跳过数据上报")
        return false
    end

    -- 构建TLV列表
    -- TLV (Tag-Length-Value) 是excloud协议的数据单元格式
    -- field_meaning 用 CONTROL_RESPONSE(0x14) 表示自定义数据
    -- data_type 使用 UNICODE/String 类型
    local tlvs = {}

    -- 添加传感器数据TLV
    if sensor_data then
        tlvs[#tlvs + 1] = {
            field_meaning = excloud.FIELD_MEANINGS.CONTROL_RESPONSE,
            data_type = excloud.DATA_TYPES.UNICODE,
            value = tostring(sensor_data.avg_distance),
        }
    end

    -- 添加FOTA信息TLV
    if fota_info then
        tlvs[#tlvs + 1] = {
            field_meaning = excloud.FIELD_MEANINGS.CONTROL_RESPONSE,
            data_type = excloud.DATA_TYPES.UNICODE,
            value = fota_info,
        }
    end

    -- 没有TLV时直接返回失败
    if #tlvs == 0 then
        return false
    end

    -- 发送TLV列表（不需要服务器回复）
    -- 第二个参数false表示不需要服务器回复ACK
    local ok, err_msg = excloud.send(tlvs, false)
    if ok then
        log.info("aircloud", "excloud数据上报成功")
    else
        log.warn("aircloud", "excloud数据上报失败:", err_msg)
    end
    return ok
end

-- ==================== API：excloud FOTA状态上报 ====================

--[[
通过excloud上报FOTA状态文本（升级中状态）

aircloud.report_fota_status(status_text, sensor_data)

本函数专门用于上报"FOTA正在检查/升级中"等过程状态。
与report_excloud的区别在于本函数强制要求status_text不为空。

@param string status_text
含义：FOTA状态描述文本
是否必选：必选
示例值：
    "FOTA: 正在检查/升级中"
    "FOTA: 下载进度 50%"

@param table sensor_data
含义：传感器数据（可选，附带上报）
是否必选：可选

@return boolean
含义：上报是否成功

@usage
aircloud.report_fota_status("FOTA: 正在检查/升级中", sensor_data)
]]
function aircloud.report_fota_status(status_text, sensor_data)
    -- 检查excloud连接状态
    local status = excloud.status()
    if not status or not status.is_connected then
        log.warn("aircloud", "excloud未连接，跳过FOTA状态上报")
        return false
    end

    -- 构建TLV列表
    local tlvs = {}

    -- 可选：附带传感器数据
    if sensor_data then
        tlvs[#tlvs + 1] = {
            field_meaning = excloud.FIELD_MEANINGS.CONTROL_RESPONSE,
            data_type = excloud.DATA_TYPES.UNICODE,
            value = tostring(sensor_data.avg_distance),
        }
    end

    -- 必选：FOTA状态文本
    tlvs[#tlvs + 1] = {
        field_meaning = excloud.FIELD_MEANINGS.CONTROL_RESPONSE,
        data_type = excloud.DATA_TYPES.UNICODE,
        value = status_text,
    }

    -- 发送TLV列表
    local ok, err_msg = excloud.send(tlvs, false)
    if ok then
        log.info("aircloud", "FOTA状态已上报:", status_text)
    else
        log.warn("aircloud", "FOTA状态上报失败:", err_msg)
    end
    return ok
end

-- ==================== API：MQTT数据上报 ====================

--[[
通过MQTT短连接上报JSON格式数据

aircloud.report_mqtt(topic, payload_table, mqtt_broker, mqtt_port)

本函数每次调用都会创建一个新的MQTT短连接：
    创建客户端 → 连接broker → 发布数据 → 断开连接 → 释放客户端
这样可以避免维护长连接，但每次有额外的TCP握手开销。

MQTT认证方式：client_id = IMEI + "_vl53l1x"

@param string topic
含义：MQTT发布主题
取值范围：任意合法的MQTT主题字符串
是否必选：必选
示例值："864317083866528/vl53l1x/up"

@param table payload_table
含义：待上报的数据表（会被json.encode编码为JSON字符串）
取值范围：任意可被json.encode序列化的table
是否必选：必选
示例值：{distance_mm=265, project="Air8780P_VL53L1X"}

@param string mqtt_broker
含义：MQTT服务器地址（域名或IP）
是否必选：必选
示例值："lbsmqtt.airm2m.com"

@param number mqtt_port
含义：MQTT服务器端口号
取值范围：1~65535
是否必选：可选
默认值：1884

@return boolean
含义：上报是否成功
true  — 数据已成功发布到broker
false — 连接失败或发布失败

@usage
local payload = {distance_mm=265, project="Air8780P_VL53L1X"}
aircloud.report_mqtt("IMEI/vl53l1x/up", payload, "lbsmqtt.airm2m.com", 1884)
]]
function aircloud.report_mqtt(topic, payload_table, mqtt_broker, mqtt_port)
    -- 参数有效性检查
    if not topic or not payload_table or not mqtt_broker then
        return false
    end

    log.info("aircloud", "MQTT上报数据到:", topic)

    -- 重置MQTT同步变量
    g_mqtt_publish_done = false
    g_mqtt_publish_success = false

    -- 第一步：创建MQTT客户端
    -- mqtt.create(adapter, host, port, ssl)
    -- adapter传nil使用默认网卡
    local mqtt_client = mqtt.create(nil, mqtt_broker, mqtt_port or 1884)
    if not mqtt_client then
        log.error("aircloud", "MQTT创建失败")
        return false
    end

    -- 第二步：设置认证信息和事件回调
    -- client_id使用IMEI保证唯一性
    -- username/password为空表示匿名登录
    -- clean_session=false表示不清理session
    mqtt_client:auth(mobile.imei() .. "_vl53l1x", "", "", false)
    mqtt_client:on(mqtt_event_callback)

    -- 第三步：发起TCP连接
    if not mqtt_client:connect() then
        log.error("aircloud", "MQTT连接失败")
        mqtt_client:close()
        return false
    end

    -- 第四步：等待连接确认（CONNACK），最长5秒
    local no_timeout, connected_client = sys.waitUntil("MQTT_CONNECT_OK", 5000)
    if not no_timeout or not connected_client then
        log.warn("aircloud", "MQTT连接超时")
        mqtt_client:disconnect()
        sys.wait(500)
        mqtt_client:close()
        return false
    end

    -- 第五步：发布数据
    -- qos=1, retain=0
    local payload_json = json.encode(payload_table)
    connected_client:publish(topic, payload_json, 1, 0)
    log.info("aircloud", "MQTT已发布:", payload_json)

    -- 第六步：等待发布结果，最长8秒
    sys.waitUntil("MQTT_SENT_OK", 8000)

    -- 第七步：断开连接并释放资源
    connected_client:disconnect()
    sys.wait(500)
    connected_client:close()

    log.info("aircloud", "MQTT短连接结束，发送" .. (g_mqtt_publish_success and "成功" or "失败"))
    return g_mqtt_publish_success
end

-- ==================== API：构建MQTT payload ====================

--[[
构建MQTT上报的JSON payload数据表

aircloud.build_mqtt_payload(sensor_data, fota_info)

本函数生成统一格式的MQTT上报数据，包含以下通用字段：
    imei    — 设备IMEI号，用于设备识别
    project — 项目名称，用于区分不同项目的数据
    version — 脚本版本号，用于追踪固件版本
    ts      — Unix时间戳，记录数据采集时间

@param table sensor_data
含义：传感器数据表（由sensor_vl53l1x.collect_data返回）
是否必选：可选
当传入非nil时，payload增加以下字段：
    distance_mm  — 平均距离（number）
    distances    — 原始距离数组（table）
    valid_samples— 有效帧数（number）

@param string fota_info
含义：FOTA升级信息（可选）
是否必选：可选
当传入非nil时，payload增加以下字段：
    fota_info — FOTA升级描述字符串

@return table
含义：MQTT上报用的数据表，可直接传入json.encode

@usage
local payload = aircloud.build_mqtt_payload(sensor_data, "FOTA升级成功")
-- 返回: {imei="xxx", project="Air8780P_VL53L1X", version="001.999.000",
--        ts=1784623861, distance_mm=265, distances={267,261,267},
--        valid_samples=3, fota_info="FOTA升级成功"}
]]
function aircloud.build_mqtt_payload(sensor_data, fota_info)
    -- 基础payload：所有上报必含设备标识和时间戳
    local payload = {
        imei = mobile.imei(),
        project = PROJECT,
        version = VERSION,
        ts = os.time(),
    }

    -- 可选：添加传感器数据字段
    if sensor_data then
        payload.distance_mm = sensor_data.avg_distance
        payload.distances = sensor_data.distance_list
        payload.valid_samples = sensor_data.valid_count
    end

    -- 可选：添加FOTA信息字段
    if fota_info then
        payload.fota_info = fota_info
    end

    return payload
end

return aircloud
