--[[
@summary excloud扩展库
@version 2.0
@date    2026.01.01
@author  合宙（合并HH+QD版本）
@usage
-- 应用场景
该扩展库适用于各种物联网设备（如4G/WiFi/以太网设备）与云端服务器进行数据交互的场景。
可用于设备状态上报、数据采集、远程控制等物联网应用。

实现的功能：
1. 支持多种设备类型（4G/WiFi/以太网/虚拟设备）的接入认证
2. 提供TCP、UDP、MQTT三种传输协议选择
3. 实现设备与云端的双向通信（数据上报和命令下发）
4. 支持数据的TLV格式编解码
5. 提供自动重连机制，保证连接稳定性
6. 支持不同数据类型（整数、浮点数、布尔值、字符串、二进制等）的传输
7. 支持ZBUFF模式的文件上传（图片、音频、运维日志）
8. 使用httpplus接口优化HTTP文件上传性能和内存管理
9. 完善的key验证和防呆处理机制

-- 用法实例
本扩展库对外提供了以下接口：
1. excloud.setup(params) - 设置配置参数
2. excloud.on(cbfunc) - 注册回调函数
3. excloud.open() - 开启excloud服务
4. excloud.send(data, need_reply, is_auth_msg) - 发送数据
5. excloud.close() - 关闭excloud服务
6. excloud.status() - 获取当前状态
7. excloud.start_heartbeat(interval, custom_data) - 启动自动心跳机制
8. excloud.stop_heartbeat() - 停止自动心跳机制
9. excloud.upload_image(file_path, file_name) - 上传图片文件（支持ZBUFF）
10. excloud.upload_audio(file_path, file_name) - 上传音频文件（支持ZBUFF）
11. excloud.get_server_info() - 获取getip获取的服务器信息
12. excloud.mtn_log(tag, ...) - 记录运维日志
13. excloud.upload_mtnlog(file_path, file_name) - 上传运维日志文件
14. excloud.set_upload_callback(cb) - 设置文件上传回调函数
15. excloud.get_qrinfo() - 获取二维码信息
16. excloud.get_mtn_log_status() - 获取运维日志状态
]]
local excloud = {}
local httpplus = require "httpplus"
local exmtn = require "exmtn"

local config = {
    device_type = 1,         -- 默认设备类型: 4G
    device_id = "",          -- 设备ID
    protocol_version = 2,    -- 协议版本
    transport = "",          -- 传输协议: tcp/mqtt
    host = "",               -- 服务器地址
    port = nil,              -- 服务器端口
    auth_key = nil,          -- 用户项目密钥
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
    ipv6 = false, -- 是否使用IPv6连接
    -- getip相关配置
    getip_url = "https://gps.openluat.com/iam/iot/getip", -- 根据协议修正URL
    current_conninfo = {},                                -- 当前连接信息
    current_imginfo = nil,                                -- 当前图片上传信息
    current_audinfo = nil,                                -- 当前音频上传信息
    current_mtninfo = nil,                                -- 新增：运维日志上传信息
    current_qrinfo = nil,                                 -- 当前二维码信息
    getip_retry_count = 0,                                -- getip重试次数
    max_getip_retry = 3,                                  -- 最大getip重试次数

    -- 虚拟设备相关配置
    virtual_phone_number = nil, -- 手机号
    virtual_serial_num = 0,     -- 序列号（0-999）

    -- 运维日志配置
    mtn_log_enabled = false,               -- 是否启用运维日志
    aircloud_mtn_log_enabled = false,      -- 是否启用aircloud运维日志
    mtn_log_blocks = 1,                    -- 每个文件的块数
    mtn_log_write_way = exmtn.CACHE_WRITE, -- 写入方式
}

local callback_func = nil          -- 回调函数
local upload_callback = nil        -- 文件上传回调函数
local is_open = false              -- 服务是否开启
local is_connected = false         -- 是否已连接
local is_authenticated = false     -- 是否已鉴权
local sequence_num = 1             -- 流水号
local connection = nil             -- 连接对象

-- 根据传输协议转换为getip_type（消除4处重复）
local function transport_to_getip_type()
    if config.transport == "tcp" then return 3 end
    if config.transport == "udp" then return 4 end
    if config.transport == "mqtt" then return 5 end
    return 3
end

-- 安全清理连接对象（消除5处重复）
local function cleanup_connection()
    if not connection then return end
    if config.transport == "tcp" or config.transport == "udp" then
        socket.close(connection)
        socket.release(connection)
    elseif config.transport == "mqtt" then
        connection:disconnect()
        connection:close()
    end
    connection = nil
end

-- 停止连接超时定时器
local function stop_connect_timeout()
    if connect_timeout_timer then
        sys.timerStop(connect_timeout_timer)
        connect_timeout_timer = nil
    end
end

-- 启动连接超时定时器
local function start_connect_timeout(protocol_name)
    connect_timeout_timer = sys.timerStart(function()
        if not is_connected then
            log.error(protocol_name .. " connection timeout")
            cleanup_connection()

            if callback_func then
                callback_func("connect_result", { success = false, error = "Connection timeout" })
            end

            if config.auto_reconnect and is_open then
                schedule_reconnect()
            end
        end
    end, config.timeout * 1000)
end
local device_id_binary = nil       -- 二进制格式的设备ID
local reconnect_timer = nil        -- 重连定时器
local reconnect_count = 0          -- 重连次数
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
    MTN_LOG_UPLOAD_REQ_SIGNAL    = 25, -- 运维日志上传请求 - 下行
    MTN_LOG_UPLOAD_RESP_SIGNAL   = 26, -- 运维日志上传响应 - 上行
    MTN_LOG_UPLOAD_STATUS_SIGNAL = 27, -- 运维日志上传状态 - 上行

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
    DEVICE_ID                    = 798, -- 设备号
    VOLTAGE                      = 799, -- 电压

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

    -- 工牌设备参数字段 (793-797)
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
        log.info("[excloud]未知设备类型")
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

--[[
构建TLV字段
@api excloud.build_tlv(field_meaning, data_type, value)
@number field_meaning 字段含义，使用 FIELD_MEANINGS 中的常量
@number data_type 数据类型，使用 DATA_TYPES 中的常量
@param value 要编码的值，根据 data_type 类型不同，value 类型也不同
@return boolean success 是否构建成功
@return string tlv_data 构建好的 TLV 数据
@usage
-- 构建一个温度数据的 TLV 字段
local success, tlv_data = excloud.build_tlv(excloud.FIELD_MEANINGS.TEMPERATURE, excloud.DATA_TYPES.FLOAT, 25.5)
if success then
    -- 使用 tlv_data
end
]]
-- 保留本地函数引用，以便内部调用
local function build_tlv(field_meaning, data_type, value)
    return excloud.build_tlv(field_meaning, data_type, value)
end

function excloud.build_tlv(field_meaning, data_type, value)
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
    local tlv_data = to_big_endian(field_meaning, 2) ..
                     to_big_endian(data_type, 1) ..
                     to_big_endian(#value_encoded, 4) ..
                     value_encoded
    return true, tlv_data
end

-- 解析消息
local function parse_message(data)
    if #data < 15 then
        return nil, "Data too short"
    end

    -- 解析头部（15字节）
    -- local device_id = data:sub(1, 8)
    local sequence = from_big_endian(data, 9, 2)
    local data_length = from_big_endian(data, 11, 2)
    local flags = from_big_endian(data, 13, 4)

    local header = {
        sequence = sequence,
        data_length = data_length,
        protocol_version = flags % 16,
        need_reply = (bit.band(flags, 16) ~= 0),
        is_udp = (bit.band(flags, 32) ~= 0),
        has_auth_key = (bit.band(flags, 64) ~= 0)
    }

    -- 解析TLV字段
    local tlvs = {}
    local offset = 15

    while offset < #data do
        if offset + 7 > #data then
            break
        end

        local field = from_big_endian(data, offset, 2)
        local data_type = data:byte(offset + 2)
        local length = from_big_endian(data, offset + 3, 4)

        if offset + 7 + length > #data then
            break
        end

        local value = data:sub(offset + 7, offset + 6 + length)
        local decoded_value = decode_value(data_type, value)

        table.insert(tlvs, {
            field = field,
            data_type = data_type,
            length = length,
            raw_value = value,
            value = decoded_value
        })

        offset = offset + 7 + length
    end

    return {
        header = header,
        tlvs = tlvs
    }
end

-- 发送鉴权请求
local function send_auth_request()
    if not config.auth_key then
        log.error("[excloud]没有配置auth_key，无法发送鉴权请求")
        return false, "No auth key configured"
    end
    local auth_data
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
    return excloud.send(message, true, true)
end

-- 初始化运维日志
local function init_mtn_log()
    if not config.mtn_log_enabled then
        return true, "运维日志功能已禁用"
    end

    local blocks = config.mtn_log_blocks or 1
    local write_way = config.mtn_log_write_way or exmtn.CACHE_WRITE

    local ok, err = exmtn.init(blocks, write_way)
    if not ok then
        log.error("[excloud]运维日志初始化失败:", err)
        return false, err
    end

    log.info("[excloud]运维日志初始化成功")
    return true
end

-- 扫描运维日志文件
local function scan_mtn_log_files()
    local files = {}
    local base_path = "/exmtn/"

    for i = 1, 4 do
        local file_path = base_path .. "hzmtn" .. i .. ".trc"
        local file_size = io.fileSize(file_path)
        if file_size and file_size > 0 then
            table.insert(files, {
                index = i,
                path = file_path,
                size = file_size,
                name = "hzmtn" .. i .. ".trc"
            })
        end
    end

    return files
end

-- 构建运维日志响应TLV
local function build_mtn_log_response_tlv(total_files, latest_index)
    local response = {
        total_files = total_files,
        latest_index = latest_index,
        timestamp = os.time()
    }
    return json.encode(response)
end

-- 处理运维日志上传请求
local function handle_mtn_log_upload_request()
    -- 检查是否正在上传，如果是则直接返回，抛弃新请求
    if is_mtn_log_uploading then
        log.info("[excloud]运维日志正在上传中，抛弃新的上传请求")
        return
    end

    local total_files = 4
    local latest_index = 4

    if config.aircloud_mtn_log_enabled then
        exmtn.log("info", "aircloud", "cloud_cmd", "收到运维日志上传请求", "file_count", total_files)
    end

    log.info("开始处理运维日志上传请求", "文件总数:", total_files, "最新序号:", latest_index)

    -- 发送运维日志上传响应
    local response_ok, err_msg = excloud.send({
        {
            field_meaning = FIELD_MEANINGS.MTN_LOG_UPLOAD_RESP_SIGNAL,
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
    sys.taskInit(function()
        upload_mtn_log_files()
    end)
end

-- 接收消息解析处理
local function parse_data(data)
    local message, err = parse_message(data)
    if not message then
        log.info("[excloud]Failed to parse message: " .. err)
        return
    end

    -- 处理运维日志上传请求
    for _, tlv in ipairs(message.tlvs) do
        if tlv.field == FIELD_MEANINGS.MTN_LOG_UPLOAD_REQ_SIGNAL then
            log.info("[excloud]收到运维日志上传请求")
            handle_mtn_log_upload_request()
            return
        end
    end

    --数据返回给回调
    if callback_func then
        callback_func("message", message)
    end
end

-- 合并版本的getip函数（HH的key验证 + QD的内存释放）
function excloud.getip(getip_type)
    getip_type = getip_type or 3

    -- 添加参数验证
    if not config.device_id then
        return false, "缺少必要的认证参数: device_id"
    end

    -- 构建key（HH版本的key验证逻辑）
    local key = config.auth_key and (config.auth_key .. "-" .. config.device_id) or config.device_id
    log.info("[excloud]excloud.getip", "类型:", getip_type, "key:", key)

    -- 执行HTTP请求
    local code, response = httpplus.request(
        {
            method = "POST",
            url = config.getip_url,
            forms = { key = key, type = getip_type }
        })

    -- 添加对HTTP响应为空值的处理
    if not response or not response.body then
        log.error("[excloud]getip请求失败", "HTTP响应为空")
        response = nil
        return false, "HTTP响应为空"
    end
    
    -- 读取响应体
    local response_body = response.body:toStr()
    log.info("[excloud]excloud.getip响应", "HTTP Code:", code, "Body:", #response_body > 128 and string.sub(response_body, 1, 128) .. "..." or response_body)

    if not response_body or response_body == "" then
        log.error("[excloud]getip请求失败", "响应体为空")
        response = nil
        response_body = nil
        return false, "响应体为空"
    end

    -- 处理HTTP错误码
    if code ~= 200 then
        log.info("[excloud]getip请求失败", "HTTP Code:", code)
        response = nil
        response_body = nil
        return false, "HTTP请求失败: " .. tostring(code)
    end

    -- 解析JSON响应
    local response_json = json.decode(response_body)
    response_body = nil
    
    if not response_json then
        response = nil
        return false, "JSON解析失败"
    end

    -- 检查服务器返回状态（HH版本的防呆处理）
    if not response_json.msg then
        log.error("[excloud]getip响应格式错误", "缺少msg字段")
        response = nil
        return false, "服务器响应格式错误: 缺少msg字段"
    end

    if response_json.msg ~= "ok" then
        local err_msg = response_json.msg
        response = nil
        return false, "服务器返回错误: " .. tostring(err_msg)
    end

    -- 保存需要返回的完整响应信息（QD版本的内存管理）
    local return_result = {
        conninfo = response_json.conninfo,
        imginfo = response_json.imginfo,
        audinfo = response_json.audinfo,
        mtninfo = response_json.mtninfo,
        qrinfo = response_json.qrinfo
    }

    if getip_type >= 3 and getip_type <= 5 then
        if response_json.conninfo then
            config.current_conninfo = response_json.conninfo

            if getip_type == 5 then
                log.info("[excloud]获取到MQTT连接信息",
                    "host:", response_json.conninfo.ssl,
                    "port:", response_json.conninfo.port,
                    "username:", response_json.conninfo.username,
                    "password:", response_json.conninfo.password)
                log.info("[excloud]实际MQTT连接将使用设备信息:",
                    "client_id:", mobile.imei(),
                    "username:", mobile.imei(),
                    "password:", mobile.muid())
            else
                log.info("[excloud]获取到TCP/UDP连接信息",
                    "host:", response_json.conninfo.ipv4,
                    "port:", response_json.conninfo.port,
                    "key:", response_json.conninfo.key)
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

        if response_json.mtninfo then
            config.current_mtninfo = response_json.mtninfo
            log.info("[excloud]获取到运维日志上传信息")
        else
            log.warn("[excloud]未获取到运维日志上传信息")
        end
        
        if response_json.qrinfo then
            config.current_qrinfo = response_json.qrinfo
            log.info("[excloud]获取到二维码信息")
        else
            log.warn("[excloud]未获取到二维码信息")
        end
    end

    -- 如果获取到连接信息，自动更新配置
    if config.current_conninfo then
        if getip_type == 5 then
            if config.current_conninfo.ssl then
                config.host = config.current_conninfo.ssl
            else
                log.warn("[excloud]MQTT连接信息中缺少SSL域名")
            end
        else
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
            -- 如果服务器返回了auth_key，且本地没有设置，则保存
            if config.current_conninfo.auth_key and not config.auth_key then
                config.auth_key = config.current_conninfo.auth_key
                log.info("[excloud]自动获取到auth_key")
            end
        else
            -- 更新UDP认证密钥
            if config.current_conninfo.key then
                config.udp_auth_key = config.current_conninfo.key
                log.info("[excloud]更新UDP认证密钥")
            end
            
            -- 如果服务器返回了auth_key，且本地没有设置，则保存
            if config.current_conninfo.auth_key and not config.auth_key then
                config.auth_key = config.current_conninfo.auth_key
                log.info("[excloud]自动获取到auth_key")
            end
        end

        log.info("[excloud]excloud.getip", "更新配置:", config.host, config.port)
    else
        log.warn("[excloud]未获取到有效的连接信息，将使用原有配置")
    end

    -- 释放临时变量（QD版本的内存优化）
    response_json = nil
    response = nil
    
    return true, return_result
end

-- 带重试的getip请求
function excloud.getip_with_retry(getip_type)
    local retry_count = 0
    local max_retry = config.max_getip_retry or 3
    local success, result

    while retry_count < max_retry do
        success, result = excloud.getip(getip_type)
        if success then
            log.info("[excloud]excloud.getip", "成功:", success)
            config.getip_retry_count = 0
            return true, result
        end

        retry_count = retry_count + 1
        config.getip_retry_count = retry_count
        log.warn("excloud.getip重试", "次数:", retry_count, "错误:", result)

        if retry_count < max_retry then
            sys.wait(5000)
        end
    end

    return false, "getip请求失败，已达最大重试次数"
end

-- 发送文件上传开始通知
local function send_file_upload_start(file_type, file_name, file_size)
    local sub_tlvs = 0
    local message = {
        {
            field_meaning = FIELD_MEANINGS.FILE_UPLOAD_START,
            data_type = DATA_TYPES.INTEGER,
            value = sub_tlvs
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
    local sub_tlvs = 0
    local message = {
        {
            field_meaning = FIELD_MEANINGS.FILE_UPLOAD_FINISH,
            data_type = DATA_TYPES.INTEGER,
            value = sub_tlvs
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

-- 判断是否是ZBUFF对象
local function is_zbuff(obj)
    return obj and type(obj) == "userdata" 
end

-- 合并版本的异步文件上传协程（QD的httpplus + HH的zbuff支持）
local function do_upload_file(file_type, file_path, file_name, upload_info)
    local file_size
    local use_zbuff = is_zbuff(file_path)

    if use_zbuff then
        file_size = file_path:used()
        if not file_size or file_size == 0 then
            log.info("[excloud]ZBUFF数据为空", "文件:", file_name)
            return false, "ZBUFF数据为空"
        end
        log.info("[excloud]开始ZBUFF上传", "类型:", file_type, "文件:", file_name, "大小:", file_size)
    else
        file_size = io.fileSize(file_path)
        if not file_size or file_size == 0 then
            log.info("[excloud]文件不存在或为空", "文件:", file_name, file_size)
            return false, "文件不存在或为空"
        end
        log.info("[excloud]开始文件上传", "类型:", file_type, "文件:", file_path, "大小:", file_size)
    end

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
    local upload_success = false
    local result_msg = ""

    while retry_count <= max_retries do
        -- 检查主连接状态，避免在重连期间上传
        if file_type ~= 3 and not is_connected then
            log.warn("[excloud]主连接已断开，暂停文件上传")
            result_msg = "主连接已断开"
            break
        end

        -- 使用httpplus.request上传文件（QD版本的接口）
        log.info("[excloud]开始发送HTTP请求", "URL:", upload_info.url)
        local code, response
        
        if use_zbuff then
            -- 使用ZBUFF流式构建，避免内存双倍分配
            local boundary = "----LuatOSFormBoundary" .. os.time()
            
            -- 计算所需ZBUFF大小并创建
            local file_data_size = file_path:used()
            local header_size = 512 -- 预留足够的头部空间
            local total_size = file_data_size + header_size
            local body_zbuff = zbuff.create(total_size)
            
            -- 流式写入：key 表单字段
            body_zbuff:write("--" .. boundary .. "\r\n")
            body_zbuff:write("Content-Disposition: form-data; name=\"key\"\r\n\r\n")
            body_zbuff:write(upload_info.data_param.key .. "\r\n")
            
            -- 流式写入：文件字段
            body_zbuff:write("--" .. boundary .. "\r\n")
            body_zbuff:write("Content-Disposition: form-data; name=\"" .. (upload_info.data_key or "f") .. "\"; filename=\"" .. file_name .. "\"\r\n")
            body_zbuff:write("Content-Type: application/octet-stream\r\n\r\n")
            
            -- 直接写入原ZBUFF数据（用query+write，避免额外内存分配）
            local data_zb = file_path:query()
            body_zbuff:write(data_zb)
            data_zb = nil -- 立即释放临时引用
            
            -- 写入结束边界
            body_zbuff:write("\r\n--" .. boundary .. "--\r\n")
            
            code, response = httpplus.request({
                method = "POST",
                url = upload_info.url,
                headers = {
                    ["Content-Type"] = "multipart/form-data; boundary=" .. boundary
                },
                body = body_zbuff, -- 直接传ZBUFF，httpplus原生支持
                timeout = 30000
            })
        else
            -- 使用文件路径上传
            code, response = httpplus.request({
                method = "POST",
                url = upload_info.url,
                forms = { ["key"] = upload_info.data_param.key },
                files = { [upload_info.data_key or "f"] = file_path },
                timeout = 30000
            })
        end

        -- 处理响应后立即释放内存
        if code == 200 and response and response.body then
            local body_str = is_zbuff(response.body) and response.body:toStr() or tostring(response.body)
            log.info("[excloud]文件上传响应", "HTTP Code:", code, "Body:", #body_str > 128 and string.sub(body_str, 1, 128) .. "..." or body_str)

            local resp_data, err = json.decode(body_str)
            if resp_data and resp_data.code == 0 then
                upload_success = true
                result_msg = "上传成功"
                log.info("[excloud]文件上传成功", "URL:", resp_data.value and resp_data.value.uri or "未知")
                resp_data = nil
            else
                result_msg = "服务器返回错误: " .. (resp_data and tostring(resp_data.code) or "未知")
                log.error("文件上传失败", result_msg, "响应:", body_str)
                resp_data = nil
            end
            body_str = nil
        else
            result_msg = "HTTP请求失败: " .. tostring(code)
            log.error("文件上传HTTP请求失败", result_msg, "响应:", response)
        end

        -- 释放response对象
        response = nil

        -- 如果失败且未达到最大重试次数，则重试
        if not upload_success and retry_count < max_retries then
            retry_count = retry_count + 1
            log.info("[excloud]文件上传失败，开始第" .. retry_count .. "次重试")
            sys.wait(1000)
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

    -- 文件上传完成后，执行轻量级GC
    collectgarbage("step", 200)
    log.info("[excloud]文件上传完成")

    return upload_success, result_msg
end

-- 通用文件上传函数
local function upload_file(file_type, file_path, file_name, is_async)
    local upload_info
    if file_type == 1 then
        upload_info = config.current_imginfo
    elseif file_type == 2 then
        upload_info = config.current_audinfo
    elseif file_type == 3 then
        upload_info = config.current_mtninfo
    else
        return false, "不支持的文件类型"
    end

    if not upload_info then
        return false, "未获取到上传配置信息，请先执行getip"
    end

    if not upload_info.url then
        return false, "上传URL为空"
    end

    if is_async then
        -- 使用协程异步执行文件上传
        sys.taskInit(function()
            local result_ok, result_msg = do_upload_file(file_type, file_path, file_name, upload_info)
            
            if upload_callback then
                upload_callback(file_type, file_name, result_ok, result_msg)
            end
        end)
        
        return true, "文件上传已启动"
    else
        -- 同步执行
        return do_upload_file(file_type, file_path, file_name, upload_info)
    end
end

-- 通用上传参数检查
local function prepare_upload(file_data, file_name, upload_type)
    if not file_data then
        log.error("[excloud]" .. upload_type, upload_type .. "数据为空")
        return false, upload_type .. "数据为空"
    end

    if not config.use_getip then
        log.warn("[excloud]" .. upload_type, "手动填写IP时不允许上传文件")
        return false, "手动填写IP时不允许上传文件"
    end

    local is_zbuff_data = type(file_data) == "userdata" and file_data.used and true or false
    
    if not is_zbuff_data then
        if type(file_data) ~= "string" then
            log.error("[excloud]" .. upload_type, "无效的文件路径类型")
            return false, "无效的文件路径类型"
        end
        if not io.exists(file_data) then
            return false, "文件不存在: " .. file_data
        end
    end
    
    if not is_connected then
        log.warn("[excloud]" .. upload_type, "没有连接到服务器")
        return false, "没有连接到服务器"
    end
    
    return true
end

-- 设置上传回调函数
function excloud.set_upload_callback(cb)
    if type(cb) ~= "function" then
        return false, "Callback must be a function"
    end
    upload_callback = cb
    return true
end

-- 上传运维日志文件（支持ZBUFF）
function excloud.upload_mtnlog(file_data, file_name)
    local ok, err = prepare_upload(file_data, file_name, "upload_mtnlog")
    if not ok then
        return false, err
    end
    
    file_name = file_name or "mtnlog_" .. os.time() .. ".trc"

    if not config.current_mtninfo then
        log.info("[excloud]upload_mtnlog", "获取运维日志上传配置...")
        local ok, err = excloud.getip_with_retry(transport_to_getip_type())
        if not ok then
            log.error("[excloud]upload_mtnlog", "获取运维日志上传配置失败", err)
            return false, "获取运维日志上传配置失败: " .. err
        end
    end

    return upload_file(3, file_data, file_name, false)
end

-- 图片上传接口（支持ZBUFF）
function excloud.upload_image(file_data, file_name)
    local ok, err = prepare_upload(file_data, file_name, "upload_image")
    if not ok then
        return false, err
    end
    
    file_name = file_name or "image_" .. os.time() .. ".jpg"

    if not config.current_imginfo then
        log.info("[excloud]excloud.upload_image", "获取图片上传配置...")
        local ok, err = excloud.getip_with_retry(transport_to_getip_type())
        if not ok then
            log.error("[excloud]upload_image", "获取图片上传配置失败", err)
            return false, "获取图片上传配置失败: " .. err
        end
    end

    return upload_file(1, file_data, file_name, false)
end

-- 音频上传接口（支持ZBUFF）
function excloud.upload_audio(file_data, file_name)
    local ok, err = prepare_upload(file_data, file_name, "upload_audio")
    if not ok then
        return false, err
    end
    
    file_name = file_name or "audio_" .. os.time() .. ".mp3"

    if not config.current_audinfo then
        log.info("[excloud]excloud.upload_audio", "获取音频上传配置...")
        local ok, err = excloud.getip_with_retry(transport_to_getip_type())
        if not ok then
            return false, "获取音频上传配置失败: " .. err
        end
    end

    return upload_file(2, file_data, file_name, false)
end

-- 记录运维日志
function excloud.mtn_log(level, tag, ...)
    if not config.mtn_log_enabled then
        return false, "运维日志功能已禁用"
    end
    exmtn.log(level, tag, ...)
    return true
end

-- 获取二维码信息
function excloud.get_qrinfo()
    return config.current_qrinfo
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

-- 重连逻辑
local function schedule_reconnect()
    if not is_open then
        log.info("[excloud]服务已关闭，停止重连")
        return
    end
    reconnect_count = reconnect_count + 1
    log.info("[excloud]安排第 " .. reconnect_count .. "/" .. config.max_reconnect .. " 次重连，等待 " .. config.reconnect_interval .. " 秒")

    if reconnect_count >= config.max_reconnect then
        log.info("[excloud]到达最大重连次数 " .. reconnect_count .. "/" .. config.max_reconnect)

        sys.taskInit(function()
            collectgarbage("step", 300) -- 轻量级GC，避免卡顿

            if config.use_getip then
                log.info("[excloud]连接多次失败，重新获取服务器信息...")
                config.current_conninfo = nil
                local ok, result = excloud.getip_with_retry(transport_to_getip_type())
                if ok then
                    log.info("[excloud]重新获取服务器信息成功，重置重连计数",
                        "host:", config.host,
                        "port:", config.port,
                        "transport:", config.transport)

                    reconnect_count = 0

                    excloud.close()
                    sys.wait(200)
                    excloud.open()
                else
                    log.error("[excloud]重新获取服务器信息失败，将在网络恢复后重试")
                    if callback_func then
                        callback_func("reconnect_failed", {
                            count = reconnect_count,
                            max_reconnect = config.max_reconnect,
                            getip_failed = true
                        })
                    end
                    reconnect_count = 0
                end
            else
                log.info("[excloud]达到最大重连次数，将在网络恢复后重试")
                if callback_func then
                    callback_func("reconnect_failed", {
                        count = reconnect_count,
                        max_reconnect = config.max_reconnect
                    })
                end
                reconnect_count = 0
            end
        end)
        return
    end

    reconnect_timer = sys.timerStart(function()
        sys.taskInit(function()
            log.info("[excloud]执行第 " .. reconnect_count .. "/" .. config.max_reconnect .. " 次重连")

            if not is_open then
                log.info("[excloud]服务已关闭，取消重连")
                return
            end

            collectgarbage("step", 300) -- 轻量级GC，避免卡顿

            if connection and not is_connected then
                log.info("[excloud]清理残留的连接对象")
                cleanup_connection()
                sys.wait(50)
            end

            is_connected = false
            is_authenticated = false

            local success, err = excloud.open()
            if not success then
                log.error("[excloud]重连失败:", err)
            else
                log.info("[excloud]重连操作已发起")
            end
        end)
    end, config.reconnect_interval * 1000)
end

-- TCP socket事件回调函数
local function tcp_socket_callback(netc, event, param)
    log.info("[excloud]socket cb", netc, event, param)
    stop_connect_timeout()

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
        socket.release(connection)
        connection = nil

        if config.auto_reconnect and is_open then
            schedule_reconnect()
        end
        return
    end
    if event == socket.LINK then
        log.info("[excloud]socket", "网络连接成功")
    elseif event == socket.ON_LINE then
        log.info("[excloud]socket", "TCP连接成功")
        is_connected = true

        reconnect_count = 0
        if callback_func then
            callback_func("connect_result", { success = true })
        end
        send_auth_request()
    elseif event == socket.EVENT then
        socket.rx(netc, rxbuff)
        if rxbuff:used() > 0 then
            local data = rxbuff:query()
            log.info("[excloud]socket", "收到数据", #data, "字节", data:toHex())
            parse_data(data)
        end
        rxbuff:del()
    elseif event == socket.TX_OK then
        socket.wait(netc)
        log.info("[excloud]socket", "发送完成")
    elseif event == socket.CLOSED then
        socket.release(connection)
        connection = nil
        log.info("[excloud]socket", "主动断开链接")
    end
end

-- UDP socket回调函数
local function udp_socket_callback(netc, event, param)
    log.info("[excloud]UDP socket cb", netc, event, param)
    stop_connect_timeout()

    if config.aircloud_mtn_log_enabled then
        if event == socket.LINK then
            exmtn.log("info", "aircloud", "net_conn", "网络连接成功")
        elseif event == socket.ON_LINE then
            exmtn.log("info", "aircloud", "net_conn", "UDP连接成功", "host", config.host, "port", config.port)
        elseif event == socket.CLOSED then
            exmtn.log("info", "aircloud", "net_conn", "UDP连接断开", "param", param)
        end
    end

    if param ~= 0 then
        log.info("[excloud]UDP socket", "连接断开")
        is_connected = false
        is_authenticated = false

        if callback_func then
            callback_func("disconnect", {})
        end
        socket.release(connection)
        connection = nil

        if config.auto_reconnect and is_open then
            schedule_reconnect()
        end
        return
    end
    if event == socket.LINK then
        log.info("[excloud]UDP socket", "网络连接成功")
    elseif event == socket.ON_LINE then
        log.info("[excloud]UDP socket", "UDP连接成功")
        is_connected = true

        reconnect_count = 0
        if callback_func then
            callback_func("connect_result", { success = true })
        end
        send_auth_request()
    elseif event == socket.EVENT then
        local ok, len, remote_ip, remote_port = socket.rx(netc, rxbuff)
        if ok then
            local data = rxbuff:query()
            log.info("[excloud]UDP socket", "收到数据", #data, "字节", data:toHex())
            parse_data(data)
            rxbuff:del()
        else
            log.info("[excloud]UDP socket", "服务器断开了连接")
            is_connected = false
            is_authenticated = false

            if callback_func then
                callback_func("disconnect", {})
            end
            socket.release(connection)
            connection = nil

            if config.auto_reconnect and is_open then
                schedule_reconnect()
            end
        end
    elseif event == socket.TX_OK then
        log.info("[excloud]UDP socket", "上行完成")
    else
        log.info("[excloud]UDP socket", "其他事件", event)
    end
end

-- MQTT client的事件回调函数
local function mqtt_client_event_cbfunc(connected, event, data, payload, metas)
    log.info("[excloud]mqtt_client_event_cbfunc", event, data, payload, json.encode(metas))
    stop_connect_timeout()

    if config.aircloud_mtn_log_enabled then
        if event == "conack" then
            exmtn.log("info", "aircloud", "mqtt_conn", "MQTT连接成功", "host", config.host)
        elseif event == "disconnect" then
            exmtn.log("info", "aircloud", "mqtt_conn", "MQTT连接断开")
        elseif event == "error" then
            exmtn.log("info", "aircloud", "mqtt_error", "MQTT错误", "type", data, "code", payload)
        end
    end

    if event == "conack" then
        is_connected = true
        log.info("[excloud]MQTT connected")
        reconnect_count = 0
        local device_id_hex = string.toHex(device_id_binary)
        local auth_topic = "/AirCloud/down/" .. device_id_hex .. "/auth"
        local all_topic = "/AirCloud/down/" .. device_id_hex .. "/all"
        log.info("[excloud]mqtt_client_event_cbfunc", "订阅主题", auth_topic, all_topic)
        connection:subscribe(auth_topic, 0)
        connection:subscribe(all_topic, 0)

        if callback_func then
            callback_func("connect_result", { success = true })
        end
        send_auth_request()
    elseif event == "suback" then
    elseif event == "unsuback" then
    elseif event == "recv" then
        log.info("[excloud]接收到MQTT消息",
            "主题:", data,
            "数据长度:", #payload,
            "QoS:", metas and metas.qos or "unknown",
            "消息ID:", metas and metas.message_id or "unknown")

        parse_data(payload)
    elseif event == "sent" then
    elseif event == "disconnect" then
        is_connected = false
        is_authenticated = false
        log.info("[excloud]MQTT disconnected")

        if callback_func then
            callback_func("disconnect", {})
        end

        if config.auto_reconnect and is_open then
            schedule_reconnect()
        end
    elseif event == "pong" then
    elseif event == "error" then
        is_connected = false
        is_authenticated = false
        local error_msg = "Unknown MQTT error"

        if data == "connect" then
            error_msg = "TCP connection failed"
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
        if connection then
            connection:disconnect()
            connection:close()
            connection = nil
        end
        if config.auto_reconnect and is_open then
            schedule_reconnect()
        end
    end
end

function excloud.setup(params)
    if is_open then
        return false, "excloud is already open"
    end

    for k, v in pairs(params) do
        config[k] = v
    end

    if config.device_type == 1 then
        config.device_id = mobile.imei()
        log.info("[excloud]4G设备", "IMEI:", config.device_id, "MUID:", mobile.muid())
    elseif config.device_type == 2 then
        config.device_id = wlan.getMac(nil, true)
    elseif config.device_type == 4 then
        config.device_id = netdrv.mac(socket.LWIP_ETH)
    elseif config.device_type == 9 then
        if not config.virtual_phone_number then
            return false, "虚拟设备需要配置 virtual_phone_number"
        end

        local phone_clean = config.virtual_phone_number:gsub("%D", "")
        if #phone_clean ~= 11 then
            return false, "虚拟手机号必须为11位数字"
        end

        if config.virtual_serial_num == nil then
            config.virtual_serial_num = 0
        end

        config.virtual_serial_num = config.virtual_serial_num % 1000

        local serial_str = string.format("%03d", config.virtual_serial_num)
        config.device_id = phone_clean .. serial_str

        log.info("虚拟设备配置", "手机号:", config.virtual_phone_number, "序列号:", serial_str, "设备ID:", config.device_id)
    else
        log.info("[excloud]未知设备类型", config.device_type)
        config.device_id = "unknown"
    end

    device_id_binary = packDeviceInfo(config.device_type, config.device_id)

    local mtn_ok, mtn_err = init_mtn_log()
    if not mtn_ok then
        log.warn("[excloud]运维日志初始化失败，但继续excloud初始化:", mtn_err)
    end

    log.info("[excloud]excloud.setup", "初始化成功", "设备ID:", config.device_id)
    return true
end

function excloud.on(cbfunc)
    if type(cbfunc) ~= "function" then
        return false, "Callback must be a function"
    end

    callback_func = cbfunc
    return true
end

function excloud.open()
    if is_open and not is_connected then
        log.warn("[excloud]检测到状态不一致，先清理残留状态")
        excloud.close()
    end
    if is_open and is_connected then
        return false, "excloud is already open and connected"
    end

    if not device_id_binary then
        return false, "excloud 没有初始化，请先调用setup"
    end
    
    sys.subscribe("IP_READY", function()
        if is_open and not is_connected then
            log.info("[excloud]网络已恢复，尝试重新连接")
            sys.taskInit(function()
                reconnect_count = 0
                local success, err = excloud.open()
                if not success then
                    log.error("[excloud]网络恢复后重连失败:", err)
                end
            end)
        end
    end)

    if config.use_getip then
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

        if not config.current_conninfo or (config.transport ~= "mqtt" and not config.current_conninfo.ipv4) or
            (config.transport == "mqtt" and not config.current_conninfo.ssl) then
            log.info("[excloud]首次连接，获取服务器信息...")
            local ok, result = excloud.getip_with_retry(getip_type)
            if not ok then
                return false, "获取服务器信息失败: " .. result
            end

            if not config.auth_key then
                log.error("[excloud]未能获取到auth_key，无法继续")
                if callback_func then
                    callback_func("auth_key_error", { error = "未能获取到auth_key" })
                end
                return false, "未能获取到auth_key"
            end

            log.info("[excloud]服务器信息获取成功", "host:", config.host, "port:", config.port, "transport:", config.transport)

            if result.imginfo then
                config.current_imginfo = result.imginfo
            end
            if result.audinfo then
                config.current_audinfo = result.audinfo
            end
            if result.mtninfo then
                config.current_mtninfo = result.mtninfo
            end
            if result.qrinfo then
                config.current_qrinfo = result.qrinfo
                log.info("[excloud]获取到二维码信息")
            end
        end
    else
        log.info("使用手动配置的服务器地址", config.host, config.port)
        if not config.host or not config.port then
            return false, "use_getip为false时，必须配置host和port"
        end
    end

    if config.transport == "tcp" then
        rxbuff = zbuff.create(2048)
        log.info("[excloud]创建TCP连接")
        connection = socket.create(socket.dft(), tcp_socket_callback)
        if not connection then
            return false, "Failed to create socket"
        end

        local ssl_config = config.ssl

        local config_success = socket.config(
            connection,
            config.local_port,
            false,
            ssl_config and true or false,
            config.keep_idle,
            config.keep_interval,
            config.keep_cnt,
            ssl_config and ssl_config.server_cert or nil,
            ssl_config and ssl_config.client_cert or nil,
            ssl_config and ssl_config.client_key or nil,
            ssl_config and ssl_config.client_password or nil
        )
        if not config_success then
            socket.release(connection)
            connection = nil
            return false, "Socket config failed"
        end

        if config and config.debug then
            log.info("[excloud]TCP调试模式已启用")
            socket.debug(connection, true)
        end

        start_connect_timeout("TCP")

        local ok, result = socket.connect(connection, config.host, config.port, config.ipv6)
        log.info("[excloud]TCP连接结果", ok, result)
        if not ok then
            socket.close(connection)
            socket.release(connection)
            connection = nil

            if config.auto_reconnect then
                schedule_reconnect()
            end
            return false, result
        end
    elseif config.transport == "mqtt" then
        local ssl_config = true

        if config.ssl and type(config.ssl) == "table" then
            ssl_config = config.ssl
        end

        local mqtt_opts = {
            rxSize = config.mqtt_rx_size or 32 * 1024,
            conn_timeout = config.mqtt_conn_timeout or 30,
            ipv6 = config.ipv6 or false
        }

        connection = mqtt.create(socket.dft(), config.host, config.port, ssl_config, mqtt_opts)
        if not connection then
            return false, "Failed to create MQTT client"
        end

        if config.debug then
            connection:debug(true)
        end

        local client_id, username, password

        if config.device_type == 1 then
            client_id = mobile.imei()
            username = mobile.imei()
            password = mobile.muid()
        else
            return false, "MQTT connect failed, device_type not supported"
        end

        log.info("[excloud]MQTT认证信息",
            "client_id:", client_id,
            "username:", username,
            "password:", password)

        connection:auth(client_id, username, password, config.clean_session)
        connection:keepalive(config.keepalive or 240)

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

        if config.auto_reconnect then
            connection:autoreconn(true, (config.reconnect_interval or 10) * 1000)
        end

        connection:on(mqtt_client_event_cbfunc)

        start_connect_timeout("MQTT")

        local ok = connection:connect()
        if not ok then
            connection:close()
            connection = nil
            if config.auto_reconnect then
                schedule_reconnect()
            end
            return false, "MQTT connect failed"
        end
    elseif config.transport == "udp" then
        rxbuff = zbuff.create(2048)
        log.info("[excloud]创建UDP连接")
        connection = socket.create(socket.dft(), udp_socket_callback)
        if not connection then
            return false, "Failed to create UDP socket"
        end

        local config_success = socket.config(
            connection,
            config.local_port,
            true,
            false,
            nil,
            nil,
            nil
        )
        if not config_success then
            socket.release(connection)
            connection = nil
            return false, "Socket config failed"
        end

        if config and config.debug then
            log.info("[excloud]UDP调试模式已启用")
            socket.debug(connection, true)
        end

        start_connect_timeout("UDP")

        local ok, result = socket.connect(connection, config.host, config.port, config.ipv6)
        log.info("[excloud]UDP连接结果", ok, result)
        if not ok then
            socket.close(connection)
            socket.release(connection)
            connection = nil

            if config.auto_reconnect then
                schedule_reconnect()
            end
            return false, result
        end
    else
        return false, "Unsupported transport: " .. config.transport
    end

    is_open = true

    if config.aircloud_mtn_log_enabled then
        exmtn.log("info", "aircloud", "system", "excloud服务启动", "transport", config.transport, "host", config.host, "port",
            config.port)
    end

    log.info("[excloud]excloud service started")

    return true
end

function excloud.send(data, need_reply, is_auth_msg)
    if not is_open then
        if callback_func then
            callback_func("send_result", {
                success = false,
                error_msg = "excloud服务未开启"
            })
        end
        return false, "excloud服务未开启"
    end

    if not is_connected then
        if callback_func then
            callback_func("send_result", {
                success = false,
                error_msg = "未连接到服务器"
            })
        end
        return false, "未连接到服务器"
    end

    if type(data) ~= "table" then
        return false, "data must be table"
    end
    if need_reply == nil then
        need_reply = false
    end
    if is_auth_msg == nil then
        is_auth_msg = false
    end

    local current_sequence = sequence_num
    local message_body = ""
    local parts = {}
    for _, item in ipairs(data) do
        log.info("[excloud]构建发送数据", item.field_meaning, item.data_type, item.value, message_body)
        local success, tlv = build_tlv(item.field_meaning, item.data_type, item.value)
        if not success then
            return false, "excloud.send data is failed"
        end
        table.insert(parts, tlv)
    end
    if #parts > 0 then
        message_body = table.concat(parts)
        parts = {}
    else
        log.warn("[excloud]没有有效的TLV数据可发送")
    end

    local udp_auth_key = config.udp_auth_key and true or false
    local total_length = #message_body

    log.info("[excloud]tlv发送数据长度4", total_length)

    local is_udp_transport = (config.transport == "udp") and true or false
    local header = build_header(need_reply, is_udp_transport, total_length)

    local full_message
    if config.transport == "udp" then
        full_message = header .. config.udp_auth_key .. message_body
    else
        full_message = header .. message_body
    end

    local success, err_msg
    if config.transport == "tcp" then
        if not connection then
            err_msg = "TCP connection not available"
            success = false
        else
            success, err_msg = socket.tx(connection, full_message)
        end
    elseif config.transport == "mqtt" then
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
    elseif config.transport == "udp" then
        if not connection then
            err_msg = "UDP connection not available"
            success = false
        else
            success, err_msg = socket.tx(connection, full_message)
        end
    end

    if callback_func then
        callback_func("send_result", {
            success = success,
            error_msg = success and "Send successful" or err_msg,
            sequence_num = current_sequence
        })
    end
    if success then
        log.info("[excloud]数据发送成功", #full_message, "字节")
        return true
    else
        log.error("数据发送失败", err_msg)
        return false, err_msg
    end
end

function excloud.close()
    if not is_open then
        return false, "excloud not open"
    end

    if reconnect_timer then
        sys.timerStop(reconnect_timer)
        reconnect_timer = nil
    end
    stop_connect_timeout()
    excloud.stop_heartbeat()
    cleanup_connection()

    callback_func = nil
    if config.aircloud_mtn_log_enabled then
        exmtn.log("info", "aircloud", "system", "excloud服务关闭")
    end

    is_open = false
    is_connected = false
    is_authenticated = false

    rxbuff = nil
    is_heartbeat_running = false
    collectgarbage("collect")
    log.info("[excloud]excloud service stopped")
    return true
end

function excloud.status()
    return {
        is_open = is_open,
        is_connected = is_connected,
        is_authenticated = is_authenticated,
        sequence_num = sequence_num,
        reconnect_count = reconnect_count,
    }
end

function excloud.heartbeat(custom_data, need_reply)
    local data = custom_data or heartbeat_data

    if need_reply == nil then
        need_reply = false
    end

    return excloud.send(data, need_reply, false)
end

function excloud.start_heartbeat(interval, custom_data)
    if is_heartbeat_running then
        excloud.stop_heartbeat()
    end

    heartbeat_interval = interval or 300
    heartbeat_data = custom_data or {}

    heartbeat_timer = sys.timerLoopStart(function()
        if is_open and is_connected then
            local ok, err_msg = excloud.heartbeat()
            if not ok then
                log.info("[excloud]excloud", "心跳发送失败: " .. err_msg)
            else
                log.info("[excloud]excloud", "心跳发送成功")
            end
        end
    end, heartbeat_interval * 1000)

    is_heartbeat_running = true
    log.info("[excloud]excloud", "自动心跳已启动，间隔 " .. heartbeat_interval .. " 秒")
    return true
end

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

function excloud.get_server_info()
    return {
        conninfo = config.current_conninfo,
        imginfo = config.current_imginfo,
        audinfo = config.current_audinfo,
        mtninfo = config.current_mtninfo
    }
end

excloud.DATA_TYPES = DATA_TYPES
excloud.FIELD_MEANINGS = FIELD_MEANINGS
excloud.MTN_LOG_STATUS = MTN_LOG_STATUS
excloud.MTN_LOG_CACHE_WRITE = exmtn.CACHE_WRITE
excloud.MTN_LOG_ADD_WRITE = exmtn.ADD_WRITE

return excloud
