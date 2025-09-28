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

-- 示例：
-- 导入excloud库
local excloud = require("excloud")

-- 注册回调函数
excloud.on(function(event, data)
    log.info("用户回调函数", event, json.encode(data))

    if event == "connect_result" then
        if data.success then
            log.info("连接成功")
        else
            log.info("连接失败: " .. (data.error or "未知错误"))
        end
    elseif event == "auth_result" then
        if data.success then
            log.info("认证成功")
        else
            log.info("认证失败: " .. data.message)
        end
    elseif event == "message" then
        log.info("收到消息, 流水号: " .. data.header.sequence_num)

        -- 处理服务器下发的消息
        for _, tlv in ipairs(data.tlvs) do
            if tlv.field == excloud.FIELD_MEANINGS.CONTROL_COMMAND then
                log.info("收到控制命令: " .. tostring(tlv.value))

                -- 处理控制命令并发送响应
                local response_ok, err_msg = excloud.send({
                    {
                        field_meaning = excloud.FIELD_MEANINGS.CONTROL_RESPONSE,
                        data_type = excloud.DATA_TYPES.ASCII,
                        value = "命令执行成功"
                    }
                }, false)

                if not response_ok then
                    log.info("发送控制响应失败: " .. err_msg)
                end
            end
        end
    elseif event == "disconnect" then
        log.warn("与服务器断开连接")
    elseif event == "reconnect_failed" then
        log.info("重连失败，已尝试 " .. data.count .. " 次")
    elseif event == "send_result" then
        if data.success then
            log.info("发送成功，流水号: " .. data.sequence_num)
        else
            log.info("发送失败: " .. data.error_msg)
        end
    end
end)


sys.taskInit(function()
    -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
    while not socket.adapter(socket.dft()) do
        log.warn("tcp_client_main_task_func", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end
    sys.wait(1000)
    -- 配置excloud参数
    -- local ok, err_msg = excloud.setup({
    --     -- device_id = "862419074073247",   -- 设备ID (IMEI前14位)
    --     device_type = 1,                 -- 设备类型: 4G
    --     host = "112.125.89.8",         -- 服务器地址
    --     port = 33316,                     -- 服务器端口
    --     auth_key = "VmhtOb81EgZau6YyuuZJzwF6oUNGCbXi", -- 鉴权密钥
    --     transport = "tcp",               -- 使用TCP传输
    --     auto_reconnect = true,           -- 自动重连
    --     reconnect_interval = 10,         -- 重连间隔(秒)
    --     max_reconnect = 5,               -- 最大重连次数
    --     timeout = 30,                    -- 超时时间(秒)
    -- })

    if not ok then
        log.info("初始化失败: " .. err_msg)
        return
    end
    log.info("excloud初始化成功")
    -- 开启excloud服务
    local ok, err_msg = excloud.open()
    if not ok then
        log.info("开启excloud服务失败: " .. err_msg)
        return
    end

    log.info("excloud服务已开启")
    -- 在主循环中定期上报数据
    while true do
        -- 每30秒上报一次数据
        sys.wait(30000)
        local ok, err_msg = excloud.send({
            {
                field_meaning = excloud.FIELD_MEANINGS.LOCATION_METHOD,
                data_type = excloud.DATA_TYPES.INTEGER,
                value = 22     -- 随机温度值
            },
            {
                field_meaning = excloud.FIELD_MEANINGS.HUMIDITY,
                data_type = excloud.DATA_TYPES.FLOAT,
                value = 33.2543     -- 随机湿度值
            }
        }, false)                   -- 不需要服务器回复

        if not ok then
            log.info("发送数据失败: " .. err_msg)
        else
            log.info("数据发送成功")
        end
    end
end)

]]
local excloud = {}

local config = {
    device_type = 1,           -- 默认设备类型: 4G
    device_id = "",            -- 设备ID
    protocol_version = 1,      -- 协议版本
    transport = "tcp",         -- 传输协议: tcp/mqtt
    host = "cloud.luatos.com", -- 服务器地址
    port = 8900,               -- 服务器端口
    auth_key = nil,            -- 用户鉴权密钥
    keepalive = 300,           -- mqtt心跳
    auto_reconnect = true,     -- 是否自动重连
    reconnect_interval = 10,   -- 重连间隔(秒)
    max_reconnect = 3,         -- 最大重连次数
    timeout = 30,              -- 连接超时时间(秒)
    qos = 0,                   -- MQTT QoS等级
    -- retain = false,            -- MQTT retain标志
    clean_session = true,      -- MQTT clean session标志
    ssl = false,               -- 是否使用SSL
    username = nil,            -- MQTT用户名
    password = nil,            -- MQTT密码
    udp_auth_key = nil,        -- UDP鉴权密钥

    -- 新增socket配置参数
    local_port = nil,      -- 本地端口号，nil表示自动分配
    keep_idle = nil,       -- TCP keepalive idle时间(秒)
    keep_interval = nil,   -- TCP keepalive 探测间隔(秒)
    keep_cnt = nil,        -- TCP keepalive 探测次数
    server_cert = nil,     -- 服务器CA证书数据
    client_cert = nil,     -- 客户端证书数据
    client_key = nil,      -- 客户端私钥数据
    client_password = nil, -- 客户端私钥口令

    -- MQTT扩展参数
    -- mqtt_rx_size = 32 * 1024, -- MQTT接收缓冲区大小，默认32K
    -- mqtt_conn_timeout = 30, -- MQTT连接超时时间
    -- mqtt_ipv6 = false, -- 是否使用IPv6连接
}

local callback_func = nil         -- 回调函数
local is_open = false             -- 服务是否开启
local is_connected = false        -- 是否已连接
local is_authenticated = false    -- 是否已鉴权
local sequence_num = 0            -- 流水号
local connection = nil            -- 连接对象
local device_id_binary = nil      -- 二进制格式的设备ID
local reconnect_timer = nil       -- 重连定时器
local reconnect_count = 0         -- 重连次数
local pending_messages = {}       -- 待发送消息队列
local rxbuff = nil                -- 接收缓冲区
local connect_timeout_timer = nil -- 连接超时定时器

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
    AUTH_REQUEST       = 16, -- 鉴权请求
    AUTH_RESPONSE      = 17, -- 鉴权回复
    REPORT_RESPONSE    = 18, -- 上报回应
    CONTROL_COMMAND    = 19, -- 控制命令
    CONTROL_RESPONSE   = 20, -- 控制回应
    IRTU_DOWN          = 21, -- iRTU下行命令
    IRTU_UP            = 22, -- iRTU上行回复

    -- 传感类 (256-511)
    TEMPERATURE        = 256, -- 温度
    HUMIDITY           = 257, -- 湿度
    PARTICULATE        = 258, -- 颗粒数
    ACIDITY            = 259, -- 酸度
    ALKALINITY         = 260, -- 碱度
    ALTITUDE           = 261, -- 海拔
    WATER_LEVEL        = 262, -- 水位
    ENV_TEMPERATURE    = 263, -- CPU温度/环境温度
    POWER_METERING     = 264, -- 电量计量

    -- 资产管理类 (512-767)
    GNSS_LONGITUDE     = 512, -- GNSS经度
    GNSS_LATITUDE      = 513, -- GNSS纬度
    SPEED              = 514, -- 行驶速度
    GNSS_CN            = 515, -- 最强的4颗GNSS卫星的CN
    SATELLITES_TOTAL   = 516, -- 搜到的所有卫星数
    SATELLITES_VISIBLE = 517, -- 可见卫星数
    HEADING            = 518, -- 航向角
    LOCATION_METHOD    = 519, -- 基站定位/GNSS定位标识
    GNSS_INFO          = 520, -- GNSS芯片型号和固件版本号
    DIRECTION          = 521, -- 方向

    -- 设备参数类 (768-1023)
    HEIGHT             = 768, -- 高度
    WIDTH              = 769, -- 宽度
    ROTATION_SPEED     = 770, -- 转速
    BATTERY_LEVEL      = 771, -- 电量(mV)
    SERVING_CELL       = 772, -- 驻留频段
    CELL_INFO          = 773, -- 驻留小区和邻区
    COMPONENT_MODEL    = 774, -- 元器件型号
    GPIO_LEVEL         = 775, -- GPIO高低电平
    BOOT_REASON        = 776, -- 开机原因
    BOOT_COUNT         = 777, -- 开机次数
    SLEEP_MODE         = 778, -- 休眠模式
    WAKE_INTERVAL      = 779, -- 定时唤醒间隔
    NETWORK_IP_TYPE    = 780, -- 设备入网的IP类型
    NETWORK_TYPE       = 781, -- 当前联网方式
    SIGNAL_STRENGTH_4G = 782, --4G信号强度
    SIM_ICCID          = 783, -- SIM卡ICCID

    -- 软件数据类 (1024-1279)
    LUA_CORE_ERROR     = 1024, -- Lua核心库错误上报
    LUA_EXT_ERROR      = 1025, -- Lua扩展卡错误上报
    LUA_APP_ERROR      = 1026, -- Lua业务错误上报
    FIRMWARE_VERSION   = 1027, -- 固件版本号
    SMS_FORWARD        = 1028, -- SMS转发
    CALL_FORWARD       = 1029, -- 来电转发

    -- 设备无关数据类 (1280-1535)
    TIMESTAMP          = 1280, -- 时间
    RANDOM_DATA        = 1281  -- 无意义数据
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
    -- log.info("from_big_endian", value)
    return value
end

-- 将设备ID进行编码
function packDeviceInfo(deviceType, deviceId)
    -- 验证设备类型
    if deviceType ~= 1 and deviceType ~= 2 then
        log.info("设备类型错误: 4G设备应为1, WIFI设备应为2")
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
    else
        log.info("未知设备类型 ")
        return deviceId
    end

    -- 返回8字节的二进制数据
    return table.concat(result)
end

-- -- 编码数据值
local function encode_value(data_type, value)
    -- 添加参数类型检查
    if  data_type == nil or value == nil then
        log.info("Data type or value is nil")
        return ""
    end
    if data_type == DATA_TYPES.INTEGER then
        -- 验证value是否为数字
        if type(value) ~= "number" then
            log.info("Integer value must be a number")
            return ""
        end
        return to_big_endian(math.floor(value), 4)
    elseif data_type == DATA_TYPES.FLOAT then
        -- 验证value是否为数字
        if type(value) ~= "number" then
            log.info("Float value must be a number")
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
        log.info("Unsupported data type: " .. tostring(data_type))
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
        log.info("Unsupported data type: " .. data_type)
        return nil
    end
end

-- 构建消息头
-- @param need_reply boolean 是否需要服务器回复
-- @param has_auth_key boolean 是否携带鉴权key
-- @param data_length number 数据长度
local function build_header(need_reply, is_udp_transport, data_length)
    sequence_num = (sequence_num + 1) % 65536

    -- 消息标识字段
    local flags = config.protocol_version -- bit0-3: 协议版本号
    if need_reply then
        flags = flags + 16                -- bit4: 是否需要回复
    end
    if is_udp_transport then
        flags = flags + 32 -- bit5: 是否是UDP承载
    end
    log.info("构建消息头", device_id_binary, to_big_endian(sequence_num, 2), to_big_endian(data_length, 2),
        to_big_endian(flags, 4))
    return device_id_binary ..
        to_big_endian(sequence_num, 2) ..
        to_big_endian(data_length, 2) ..
        to_big_endian(flags, 4)
end

-- 构建TLV字段
local function build_tlv(field_meaning, data_type, value)
    if field_meaning == nil or data_type == nil or value == nil then
        log.info("构建tlv参数不能为空")
        return false
    end
    local value_encoded = encode_value(data_type, value)
    if value_encoded == nil then
        log.info("构建tlv打包数据时长度为0")
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
        log.info("消息头解析失败", "Header too short")
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
    -- log.info("消息头解析结果",
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
    -- log.info("消息体解析结果", field_meaning, data_type, decoded_value)
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
    --  auth_data = config.auth_key .. "-" .. config.device_id .. "-" .. "323B131815B0DFC9"
    --设备实测时打开
    if config.device_type == 1 then
        auth_data = config.auth_key .. "-" .. mobile.imei() .. "-" .. mobile.muid()
    elseif config.device_type == 2 then
        auth_data = config.auth_key .. "-" .. wlan.getMac(nil, true) .. "-" .. mobile.muid():toHex()
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
    -- log.info("send auth request", message,message[1].value,message[1].data_type,message[1].field_meaning)
    return excloud.send(message, true, true) -- 鉴权消息需要设置 is_auth_msg 为 true
end

-- 处理认证响应AAA
local function handle_auth_response(tlvs)
    for _, tlv in ipairs(tlvs) do
        if tlv.field_meaning == FIELD_MEANINGS.AUTH_RESPONSE then
            local success = (tlv.value == "OK" or tlv.value == "SUCCESS")
            is_authenticated = success
            if callback_func then
                callback_func("auth_result", {
                    success = success,
                    message = tlv.value
                })
            end
            -- 认证成功，发送待处理消息
            if success then
                for _, msg in ipairs(pending_messages) do
                    excloud.send(msg.data, msg.need_reply)
                end
                pending_messages = {}
            end

            return success
        end
    end

    return false
end

-- 接收消息解析处理
local function parse_data(data)
    local message, err = parse_message(data)
    if not message then
        log.info("Failed to parse message: " .. err)
        return
    end

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
-- 重连  AAA
local function schedule_reconnect()
    if reconnect_count >= config.max_reconnect then
        log.info("到达最大重连次数 " .. reconnect_count)
        if callback_func then
            callback_func("reconnect_failed", { count = reconnect_count })
        end
        return
    end

    reconnect_count = reconnect_count + 1
    log.info("重连次数 " .. reconnect_count)

    -- 使用定时器安排重连
    reconnect_timer = sys.timerStart(function()
        log.info("等待重连")
        excloud.open()
    end, config.reconnect_interval * 1000)
end

-- TCP socket事件回调函数
local function tcp_socket_callback(netc, event, param)
    log.info("socket cb", netc, event, param)
    -- 取消连接超时定时器
    if connect_timeout_timer then
        sys.timerStop(connect_timeout_timer)
        connect_timeout_timer = nil
    end

    if param ~= 0 then
        log.info("socket", "连接断开")
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
            is_open = false
            schedule_reconnect()
        end
        return
    end
    if event == socket.LINK then
        -- 网络连接成功
        log.info("socket", "网络连接成功")
    elseif event == socket.ON_LINE then
        -- TCP连接成功
        log.info("socket", "TCP连接成功")
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
            log.info("socket", "收到数据", #data, "字节", data:toHex())
            -- 处理接收到的数据
            parse_data(data)
        end
        -- 清空缓冲区
        rxbuff:del()
    elseif event == socket.TX_OK then
        socket.wait(netc)
        log.info("socket", "发送完成")
    elseif event == socket.CLOSED then
        -- 连接错误或关闭
        log.info("socket", "主动断开链接")
    end
end

-- mqtt client的事件回调函数
local function mqtt_client_event_cbfunc(connected, event, data, payload, metas)
    log.info("mqtt_client_event_cbfunc", connected, event, data, payload, json.encode(metas))
    -- 取消连接超时定时器
    if connect_timeout_timer then
        sys.timerStop(connect_timeout_timer)
        connect_timeout_timer = nil
    end

    -- mqtt连接成功
    if event == "conack" then
        is_connected = true
        log.info("MQTT connected")
        -- 重置重连计数，如果是重连的话，连接上服务器给重连计数重置为0
        reconnect_count = 0
        -- 订阅主题
        local auth_topic = "/AirCloud/down/" .. config.device_id .. "/auth"
        local all_topic = "/AirCloud/down/" .. config.device_id .. "/all"
        log.info("mqtt_client_event_cbfunc", "订阅主题", auth_topic, all_topic)
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
        -- 对接收到的publish数据处理
        parse_data(payload)


        -- 发送成功publish数据
        -- data：number类型，表示message id
    elseif event == "sent" then
        -- 服务器断开mqtt连接
    elseif event == "disconnect" then
        is_connected = false
        is_authenticated = false
        connection:disconnect()
        log.info("MQTT disconnected")

        if callback_func then
            callback_func("disconnect", {})
        end

        -- 尝试重连
        if config.auto_reconnect and is_open then
            is_open = false
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
        connection:disconnect()
        local error_msg = "Unknown MQTT error"

        if data == "connect" then
            error_msg = "TCP connection failed"
        elseif data == "tx" then
            error_msg = "Data transmission failed"
        elseif data == "conack" then
            error_msg = "MQTT authentication failed with code: " .. tostring(payload)
        end

        log.info("MQTT error: " .. error_msg)

        if callback_func then
            callback_func("disconnect", { error = error_msg })
        end

        -- 尝试重连
        if config.auto_reconnect and is_open then
            is_open = false
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
    if config.device_type == 1 then
        config.device_id = mobile.imei()
    elseif config.device_type == 2 then
        config.device_id = wlan.getMac(nil, true)
        --以太网设备
    elseif config.device_type == 4 then
        config.device_id = netdrv.mac(socket.LWIP_ETH)
    else
        log.info("未知设备类型", config.device_type)
        config.device_id = "unknown"
    end

    -- 打包设备id
    device_id_binary = packDeviceInfo(config.device_type, config.device_id)

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
    -- 检查是否已打开
    if is_open then
        return false, "excloud is already open"
    end

    --判断是否初始化
    if not device_id_binary then
        return false, "excloud 没有初始化，请先调用setup"
    end

    -- 根据传输协议创建连接
    if config.transport == "tcp" then
        -- 创建接收缓冲区
        rxbuff = zbuff.create(2048)
        -- 创建TCP连接
        log.info("创建TCP连接")
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
                    is_open = false
                    schedule_reconnect()
                end
            end
        end, config.timeout * 1000)

        -- 连接到服务器
        local ok, result = socket.connect(connection, config.host, config.port, config.mqtt_ipv6)
        log.info("TCP连接结果", ok, result)
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
        -- 准备MQTT SSL配置
        local ssl_config = nil
        if config.ssl then
            if type(config.ssl) == "table" then
                ssl_config = config.ssl
            else
                ssl_config = true -- 简单SSL启用
            end
        end
        local mqtt_opts = nil
        -- 准备MQTT扩展参数
        -- local mqtt_opts = {
        --     rxSize = config.mqtt_rx_size,
        --     conn_timeout = config.mqtt_conn_timeout,
        --     ipv6 = config.mqtt_ipv6
        -- }

        -- 创建MQTT客户端
        connection = mqtt.create(nil, config.host, config.port, ssl_config, mqtt_opts)
        if not connection then
            return false, "Failed to create MQTT client"
        end

        -- 设置认证信息
        connection:auth(config.device_id, config.username, config.password, config.clean_session)

        -- 注册事件回调
        connection:on(mqtt_client_event_cbfunc)
        -- 设置保持连接间隔
        connection:keepalive(config.keepalive)

        -- 设置连接超时定时器
        connect_timeout_timer = sys.timerStart(function()
            if not is_connected then
                log.error("MQTT connection timeout")
                if connection then
                    connection:disconnect()
                end

                if callback_func then
                    callback_func("connect_result", { success = false, error = "Connection timeout" })
                end

                -- 尝试重连
                if config.auto_reconnect and is_open then
                    is_open = false
                    schedule_reconnect()
                end
            end
        end, config.timeout * 1000)

        -- 连接到服务器
        local ok = connection:connect()
        if not ok then
            --连接失败，释放资源
            connection:disconnect()
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
    reconnect_count = 0
    log.info("excloud service started")

    return true
end

-- 发送数据
-- 发送消息到云端
-- @param data table 待发送的数据，每个元素是一个包含 field_meaning、data_type 和 value 的表
-- @param need_reply boolean 是否需要服务器回复，默认为 false
-- @param is_auth_msg boolean 是否是鉴权消息，默认为 false
function excloud.send(data, need_reply, is_auth_msg)
    -- 检查参数是否为table
    if type(data) ~= "table" then
        return false, "data must be table"
    end
    if need_reply == nil then
        return false, "need_reply cannot be nil"
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
    local success
    -- 构建消息体
    local message_body = ""
    for _, item in ipairs(data) do
        log.info("发送数据333", item.field_meaning, item.data_type, item.value, message_body)
        local success, tlv = build_tlv(item.field_meaning, item.data_type, item.value)
        if not success then
            return false, "excloud.send data is failed"
        end
        message_body = message_body .. tlv
    end

    -- 检查消息长度
    local udp_auth_key = config.udp_auth_key and true or false
    local total_length = #message_body + (udp_auth_key and 64 or 0)

    log.info("tlv发送数据长度4", total_length)

    -- 构建消息头
    local is_udp_transport = (config.transport == "udp")
    local header = build_header(need_reply or false, is_udp_transport, total_length)

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

    log.info("发送消息长度", #header, #message_body, #full_message, full_message:toHex())

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
        if is_auth_msg then
            topic = "/AirCloud/up/" .. config.device_id .. "/auth"
        else
            topic = "/AirCloud/up/" .. config.device_id .. "/all"
        end
        log.info("发布主题", topic, #full_message, full_message:toHex())
        success = connection:publish(topic, full_message, config.qos, config.retain)
    end

    -- 通过回调返回发送结果
    if callback_func then
        callback_func("send_result", {
            success = success,
            error_msg = success and "Send successful" or err_msg,
            sequence_num = current_sequence
        })
    end

    if success then
        log.info("数据发送成功", #full_message, "字节")
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

    -- 取消重连定时器
    if reconnect_timer then
        sys.timerStop(reconnect_timer)
        reconnect_timer = nil
    end

    -- 关闭连接
    if connection then
        if config.transport == "tcp" then
            socket.close(connection)
            socket.release(connection)
        elseif config.transport == "mqtt" then
            connection:disconnect()
        end
        connection = nil
    end

    -- 重置状态
    is_open = false
    is_connected = false
    is_authenticated = false
    pending_messages = {}
    rxbuff = nil

    log.info("excloud service stopped")
    return true
end

-- 获取当前状态
function excloud.status()
    return {
        is_open = is_open,
        is_connected = is_connected,
        sequence_num = sequence_num,
        reconnect_count = reconnect_count,
        pending_messages = #pending_messages,
    }
end

-- 导出常量
excloud.DATA_TYPES = DATA_TYPES
excloud.FIELD_MEANINGS = FIELD_MEANINGS

return excloud
