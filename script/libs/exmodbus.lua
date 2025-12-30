--[[
@module exmodbus
@summary exmodbus 控制Modbus RTU/ASCII/TCP主站/从站通信
@version 1.0
@date    2025.
@author  马梦阳
@usage
本文件的对外接口有 5 个：
1、exmodbus.create(config)：创建 modbus 主站/从站，支持 RTU、ASCII、TCP 三种通信模式
2、modbus:read(config)：主站向从站发起读取请求（仅适用于 RTU、ASCII、TCP 主站模式）
3、modbus:write(config)：主站向从站发起写入请求（仅适用于 RTU、ASCII、TCP 主站模式）
4、modbus:destroy()：销毁 modbus 主站/从站实例对象
5、modbus:on(callback)：从站注册回调接口，用于处理主站发起的请求（仅适用于 RTU、ASCII、TCP 从站模式）
]]
local exmodbus = {}

-- 定义通信模式常量
exmodbus.RTU_MASTER = 0   -- RTU 主站模式
exmodbus.RTU_SLAVE = 1    -- RTU 从站模式
exmodbus.ASCII_MASTER = 2 -- ASCII 主站模式
exmodbus.ASCII_SLAVE = 3  -- ASCII 从站模式
exmodbus.TCP_MASTER = 4   -- TCP 主站模式
exmodbus.TCP_SLAVE = 5    -- TCP 从站模式

-- 定义数据类型常量
exmodbus.COIL_STATUS = 0      -- 线圈状态
exmodbus.INPUT_STATUS = 1     -- 离散输入状态
exmodbus.HOLDING_REGISTER = 4 -- 保持寄存器
exmodbus.INPUT_REGISTER = 3   -- 输入寄存器

-- 定义操作类型常量
exmodbus.READ_COILS = 0x01                       -- 读线圈状态
exmodbus.READ_DISCRETE_INPUTS = 0x02             -- 读离散输入状态
exmodbus.READ_HOLDING_REGISTERS = 0x03           -- 读保持寄存器
exmodbus.READ_INPUT_REGISTERS = 0x04             -- 读输入寄存器
exmodbus.WRITE_SINGLE_COIL = 0x05                -- 写单个线圈状态
exmodbus.WRITE_SINGLE_HOLDING_REGISTER = 0x06    -- 写单个保持寄存器
exmodbus.WRITE_MULTIPLE_HOLDING_REGISTERS = 0x10 -- 写多个保持寄存器
exmodbus.WRITE_MULTIPLE_COILS = 0x0F             -- 写多个线圈状态

-- 定义响应结果常量
exmodbus.STATUS_SUCCESS = 0       -- 收到响应数据且数据有效
exmodbus.STATUS_DATA_INVALID = 1  -- 收到响应数据但数据损坏/校验失败
exmodbus.STATUS_EXCEPTION = 2     -- 收到标准异常响应码
exmodbus.STATUS_TIMEOUT = 3       -- 超时未收到响应
exmodbus.STATUS_PARAM_INVALID = 4 -- 请求参数不正确

-- 异常响应码常量
exmodbus.ILLEGAL_FUNCTION = 0x01           -- 不支持请求的功能码
exmodbus.ILLEGAL_DATA_ADDRESS = 0x02       -- 请求的数据地址无效或超出范围
exmodbus.ILLEGAL_DATA_VALUE = 0x03         -- 请求的数据值无效
exmodbus.SLAVE_DEVICE_FAILURE = 0x04       -- 从站在执行操作时发生内部错误
exmodbus.ACKNOWLEDGE = 0x05                -- 请求已接受，但需要长时间处理
exmodbus.SLAVE_DEVICE_BUSY = 0x06          -- 从站正忙，无法处理请求
exmodbus.NEGATIVE_ACKNOWLEDGE = 0x07       -- 无法执行编程功能
exmodbus.MEMORY_PARITY_ERROR = 0x08        -- 内存奇偶校验错误
exmodbus.GATEWAY_PATH_UNAVAILABLE = 0x0A   -- 网关路径不可用
exmodbus.GATEWAY_TARGET_NO_RESPONSE = 0x0B -- 网关目标设备无响应

-- 全局队列与调度器；
local request_queue = {}
local next_request_id = 1
local scheduler_started = false

-- 生成唯一请求 ID；
local function gen_request_id()
    local id = next_request_id
    next_request_id = next_request_id + 1
    -- 确保请求 ID 在 32 位有符号整数范围内；
    if next_request_id == 0x7FFFFFFF then next_request_id = 1 end
    return id
end

-- 处理队列中的请求；
local function process_request_queue()
    while true do
        if #request_queue > 0 then
            local req = table.remove(request_queue, 1)
            local instance = req.instance
            local config = req.config
            local is_read = req.is_read
            local req_id = req.request_id

            local result
            if is_read then
                result = instance:read_internal(config)
            else
                result = instance:write_internal(config)
            end

            sys.publish("exmodbus/resp/" .. req_id, result)
        else
            sys.waitUntil("start_scheduler")
        end
    end
end

-- 启动调度器；
local function start_scheduler()
    if scheduler_started then return end
    scheduler_started = true
    sys.taskInit(process_request_queue)
end

-- 入队请求并等待响应；（内部使用）
function exmodbus.enqueue_request(instance, config, is_read)
    -- 生成唯一请求 ID；
    local req_id = gen_request_id()

    -- 检查队列是否为空；
    -- 如果为空，先入队，然后发布主题告知调度器开始处理；
    -- 如果不为空，则直接入队，不用告知调度器；
    if #request_queue == 0 then
        -- 入队请求；
        table.insert(request_queue, {
            instance = instance,
            config = config,
            is_read = is_read,
            request_id = req_id
        })

        sys.publish("start_scheduler")
    else
        -- 入队请求；
        table.insert(request_queue, {
            instance = instance,
            config = config,
            is_read = is_read,
            request_id = req_id
        })
    end

    -- 启动调度器；
    start_scheduler()
    local ok, result = sys.waitUntil("exmodbus/resp/" .. req_id)

    return result
end

--[[
创建一个新的实例；
@api exmodbus.create(config)
@param config table 配置参数表，包含以下字段：
    mode number 通信模式，必须是 exmodbus 模块定义的常量（如 exmodbus.RTU_MASTER）
    uart_id number 串口 ID，uart0 写 0，uart1 写 1，以此类推
    baud_rate number 波特率
    data_bits number 数据位
    stop_bits number 停止位
    parity_bits number 校验位
    byte_order number 字节顺序
    rs485_dir_gpio number RS485 方向转换 GPIO 引脚
    rs485_dir_rx_level number RS485 接收方向电平
    adapter number 网卡 ID
    ip_address string 服务器 IP 地址
    port number 服务器端口号
    is_udp boolean 是否使用 UDP 协议
    is_tls boolean 是否使用加密传输
    keep_idle number 连接空闲多长时间后，开始发送第一个 keepalive 探针报文，单位：秒
    keep_interval number 发送第一个探针后，如果没收到 ACK 回复，间隔多久再发送下一个探针，单位：秒
    keep_cnt number 总共发送多少次探针后，如果依然没有回复，则判断连接已断开
    server_cert string TCP 模式下的服务器 CA 证书数据，UDP 模式下的 PSK
    client_cert string TCP 模式下的客户端证书数据，UDP 模式下的 PSK-ID
    client_key string TCP 模式下的客户端私钥加密数据
    client_password string TCP 模式下的客户端私钥口令数据
@return table/nil 成功时返回实例对象，失败时返回 nil
@usage
RTU/ASCII 通信模式：
local config = {
    mode = exmodbus.RTU_MASTER, -- 通信模式：RTU 主站
    uart_id = 1,                -- 串口 ID：uart1
    baud_rate = 115200,         -- 波特率：115200
    data_bits = 8,              -- 数据位：8
    stop_bits = 1,              -- 停止位：1
    parity_bits = uart.None,    -- 校验位：无校验
    byte_order = uart.LSB,      -- 字节顺序：小端序
    rs485_dir_gpio = 23,        -- RS485 方向转换 GPIO 引脚
    rs485_dir_rx_level = 0      -- RS485 接收方向电平：0 为低电平，1 为高电平
}
local rtu_master = exmodbus.create(config)

TCP 通信模式：
local config = {
    mode = exmodbus.TCP_MASTER, -- 通信模式：TCP 主站
    adapter = socket.LWIP_ETH,  -- 网卡 ID：LwIP 协议栈的以太网卡
    ip_address = "192.168.1.100", -- 服务器 IP 地址：192.168.1.100（主站：服务器 IP；从站：本地 IP，从站可以不用填此参数）
    port = 502,                 -- 服务器端口号：502（主站：服务器端口；从站：本地端口）
    is_udp = false,             -- 是否使用 UDP 协议：不使用 UDP 协议，false/nil 表示使用 TCP 协议
    is_tls = false,             -- 是否使用加密传输：不使用加密传输，false/nil 表示不使用加密
    keep_idle = 300,            -- 连接空闲多长时间后，开始发送第一个 keepalive 探针报文：300 秒
    keep_interval = 10,         -- 发送第一个探针后，如果没收到 ACK 回复，间隔多久再发送下一个探针：10 秒
    keep_cnt = 3,               -- 总共发送多少次探针后，如果依然没有回复，则判断连接已断开：3 次
    server_cert = nil,          -- TCP 模式下的服务器 CA 证书数据，UDP 模式下的 PSK：如果客户端不需要验证服务器证书，则设为 nil 或空着
    client_cert = nil,          -- TCP 模式下的客户端证书数据，UDP 模式下的 PSK-ID：如果服务器不需要验证客户端证书，则设为 nil 或空着
    client_key = nil,           -- TCP 模式下的客户端私钥加密数据：如果服务器不需要验证客户端私钥，则设为 nil 或空着
    client_password = nil       -- TCP 模式下的客户端私钥口令数据：如果服务器不需要验证客户端私钥口令，则设为 nil 或空着
}
local tcp_master = exmodbus.create(config)
--]]
function exmodbus.create(config)
    -- 检查配置参数是否有效；
    if not config or type(config) ~= "table" then
        log.error("exmodbus", "配置必须是表格类型")
        return false
    end

    -- 根据通信模式加载对应的模块；
    if config.mode == exmodbus.RTU_MASTER or config.mode == exmodbus.RTU_SLAVE or
        config.mode == exmodbus.ASCII_MASTER or config.mode == exmodbus.ASCII_SLAVE then
        local result, mod = pcall(require, "exmodbus_rtu_ascii")
        if not result then
            log.error("exmodbus", "加载 RTU/ASCII 模块失败")
            return false
        end
        return mod.create(config, exmodbus, gen_request_id)
    elseif config.mode == exmodbus.TCP_MASTER or config.mode == exmodbus.TCP_SLAVE then
        local result, mod = pcall(require, "exmodbus_tcp")
        if not result then
            log.error("exmodbus", "加载 TCP 模块失败")
            return false
        end
        return mod.create(config, exmodbus, gen_request_id)
    else
        log.error("exmodbus", "通信模式不支持")
        return false
    end
end

--[[
主站向从站发送读取请求（仅适用于 RTU、ASCII、TCP 主站模式）
@api modbus:read(config)
@param config table 配置参数表，包含以下字段：
    slave_id number 从站 ID
    reg_type number 寄存器类型
    start_addr number 寄存器起始地址
    reg_count number 寄存器数量
    raw_request string 原始请求帧
    timeout number 超时时间，单位：毫秒
@return table 包含以下字段：
    status number 响应结果状态码，参考 exmodbus 模块定义的常量（如 exmodbus.STATUS_SUCCESS）
    execption_code number 异常码，仅在 status 为 exmodbus.STATUS_EXCEPTION 时有效
    data table 寄存器数值，仅在 status 为 exmodbus.STATUS_SUCCESS 时有效，包含以下字段
        [start_addr] number 寄存器数值，索引为寄存器地址，值为寄存器数值
        ...
    raw_response string 原始响应帧
@usage
用户在传入 config 参数时，有 原始帧 和 字段参数 两种方式
1. 原始帧方式
local read_config = {
    raw_request = "010300000002C40B", -- 原始请求帧：01 03 00 00 00 02 C4 0B（读取保持寄存器 0x0000 开始的 2 个寄存器）
    timeout = 1000                    -- 超时时间：1000 毫秒
}
local result = modbus:read(read_config)
if result.status == exmodbus.STATUS_SUCCESS then
    log.info("exmodbus_test", "读取成功，原始响应帧: ", table.concat(result.raw_response, ", "))
elseif result.status == exmodbus.STATUS_TIMEOUT then
    log.error("exmodbus_test", "读取请求超时")
else
    log.error("exmodbus_test", "读取失败")
end

2. 字段参数方式
local read_config = {
    slave_id = 1,                         -- 从站 ID：1
    reg_type = exmodbus.HOLDING_REGISTER, -- 寄存器类型：保持寄存器
    start_addr = 0x0000,                  -- 寄存器起始地址：0
    reg_count = 0x0002,                   -- 寄存器数量：2
    timeout = 1000                        -- 超时时间：1000 毫秒
}

local result = modbus:read(read_config)
-- 根据返回状态处理结果
if result.status == exmodbus.STATUS_SUCCESS then
    -- 数据解析：
    log.info("exmodbus_test", "成功读取到从站 1 保持寄存器 0-2 的值，寄存器 0 数值：", result.data[result.start_addr],
        "，寄存器 1 数值：", result.data[result.start_addr + 1])
elseif result.status == exmodbus.STATUS_DATA_INVALID then
    log.info("exmodbus_test", "收到从站 1 的响应数据但数据损坏/校验失败")
elseif result.status == exmodbus.STATUS_EXCEPTION then
    log.info("exmodbus_test", "收到从站 1 的 modbus 标准异常响应，异常码为", result.execption_code)
elseif result.status == exmodbus.STATUS_TIMEOUT then
    log.info("exmodbus_test", "未收到从站 1 的响应（超时）")
end
--]]
-- 该接口在各个子文件中，此处仅用作注释
-- function modbus:read(config) end


--[[
主站向从站发送写入请求（仅适用于 RTU、ASCII、TCP 主站模式）
@api modbus:write(config)
@param config table 配置参数表，包含以下字段：
    slave_id number 从站 ID
    reg_type number 寄存器类型
    start_addr number 寄存器起始地址
    reg_count number 寄存器数量
    data table 寄存器数值，包含以下字段：
        [start_addr] number 寄存器数值，索引为寄存器地址，值为寄存器数值
        ...
    force_multiple boolean 是否强制使用写多个功能码进行写入单个寄存器操作
    raw_request string 原始请求帧
    timeout number 超时时间，单位：毫秒
@return table 包含以下字段：
    status number 响应结果状态码，参考 exmodbus 模块定义的常量（如 exmodbus.STATUS_SUCCESS）
    execption_code number 异常码，仅在 status 为 exmodbus.STATUS_EXCEPTION 时有效
    raw_response string 原始响应帧
@usage
用户在传入 config 参数时，有 原始帧 和 字段参数 两种方式
1. 原始帧方式
local write_config = {
    raw_request = "011000000002007B01592471", -- 原始请求帧：01 10 00 00 00 02 00 7B 01 59 24 71（写入保持寄存器 0x0000 开始的 2 个寄存器，值为 0x007B 和 0x0159）
    timeout = 1000                            -- 超时时间：1000 毫秒
}
local result = modbus:write(write_config)
if result.status == exmodbus.STATUS_SUCCESS then
    log.info("exmodbus_test", "写入成功，原始响应帧: ", table.concat(result.raw_response, ", "))
elseif result.status == exmodbus.STATUS_TIMEOUT then
    log.error("exmodbus_test", "写入请求超时")
else
    log.error("exmodbus_test", "写入失败")
end

2. 字段参数方式
local write_config = {
    slave_id = 1,                         -- 从站 ID：1
    reg_type = exmodbus.HOLDING_REGISTER, -- 寄存器类型：保持寄存器
    start_addr = 0x0000,                  -- 寄存器起始地址：0
    reg_count = 0x0002,                   -- 寄存器数量：2
    data = {
        [0x0000] = 0x007B,                -- 寄存器 0 数值：0x007B
        [0x0001] = 0x0159,                -- 寄存器 1 数值：0x0159
    },
    timeout = 1000                        -- 超时时间：1000 毫秒
}

local result = modbus:write(write_config)
-- 根据返回状态处理结果
if result.status == exmodbus.STATUS_SUCCESS then
    log.info("exmodbus_test", "成功写入从站 1 保持寄存器 0-2 的值")
elseif result.status == exmodbus.STATUS_DATA_INVALID then
    log.info("exmodbus_test", "收到从站 1 的响应数据但数据损坏/校验失败")
elseif result.status == exmodbus.STATUS_EXCEPTION then
    log.info("exmodbus_test", "收到从站 1 的 modbus 标准异常响应，异常码为", result.execption_code)
elseif result.status == exmodbus.STATUS_TIMEOUT then
    log.info("exmodbus_test", "未收到从站 1 的响应（超时）")
end
--]]
-- 该接口在各个子文件中，此处仅用作注释
-- function modbus:write(config) end


--[[
销毁 modbus 主站/从站实例对象
@api modbus:destroy()
@return nil
@usage
modbus:destroy()
--]]
-- 该接口在各个子文件中，此处仅用作注释
-- function modbus:destroy() end


--[[
从站注册回调接口，用于处理主站发起的请求（仅适用于 RTU、ASCII、TCP 从站模式）
@api modbus:on(callback)
@param callback function 回调函数，格式为：
    function callback(request)
        -- 用户代码
    end
    该回调函数接收 requset 一个参数，该参数为 table 类型，包含以下字段：
        slave_id number 从站 ID
        func_code number 功能码
        reg_type number 寄存器类型
        start_addr number 寄存器起始地址
        reg_count number 寄存器数量
        data table 寄存器数值，包含以下字段：
            [start_addr] number 寄存器数值，索引为寄存器地址，值为寄存器数值
            ...
@return nil
@usage
function callback(request)
    -- 用户处理代码
end
--]]
-- 该接口在各个子文件中，此处仅用作注释
-- modbus:on(callback)

return exmodbus
