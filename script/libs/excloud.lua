--[[
@summary excloud扩展库
@version 1.0
@date    2025.09.22
@author  孟伟
@usage
-- 应用场景
该扩展库适用于各种物联网设备（如4G/WiFi/以太网设备）与云端服务器进行数据交互的场景。
可用于设备状态上报、数据采集、远程控制等物联网应用。

实现的功能：
1. 支持多种设备类型（4G/WiFi/以太网）的接入认证
2. 提供TCP和MQTT两种传输协议选择
3. 实现设备与云端的双向通信（数据上报和命令下发）
4. 支持数据的TLV格式编解码
5. 提供自动重连机制，保证连接稳定性
6. 支持不同数据类型（整数、浮点数、布尔值、字符串、二进制等）的传输

-- 用法实例
本扩展库对外提供了以下6个接口：
1. excloud.setup(params) - 设置配置参数
2. excloud.on(cbfunc) - 注册回调函数
3. excloud.open() - 开启excloud服务
4. excloud.send(data, need_reply, is_auth_msg) - 发送数据
5. excloud.close() - 关闭excloud服务
6. excloud.status() - 获取当前状态
7. excloud.start_heartbeat(interval, custom_data) - 启动自动心跳机制，定期向云平台发送心跳消息；
8. excloud.stop_heartbeat() -停止自动心跳机制；
9. excloud.upload_image(file_path, file_name) -上传图片文件到云平台；注意，需要启用getip服务
10. excloud.upload_audio(file_path, file_name) -上传音频文件到云平台；注意，需要启用getip服务
11. excloud.get_server_info() - 获取getip获取的服务器信息
12. excloud.mtn_log(tag, ...)  - 记录运维日志；


]]
local excloud = {}
local httpplus = require "httpplus"
local exmtn = require "exmtn"

local config = {
    device_type = 1,         -- 默认设备类型: 4G
    device_id = "",          -- 设备ID
    protocol_version = 1,    -- 协议版本
    transport = "",          -- 传输协议: tcp/mqtt
    host = "",               -- 服务器地址
    port = nil,              -- 服务器端口
    auth_key = nil,          -- 用户鉴权密钥
    keepalive = 300,         -- mqtt心跳
    auto_reconnect = true,   -- 是否自动重连
    reconnect_interval = 10, -- 重连间隔(秒)
    max_reconnect = 3,       -- 最大重连次数
    timeout = 30,            -- 连接超时时间(秒)
    qos = 0,                 -- MQTT QoS等级
    retain = 0,              -- MQTT retain标志
    clean_session = true,    -- MQTT clean session标志
    ssl = false,             -- 是否使用SSL
    username = nil,          -- MQTT用户名
    password = nil,          -- MQTT密码
    udp_auth_key = nil,      -- UDP鉴权密钥

    -- 新增socket配置参数
    local_port = nil,      -- 本地端口号，nil表示自动分配
    keep_idle = nil,       -- TCP keepalive idle时间(秒)
    keep_interval = nil,   -- TCP keepalive 探测间隔(秒)
    keep_cnt = nil,        -- TCP keepalive 探测次数
    server_cert = nil,     -- 服务器CA证书数据
    client_cert = nil,     -- 客户端证书数据
    client_key = nil,      -- 客户端私钥数据
    client_password = nil, -- 客户端私钥口令
    use_getip = true,      -- 是否使用getip服务发现，默认为true
    -- MQTT扩展参数
    -- mqtt_rx_size = 32 * 1024, -- MQTT接收缓冲区大小，默认32K
    -- mqtt_conn_timeout = 30, -- MQTT连接超时时间
    -- mqtt_ipv6 = false, -- 是否使用IPv6连接
    -- getip相关配置
    getip_url = "https://gps.openluat.com/iam/iot/getip", -- 根据协议修正URL
    current_conninfo = {},                                -- 当前连接信息
    current_imginfo = nil,                                -- 当前图片上传信息
    current_audinfo = nil,                                -- 当前音频上传信息
    current_mtninfo = nil,                                -- 新增：运维日志上传信息
    getip_retry_count = 0,                                -- getip重试次数
    max_getip_retry = 3,                                  -- 最大getip重试次数

    -- 虚拟设备相关配置
    virtual_phone_number = nil, -- 手机号
    virtual_serial_num = 0,     -- 序列号（0-999）

    -- 运维日志配置
    mtn_log_enabled = false,               -- 是否启用运维日志
    aircloud_mtn_log_enabled = false,      -- 是否启用aircloud运维日志：true-开启，false-关闭；开启后设备认证/重连等关键事件会自动记录到运维日志文件，便于云端统一收集分析
    mtn_log_blocks = 1,                    -- 每个文件的块数
    mtn_log_write_way = exmtn.CACHE_WRITE, -- 写入方式

}

local callback_func = nil          -- 回调函数
local is_open = false              -- 服务是否开启
local is_connected = false         -- 是否已连接
local is_authenticated = false     -- 是否已鉴权
local sequence_num = 1             -- 流水号

-- 辅助函数：构建multipart/form-data请求体
local function build_multipart_form_data(forms, files)
    local boundary = "----WebKitFormBoundary" .. tostring(os.time())
    local body = {}

    -- 添加表单数据
    if forms then
        for k, v in pairs(forms) do
            table.insert(body, "--" .. boundary .. "\r\n")
            table.insert(body, string.format("Content-Disposition: form-data; name=\"%s\"\r\n\r\n", k))
            table.insert(body, tostring(v) .. "\r\n")
        end
    end

    -- 添加文件数据
    if files then
        for k, file_path in pairs(files) do
            local fd = io.open(file_path, "rb")
            if fd then
                local file_content = fd:read("*a")
                fd:close()

                local file_name = file_path:match("[^/\\]+$" or "")
                local content_type = "application/octet-stream"

                -- 根据文件扩展名设置Content-Type
                local ext = file_name:match("%.(%w+)$" or ""):lower()
                local content_types = {
                    txt = "text/plain",
                    jpg = "image/jpeg",
                    jpeg = "image/jpeg",
                    png = "image/png",
                    gif = "image/gif",
                    mp3 = "audio/mpeg",
                    wav = "audio/wav",
                    json = "application/json",
                    html = "text/html"
                }
                if content_types[ext] then
                    content_type = content_types[ext]
                end

                table.insert(body, "--" .. boundary .. "\r\n")
                table.insert(body, string.format("Content-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\n", k, file_name))
                table.insert(body, "Content-Type: " .. content_type .. "\r\n\r\n")
                table.insert(body, file_content .. "\r\n")
            end
        end
    end

    -- 添加结束边界
    table.insert(body, "--" .. boundary .. "--\r\n")

    return table.concat(body), boundary
end
local connection = nil             -- 连接对象
local device_id_binary = nil       -- 二进制格式的设备ID
local reconnect_timer = nil        -- 重连定时器
local reconnect_count = 0          -- 重连次数
local pending_messages = {}        -- 待发送消息队列
local rxbuff = nil                 -- 接收缓冲区
local connect_timeout_timer = nil  -- 连接超时定时器
local heartbeat_timer = nil        -- 心跳定时器
local heartbeat_interval = 300     -- 心跳间隔(秒)，默认5分钟
local heartbeat_data = {}          -- 心跳数据，默认空表
local is_heartbeat_running = false -- 心跳是否正在运行
local is_mtn_log_uploading = false -- 运维日志是否正在上传

-- 数据类型定义
local DATA_TYPES = {
    INTEGER = 0x0, -- 整数
    FLOAT = 0x1,   -- 浮点数
    BOOLEAN = 0x2, -- 布尔值
    ASCII = 0x3,   -- ASCII字符串
    BINARY = 0x4,  -- 二进制数据
    UNICODE = 0x5  -- Unicode字符串
}

-- 字段含义定义
local FIELD_MEANINGS = {
    -- 控制信令类型 (16-255)
    AUTH_REQUEST                 = 16, -- 鉴权请求
    AUTH_RESPONSE                = 17, -- 鉴权回复
    REPORT_RESPONSE              = 18, -- 上报回应
    CONTROL_COMMAND              = 19, -- 控制命令
    CONTROL_RESPONSE             = 20, -- 控制回应
    IRTU_DOWN                    = 21, -- iRTU下行命令
    IRTU_UP                      = 22, -- iRTU上行回复
    -- 文件上传控制信令 (23-24)
    FILE_UPLOAD_START            = 23, -- 文件上传开始通知
    FILE_UPLOAD_FINISH           = 24, -- 文件上传完成通知

    -- 运维日志控制信令 (25-27)
    MTN_LOG_UPLOAD_REQ_SIGNAL    = 25, -- 运维日志上传请求 - 下行（信令类型）
    MTN_LOG_UPLOAD_RESP_SIGNAL   = 26, -- 运维日志上传响应 - 上行（信令类型）
    MTN_LOG_UPLOAD_STATUS_SIGNAL = 27, -- 运维日志上传状态 - 上行（信令类型）

    -- 传感类 (256-511)
    TEMPERATURE                  = 256, -- 温度
    HUMIDITY                     = 257, -- 湿度
    PARTICULATE                  = 258, -- 颗粒数
    ACIDITY                      = 259, -- 酸度
    ALKALINITY                   = 260, -- 碱度
    ALTITUDE                     = 261, -- 海拔
    WATER_LEVEL                  = 262, -- 水位
    ENV_TEMPERATURE              = 263, -- CPU温度/环境温度
    POWER_METERING               = 264, -- 电量计量

    -- 资产管理类 (512-767)
    GNSS_LONGITUDE               = 512, -- GNSS经度
    GNSS_LATITUDE                = 513, -- GNSS纬度
    SPEED                        = 514, -- 行驶速度
    GNSS_CN                      = 515, -- 最强的4颗GNSS卫星的CN
    SATELLITES_TOTAL             = 516, -- 搜到的所有卫星数
    SATELLITES_VISIBLE           = 517, -- 可见卫星数
    HEADING                      = 518, -- 航向角
    LOCATION_METHOD              = 519, -- 基站定位/GNSS定位标识
    GNSS_INFO                    = 520, -- GNSS芯片型号和固件版本号
    DIRECTION                    = 521, -- 方向

    -- 设备参数类 (768-1023)
    HEIGHT                       = 768, -- 高度
    WIDTH                        = 769, -- 宽度
    ROTATION_SPEED               = 770, -- 转速
    BATTERY_LEVEL                = 771, -- 电量(mV)
    SERVING_CELL                 = 772, -- 驻留频段
    CELL_INFO                    = 773, -- 驻留小区和邻区
    COMPONENT_MODEL              = 774, -- 元器件型号
    GPIO_LEVEL                   = 775, -- GPIO高低电平
    BOOT_REASON                  = 776, -- 开机原因
    BOOT_COUNT                   = 777, -- 开机次数
    SLEEP_MODE                   = 778, -- 休眠模式
    WAKE_INTERVAL                = 779, -- 定时唤醒间隔
    NETWORK_IP_TYPE              = 780, -- 设备入网的IP类型
    NETWORK_TYPE                 = 781, -- 当前联网方式
    SIGNAL_STRENGTH_4G           = 782, --4G信号强度
    SIM_ICCID                    = 783, -- SIM卡ICCID

    -- 文件上传业务字段 (784-787)
    FILE_UPLOAD_TYPE             = 784, -- 文件上传类型（1:图片, 2:音频）
    FILE_NAME                    = 785, -- 文件名称
    FILE_SIZE                    = 786, -- 文件大小
    UPLOAD_RESULT_STATUS         = 787, -- 上传结果状态

    -- 运维日志业务字段 (788-792)
    MTN_LOG_FILE_INDEX           = 788, -- 运维日志文件序号
    MTN_LOG_FILE_TOTAL           = 789, -- 运维日志文件总数
    MTN_LOG_FILE_SIZE            = 790, -- 运维日志文件大小
    MTN_LOG_UPLOAD_STATUS_FIELD  = 791, -- 运维日志上传状态
    MTN_LOG_FILE_NAME            = 792, -- 运维日志文件名称

    -- 工牌设备参数字段 (793-797) - 新增
    BADGE_TOTAL_DISK             = 793, -- 工牌总磁盘空间
    BADGE_AVAILABLE_DISK         = 794, -- 工牌剩余磁盘空间
    BADGE_TOTAL_MEM              = 795, -- 工牌总内存
    BADGE_AVAILABLE_MEM          = 796, -- 工牌剩余内存
    BADGE_RECORD_COUNT           = 797, -- 工牌录音数量

    -- 软件数据类 (1024-1279)
    LUA_CORE_ERROR               = 1024, -- Lua核心库错误上报
    LUA_EXT_ERROR                = 1025, -- Lua扩展卡错误上报
    LUA_APP_ERROR                = 1026, -- Lua业务错误上报
    FIRMWARE_VERSION             = 1027, -- 固件版本号
    SMS_FORWARD                  = 1028, -- SMS转发
    CALL_FORWARD                 = 1029, -- 来电转发

    -- 设备无关数据类 (1280-1535)
    TIMESTAMP                    = 1280, -- 时间
    RANDOM_DATA                  = 1281  -- 无意义数据
}

-- 运维日志上传状态
local MTN_LOG_STATUS = {
    START = 0,   -- 开始上传
    SUCCESS = 1, -- 上传成功
    FAILED = 2   -- 上传失败
}

-- 将数字转换为大端字节序列
local function to_big_endian(num, bytes)
    local result = {}
    for i = bytes, 1, -1 do
        result[i] = string.char(num % 256)
        num = math.floor(num / 256)
    end
    return table.concat(result)
end

-- 从大端字节序列转换为数字
local function from_big_endian(data, start, length)
    local value = 0
    for i = start, start + length - 1 do
        value = value * 256 + data:byte(i)
    end
    -- log.info("[excloud]from_big_endian", value)
    return value
end

-- 将设备ID进行编码
local function packDeviceInfo(deviceType, deviceId)
    -- 验证设备类型
    if deviceType ~= 1 and deviceType ~= 2 and deviceType ~= 9 then
        log.info("[excloud]设备类型错误: 4G设备应为1, WIFI设备应为2")
    end

    -- 设备类型字节
    local result = { string.char(deviceType) }

    -- 清理设备ID（移除非数字和字母字符，并转换为大写）
    local cleanId = deviceId:gsub("[^%w]", ""):upper()

    -- 处理不同类型的设备ID
    if deviceType == 1 then
        -- 4G设备 - IMEI处理
        -- 只取前14位数字，忽略第15位
        cleanId = cleanId:gsub("%D", ""):sub(1, 14)

        -- 确保长度为14位（不足时前面补0）
        if #cleanId < 14 then
            cleanId = string.rep("0", 14 - #cleanId) .. cleanId
        end

        -- 转换为BCD格式的字节
        for i = 1, 14, 2 do
            local byte = (tonumber(cleanId:sub(i, i)) * 16) + tonumber(cleanId:sub(i + 1, i + 1))
            table.insert(result, string.char(byte))
        end
    elseif deviceType == 2 then
        -- WIFI设备 - MAC地址处理
        -- 移除非十六进制字符
        cleanId = cleanId:gsub("[^0-9A-Fa-f]", "")

        -- 确保长度为12个十六进制字符（6字节）
        if #cleanId < 12 then
            cleanId = string.rep("0", 12 - #cleanId) .. cleanId
        else
            cleanId = cleanId:sub(1, 12)
        end

        -- 转换为字节
        local bytes = {}
        for i = 1, 12, 2 do
            local byteStr = cleanId:sub(i, i + 1)
            table.insert(bytes, string.char(tonumber(byteStr, 16)))
        end

        -- 确保有7个字节（不足时前面补0）
        while #bytes < 7 do
            table.insert(bytes, 1, string.char(0))
        end

        -- 添加到结果中
        for _, byte in ipairs(bytes) do
            table.insert(result, byte)
        end
    elseif deviceType == 9 then
        -- 虚拟设备处理：11位手机号 + 3位序列号
        cleanId = cleanId:gsub("%D", ""):sub(1, 14)
        if #cleanId < 14 then
            cleanId = string.rep("0", 14 - #cleanId) .. cleanId
        end

        -- 转换为BCD格式的字节（每2位数字转换为1个字节）
        for i = 1, 14, 2 do
            local byte = (tonumber(cleanId:sub(i, i)) * 16) + tonumber(cleanId:sub(i + 1, i + 1))
            table.insert(result, string.char(byte))
        end
    else
        log.info("[excloud]未知设备类型 ")
        return deviceId
    end

    -- 返回8字节的二进制数据
    return table.concat(result)
end

-- 编码数据值
local function encode_value(data_type, value)
    -- 添加参数类型检查
    if data_type == nil or value == nil then
        log.info("[excloud]Data type or value is nil")
        return ""
    end
    if data_type == DATA_TYPES.INTEGER then
        -- 验证value是否为数字
        if type(value) ~= "number" then
            log.info("[excloud]Integer value must be a number")
            return ""
        end
        return to_big_endian(math.floor(value), 4)
    elseif data_type == DATA_TYPES.FLOAT then
        -- 验证value是否为数字
        if type(value) ~= "number" then
            log.info("[excloud]Float value must be a number")
            return ""
        end
        -- 简化处理：将浮点数转换为整数，乘以1000以保留三位小数
        return to_big_endian(math.floor(value * 1000), 4)
    elseif data_type == DATA_TYPES.BOOLEAN then
        return value and "\1" or "\0"
    elseif data_type == DATA_TYPES.ASCII or data_type == DATA_TYPES.BINARY or data_type == DATA_TYPES.UNICODE then
        -- 确保value是字符串类型
        return tostring(value)
    else
        log.info("[excloud]Unsupported data type: " .. tostring(data_type))
        -- 返回空字符串而不是nil，避免后续处理出错
        return ""
    end
end

-- 解码数据值
local function decode_value(data_type, value)
    if data_type == DATA_TYPES.INTEGER then
        return from_big_endian(value, 1, #value)
    elseif data_type == DATA_TYPES.FLOAT then
        -- 简化处理：将整数转换为浮点数（实际应使用IEEE 754格式）
        return from_big_endian(value, 1, #value) / 1000
    elseif data_type == DATA_TYPES.BOOLEAN then
        return value:byte(1) ~= 0
    elseif data_type == DATA_TYPES.ASCII then
        return value
    elseif data_type == DATA_TYPES.BINARY then
        return value
    elseif data_type == DATA_TYPES.UNICODE then
        return value
    else
        log.info("[excloud]Unsupported data type: " .. data_type)
        return nil
    end
end

-- 构建消息头
-- @param need_reply boolean 是否需要服务器回复
-- @param has_auth_key boolean 是否携带鉴权key
-- @param data_length number 数据长度
local function build_header(need_reply, is_udp_transport, data_length)
    sequence_num = sequence_num + 1
    if sequence_num > 65535 then
        sequence_num = 1
    end

    -- 消息标识字段
    local flags = config.protocol_version -- bit0-3: 协议版本号
    if need_reply then
        flags = flags + 16                -- bit4: 是否需要回复
    end
    if is_udp_transport then
        flags = flags + 32 -- bit5: 是否是UDP承载
    end
    log.info("[excloud]构建消息头", device_id_binary, to_big_endian(sequence_num, 2), to_big_endian(data_length, 2),
        to_big_endian(flags, 4))
    return device_id_binary ..
        to_big_endian(sequence_num, 2) ..
        to_big_endian(data_length, 2) ..
        to_big_endian(flags, 4)
end

-- 构建TLV字段
local function build_tlv(field_meaning, data_type, value)
    if field_meaning == nil or data_type == nil or value == nil then
        log.info("[excloud]构建tlv参数不能为空")
        return false
    end
    local value_encoded = encode_value(data_type, value)
    if value_encoded == nil then
        log.info("[excloud]构建tlv打包数据时长度为0")
        -- 添加空字符串作为默认值，避免后续获取长度时出错
        value_encoded = ""
    end
    local length = #value_encoded
    -- 字段类型（字段含义 + 数据类型）
    local head   = (field_meaning & 0x0FFF) | (data_type << 12) -- 2 字节头
    return true, to_big_endian(head, 2) ..
        to_big_endian(length, 2) ..
        value_encoded
end

-- 解析消息头
local function parse_header(header)
    if #header < 16 then
        log.info("[excloud]消息头解析失败", "Header too short")
        return nil, "Header too short"
    end

    local device_id = header:sub(1, 8)
    local seq_num = from_big_endian(header, 9, 2)
    local msg_length = from_big_endian(header, 11, 2)
    local flags = from_big_endian(header, 13, 4)

    -- 提取标志位
    local protocol_version = flags % 16
    local need_reply = (flags % 32) >= 16
    local is_udp_transport = (flags % 64) >= 32

    -- 打印解析结果，方便调试
    -- log.info("[excloud]消息头解析结果",
    --     string.format(
    --         "device_id: %s, sequence_num: %d, msg_length: %d, protocol_version: %d, need_reply: %s, is_udp_transport: %s",
    --         string.toHex(device_id), seq_num, msg_length, protocol_version,
    --         tostring(need_reply), tostring(is_udp_transport)))

    return {
        device_id = string.toHex(device_id),
        sequence_num = seq_num,
        msg_length = msg_length,
        protocol_version = protocol_version,
        need_reply = need_reply,
        is_udp_transport = is_udp_transport
    }
end

-- 工具函数：解析TLV
local function parse_tlv(data, startPos)
    -- 检查数据是否足够解析TLV的T的长度。
    if #data < startPos + 3 then
        return nil, startPos, "TLV data too short"
    end

    local fieldType = from_big_endian(data, startPos, 2)
    local length = from_big_endian(data, startPos + 2, 2)
    -- 提取原始字节值
    local value = data:sub(startPos + 4, startPos + 4 + length - 1)
    --解析TLV字段中的T
    -- bit0-11: 字段含义
    -- bit12-15: 数据类型
    local field_meaning = fieldType & 0x0FFF -- 取低12位作为字段含义
    local data_type = fieldType >> 12        -- 取高4位作为数据类型

    local decoded_value = decode_value(data_type, value)
    -- log.info("[excloud]消息体解析结果", field_meaning, data_type, decoded_value)
    return {
        field = field_meaning,
        type = data_type,
        value = decoded_value,
        length = length, --数据长度
    }, startPos + 4 + length
end

-- 解析完整消息
local function parse_message(data)
    local header, err = parse_header(data:sub(1, 16))
    if not header then
        return nil, err
    end
    local auth_key = nil
    local body_start = 17

    -- 如果是UDP传输，解析认证key
    if header.is_udp_transport then
        if #data >= body_start + 64 - 1 then
            auth_key = data:sub(body_start, body_start + 64 - 1)
            body_start = body_start + 64
        else
            return nil, "Incomplete UDP authentication key"
        end
    end

    -- 解析TLV字段
    local tlvs = {}
    local pos = body_start
    local end_pos = 16 + (header.msg_length)

    if #data < end_pos then
        return nil, "Message incomplete"
    end
    while pos < end_pos do
        local tlv, new_pos, err = parse_tlv(data, pos)
        if not tlv then
            return nil, "Failed to parse TLV at position " .. err
        end
        table.insert(tlvs, tlv)
        -- 更新解析位置为解析完当前TLV字段后的新位置，以便继续解析后续的TLV字段
        pos = new_pos
    end

    return {
        header = header,
        auth_key = auth_key,
        tlvs = tlvs
    }
end

-- 发送鉴权请求
local function send_auth_request()
    if not config.auth_key then
        return false, "No auth key configured"
    end
    local auth_data
    --设备实测时打开
    if config.device_type == 1 then
        auth_data = config.auth_key .. "-" .. mobile.imei() .. "-" .. mobile.muid()
    elseif config.device_type == 2 then
        auth_data = config.auth_key .. "-" .. wlan.getMac(nil, true) .. "-" .. mcu.unique_id():toHex()
    elseif config.device_type == 9 then --虚拟设备
        auth_data = config.auth_key .. "-" .. config.device_id
    else
        auth_data = config.auth_key .. "-"
    end

    local message = {
        {
            field_meaning = FIELD_MEANINGS.AUTH_REQUEST,
            data_type = DATA_TYPES.ASCII,
            value = auth_data
        }
    }
    -- log.info("[excloud]send auth request", message,message[1].value,message[1].data_type,message[1].field_meaning)
    return excloud.send(message, true, true) -- 鉴权消息需要设置 is_auth_msg 为 true
end

-- 处理认证响应
-- local function handle_auth_response(tlvs)
--     for _, tlv in ipairs(tlvs) do
--         if tlv.field_meaning == FIELD_MEANINGS.AUTH_RESPONSE then
--             local success = (tlv.value == "OK" or tlv.value == "SUCCESS")
--             is_authenticated = true

--             -- 记录认证结果到运维日志
--             if config.aircloud_mtn_log_enabled then
--                 exmtn.log("info", "aircloud","auth", "认证结果", "success", success, "message", tlv.value)
--             end


--             if callback_func then
--                 callback_func("auth_result", {
--                     success = success,
--                     message = tlv.value
--                 })
--             end

--             -- 认证成功，发送待处理消息
--             if success then
--                 for _, msg in ipairs(pending_messages) do
--                     excloud.send(msg.data, msg.need_reply)
--                 end
--                 pending_messages = {}
--             end

--             return success
--         end
--     end

--     return false
-- end

-- 初始化运维日志模块
local function init_mtn_log()
    if not config.mtn_log_enabled then
        log.info("[excloud]aircloud运维日志功能已禁用")
        return true
    end

    local ok, err = exmtn.init(config.mtn_log_blocks, config.mtn_log_write_way)
    if not ok then
        log.error("[excloud]运维日志初始化失败:", err)
        return false, err
    end

    log.info("[excloud]运维日志初始化成功")
    return true
end

-- 扫描运维日志文件
local function scan_mtn_log_files()
    local log_files = {}

    -- 使用exmtn管理的文件信息
    for i = 1, 4 do -- exmtn管理4个日志文件
        local file_path = string.format("/hzmtn%d.trc", i)
        if io.exists(file_path) then
            local file_size = io.fileSize(file_path)
            if file_size > 0 then
                table.insert(log_files, {
                    name = string.format("hzmtn%d.trc", i),
                    path = file_path,
                    size = file_size,
                    index = i
                })
                log.info("发现运维日志文件", "路径:", file_path, "大小:", file_size, "序号:", i)
            else
                log.info("运维日志文件为空", "路径:", file_path)
            end
        else
            log.info("运维日志文件不存在", "路径:", file_path)
        end
    end

    -- 按文件序号排序
    table.sort(log_files, function(a, b)
        return a.index < b.index
    end)

    log.info("扫描运维日志文件完成", "有效文件数量:", #log_files)
    return log_files
end

-- 构建运维日志响应TLV数据
local function build_mtn_log_response_tlv(total_files, latest_index)
    local sub_tlvs = ""

    -- 文件总数
    local success, tlv_data = build_tlv(FIELD_MEANINGS.MTN_LOG_FILE_TOTAL, DATA_TYPES.INTEGER, total_files)
    if success then
        sub_tlvs = sub_tlvs .. tlv_data
    else
        log.error("构建文件总数TLV失败")
        return ""
    end

    -- 当前最新文件序号
    success, tlv_data = build_tlv(FIELD_MEANINGS.MTN_LOG_FILE_INDEX, DATA_TYPES.INTEGER, latest_index)
    if success then
        sub_tlvs = sub_tlvs .. tlv_data
    else
        log.error("构建最新文件序号TLV失败")
        return ""
    end

    log.info("构建运维日志响应TLV", "文件总数:", total_files, "最新序号:", latest_index)
    return sub_tlvs
end

-- 发送运维日志上传状态
local function send_mtn_log_status(status, file_index, file_name, file_size)
    local sub_tlvs = ""

    -- 上传状态（必须）
    local success, tlv_data = build_tlv(FIELD_MEANINGS.MTN_LOG_UPLOAD_STATUS_FIELD, DATA_TYPES.INTEGER, status)
    if success then
        sub_tlvs = sub_tlvs .. tlv_data
    else
        log.error("构建运维日志上传状态TLV失败")
        return false, "构建状态TLV失败"
    end

    -- 文件序号
    success, tlv_data = build_tlv(FIELD_MEANINGS.MTN_LOG_FILE_INDEX, DATA_TYPES.INTEGER, file_index)
    if success then
        sub_tlvs = sub_tlvs .. tlv_data
    else
        log.error("构建文件序号TLV失败")
        return false, "构建文件序号TLV失败"
    end

    -- 根据状态添加不同的字段
    if status == MTN_LOG_STATUS.START then
        -- 开始上传：包含文件名
        if file_name then
            success, tlv_data = build_tlv(FIELD_MEANINGS.MTN_LOG_FILE_NAME, DATA_TYPES.ASCII, file_name)
            if success then
                sub_tlvs = sub_tlvs .. tlv_data
            else
                log.warn("构建文件名TLV失败，但继续发送状态")
            end
        else
            log.warn("开始上传状态缺少文件名")
        end
    elseif status == MTN_LOG_STATUS.SUCCESS then
        -- 上传成功：包含文件大小
        if file_size then
            success, tlv_data = build_tlv(FIELD_MEANINGS.MTN_LOG_FILE_SIZE, DATA_TYPES.INTEGER, file_size)
            if success then
                sub_tlvs = sub_tlvs .. tlv_data
            else
                log.warn("构建文件大小TLV失败，但继续发送状态")
            end
        else
            log.warn("上传成功状态缺少文件大小")
        end
    end
    -- 上传失败：只需要状态和序号

    -- 发送状态消息
    local ok, err_msg = excloud.send({
        {
            field_meaning = FIELD_MEANINGS.MTN_LOG_UPLOAD_STATUS_SIGNAL,
            data_type = DATA_TYPES.BINARY,
            value = sub_tlvs
        }
    }, false)

    if not ok then
        log.error("发送运维日志上传状态失败: " .. (err_msg or "未知错误"))
        return false, err_msg
    end

    log.info("运维日志上传状态发送成功",
        "状态:", status,
        "文件序号:", file_index,
        "文件名:", file_name or "N/A",
        "文件大小:", file_size or "N/A")

    return true
end
-- 上传运维日志文件
local function upload_mtn_log_files()

    sys.taskInit(function()
        -- 设置上传标志位为true
        is_mtn_log_uploading = true

        local total_files = 4 -- 固定为4个日志文件
        local success_count = 0
        local failed_count = 0
        local processed_count = 0

        -- -- 通知开始上传
        -- if callback_func then
        --     callback_func("mtn_log_upload_start", {
        --         file_count = total_files
        --     })
        -- end

        -- 按顺序检查并上传每个日志文件
        for i = 1, 4 do
            local file_path = string.format("/hzmtn%d.trc", i)
            local file_name = string.format("/hzmtn%d.trc", i)

            -- 在上传前再次检查文件是否存在且不为空
            local file_size = io.fileSize(file_path)
            if file_size and file_size > 0 then
                processed_count = processed_count + 1

                -- 发送开始上传状态
                send_mtn_log_status(MTN_LOG_STATUS.START, i, file_name, file_size)

                log.info("[excloud]开始上传运维日志文件", "文件:", file_name, "大小:", file_size)

                -- 上传文件
                local success, err_msg = excloud.upload_mtnlog(file_path, file_name)

                if success then
                    -- 发送上传成功状态
                    log.info("运维日志文件上传成功", "文件:", file_name, "大小:", file_size)
                    send_mtn_log_status(MTN_LOG_STATUS.SUCCESS, i, file_name, file_size)
                    success_count = success_count + 1

                    -- 记录上传成功的运维日志
                    if config.aircloud_mtn_log_enabled then
                        exmtn.log("info", "aircloud", "mtn_upload", "文件上传成功", "file", file_name, "size", file_size)
                    end
                else
                    -- 发送上传失败状态
                    log.error("运维日志文件上传失败", "文件:", file_name, "错误:", err_msg)
                    send_mtn_log_status(MTN_LOG_STATUS.FAILED, i, file_name, file_size)
                    failed_count = failed_count + 1

                    -- 记录上传失败的运维日志
                    if config.aircloud_mtn_log_enabled then
                        exmtn.log("info", "aircloud", "mtn_upload_error", "文件上传失败", "file", file_name, "error", err_msg)
                    end
                end

                -- 通知上传进度
                if callback_func then
                    callback_func("mtn_log_upload_progress", {
                        current_file = processed_count,
                        total_files = total_files,
                        file_name = file_name,
                        file_size = file_size,
                        status = success and "success" or "failed",
                        error_msg = err_msg
                    })
                end
            else
                -- 文件不存在或为空，跳过上传
                log.info("运维日志文件不存在或为空，跳过上传", "文件:", file_name)
            end
            -- -- 文件间延迟，避免同时上传多个文件
            -- if i < 4 then
            --     sys.wait(2000)
            -- end
        end

        log.info("运维日志上传完成", "成功:", success_count, "失败:", failed_count, "总计:", processed_count)

        -- 记录上传完成日志
        if config.aircloud_mtn_log_enabled then
            exmtn.log("info", "aircloud", "mtn_upload", "运维日志上传完成", "success", success_count, "failed", failed_count,
                "total", processed_count)
        end

        -- 通知上传完成
        if callback_func then
            callback_func("mtn_log_upload_complete", {
                success_count = success_count,
                failed_count = failed_count,
                total_files = processed_count
            })
        end

        -- 上传完成，设置标志位为false
        is_mtn_log_uploading = false
    end)
end

-- 处理运维日志上传请求
local function handle_mtn_log_upload_request()
    -- 检查是否正在上传，如果是则直接返回，抛弃新请求
    if is_mtn_log_uploading then
        log.info("[excloud]运维日志正在上传中，抛弃新的上传请求")
        return
    end

    local total_files = 4 -- 固定为4个日志文件
    local latest_index = 4 -- 最新序号固定为4

    if config.aircloud_mtn_log_enabled then
        exmtn.log("info", "aircloud", "cloud_cmd", "收到运维日志上传请求", "file_count", total_files)
    end

    log.info("开始处理运维日志上传请求", "文件总数:", total_files, "最新序号:", latest_index)

    -- 发送运维日志上传响应（信令26）- 在开始上传前发送
    local response_ok, err_msg = excloud.send({
        {
            field_meaning = FIELD_MEANINGS.MTN_LOG_UPLOAD_RESP_SIGNAL, -- 使用信令类型
            data_type = DATA_TYPES.BINARY,
            value = build_mtn_log_response_tlv(total_files, latest_index)
        }
    }, false)

    if not response_ok then
        log.error("发送运维日志上传响应失败: " .. err_msg)
        return
    end

    log.info("运维日志上传响应已发送", "文件总数:", total_files, "最新序号:", latest_index)

    -- 开始上传日志文件
    sys.timerStart(function()
        upload_mtn_log_files()
    end, 100)
end



-- 接收消息解析处理
local function parse_data(data)
    local message, err = parse_message(data)
    if not message then
        log.info("[excloud]Failed to parse message: " .. err)
        return
    end

    -- 处理运维日志上传请求（信令25）
    for _, tlv in ipairs(message.tlvs) do
        if tlv.field == FIELD_MEANINGS.MTN_LOG_UPLOAD_REQ_SIGNAL then
            log.info("[excloud]收到运维日志上传请求")
            handle_mtn_log_upload_request()
            return
        end
    end

    -- 处理认证响应
    -- if not is_authenticated then
    --   for _, tlv in ipairs(message.tlvs) do
    --        if tlv.field == FIELD_MEANINGS.AUTH_RESPONSE then
    --           handle_auth_response(message.tlvs)
    --          return
    --       end
    --   end
    --end

    --数据返回给回调
    if callback_func then
        callback_func("message", message)
    end

    -- -- 如果需要回复，发送确认AAA
    -- if message.header.need_reply then
    --     local response = {
    --         {
    --             field_meaning = FIELD_MEANINGS.REPORT_RESPONSE,
    --             data_type = DATA_TYPES.ASCII,
    --             value = "ACK"
    --         }
    --     }
    --     excloud.send(response, false)
    -- end
end

function excloud.getip(getip_type)
    getip_type = getip_type or 3 -- 默认使用AirCloud TCP协议

    -- 添加参数验证
    if not config.auth_key or not config.device_id then
        return false, "缺少必要的认证参数: auth_key 或 device_id"
    end

    local key = config.auth_key .. "-" .. config.device_id
    log.info("[excloud]excloud.getip", "类型:", getip_type, "key:", key)

    -- 执行HTTP请求
    local code, response = httpplus.request(
        {
            method = "POST",
            url = config.getip_url,
            forms = { key = key, type = getip_type }
        })

    log.info("[excloud]excloud.getip响应", "HTTP Code:", code, "Body:", response.body:query())
    -- 添加对HTTP响应为空值的处理
    if not response or not response.body then
        log.error("[excloud]getip请求失败", "HTTP响应为空")
        return false, "HTTP响应为空"
    end

    local response_body = response.body:query()
    if not response_body or response_body == "" then
        log.error("[excloud]getip请求失败", "响应体为空")
        return false, "响应体为空"
    end

    log.info("[excloud]excloud.getip响应", "HTTP Code:", code, "Body:", response_body)

    -- 处理HTTP错误码
    if code ~= 200 then
        log.info("[excloud]getip请求失败", "HTTP Code:", code)
        return false, "HTTP请求失败: " .. tostring(code)
    end

    -- 解析JSON响应，添加对解析失败的处理
    local response_json = json.decode(response_body)
    if not response_json then
        return false, "JSON解析失败: " .. tostring(err)
    end

    -- 检查服务器返回状态
    if not response_json.msg then
        log.error("[excloud]getip响应格式错误", "缺少msg字段")
        return false, "服务器响应格式错误: 缺少msg字段"
    end

    if response_json.msg ~= "ok" then
        log.error("[excloud]服务器返回错误", "消息:", response_json.msg)
        return false, "服务器返回错误: " .. tostring(response_json.msg)
    end


    if getip_type >= 3 and getip_type <= 5 then
        -- AirCloud业务
        if response_json.conninfo then
            config.current_conninfo = response_json.conninfo

            -- 根据连接类型处理不同的连接信息
            if getip_type == 5 then -- MQTT连接
                log.info("[excloud]获取到MQTT连接信息",
                    "host:", response_json.conninfo.ssl,
                    "port:", response_json.conninfo.port,
                    "username:", response_json.conninfo.username,
                    "password:", response_json.conninfo.password)
                log.info("[excloud]实际MQTT连接将使用设备信息:",
                    "client_id:", mobile.imei(),
                    "username:", mobile.imei(),
                    "password:", mobile.muid())
            else -- TCP/UDP连接
                log.info("[excloud]获取到TCP/UDP连接信息",
                    "host:", response_json.conninfo.ipv4,
                    "port:", response_json.conninfo.port)
            end
        else
            log.warn("[excloud]未获取到连接信息")
        end

        if response_json.imginfo then
            config.current_imginfo = response_json.imginfo
            log.info("[excloud]获取到图片上传信息")
        else
            log.warn("[excloud]未获取到图片上传信息")
        end

        if response_json.audinfo then
            config.current_audinfo = response_json.audinfo
            log.info("[excloud]获取到音频上传信息")
        else
            log.warn("[excloud]未获取到音频上传信息")
        end
        -- 新增：运维日志上传信息 (mtninfo)
        if response_json.mtninfo then
            config.current_mtninfo = response_json.mtninfo
            log.info("[excloud]获取到运维日志上传信息")
        else
            log.warn("[excloud]未获取到运维日志上传信息")
        end
    end

    -- 如果获取到连接信息，自动更新配置
    if config.current_conninfo then
        -- 根据连接类型设置不同的主机字段
        if getip_type == 5 then -- MQTT连接
            if config.current_conninfo.ssl then
                config.host = config.current_conninfo.ssl
            else
                log.warn("[excloud]MQTT连接信息中缺少SSL域名")
            end
        else -- TCP/UDP连接
            if config.current_conninfo.ipv4 then
                config.host = config.current_conninfo.ipv4
            else
                log.warn("[excloud]TCP/UDP连接信息中缺少IP地址")
            end
        end

        if config.current_conninfo.port then
            config.port = config.current_conninfo.port
        else
            log.warn("[excloud]连接信息中缺少端口号")
        end

        -- 更新MQTT认证信息
        if getip_type == 5 then
            if config.current_conninfo.username then
                config.username = config.current_conninfo.username
            end
            if config.current_conninfo.password then
                config.password = config.current_conninfo.password
            end
        end

        log.info("[excloud]excloud.getip", "更新配置:", config.host, config.port)
    else
        log.warn("[excloud]未获取到有效的连接信息，将使用原有配置")
    end

    return true, config.current_conninfo
end

-- 带重试的getip请求
function excloud.getip_with_retry(getip_type)
    local retry_count = 0
    local max_retry = config.max_getip_retry or 3
    local success, result

    while retry_count < max_retry do
        success, result = excloud.getip(getip_type)
        if success and result then
            log.info("[excloud]excloud.getip", "成功:", success, "结果:", json.encode(result))
            config.getip_retry_count = 0
            return true, result
        end

        retry_count = retry_count + 1
        config.getip_retry_count = retry_count
        log.warn("excloud.getip重试", "次数:", retry_count, "错误:", result)

        if retry_count < max_retry then
            sys.wait(5000) -- 等待5秒后重试
        end
    end

    return false, "getip请求失败，已达最大重试次数: " .. (result or "未知错误")
end

-- 发送文件上传开始通知
local function send_file_upload_start(file_type, file_name, file_size)
    -- 构建子TLV数据
    -- local sub_tlvs = ""

    -- 文件上传类型子TLV
    -- local success, tlv_data = build_tlv(FIELD_MEANINGS.FILE_UPLOAD_TYPE, DATA_TYPES.INTEGER, file_type)
    -- if success then
    --     sub_tlvs = sub_tlvs .. tlv_data
    -- end

    -- 文件名称子TLV
    -- success, tlv_data = build_tlv(FIELD_MEANINGS.FILE_NAME, DATA_TYPES.ASCII, file_name)
    -- if success then
    --     sub_tlvs = sub_tlvs .. tlv_data
    -- end

    -- 文件大小子TLV
    -- success, tlv_data = build_tlv(FIELD_MEANINGS.FILE_SIZE, DATA_TYPES.INTEGER, file_size)
    -- if success then
    --     sub_tlvs = sub_tlvs .. tlv_data
    -- end
    local sub_tlvs = 0
    -- 主TLV（文件上传开始通知）
    local message = {
        {
            field_meaning = FIELD_MEANINGS.FILE_UPLOAD_START,
            data_type = DATA_TYPES.INTEGER,
            value = sub_tlvs -- 子TLV数据作为二进制值
        },
        {
            field_meaning = FIELD_MEANINGS.FILE_UPLOAD_TYPE,
            data_type = DATA_TYPES.INTEGER,
            value = file_type
        },
        {
            field_meaning = FIELD_MEANINGS.FILE_NAME,
            data_type = DATA_TYPES.ASCII,
            value = file_name
        },
        {
            field_meaning = FIELD_MEANINGS.FILE_SIZE,
            data_type = DATA_TYPES.INTEGER,
            value = file_size
        }
    }

    return excloud.send(message, false)
end

-- 发送文件上传完成通知
local function send_file_upload_finish(file_type, file_name, file_success)
    -- 构建子TLV数据
    -- local sub_tlvs = ""

    -- -- 文件上传类型子TLV
    -- local success, tlv_data = build_tlv(FIELD_MEANINGS.FILE_UPLOAD_TYPE, DATA_TYPES.INTEGER, file_type)
    -- if success then
    --     sub_tlvs = sub_tlvs .. tlv_data
    -- end

    -- 文件名称子TLV
    -- success, tlv_data = build_tlv(FIELD_MEANINGS.FILE_NAME, DATA_TYPES.ASCII, file_name)
    -- if success then
    --     sub_tlvs = sub_tlvs .. tlv_data
    -- end

    -- 上传结果状态子TLV
    -- success, tlv_data = build_tlv(FIELD_MEANINGS.UPLOAD_RESULT_STATUS, DATA_TYPES.INTEGER, file_success and 0 or 1)
    -- if success then
    --     sub_tlvs = sub_tlvs .. tlv_data
    -- end
    local sub_tlvs = 0
    -- 主TLV（文件上传完成通知）
    local message = {

        {
            field_meaning = FIELD_MEANINGS.FILE_UPLOAD_FINISH,
            data_type = DATA_TYPES.INTEGER,
            value = sub_tlvs -- 子TLV数据作为二进制值
        },

        {
            field_meaning = FIELD_MEANINGS.FILE_UPLOAD_TYPE,
            data_type = DATA_TYPES.INTEGER,
            value = file_type
        },

        {
            field_meaning = FIELD_MEANINGS.FILE_NAME,
            data_type = DATA_TYPES.ASCII,
            value = file_name
        },

        {
            field_meaning = FIELD_MEANINGS.UPLOAD_RESULT_STATUS,
            data_type = DATA_TYPES.INTEGER,
            value = file_success and 0 or 1
        }

    }

    return excloud.send(message, false)
end

local function upload_file(file_type, file_path, file_name)
    local upload_info
    if file_type == 1 then
        upload_info = config.current_imginfo
    elseif file_type == 2 then
        upload_info = config.current_audinfo
    elseif file_type == 3 then
        upload_info = config.current_mtninfo -- 新增：运维日志上传
    else
        return false, "不支持的文件类型"
    end

    if not upload_info then
        return false, "未获取到上传配置信息，请先执行getip"
    end

    if not upload_info.url then
        return false, "上传URL为空"
    end
    local file_size = io.fileSize(file_path)
    if not file_size or file_size == 0 then
        log.info("[excloud]文件不存在或为空", "文件:", file_name,file_size)
        return false, "文件不存在或为空"
    end

    log.info("[excloud]开始文件上传", "类型:", file_type, "文件:", file_path, "大小:", file_size)
    log.info("[excloud]开始文件上传", "类型:", file_type, "文件:", file_name, "大小:", file_size)

    -- 发送上传开始通知（运维日志不需要）
    if file_type ~= 3 then
        local ok, err = send_file_upload_start(file_type, file_name, file_size)
        if not ok then
            log.warn("发送上传开始通知失败", err)
        end
    end

    -- 执行HTTP请求，添加重传机制
    local max_retries = 1
    local retry_count = 0
    local code, headers, body
    local upload_success = false
    local result_msg = ""

    while retry_count <= max_retries do
        -- 构建multipart/form-data请求体
        local forms = { ["key"] = upload_info.data_param.key }
        local files = { [upload_info.data_key or "f"] = file_path }
        local request_body, boundary = build_multipart_form_data(forms, files)

        -- 构建请求头
        local headers = {
            ["Content-Type"] = "multipart/form-data; boundary=" .. boundary,
            ["Content-Length"] = tostring(#request_body)
        }

        -- 发送HTTP请求
        log.info("[excloud]开始发送HTTP请求", "URL:", upload_info.url)
        code, headers, body = http.request("POST", upload_info.url, headers, request_body, {timeout=30000}).wait()

        -- 检查响应
        if code == 200 then
            log.info("[excloud]excloud.getip文件上传响应", "HTTP Code:", code, "Body:", body and (#body > 512 and #body or body) or "nil")

            local resp_data, err = json.decode(body)
            if resp_data and resp_data.code == 0 then
                upload_success = true
                result_msg = "上传成功"
                log.info("[excloud]文件上传成功", "URL:", resp_data.value and resp_data.value.uri or "未知")
                break
            else
                result_msg = "服务器返回错误: " .. (resp_data and tostring(resp_data.code) or "未知")
                log.error("文件上传失败", result_msg, "响应:", body)
            end
        else
            result_msg = "HTTP请求失败: " .. tostring(code)
            log.error("文件上传HTTP请求失败", result_msg, "Headers:", headers, "Body:", body)
        end

        -- 如果失败且未达到最大重试次数，则重试
        if not upload_success and retry_count < max_retries then
            retry_count = retry_count + 1
            log.info("[excloud]文件上传失败，开始第" .. retry_count .. "次重试")
            sys.wait(1000) -- 等待1秒后重试
        else
            break
        end
    end

    -- 发送上传完成通知（运维日志不需要）
    if file_type ~= 3 then
        local notify_ok, notify_err = send_file_upload_finish(file_type, file_name, upload_success)
        if not notify_ok then
            log.warn("发送上传完成通知失败", notify_err)
        end
    end

    return upload_success, result_msg
end

-- 运维日志上传接口
function excloud.upload_mtnlog(file_path, file_name)
    -- 判断是否是手动填写IP，不是getip的话，不允许上传文件
    if not config.use_getip then
        log.warn("[excloud]手动填写IP时不允许上传文件")
        return false, "手动填写IP时不允许上传文件"
    end


    -- 检查文件是否存在
    if not io.exists(file_path) then
        return false, "文件不存在: " .. file_path
    end
    log.info("[excloud]excloud.upload_mtnlog", "文件路径:", file_path, "文件名:", file_name)
    -- 如果没有文件上传配置，先获取
    if not config.current_mtninfo then
        log.info("[excloud]获取运维日志上传配置...")
        local getip_type = config.transport == "tcp" and 3 or
            config.transport == "udp" and 4 or
            config.transport == "mqtt" and 5 or 3


        local ok, err = excloud.getip_with_retry(getip_type)
        if not ok then
            return false, "获取运维日志上传配置失败: " .. err
        end
    end
    log.info("[excloud]excloud.upload_mtnlog", "文件路径:", file_path, "文件名:", file_name)
    return upload_file(3, file_path, file_name) -- 文件类型为3
end

-- 图片上传接口
function excloud.upload_image(file_path, file_name)
    -- 判断是否是手动填写IP，不是getip的话，不允许上传文件
    if not config.use_getip then
        log.warn("[excloud]手动填写IP时不允许上传图片文件")
        return false, "手动填写IP时不允许上传图片文件"
    end
    if not io.exists(file_path) then
        return false, "文件不存在: " .. file_path
    end
    -- 没有连接时直接退出
    if not is_connected then
        return false, "没有连接到服务器"
    end
    file_name = file_name or "image_" .. os.time() .. ".jpg"

    -- 如果没有图片上传配置，先获取
    if not config.current_imginfo then
        log.info("[excloud]excloud.upload_image", "获取图片上传配置...")
        local getip_type = config.transport == "tcp" and 3 or
            config.transport == "udp" and 4 or
            config.transport == "mqtt" and 5 or 3
        local ok, err = excloud.getip_with_retry(getip_type)
        if not ok then
            return false, "获取图片上传配置失败: " .. err
        end
    end

    return upload_file(1, file_path, file_name)
end

-- 音频上传接口
function excloud.upload_audio(file_path, file_name)
    -- 判断是否是手动填写IP，不是getip的话，不允许上传文件
    if not config.use_getip then
        log.warn("[excloud]手动填写IP时不允许上传音频文件")
        return false, "手动填写IP时不允许上传音频文件"
    end
    if not io.exists(file_path) then
        return false, "文件不存在: " .. file_path
    end
    -- 没有连接时直接退出
    if not is_connected then
        return false, "没有连接到服务器"
    end
    file_name = file_name or "audio_" .. os.time() .. ".mp3"

    -- 如果没有音频上传配置，先获取
    if not config.current_audinfo then
        log.info("[excloud]excloud.upload_audio", "获取音频上传配置...")
        local getip_type = config.transport == "tcp" and 3 or
            config.transport == "udp" and 4 or
            config.transport == "mqtt" and 5 or 3
        local ok, err = excloud.getip_with_retry(getip_type)
        if not ok then
            return false, "获取音频上传配置失败: " .. err
        end
    end

    return upload_file(2, file_path, file_name)
end

-- 记录运维日志
--[[
输出运维日志并写入文件
@api excloud.mtn_log(level, tag, ...)
@string level 日志级别，必须是 "info", "warn", 或 "error"
@string tag 日志标识，必须是字符串
@... 需打印的参数
@return boolean 成功返回true，失败返回false
@usage
excloud.mtn_log("info", "message", 123)
excloud.mtn_log("warn", "message", 456)
excloud.mtn_log("error", "message", 789)
]]
function excloud.mtn_log(level, tag, ...)
    if not config.mtn_log_enabled then
        return false, "运维日志功能已禁用" -- 禁用时返回失败
    end
    exmtn.log(level, tag, ...)
    return true
end

-- 获取运维日志状态
function excloud.get_mtn_log_status()
    if not config.mtn_log_enabled then
        return {
            enabled = false,
            message = "运维日志功能已禁用"
        }
    end

    local config_info = exmtn.get_config()
    local log_files = scan_mtn_log_files()
    local total_size = 0

    for _, file in ipairs(log_files) do
        total_size = total_size + file.size
    end

    return {
        enabled = true,
        config = config_info,
        file_count = #log_files,
        total_size = total_size,
        files = log_files,
        last_error = exmtn.get_last_error()
    }
end

-- 重连
local function schedule_reconnect()
    -- 检查是否已经关闭服务
    if not is_open then
        log.info("[excloud]服务已关闭，停止重连")
        return
    end

    -- 检查是否达到最大重连次数
    if reconnect_count >= config.max_reconnect then
        log.info("[excloud]到达最大重连次数 " .. reconnect_count .. "/" .. config.max_reconnect)

        -- 使用协程执行复杂的重连逻辑
        sys.taskInit(function()
            -- 执行紧急内存清理
            collectgarbage("collect")
            pending_messages = {}

            -- 根据use_getip决定是否重新获取服务器信息
            if config.use_getip then
                log.info("[excloud]TCP连接多次失败，重新获取服务器信息...")
                local getip_type = config.transport == "tcp" and 3 or
                    config.transport == "udp" and 4 or
                    config.transport == "mqtt" and 5 or 3

                -- 清除当前连接信息，强制重新获取
                config.current_conninfo = nil

                local ok, result = excloud.getip_with_retry(getip_type)
                if ok then
                    log.info("[excloud]重新获取服务器信息成功，重置重连计数",
                        "host:", config.host,
                        "port:", config.port,
                        "transport:", config.transport)

                    -- 重置重连计数
                    reconnect_count = 0

                    -- 使用新的服务器信息重新连接（先关闭再打开）
                    excloud.close() -- 确保完全关闭
                    sys.wait(200)   -- 在协程中可以安全使用 wait
                    excloud.open()  -- 重新打开
                else
                    log.error("[excloud]重新获取服务器信息失败，停止重连")
                    if callback_func then
                        callback_func("reconnect_failed", {
                            count = reconnect_count,
                            max_reconnect = config.max_reconnect,
                            getip_failed = true
                        })
                    end
                    -- 彻底停止重连
                    is_open = false
                end
            else
                -- 不使用getip，直接停止重连
                log.info("[excloud]达到最大重连次数，停止重连")
                if callback_func then
                    callback_func("reconnect_failed", {
                        count = reconnect_count,
                        max_reconnect = config.max_reconnect
                    })
                end
                is_open = false
            end
        end)
        return
    end

    -- 增加重连计数
    reconnect_count = reconnect_count + 1
    log.info("[excloud]安排第 " ..
        reconnect_count .. "/" .. config.max_reconnect .. " 次重连，等待 " .. config.reconnect_interval .. " 秒")

    -- 使用定时器安排重连，在协程中执行
    reconnect_timer = sys.timerStart(function()
        sys.taskInit(function()
            log.info("[excloud]执行第 " .. reconnect_count .. "/" .. config.max_reconnect .. " 次重连")

            -- 在重连前检查服务状态
            if not is_open then
                log.info("[excloud]服务已关闭，取消重连")
                return
            end

            -- 先执行内存清理
            collectgarbage("collect")

            -- 如果连接对象存在但连接已断开，先清理
            if connection and not is_connected then
                log.info("[excloud]清理残留的连接对象")
                if config.transport == "tcp" then
                    socket.close(connection)
                    socket.release(connection)
                elseif config.transport == "mqtt" then
                    connection:disconnect()
                    connection:close()
                end
                connection = nil
                sys.wait(50) -- 在协程中安全等待
            end

            -- 重置连接状态但保持服务开启状态
            is_connected = false
            is_authenticated = false

            -- 执行重连
            local success, err = excloud.open()
            if not success then
                log.error("[excloud]重连失败:", err)
                -- 重连失败会再次触发schedule_reconnect
            else
                log.info("[excloud]重连操作已发起")
            end
        end)
    end, config.reconnect_interval * 1000)
end

-- TCP socket事件回调函数
local function tcp_socket_callback(netc, event, param)
    log.info("[excloud]socket cb", netc, event, param)
    -- 取消连接超时定时器
    if connect_timeout_timer then
        sys.timerStop(connect_timeout_timer)
        connect_timeout_timer = nil
    end

    -- 记录连接状态变化的运维日志
    if config.aircloud_mtn_log_enabled then
        if event == socket.LINK then
            exmtn.log("info", "aircloud", "net_conn", "网络连接成功")
        elseif event == socket.ON_LINE then
            exmtn.log("info", "aircloud", "net_conn", "TCP连接成功", "host", config.host, "port", config.port)
        elseif event == socket.CLOSED then
            exmtn.log("info", "aircloud", "net_conn", "TCP连接断开", "param", param)
        end
    end

    if param ~= 0 then
        log.info("[excloud]socket", "连接断开")
        is_connected = false
        is_authenticated = false

        if callback_func then
            callback_func("disconnect", {})
        end
        -- 连接断开，释放资源
        socket.release(connection)
        connection = nil

        -- 尝试重连
        if config.auto_reconnect and is_open then
            -- is_open = false
            schedule_reconnect()
        end
        return
    end
    if event == socket.LINK then
        -- 网络连接成功
        log.info("[excloud]socket", "网络连接成功")
    elseif event == socket.ON_LINE then
        -- TCP连接成功
        log.info("[excloud]socket", "TCP连接成功")
        is_connected = true

        -- 重置重连计数，如果是重连的话，连接上服务器给重连计数重置为0
        reconnect_count = 0
        if callback_func then
            callback_func("connect_result", { success = true })
        end
        -- 发送认证请求
        send_auth_request()
    elseif event == socket.EVENT then
        -- 有数据到达
        socket.rx(netc, rxbuff)
        if rxbuff:used() > 0 then
            local data = rxbuff:query()
            log.info("[excloud]socket", "收到数据", #data, "字节", data:toHex())
            -- 处理接收到的数据
            parse_data(data)
        end
        -- -- 清空缓冲区
        rxbuff:del()
    elseif event == socket.TX_OK then
        socket.wait(netc)
        log.info("[excloud]socket", "发送完成")
    elseif event == socket.CLOSED then
        -- 连接错误或关闭
        socket.release(connection)
        connection = nil
        log.info("[excloud]socket", "主动断开链接")
    end
end

-- mqtt client的事件回调函数
local function mqtt_client_event_cbfunc(connected, event, data, payload, metas)
    log.info("[excloud]mqtt_client_event_cbfunc", event, data, payload, json.encode(metas))
    -- 取消连接超时定时器
    if connect_timeout_timer then
        sys.timerStop(connect_timeout_timer)
        connect_timeout_timer = nil
    end

    -- 记录MQTT状态变化的运维日志
    if config.aircloud_mtn_log_enabled then
        if event == "conack" then
            exmtn.log("info", "aircloud", "mqtt_conn", "MQTT连接成功", "host", config.host)
        elseif event == "disconnect" then
            exmtn.log("info", "aircloud", "mqtt_conn", "MQTT连接断开")
        elseif event == "error" then
            exmtn.log("info", "aircloud", "mqtt_error", "MQTT错误", "type", data, "code", payload)
        end
    end

    -- mqtt连接成功
    if event == "conack" then
        is_connected = true
        log.info("[excloud]MQTT connected")
        -- 重置重连计数，如果是重连的话，连接上服务器给重连计数重置为0
        reconnect_count = 0
        -- 订阅主题
        local device_id_hex = string.toHex(device_id_binary)
        local auth_topic = "/AirCloud/down/" .. device_id_hex .. "/auth"
        local all_topic = "/AirCloud/down/" .. device_id_hex .. "/all"
        log.info("[excloud]mqtt_client_event_cbfunc", "订阅主题", auth_topic, all_topic)
        connection:subscribe(auth_topic, 0)
        connection:subscribe(all_topic, 0)

        if callback_func then
            callback_func("connect_result", { success = true })
        end
        -- 发送认证请求
        send_auth_request()

        -- 订阅成功
    elseif event == "suback" then
        -- 取消订阅成功
    elseif event == "unsuback" then
        -- 接收到服务器下发的publish数据
        -- data：string类型，表示topic
        -- payload：string类型，表示payload
        -- metas：table类型，数据内容如下
        -- {
        --     qos: number类型，取值范围0,1,2
        --     retain：number类型，取值范围0,1
        --     dup：number类型，取值范围0,1
        --     message_id: number类型
        -- }
    elseif event == "recv" then
        log.info("[excloud]接收到MQTT消息",
            "主题:", data,
            "数据长度:", #payload,
            "QoS:", metas and metas.qos or "unknown",
            "消息ID:", metas and metas.message_id or "unknown")

        -- 对接收到的publish数据处理
        parse_data(payload)

        -- 发送成功publish数据
        -- data：number类型，表示message id
    elseif event == "sent" then
        -- 服务器断开mqtt连接
    elseif event == "disconnect" then
        is_connected = false
        is_authenticated = false
        log.info("[excloud]MQTT disconnected")

        if callback_func then
            callback_func("disconnect", {})
        end

        -- 尝试重连
        if config.auto_reconnect and is_open then
            -- is_open = false
            schedule_reconnect()
        end

        -- 收到服务器的心跳应答
    elseif event == "pong" then
        -- 严重异常，本地会主动断开连接
        -- data：string类型，表示具体的异常，有以下几种：
        --       "connect"：tcp连接失败
        --       "tx"：数据发送失败
        --       "conack"：mqtt connect后，服务器应答CONNACK鉴权失败，失败码为payload（number类型）
        --       "other"：其他异常
    elseif event == "error" then
        is_connected = false
        is_authenticated = false
        local error_msg = "Unknown MQTT error"

        if data == "connect" then
            error_msg = "TCP connection failed"
            -- 连接失败，应该考虑重新获取服务器信息
            if reconnect_count >= config.max_reconnect and config.use_getip then
                log.info("[excloud]MQTT连接多次失败，需要重新获取服务器信息")
                config.current_conninfo = nil
            end
        elseif data == "tx" then
            error_msg = "Data transmission failed"
        elseif data == "conack" then
            error_msg = "MQTT authentication failed with code: " .. tostring(payload)
        else
            error_msg = "Other MQTT error: " .. tostring(data)
        end

        log.info("[excloud]MQTT error: " .. error_msg)

        if callback_func then
            callback_func("disconnect", { error = error_msg })
        end
        -- 安全释放连接资源
        if connection then
            connection:disconnect()
            connection:close()
            connection = nil
        end
        -- 尝试重连
        if config.auto_reconnect and is_open then
            -- is_open = false
            schedule_reconnect()
        end
    end
end

-- 设置配置参数
function excloud.setup(params)
    if is_open then
        return false, "excloud is already open"
    end

    -- 合并配置参数
    for k, v in pairs(params) do
        config[k] = v
    end

    -- 验证必要参数
    if not config.auth_key then
        return false, "auth_key is required"
    end
    if config.device_type == 1 then
        config.device_id = mobile.imei()
        log.info("[excloud]4G设备", "IMEI:", config.device_id, "MUID:", mobile.muid())
    elseif config.device_type == 2 then
        config.device_id = wlan.getMac(nil, true)
        --以太网设备
    elseif config.device_type == 4 then
        config.device_id = netdrv.mac(socket.LWIP_ETH)
    elseif config.device_type == 9 then
        -- 虚拟设备：验证手机号和序列号
        if not config.virtual_phone_number then
            return false, "虚拟设备需要配置 virtual_phone_number"
        end

        -- 验证手机号格式（11位数字）
        local phone_clean = config.virtual_phone_number:gsub("%D", "")
        if #phone_clean ~= 11 then
            return false, "虚拟手机号必须为11位数字"
        end

        -- 设置默认序列号（如果未提供）
        if config.virtual_serial_num == nil then
            config.virtual_serial_num = 0
        end

        -- 序列号范围检查（0-999）
        config.virtual_serial_num = config.virtual_serial_num % 1000

        -- 生成设备ID：手机号 + 3位序列号
        local serial_str = string.format("%03d", config.virtual_serial_num)
        config.device_id = phone_clean .. serial_str

        log.info("虚拟设备配置", "手机号:", config.virtual_phone_number, "序列号:", serial_str, "设备ID:", config.device_id)
    else
        log.info("[excloud]未知设备类型", config.device_type)
        config.device_id = "unknown"
    end

    -- 打包设备id
    device_id_binary = packDeviceInfo(config.device_type, config.device_id)

    -- 初始化运维日志模块
    local mtn_ok, mtn_err = init_mtn_log()
    if not mtn_ok then
        log.warn("[excloud]运维日志初始化失败，但继续excloud初始化:", mtn_err)
    end

    log.info("[excloud]excloud.setup", "初始化成功", "设备ID:", config.device_id)
    return true
end

-- 注册回调函数
function excloud.on(cbfunc)
    if type(cbfunc) ~= "function" then
        return false, "Callback must be a function"
    end

    callback_func = cbfunc
    return true
end

-- 开启excloud服务
function excloud.open()
    -- 如果之前连接异常断开，但状态未重置，先清理
    if is_open and not is_connected then
        log.warn("[excloud]检测到状态不一致，先清理残留状态")
        excloud.close()
    end
    -- 检查是否已打开
    if is_open and is_connected then
        return false, "excloud is already open and connected"
    end
    reconnect_count = 0
    -- 判断是否初始化
    if not device_id_binary then
        return false, "excloud 没有初始化，请先调用setup"
    end

    -- 根据use_getip决定是否使用getip服务
    if config.use_getip then
        -- 使用getip服务发现
        local getip_type
        if config.transport == "tcp" then
            getip_type = 3
        elseif config.transport == "udp" then
            getip_type = 4
        elseif config.transport == "mqtt" then
            getip_type = 5
        else
            return false, "不支持的传输协议: " .. config.transport
        end

        -- 获取服务器连接信息
        if not config.current_conninfo or (config.transport ~= "mqtt" and not config.current_conninfo.ipv4) or
            (config.transport == "mqtt" and not config.current_conninfo.ssl) then
            log.info("[excloud]首次连接，获取服务器信息...")
            local ok, result = excloud.getip_with_retry(getip_type)
            if not ok then
                return false, "获取服务器信息失败: " .. result
            end

            -- 更新连接配置
            log.info("[excloud]服务器信息获取成功", "host:", config.host, "port:", config.port, "transport:", config.transport)

            -- 保存文件上传信息
            if result.imginfo then
                config.current_imginfo = result.imginfo
            end
            if result.audinfo then
                config.current_audinfo = result.audinfo
            end
        end
    else
        -- 不使用getip，直接使用用户配置的host和port
        log.info("使用手动配置的服务器地址", config.host, config.port)
        if not config.host or not config.port then
            return false, "use_getip为false时，必须配置host和port"
        end
    end

    -- 根据传输协议创建连接
    if config.transport == "tcp" then
        -- 创建接收缓冲区
        rxbuff = zbuff.create(2048)
        -- 创建TCP连接
        log.info("[excloud]创建TCP连接")
        connection = socket.create(nil, tcp_socket_callback)
        if not connection then
            return false, "Failed to create socket"
        end

        -- 准备SSL配置参数
        local ssl_config = nil
        if config.ssl then
            if type(config.ssl) == "table" then
                -- 使用详细的SSL配置
                ssl_config = config.ssl
            else
                -- 简单的SSL启用
                ssl_config = true
            end
        end

        -- 配置socket参数
        local config_success = socket.config(
            connection,
            config.local_port,                               -- 本地端口号
            false,                                           -- 是否是UDP，TCP连接为false
            ssl_config and true or false,                    -- 是否是加密传输
            config.keep_idle,                                -- keepalive idle时间
            config.keep_interval,                            -- keepalive 探测间隔
            config.keep_cnt,                                 -- keepalive 探测次数
            ssl_config and ssl_config.server_cert or nil,    -- 服务器CA证书
            ssl_config and ssl_config.client_cert or nil,    -- 客户端证书
            ssl_config and ssl_config.client_key or nil,     -- 客户端私钥
            ssl_config and ssl_config.client_password or nil -- 客户端私钥口令
        )
        if not config_success then
            socket.release(connection)
            connection = nil
            return false, "Socket config failed"
        end

        socket.debug(connection, true)

        -- 设置连接超时定时器
        connect_timeout_timer = sys.timerStart(function()
            if not is_connected then
                log.error("TCP connection timeout")
                if connection then
                    socket.close(connection)
                    socket.release(connection)
                    connection = nil
                end

                if callback_func then
                    callback_func("connect_result", { success = false, error = "Connection timeout" })
                end

                -- 尝试重连
                if config.auto_reconnect and is_open then
                    -- is_open = false
                    schedule_reconnect()
                end
            end
        end, config.timeout * 1000)

        -- 连接到服务器
        local ok, result = socket.connect(connection, config.host, config.port, config.mqtt_ipv6)
        log.info("[excloud]TCP连接结果", ok, result)
        if not ok then
            --发生异常，强制close
            socket.close(connection)
            --释放资源
            socket.release(connection)
            connection = nil

            if config.auto_reconnect then
                is_open = false
                schedule_reconnect()
            end
            return false, result
        end
    elseif config.transport == "mqtt" then
        -- 准备MQTT SSL配置 - MQTT连接默认使用SSL加密
        local ssl_config = true -- 最简单的SSL加密，不验证服务器证书

        -- 如果有详细的SSL配置，使用详细配置
        if config.ssl and type(config.ssl) == "table" then
            ssl_config = config.ssl
        end

        -- 准备MQTT扩展参数
        local mqtt_opts = {
            rxSize = config.mqtt_rx_size or 32 * 1024,     -- MQTT接收缓冲区大小，默认32K
            conn_timeout = config.mqtt_conn_timeout or 30, -- MQTT连接超时时间，默认30秒
            ipv6 = config.mqtt_ipv6 or false               -- 是否使用IPv6连接，默认false
        }

        -- 创建MQTT客户端
        connection = mqtt.create(nil, config.host, config.port, ssl_config, mqtt_opts)
        if not connection then
            return false, "Failed to create MQTT client"
        end

        -- 开启调试信息（可选）
        if config.debug then
            connection:debug(true)
        end

        -- 设置真实的MQTT认证信息
        local client_id, username, password

        if config.device_type == 1 then -- 4G设备
            client_id = mobile.imei()
            username = mobile.imei()
            password = mobile.muid()
            -- elseif config.device_type == 2 then -- WIFI设备
            --     client_id = wlan.getMac(nil, true)
            --     username = wlan.getMac(nil, true)
            --     password = mobile.muid():toHex()
            -- elseif config.device_type == 4 then -- 以太网设备
            --     client_id = netdrv.mac(socket.LWIP_ETH)
            --     username = netdrv.mac(socket.LWIP_ETH)
            --     password = mobile.muid():toHex()
            -- elseif config.device_type == 9 then -- 虚拟设备
            --     -- 虚拟设备使用配置的设备ID
            --     client_id = config.device_id
            --     username = config.device_id
            --     password = config.auth_key or config.device_id
        else
            return false, "MQTT connect failed, device_type not supported"
        end

        log.info("[excloud]MQTT认证信息",
            "client_id:", client_id,
            "username:", username,
            "password:", password)

        -- 设置认证信息（使用真实的设备信息，而不是getip返回的提示）
        connection:auth(client_id, username, password, config.clean_session)

        -- 设置保持连接间隔
        connection:keepalive(config.keepalive or 240) -- 默认240秒

        -- 设置遗嘱消息（如果需要）
        if config.will_topic and config.will_payload then
            local will_result = connection:will(
                config.will_topic,
                config.will_payload,
                config.will_qos or 0,
                config.will_retain or 0
            )
            if not will_result then
                log.warn("[excloud]设置遗嘱消息失败")
            end
        end

        -- 设置自动重连
        if config.auto_reconnect then
            connection:autoreconn(true, (config.reconnect_interval or 10) * 1000) -- 转换为毫秒
        end

        -- 注册事件回调
        connection:on(mqtt_client_event_cbfunc)

        -- 设置连接超时定时器
        connect_timeout_timer = sys.timerStart(function()
            if not is_connected then
                log.error("MQTT connection timeout")
                if connection then
                    connection:disconnect()
                    connection:close()
                    connection = nil
                end

                if callback_func then
                    callback_func("connect_result", { success = false, error = "Connection timeout" })
                end

                -- 尝试重连
                if config.auto_reconnect and is_open then
                    -- is_open = false
                    schedule_reconnect()
                end
            end
        end, config.timeout * 1000)

        -- 连接到服务器
        local ok = connection:connect()
        if not ok then
            --连接失败，释放资源
            connection:close()
            connection = nil
            -- 发起连接失败，尝试重连
            if config.auto_reconnect then
                is_open = false
                schedule_reconnect()
            end
            return false, "MQTT connect failed"
        end
    else
        return false, "Unsupported transport: " .. config.transport
    end

    is_open = true


    -- 记录服务启动日志
    if config.aircloud_mtn_log_enabled then
        exmtn.log("info", "aircloud", "system", "excloud服务启动", "transport", config.transport, "host", config.host, "port",
            config.port)
    end

    log.info("[excloud]excloud service started")

    return true
end

-- 发送数据
-- 发送消息到云端
-- @param data table 待发送的数据，每个元素是一个包含 field_meaning、data_type 和 value 的表
-- @param need_reply boolean 是否需要服务器回复，默认为 false
-- @param is_auth_msg boolean 是否是鉴权消息，默认为 false
function excloud.send(data, need_reply, is_auth_msg)
    if not is_open then
        return false, "excloud服务未开启"
    end

    if not is_connected then
        return false, "未连接到服务器"
    end

    -- if not is_authenticated and not is_auth_msg then
    --     return false, "设备未认证"
    -- end
    -- 检查参数是否为table
    if type(data) ~= "table" then
        return false, "data must be table"
    end
    if need_reply == nil then
        need_reply = false
    end
    if is_auth_msg == nil then
        is_auth_msg = false
    end
    -- 检查服务是否开启
    if not is_open then
        if callback_func then
            callback_func("send_result", {
                success = false,
                error_msg = "excloud not open"
            })
        end
        return false, "excloud not open"
    end

    -- 检查是否已连接
    if not is_connected then
        if callback_func then
            callback_func("send_result", {
                success = false,
                error_msg = "excloud not connected"
            })
        end
        return false, "excloud not connected"
    end

    -- 保存当前序列号用于回调
    local current_sequence = sequence_num
    -- 构建消息体
    local message_body = ""
    local parts = {}
    for _, item in ipairs(data) do
        log.info("[excloud]构建发送数据", item.field_meaning, item.data_type, item.value, message_body)
        local success, tlv = build_tlv(item.field_meaning, item.data_type, item.value)
        if not success then
            return false, "excloud.send data is failed"
        end
        table.insert(parts, tlv)
        -- message_body = message_body .. tlv
    end
    if #parts > 0 then
        message_body = table.concat(parts)
        parts = {}
    else
        log.warn("[excloud]没有有效的TLV数据可发送")
        -- return false, "No valid TLV data to send"
    end

    -- 检查消息长度
    local udp_auth_key = config.udp_auth_key and true or false
    local total_length = #message_body + (udp_auth_key and 64 or 0)

    log.info("[excloud]tlv发送数据长度4", total_length)

    -- 构建消息头
    local is_udp_transport = (config.transport == "udp")
    local header = build_header(need_reply, is_udp_transport, total_length)

    -- -- 添加鉴权key（如果是UDP的话）
    local auth_key_part = ""
    if config.transport == "udp" and udp_auth_key then
        auth_key_part = config.udp_auth_key
        if #auth_key_part < 64 then
            auth_key_part = auth_key_part .. string.rep("\0", 64 - #auth_key_part)
        elseif #auth_key_part > 64 then
            auth_key_part = auth_key_part:sub(1, 64)
        end
    end
    local full_message
    -- 发送完整消息
    if config.transport == "udp" then
        full_message = header .. auth_key_part .. message_body
    else
        full_message = header .. message_body
    end

    log.info("[excloud]发送消息长度", #header, #message_body, #full_message, full_message:toHex())

    local success, err_msg
    if config.transport == "tcp" then
        if not connection then
            err_msg = "TCP connection not available"
            success = false
        else
            success, err_msg = socket.tx(connection, full_message)
        end
    elseif config.transport == "mqtt" then
        -- 根据是否为鉴权消息选择不同的topic
        local topic
        local device_id_hex = string.toHex(device_id_binary)
        if is_auth_msg then
            topic = "/AirCloud/up/" .. device_id_hex .. "/auth"
        else
            topic = "/AirCloud/up/" .. device_id_hex .. "/all"
        end
        log.info("[excloud]发布主题", topic, #full_message, full_message:toHex())
        local message_id = connection:publish(topic, full_message, config.qos, config.retain)
        if message_id then
            success = true
            if config.qos and config.qos > 0 then
                log.info("[excloud]MQTT消息发布成功", "消息ID:", message_id)
            else
                log.info("[excloud]MQTT消息发布成功")
            end
        else
            success = false
            err_msg = "MQTT publish failed"
        end
    end

    -- 通过回调返回发送结果
    if callback_func then
        callback_func("send_result", {
            success = success,
            error_msg = success and "Send successful" or err_msg,
            sequence_num = current_sequence
        })
    end
    collectgarbage("collect")
    if success then
        log.info("[excloud]数据发送成功", #full_message, "字节")
        return true
    else
        log.error("数据发送失败", err_msg)
        return false, err_msg
    end
end

-- 关闭excloud服务
function excloud.close()
    if not is_open then
        return false, "excloud not open"
    end

    -- 停止所有定时器
    if reconnect_timer then
        sys.timerStop(reconnect_timer)
        reconnect_timer = nil
    end
    if connect_timeout_timer then
        sys.timerStop(connect_timeout_timer)
        connect_timeout_timer = nil
    end
    -- 停止心跳
    excloud.stop_heartbeat()
    -- 关闭连接
    if connection then
        if config.transport == "tcp" then
            socket.close(connection)
            socket.release(connection)
        elseif config.transport == "mqtt" then
            -- 断开连接并释放资源
            connection:disconnect()
            connection:close()
        end
        connection = nil
    end
    -- 释放缓冲区
    if rxbuff then
        rxbuff = nil
    end
    -- 清空队列
    pending_messages = {}
    callback_func = nil
    -- 记录服务关闭日志
    if config.aircloud_mtn_log_enabled then
        exmtn.log("info", "aircloud", "system", "excloud服务关闭")
    end

    -- 重置状态
    is_open = false
    is_connected = false
    is_authenticated = false
    pending_messages = {}
    rxbuff = nil
    reconnect_count = 0
    is_heartbeat_running = false
    collectgarbage("collect")
    log.info("[excloud]excloud service stopped")
    return true
end

-- 获取当前状态
function excloud.status()
    return {
        is_open = is_open,
        is_connected = is_connected,
        is_authenticated = is_authenticated,
        sequence_num = sequence_num,
        reconnect_count = reconnect_count,
        pending_messages = #pending_messages,
    }
end

-- 发送心跳消息
-- @param custom_data table 可选参数，自定义心跳内容
-- @param need_reply boolean 是否需要服务器回复，默认为false
-- @return boolean 是否发送成功
-- @return string 错误信息（如果失败）
function excloud.heartbeat(custom_data, need_reply)
    -- 如果心跳数据未提供，则使用默认的心跳数据（空表）
    local data = custom_data or heartbeat_data

    -- 设置默认不需要回复
    if need_reply == nil then
        need_reply = false
    end

    -- 调用send函数发送心跳数据
    return excloud.send(data, need_reply, false)
end

-- 启动自动心跳
-- @param interval number 心跳间隔(秒)，默认300秒(5分钟)
-- @param custom_data table 自定义心跳内容，默认空表
-- @return boolean 是否启动成功
function excloud.start_heartbeat(interval, custom_data)
    -- 停止现有的心跳定时器
    if is_heartbeat_running then
        excloud.stop_heartbeat()
    end

    -- 设置心跳间隔，默认5分钟
    heartbeat_interval = interval or 300

    -- 设置心跳数据
    heartbeat_data = custom_data or {}

    -- 创建并启动心跳定时器
    heartbeat_timer = sys.timerLoopStart(function()
        if is_open and is_connected then
            local ok, err_msg = excloud.heartbeat()
            if not ok then
                log.info("[excloud]excloud", "心跳发送失败: " .. err_msg)
            else
                log.info("[excloud]excloud", "心跳发送成功")
            end
        end
    end, heartbeat_interval * 1000) -- 转换为毫秒

    is_heartbeat_running = true
    log.info("[excloud]excloud", "自动心跳已启动，间隔 " .. heartbeat_interval .. " 秒")
    return true
end

-- 停止自动心跳
-- @return boolean 是否停止成功
function excloud.stop_heartbeat()
    if heartbeat_timer then
        sys.timerStop(heartbeat_timer)
        heartbeat_timer = nil
        is_heartbeat_running = false
        log.info("[excloud]excloud", "自动心跳已停止")
        return true
    end
    return false
end

-- 获取当前服务器信息
function excloud.get_server_info()
    return {
        conninfo = config.current_conninfo,
        imginfo = config.current_imginfo,
        audinfo = config.current_audinfo,
        mtninfo = config.current_mtninfo -- 新增：运维日志上传信息
    }
end

-- 强制刷新服务器信息
-- function excloud.refresh_server_info()
--     config.current_conninfo = nil
--     config.current_imginfo = nil
--     config.current_audinfo = nil
--     return true
-- end
-- 导出常量
excloud.DATA_TYPES = DATA_TYPES
excloud.FIELD_MEANINGS = FIELD_MEANINGS
excloud.MTN_LOG_STATUS = MTN_LOG_STATUS
excloud.MTN_LOG_CACHE_WRITE = exmtn.CACHE_WRITE
excloud.MTN_LOG_ADD_WRITE = exmtn.ADD_WRITE

return excloud
