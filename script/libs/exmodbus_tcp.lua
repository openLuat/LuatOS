-- 定义类结构；
local modbus = {}                            -- 定义 modbus 实例的元表；
modbus.__index = modbus                      -- 定义 modbus 实例的索引元方法，用于访问实例的属性；
modbus.__metatable = "instance is protected" -- 定义 modbus 实例的元表，防止外部修改；

-- 模块级变量：依赖注入的引用；
local exmodbus_ref -- 主模块引用，用于访问enqueue_request等核心功能；
local gen_id_func  -- ID生成函数引用，用于生成唯一请求ID；

-- Modbus TCP 协议头长度
local MODBUS_TCP_HEADER_LEN = 7

local libnet = require "libnet"

-- 创建 modbus 实例的构造函数；
function modbus:new(config, TASK_NAME)
    local obj = {
        mode = config.mode,                       -- 通信模式
        adapter = config.adapter,                 -- 网络适配器
        ip_address = config.ip_address,           -- IP 地址
        port = config.port,                       -- 端口号
        is_udp = config.is_udp,                   -- 是否使用 UDP 协议
        is_tls = config.is_tls,                   -- 是否使用 TLS 加密
        keep_idle = config.keep_idle,             -- 连接空闲多长时间后，开始发送第一个 keepalive 探针报文（秒）
        keep_interval = config.keep_interval,     -- 发送第一个探针后，如果没收到 ACK 回复，间隔多久再发送下一个探针（秒）
        keep_cnt = config.keep_cnt,               -- 总共发送多少次探针后，如果依然没有回复，则判定连接已断开
        server_cert = config.server_cert,         -- TCP模式下的服务器ca证书数据，UDP模式下的PSK
        client_cert = config.client_cert,         -- TCP模式下的客户端证书数据，UDP模式下的PSK-ID
        client_key = config.client_key,           -- TCP模式下的客户端私钥加密数据
        client_password = config.client_password, -- TCP模式下的客户端私钥口令数据
    }

    -- 连接状态
    obj.is_connected = false
    -- 从站请求处理回调函数；
    obj.slaveHandler = nil
    -- 任务名称
    obj.TASK_NAME = TASK_NAME
    -- 接收数据缓冲区
    obj.recv_buff = nil
    -- 发送请求队列
    obj.send_queue = {}
    -- 当前等待响应的事务ID
    obj.pending_transaction = nil

    -- 设置原表；
    setmetatable(obj, modbus)
    -- 返回实例；
    return obj
end

-- 构建 Modbus TCP 请求帧（主站使用）
local function build_tcp_frame(request_type, config)
    -- 参数验证
    if not config or type(config) ~= "table" then
        log.error("exmodbus", "配置必须是表格类型")
        return false
    end

    -- 验证必要参数
    if not config.slave_id then
        log.error("exmodbus", "缺少必要参数: slave_id")
        return false
    end

    if not config.reg_type then
        log.error("exmodbus", "缺少必要参数: reg_type")
        return false
    end

    if not config.start_addr then
        log.error("exmodbus", "缺少必要参数: start_addr")
        return false
    end

    if not config.reg_count then
        log.error("exmodbus", "缺少必要参数: reg_count")
        return false
    end

    if request_type == "write" then
        if not config.data then
            log.error("exmodbus", "缺少写入请求必要参数: data")
            return false
        end
    end

    -- 参数范围验证
    if type(config.slave_id) ~= "number" or config.slave_id < 1 or config.slave_id > 247 then
        log.error("exmodbus", "从站地址必须在 1-247 范围内")
        return false
    end

    if type(config.start_addr) ~= "number" or config.start_addr < 0 or config.start_addr > 65535 then
        log.error("exmodbus", "起始地址必须在 0-65535 范围内")
        return false
    end

    if config.reg_type ~= exmodbus_ref.COIL_STATUS and config.reg_type ~= exmodbus_ref.INPUT_STATUS and
        config.reg_type ~= exmodbus_ref.HOLDING_REGISTER and config.reg_type ~= exmodbus_ref.INPUT_REGISTER then
        log.error("exmodbus", "无效的寄存器类型: " .. tostring(config.reg_type))
        return false
    end

    -- 根据操作类型和寄存器类型确定功能码
    local func_code
    local data = ""

    if request_type == "read" then
        -- 读请求
        if config.reg_type == exmodbus_ref.COIL_STATUS then
            func_code = exmodbus_ref.READ_COILS
            if config.reg_count < 1 or config.reg_count > 2000 then
                log.error("exmodbus", "线圈读取数量超出范围: " .. config.reg_count .. " (范围: 1-2000)")
                return false
            end
        elseif config.reg_type == exmodbus_ref.INPUT_STATUS then
            func_code = exmodbus_ref.READ_DISCRETE_INPUTS
            if config.reg_count < 1 or config.reg_count > 2000 then
                log.error("exmodbus", "离散输入读取数量超出范围: " .. config.reg_count .. " (范围: 1-2000)")
                return false
            end
        elseif config.reg_type == exmodbus_ref.HOLDING_REGISTER then
            func_code = exmodbus_ref.READ_HOLDING_REGISTERS
            if config.reg_count < 1 or config.reg_count > 125 then
                log.error("exmodbus", "保持寄存器读取数量超出范围: " .. config.reg_count .. " (范围: 1-125)")
                return false
            end
        elseif config.reg_type == exmodbus_ref.INPUT_REGISTER then
            func_code = exmodbus_ref.READ_INPUT_REGISTERS
            if config.reg_count < 1 or config.reg_count > 125 then
                log.error("exmodbus", "输入寄存器读取数量超出范围: " .. config.reg_count .. " (范围: 1-125)")
                return false
            end
        end

        data = string.char(config.slave_id, func_code) ..
            string.char((config.start_addr >> 8) & 0xFF, config.start_addr & 0xFF) ..
            string.char((config.reg_count >> 8) & 0xFF, config.reg_count & 0xFF)
    else
        -- 写请求
        -- 校验每一个地址是否有数据，且数据是否为数字类型
        for i = 0, config.reg_count - 1 do
            local addr = config.start_addr + i
            if config.data[addr] == nil then
                log.error("exmodbus", "缺少寄存器数据", "address:", addr)
                return false
            end
            if type(config.data[addr]) ~= "number" then
                log.error("exmodbus", "寄存器数据必须是数字类型", "address:", addr)
                return false
            end
        end

        -- 判断是否强制使用写多个功能码
        local use_multiple = config.force_multiple

        if config.reg_type == exmodbus_ref.COIL_STATUS then
            if config.reg_count == 1 then
                if not use_multiple then
                    func_code = exmodbus_ref.WRITE_SINGLE_COIL
                else
                    func_code = exmodbus_ref.WRITE_MULTIPLE_COILS
                end
            else
                func_code = exmodbus_ref.WRITE_MULTIPLE_COILS
                if config.reg_count < 1 or config.reg_count > 1968 then
                    log.error("exmodbus", "线圈写入数量超出范围: " .. config.reg_count .. " (范围: 1-1968)")
                    return false
                end
            end
        elseif config.reg_type == exmodbus_ref.HOLDING_REGISTER then
            if config.reg_count == 1 then
                if not use_multiple then
                    func_code = exmodbus_ref.WRITE_SINGLE_HOLDING_REGISTER
                else
                    func_code = exmodbus_ref.WRITE_MULTIPLE_HOLDING_REGISTERS
                end
            else
                func_code = exmodbus_ref.WRITE_MULTIPLE_HOLDING_REGISTERS
                if config.reg_count < 1 or config.reg_count > 123 then
                    log.error("exmodbus", "寄存器写入数量超出范围: " .. config.reg_count .. " (范围: 1-123)")
                    return false
                end
            end
        else
            log.error("exmodbus", "不支持的寄存器类型")
            return nil
        end

        -- 构建写数据
        if func_code == exmodbus_ref.WRITE_SINGLE_COIL then
            -- 写入单个线圈，值必须是 0xFF00 (ON) 或 0x0000 (OFF)
            local value = config.data[config.start_addr] ~= 0 and 0xFF00 or 0x0000
            data = string.char(config.slave_id, func_code) ..
                string.char((config.start_addr >> 8) & 0xFF, config.start_addr & 0xFF) ..
                string.char((value >> 8) & 0xFF, value & 0xFF)

        elseif func_code == exmodbus_ref.WRITE_SINGLE_HOLDING_REGISTER then
            -- 写入单个保持寄存器
            local value = config.data[config.start_addr]
            if value < 0 or value > 65535 or value ~= math.floor(value) then
                log.error("exmodbus", "寄存器值必须是 0~65535 范围内的整数，实际值: ", value)
                return false
            end
            data = string.char(config.slave_id, func_code) ..
                string.char((config.start_addr >> 8) & 0xFF, config.start_addr & 0xFF) ..
                string.char((value >> 8) & 0xFF, value & 0xFF)

        elseif func_code == exmodbus_ref.WRITE_MULTIPLE_COILS then
            -- 写入多个线圈
            local byte_count = math.ceil(config.reg_count / 8)
            local values_bytes = ""

            -- 构建线圈数据（字节序为大端序）
            for i = 0, byte_count - 1 do
                local byte_value = 0
                -- 遍历当前字节的 8 个位
                for j = 0, 7 do
                    local bit_index = i * 8 + j
                    -- 检查当前比特是否在有效范围内
                    if bit_index < config.reg_count then
                        local addr = config.start_addr + bit_index
                        local bit_val = config.data[addr]
                        if bit_val ~= nil and bit_val ~= 0 then
                            byte_value = byte_value | (1 << j)
                        end
                    end
                end
                values_bytes = values_bytes .. string.char(byte_value)
            end

            data = string.char(config.slave_id, func_code) ..
                string.char((config.start_addr >> 8) & 0xFF, config.start_addr & 0xFF) ..
                string.char((config.reg_count >> 8) & 0xFF, config.reg_count & 0xFF) ..
                string.char(byte_count) .. values_bytes

        elseif func_code == exmodbus_ref.WRITE_MULTIPLE_HOLDING_REGISTERS then
            -- 写入多个保持寄存器
            local byte_count = config.reg_count * 2
            local values_bytes = ""

            -- 构建寄存器数据（字节序为大端序）
            for i = 0, config.reg_count - 1 do
                local addr = config.start_addr + i
                local value = config.data[addr]
                if value < 0 or value > 65535 or value ~= math.floor(value) then
                    log.error("exmodbus", "寄存器值必须是 0~65535 范围内的整数，地址:", addr, "值:", value)
                    return false
                end
                values_bytes = values_bytes .. string.char((value >> 8) & 0xFF, value & 0xFF)
            end

            data = string.char(config.slave_id, func_code) ..
                string.char((config.start_addr >> 8) & 0xFF, config.start_addr & 0xFF) ..
                string.char((config.reg_count >> 8) & 0xFF, config.reg_count & 0xFF) ..
                string.char(byte_count) .. values_bytes
        end
    end

    -- 构建完整的 TCP 请求帧
    local transaction_id = gen_id_func() % 0x10000
    local length = #data                               -- 长度包含从站ID
    local frame = string.pack(">H", transaction_id) .. -- 事务 ID
        string.pack(">H", 0) ..                        -- 协议 ID
        string.pack(">H", length) ..                   -- 长度
        data                                           -- 从站ID + PDU数据

    return frame, func_code, transaction_id
end

-- 解析 Modbus TCP 响应帧（主站使用）
local function parse_tcp_response(response, config, expected_func_code, expected_transaction_id)
    -- 定义返回数据结构；
    local return_data = {
        status = false,
        execption_code = nil,
        data = {},
    }

    -- 检查响应是否为空
    if not response or #response == 0 then
        log.error("exmodbus", "响应报文为空")
        return_data.status = exmodbus_ref.STATUS_DATA_INVALID
        return return_data
    end

    -- 检查响应帧长度
    if #response < MODBUS_TCP_HEADER_LEN + 1 then
        log.error("exmodbus", "响应帧长度不足")
        return_data.status = exmodbus_ref.STATUS_DATA_INVALID
        return return_data
    end

    -- 解析 MBAP 头
    local transaction_id = string.unpack(">H", response, 1)
    local protocol_id = string.unpack(">H", response, 3)
    local length = string.unpack(">H", response, 5)
    local slave_id = string.unpack("B", response, 7)

    -- 检查事务 ID 是否匹配
    if transaction_id ~= expected_transaction_id then
        log.error("exmodbus", "事务ID不匹配")
        return_data.status = exmodbus_ref.STATUS_DATA_INVALID
        return return_data
    end

    -- 检查协议 ID
    if protocol_id ~= 0 then
        log.error("exmodbus", "无效的协议ID")
        return_data.status = exmodbus_ref.STATUS_DATA_INVALID
        return return_data
    end

    -- 检查数据长度
    if #response ~= 6 + length then
        log.error("exmodbus", "数据长度与实际长度不匹配")
        return_data.status = exmodbus_ref.STATUS_DATA_INVALID
        return return_data
    end

    -- 检查从站ID是否匹配
    if slave_id ~= config.slave_id then
        log.error("exmodbus", "从站地址不匹配，期望:", config.slave_id, "实际:", slave_id)
        return_data.status = exmodbus_ref.STATUS_DATA_INVALID
        return return_data
    end

    -- 解析功能码
    local func_code = string.unpack("B", response, 8)
    local response_length = #response

    -- 检查异常响应
    if bit.band(func_code, 0x80) ~= 0 then
        -- 检查异常响应报文长度是否正确
        if response_length ~= 9 then
            log.error("exmodbus", "异常响应报文长度不正确，期望: 9 字节，实际:", response_length, "字节")
            return_data.status = exmodbus_ref.STATUS_DATA_INVALID
            return return_data
        end

        -- 提取异常码
        local exception_code = string.unpack("B", response, 9)
        log.error("exmodbus", "接收到 Modbus 异常响应，功能码:", func_code, "异常码:", exception_code)
        
        return_data.status = exmodbus_ref.STATUS_EXCEPTION
        return_data.execption_code = exception_code
        return return_data
    end

    -- 检查功能码是否匹配
    if func_code ~= expected_func_code then
        log.error("exmodbus", "功能码不匹配，期望:", expected_func_code, "实际:", func_code)
        return_data.status = exmodbus_ref.STATUS_DATA_INVALID
        return return_data
    end


    -- 根据不同的功能码解析数据
    local parsed_data = {}

    -- 功能码 0x01 和 0x02：读取线圈状态和离散输入状态
    if func_code == exmodbus_ref.READ_COILS or func_code == exmodbus_ref.READ_DISCRETE_INPUTS then
        -- 提取数据部分
        local byte_count = string.unpack("B", response, 9)
        local data_start_pos = 10
        local data_end_pos = response_length

        -- 验证数据长度是否正确
        if data_end_pos - data_start_pos + 1 ~= byte_count then
            log.error("exmodbus", "数据长度不匹配，期望:", byte_count, "实际:", data_end_pos - data_start_pos + 1)
            return_data.status = exmodbus_ref.STATUS_DATA_INVALID
            return return_data
        end

        -- 验证字节数是否足够表示指定数量的位
        local expected_bytes = math.ceil(config.reg_count / 8)
        if byte_count < expected_bytes then
            log.error("exmodbus", "数据字节数不足，无法表示所有位")
            return_data.status = exmodbus_ref.STATUS_DATA_INVALID
            return return_data
        end

        -- 解析位数据
        for i = 0, config.reg_count - 1 do
            local modbus_addr = config.start_addr + i           -- 计算当前位对应的 Modbus 地址
            local byte_pos = data_start_pos + math.floor(i / 8) -- 计算当前位对应的字节位置
            local bit_pos = i % 8                               -- 计算当前位对应的位位置
            local byte_value = string.unpack("B", response, byte_pos)
            parsed_data[modbus_addr] = bit.band(byte_value, bit.lshift(1, bit_pos)) ~= 0 and 1 or 0
        end

    -- 功能码 0x03 和 0x04：读取保持寄存器和输入寄存器
    elseif func_code == exmodbus_ref.READ_HOLDING_REGISTERS or func_code == exmodbus_ref.READ_INPUT_REGISTERS then
        -- 提取数据部分
        local byte_count = string.unpack("B", response, 9)
        local data_start_pos = 10
        local data_end_pos = response_length

        -- 验证数据长度是否正确
        if data_end_pos - data_start_pos + 1 ~= byte_count then
            log.error("exmodbus", "数据长度不匹配，期望:", byte_count, "实际:", data_end_pos - data_start_pos + 1)
            return_data.status = exmodbus_ref.STATUS_DATA_INVALID
            return return_data
        end

        -- 验证字节数是否足够表示指定数量的寄存器
        local expected_bytes = config.reg_count * 2
        if byte_count < expected_bytes then
            log.error("exmodbus", "数据字节数不足，无法表示所有寄存器")
            return_data.status = exmodbus_ref.STATUS_DATA_INVALID
            return return_data
        end

        -- 解析寄存器数据（大端序）
        for i = 0, config.reg_count - 1 do
            local modbus_addr = config.start_addr + i -- 计算当前寄存器对应的 Modbus 地址
            local reg_pos = data_start_pos + i * 2    -- 计算当前寄存器对应的字节位置
            parsed_data[modbus_addr] = bit.lshift(string.unpack("B", response, reg_pos), 8) + string.unpack("B", response, reg_pos + 1)
        end

    -- 功能码 0x05：写入单个线圈
    elseif func_code == exmodbus_ref.WRITE_SINGLE_COIL then
        -- 写入单个线圈响应格式：事务ID(2 字节) + 协议ID(2 字节) + 长度(2 字节) + 从站地址(1 字节) + 功能码(1 字节) + 线圈地址(2 字节) + 线圈值(2 字节)
        if response_length ~= 12 then
            log.error("exmodbus", "写入单个线圈响应报文长度不正确")
            return_data.status = exmodbus_ref.STATUS_DATA_INVALID
            return return_data
        end

        -- 解析线圈地址和值
        local coil_addr = string.unpack(">H", response, 9)
        local coil_value = string.unpack(">H", response, 11)

        -- 验证地址是否匹配请求
        if config.start_addr and coil_addr ~= config.start_addr then
            log.error("exmodbus", "线圈地址不匹配，期望:", config.start_addr, "实际:", coil_addr)
            return_data.status = exmodbus_ref.STATUS_DATA_INVALID
            return return_data
        end

        -- 线圈值应该是 0x0000(OFF) 或 0xFF00(ON)
        local normalized_value = (coil_value == 0x0000) and 0 or 1
        parsed_data[coil_addr] = normalized_value

    -- 功能码 0x06：写入单个保持寄存器
    elseif func_code == exmodbus_ref.WRITE_SINGLE_HOLDING_REGISTER then
        -- 写入单个保持寄存器响应格式：事务ID(2 字节) + 协议ID(2 字节) + 长度(2 字节) + 从站地址(1 字节) + 功能码(1 字节) + 寄存器地址(2 字节) + 寄存器值(2 字节)
        if response_length ~= 12 then
            log.error("exmodbus", "写入单个保持寄存器响应报文长度不正确")
            return_data.status = exmodbus_ref.STATUS_DATA_INVALID
            return return_data
        end

        -- 解析寄存器地址和值
        local reg_addr = string.unpack(">H", response, 9)
        local reg_value = string.unpack(">H", response, 11)

        -- 验证地址是否匹配请求
        if config.start_addr and reg_addr ~= config.start_addr then
            log.error("exmodbus", "单个保持寄存器地址不匹配，期望:", config.start_addr, "实际:", reg_addr)
            return_data.status = exmodbus_ref.STATUS_DATA_INVALID
            return return_data
        end

        parsed_data[reg_addr] = reg_value

    -- 功能码 0x0F：写入多个线圈
    elseif func_code == exmodbus_ref.WRITE_MULTIPLE_COILS then
        -- 写入多个线圈响应格式：事务ID(2 字节) + 协议ID(2 字节) + 长度(2 字节) + 从站地址(1 字节) + 功能码(1 字节) + 起始地址(2 字节) + 线圈数量(2 字节)
        if response_length ~= 12 then
            log.error("exmodbus", "写入多个线圈响应报文长度不正确")
            return_data.status = exmodbus_ref.STATUS_DATA_INVALID
            return return_data
        end

        -- 解析起始地址和线圈数量
        local start_addr = string.unpack(">H", response, 9)
        local coil_count = string.unpack(">H", response, 11)

        -- 验证地址和数量是否匹配请求
        if config.start_addr and start_addr ~= config.start_addr then
            log.error("exmodbus", "线圈起始地址不匹配，期望:", config.start_addr, "实际:", start_addr)
            return_data.status = exmodbus_ref.STATUS_DATA_INVALID
            return return_data
        end

        if config.reg_count and coil_count ~= config.reg_count then
            log.error("exmodbus", "线圈数量不匹配，期望:", config.reg_count, "实际:", coil_count)
            return_data.status = exmodbus_ref.STATUS_DATA_INVALID
            return return_data
        end

        -- 在返回数据中记录操作成功的起始地址和数量
        parsed_data.start_addr = start_addr
        parsed_data.count = coil_count

    -- 功能码 0x10：写入多个保持寄存器
    elseif func_code == exmodbus_ref.WRITE_MULTIPLE_HOLDING_REGISTERS then
        -- 写入多个保持寄存器响应格式：事务ID(2 字节) + 协议ID(2 字节) + 长度(2 字节) + 从站地址(1 字节) + 功能码(1 字节) + 起始地址(2 字节) + 寄存器数量(2 字节)
        if response_length ~= 12 then
            log.error("exmodbus", "写入多个保持寄存器响应报文长度不正确")
            return_data.status = exmodbus_ref.STATUS_DATA_INVALID
            return return_data
        end

        -- 解析起始地址和寄存器数量
        local start_addr = string.unpack(">H", response, 9)
        local reg_count = string.unpack(">H", response, 11)

        -- 验证地址和数量是否匹配请求
        if config.start_addr and start_addr ~= config.start_addr then
            log.error("exmodbus", "寄存器起始地址不匹配，期望:", config.start_addr, "实际:", start_addr)
            return_data.status = exmodbus_ref.STATUS_DATA_INVALID
            return return_data
        end

        if config.reg_count and reg_count ~= config.reg_count then
            log.error("exmodbus", "寄存器数量不匹配，期望:", config.reg_count, "实际:", reg_count)
            return_data.status = exmodbus_ref.STATUS_DATA_INVALID
            return return_data
        end

        -- 在返回数据中记录操作成功的起始地址和数量
        parsed_data.start_addr = start_addr
        parsed_data.count = reg_count

    -- 未知功能码
    else
        log.error("exmodbus", "不支持的功能码解析:", func_code)
        return_data.status = exmodbus_ref.STATUS_DATA_INVALID
        return return_data
    end

    -- 成功解析响应数据
    return_data.data = parsed_data
    return_data.status = exmodbus_ref.STATUS_SUCCESS

    return return_data
end

-- TCP 主站发送请求并等待响应
local function sendRequest_waitResponse(instance, request_frame, config)
    -- 检查连接状态
    if not instance.is_connected or not instance.socket_client then
        log.error("exmodbus", "TCP 连接未建立或已断开，无法发送请求")
        return false
    end

    -- 从请求帧中提取事务ID和功能码
    local transaction_id = string.unpack(">H", request_frame, 1)
    local function_code = string.unpack("B", request_frame, 8)

    -- 创建请求信息并添加到发送队列
    local request_info = {
        request_frame = request_frame,
        function_code = function_code,
        transaction_id = transaction_id,
        config = config
    }

    table.insert(instance.send_queue, request_info)

    -- log.info("exmodbus", "请求已添加到发送队列", transaction_id)

    sys.sendMsg(instance.TASK_NAME, socket.EVENT, 0)

    -- 等待响应
    local _, response_data = sys.waitUntil("exmodbus/tcp_resp/" .. transaction_id,
        config.timeout or 5000)

    if not response_data then
        log.error("exmodbus", "等待响应超时")
        return false, nil
    end

    return true, response_data
end

-- TCP 主站接收数据处理函数
local function tcp_master_receiver(instance)
    if instance.recv_buff == nil then
        instance.recv_buff = zbuff.create(1024)
    end

    while true do
        local succ, param = socket.rx(instance.socket_client, instance.recv_buff)

        if not succ then
            log.info("exmodbus", "读取数据失败")
            return false
        end

        if instance.recv_buff:used() > 0 then
            local data = instance.recv_buff:query()
            sys.publish("exmodbus/tcp_resp/" .. instance.current_transaction_id, data)
            -- log.info("exmodbus", "读取数据成功")
            instance.recv_buff:del()
        else
            break
        end
    end

    return true
end

-- TCP 主站发送数据处理函数
local function tcp_master_sender(instance)
    -- 检查发送队列中是否有请求
    while #instance.send_queue > 0 do
        -- 取出队列中的第一个请求
        local request_info = table.remove(instance.send_queue, 1)
        local request_frame = request_info.request_frame
        local function_code = request_info.function_code
        local transaction_id = request_info.transaction_id
        local config = request_info.config

        -- 设置当前事务信息
        instance.current_transaction_id = transaction_id

        -- 发送请求
        local result, buff_full = libnet.tx(instance.TASK_NAME, 15000, instance.socket_client, request_frame)
        if not result then
            log.error("exmodbus", "发送请求失败")
            return true
        end

        if buff_full then
            log.error("exmodbus", "缓冲区已满，将请求重新放回队列队首")
            -- 将请求重新放回队列队首
            table.insert(instance.send_queue, 1, request_info)
        end
    end

    return true
end

-- TCP 主站主任务函数
local function tcp_master_main_task_func(instance)
    local result, param

    while true do
        -- 创建 socket 客户端
        instance.socket_client = socket.create(instance.adapter, instance.TASK_NAME)
        if not instance.socket_client then
            log.error("exmodbus", "创建 socket 客户端失败")
            goto EXCEPTION_PROC
        end

        -- 配置 socket
        result = socket.config(instance.socket_client)
        if not result then
            log.error("exmodbus", "配置 socket 失败")
            goto EXCEPTION_PROC
        end

        -- 连接服务器
        result = libnet.connect(instance.TASK_NAME, 15000, instance.socket_client, instance.ip_address, instance.port)
        if not result then
            log.error("exmodbus", "连接服务器失败")
            goto EXCEPTION_PROC
        end

        log.info("exmodbus", "连接服务器成功")
        instance.is_connected = true

        -- 主循环
        while true do
            -- 处理接收数据
            if not tcp_master_receiver(instance) then
                log.info("exmodbus", "接收数据处理失败")
                break
            end

            -- 处理发送数据
            if not tcp_master_sender(instance) then
                log.info("exmodbus", "发送数据处理失败")
                break
            end

            -- 等待事件
            result, param = libnet.wait(instance.TASK_NAME, 0, instance.socket_client)
            if not result then
                log.info("exmodbus", "连接断开")
                break
            end
        end

        -- 异常处理
        ::EXCEPTION_PROC::

        -- 关闭连接
        if instance.socket_client then
            libnet.close(instance.TASK_NAME, 5000, instance.socket_client)
            socket.release(instance.socket_client)
            instance.socket_client = nil
            instance.is_connected = false
        end

        -- 等待 5 秒后重试
        sys.wait(5000)
    end
end

-- 解析 TCP 请求帧（从站使用）
local function parse_tcp_request(data)
    -- 检查请求帧长度，至少包含 MBAP 头和功能码
    if #data < MODBUS_TCP_HEADER_LEN + 1 then
        log.error("exmodbus", "请求帧长度不足")
        return nil, "请求帧长度不足"
    end

    -- 解析 MBAP 头（事务标识符(2)、协议标识符(2)、数据长度(2)、从站地址(1)）
    local transaction_id = string.unpack(">H", data, 1)
    local protocol_id = string.unpack(">H", data, 3)
    local length = string.unpack(">H", data, 5)
    local slave_id = string.unpack("B", data, 7)

    -- 检查数据长度是否与实际长度匹配
    if #data ~= 6 + length then
        log.error("exmodbus", "数据长度与实际长度不匹配")
        return nil, "数据长度与实际长度不匹配"
    end

    -- 检查协议 ID（Modbus TCP 协议 ID 必须为 0）
    if protocol_id ~= 0 then
        log.error("exmodbus", "无效的协议 ID")
        return nil, "无效的协议 ID"
    end

    -- 解析功能码
    local func_code = string.unpack("B", data, 8)
    local request = {
        transaction_id = transaction_id,
        protocol_id = protocol_id,
        length = length,
        slave_id = slave_id,
        func_code = func_code,
        reg_type = nil,
        start_addr = nil,
        reg_count = nil,
        data = {},
    }

    -- 根据功能码解析请求内容
    if func_code == exmodbus_ref.READ_COILS or func_code == exmodbus_ref.READ_DISCRETE_INPUTS then
        -- 读线圈或离散输入
        request.reg_type = func_code == exmodbus_ref.READ_COILS and exmodbus_ref.COIL_STATUS or exmodbus_ref.DISCRETE_INPUT_STATUS
        request.start_addr = string.unpack(">H", data, 9)
        request.reg_count = string.unpack(">H", data, 11)
    elseif func_code == exmodbus_ref.READ_HOLDING_REGISTERS or func_code == exmodbus_ref.READ_INPUT_REGISTERS then
        -- 读保持寄存器或输入寄存器
        request.reg_type = func_code == exmodbus_ref.READ_HOLDING_REGISTERS and exmodbus_ref.HOLDING_REGISTER or exmodbus_ref.INPUT_REGISTER
        request.start_addr = string.unpack(">H", data, 9)
        request.reg_count = string.unpack(">H", data, 11)
    elseif func_code == exmodbus_ref.WRITE_SINGLE_COIL then
        -- 写单个线圈
        request.reg_type = exmodbus_ref.COIL_STATUS
        request.start_addr = string.unpack(">H", data, 9)
        request.reg_count = 1
        local value = string.unpack(">H", data, 11)
        request.data = { [request.start_addr] = value == 0xFF00 and 1 or 0 }
    elseif func_code == exmodbus_ref.WRITE_SINGLE_HOLDING_REGISTER then
        -- 写单个寄存器
        request.reg_type = exmodbus_ref.HOLDING_REGISTER
        request.start_addr = string.unpack(">H", data, 9)
        request.reg_count = 1
        local value = string.unpack(">H", data, 11)
        request.data = { [request.start_addr] = value }
    elseif func_code == exmodbus_ref.WRITE_MULTIPLE_COILS then
        -- 写多个线圈
        request.reg_type = exmodbus_ref.COIL_STATUS
        request.start_addr = string.unpack(">H", data, 9)
        request.reg_count = string.unpack(">H", data, 11)
        -- local byte_count = string.unpack("B", data, 13)
        request.data = {}
        for i = 0, request.reg_count - 1 do
            local byte_pos = 13 + 1 + math.floor(i / 8)
            local bit_pos = i % 8
            local byte_value = string.unpack("B", data, byte_pos)
            local bit_value = bit.band(byte_value, bit.lshift(1, bit_pos)) > 0 and 1 or 0
            request.data[request.start_addr + i] = bit_value
        end
    elseif func_code == exmodbus_ref.WRITE_MULTIPLE_HOLDING_REGISTERS then
        -- 写多个寄存器
        request.reg_type = exmodbus_ref.HOLDING_REGISTER
        request.start_addr = string.unpack(">H", data, 9)
        request.reg_count = string.unpack(">H", data, 11)
        -- local byte_count = string.unpack("B", data, 13)
        request.data = {}
        for i = 0, request.reg_count - 1 do
            local value = string.unpack(">H", data, 13 + 1 + i * 2)
            request.data[request.start_addr + i] = value
        end
    else
        log.error("exmodbus", "不支持的功能码:", func_code)
    end

    return request
end

-- 构建 Modbus TCP 响应帧（从站使用）；
local function build_tcp_response(request, user_return)
    local slave_id = request.slave_id
    local func_code = request.func_code

    -- 用户返回异常码 -> 异常响应；
    if type(user_return) == "number" then
        local exception_code = user_return
        local response_payload = string.char(slave_id, bit.bor(func_code, 0x80), exception_code)
        
        -- 构建完整的 TCP 响应帧
        local length = #response_payload
        local response = string.pack(">H", request.transaction_id) .. -- 事务 ID
            string.pack(">H", 0) ..                                   -- 协议 ID
            string.pack(">H", length) ..                              -- 长度
            response_payload
        
        return response
    end

    -- 用户返回表 -> 正常响应；
    if type(user_return) ~= "table" then
        log.error("exmodbus", "从站回调必须返回 table 或 number，实际类型: ", type(user_return))
        return nil
    end

    local response_payload = ""

    -- 处理读线圈和读离散输入响应；
    if func_code == exmodbus_ref.READ_COILS or func_code == exmodbus_ref.READ_DISCRETE_INPUTS then
        local reg_count = request.reg_count

        -- 校验 reg_count 是否有效；
        if not reg_count or reg_count <= 0 then
            log.error("exmodbus", "请求中 reg_count 无效")
            return nil
        end

        local byte_count = math.ceil(reg_count / 8)
        local values = {}

        for i = 0, reg_count - 1 do
            local addr = request.start_addr + i
            local bit_val = user_return[addr]
            if bit_val == nil then
                log.error("exmodbus", "读线圈/离散输入回调未返回地址 ", addr, " 的数据")
                return nil
            end
            if bit_val ~= 0 and bit_val ~= 1 then
                log.error("exmodbus", "地址 ", addr, " 的值必须为 0 或 1，实际: ", bit_val)
                return nil
            end

            local byte_idx = math.floor(i / 8)
            if not values[byte_idx] then values[byte_idx] = 0 end
            if bit_val == 1 then
                values[byte_idx] = bit.bor(values[byte_idx], bit.lshift(1, i % 8))
            end
        end

        response_payload = string.char(slave_id, func_code, byte_count)
        for i = 0, byte_count - 1 do
            response_payload = response_payload .. string.char(values[i] or 0)
        end
    -- 处理读保持寄存器和读输入寄存器响应；
    elseif func_code == exmodbus_ref.READ_HOLDING_REGISTERS or func_code == exmodbus_ref.READ_INPUT_REGISTERS then
        local reg_count = request.reg_count
        -- 校验 reg_count 是否有效；
        if not reg_count or reg_count <= 0 then
            log.error("exmodbus", "请求中 reg_count 无效")
            return nil
        end

        local values = ""
        for i = 0, reg_count - 1 do
            local addr = request.start_addr + i
            local val = user_return[addr]
            if val == nil then
                log.error("exmodbus", "读保持寄存器/输入寄存器回调未返回地址 ", addr, " 的数据")
                return nil
            end
            if type(val) ~= "number" or val ~= math.floor(val) or val < 0 or val > 65535 then
                log.error("exmodbus", "地址 ", addr, " 的值必须为 0~65535 的整数，实际: ", val)
                return nil
            end
            values = values .. string.char((val >> 8) & 0xFF, val & 0xFF)
        end
        response_payload = string.char(slave_id, func_code, #values) .. values
    -- 处理写单个线圈响应；
    elseif func_code == exmodbus_ref.WRITE_SINGLE_COIL then
        local addr = request.start_addr
        -- 校验 start_addr 是否有效；
        if addr == nil then
            log.error("exmodbus", "请求中 start_addr 无效")
            return nil
        end
        local coil_val = (request.data and request.data[addr]) or 0
        local resp_val = (coil_val ~= 0) and 0xFF00 or 0x0000
        response_payload = string.char(slave_id, func_code) ..
            string.char((addr >> 8) & 0xFF, addr & 0xFF,
            (resp_val >> 8) & 0xFF, resp_val & 0xFF)
    -- 处理写单个保持寄存器响应；
    elseif func_code == exmodbus_ref.WRITE_SINGLE_HOLDING_REGISTER then
        local addr = request.start_addr
        -- 校验 start_addr 是否有效；
        if addr == nil then
            log.error("exmodbus", "请求中 start_addr 无效")
            return nil
        end
        local reg_val = (request.data and request.data[addr]) or 0
        -- 校验 reg_val 是否有效；
        if type(reg_val) ~= "number" or reg_val ~= math.floor(reg_val) or reg_val < 0 or reg_val > 65535 then
            log.error("exmodbus", "地址 ", addr, " 的值必须为 0~65535 的整数，实际: ", reg_val)
            return nil
        end
        response_payload = string.char(slave_id, func_code) ..
            string.char((addr >> 8) & 0xFF, addr & 0xFF,
            (reg_val >> 8) & 0xFF, reg_val & 0xFF)
    -- 处理写多个线圈/保持寄存器响应；
    elseif func_code == exmodbus_ref.WRITE_MULTIPLE_COILS or func_code == exmodbus_ref.WRITE_MULTIPLE_HOLDING_REGISTERS then
        local start_addr = request.start_addr
        local reg_count = request.reg_count
        -- 校验 start_addr 和 reg_count 是否有效；
        if not start_addr or not reg_count or reg_count <= 0 then
            log.error("exmodbus", "请求中 start_addr 或 reg_count 无效")
            return nil
        end
        response_payload = string.char(slave_id, func_code) ..
            string.char((start_addr >> 8) & 0xFF, start_addr & 0xFF,
            (reg_count >> 8) & 0xFF, reg_count & 0xFF)
    -- 处理未知功能码，视为错误；
    else
        log.error("exmodbus", "不支持的功能码，且未返回异常码: ", func_code)
        return nil
    end

    -- 构建完整的 TCP 响应帧
    local length = #response_payload  -- 长度包含从站ID
    local response = string.pack(">H", request.transaction_id) .. -- 事务 ID
        string.pack(">H", 0) ..                                   -- 协议 ID
        string.pack(">H", length) ..                              -- 长度（包含从站ID）
        response_payload                                          -- 从站ID + PDU数据

    return response
end

-- TCP 从站接收数据处理函数；
local function tcp_receiver(netc, instance)
    -- 如果数据接收缓冲区还没有申请过空间，则先申请内存空间
    if instance.recv_buff == nil then
        instance.recv_buff = zbuff.create(1024)
    end

    -- 循环从内核的缓冲区读取接收到的数据
    while true do
        -- 从内核的缓冲区中读取数据到 instance.recv_buff 中
        local succ, param = socket.rx(netc, instance.recv_buff)

        -- 读取数据失败
        if not succ then
            log.info("exmodbus", "读取数据失败，已接收数据长度", param)
            return false
        end

        -- 如果读取到了数据
        if instance.recv_buff:used() > 0 then
            -- log.info("exmodbus", "已接收数据长度", instance.recv_buff:used())
            
            -- 读取数据
            local data = instance.recv_buff:query()
            
            -- 解析 TCP 请求帧
            local request, err = parse_tcp_request(data)
            if request then
                -- 广播地址（0）不响应；
                if request.slave_id == 0 then
                    -- 调用回调以允许用户记录或处理广播命令（如写寄存器）；
                    if instance.slaveHandler then
                        instance.slaveHandler(request)
                        -- 注意：即使回调返回数据，也不发送响应；
                    end
                    -- 广播请求处理完毕，清除对应的报文数据
                    local expected_len = request.length + MODBUS_TCP_HEADER_LEN - 1
                    instance.recv_buff:del(0, expected_len)
                    -- log.info("exmodbus", "广播请求处理完毕，清除报文长度:", expected_len)
                    -- 广播请求处理完毕，不回复；
                    break
                end
                if instance.slaveHandler then
                    local user_return = instance.slaveHandler(request)
                    local response = build_tcp_response(request, user_return)
                    if response then
                        libnet.tx(instance.TASK_NAME, 0, netc, response)
                        sys.sendMsg(instance.TASK_NAME, socket.EVENT, 0)
                    else
                        log.error("exmodbus", "构建响应帧失败，从站地址:", request.slave_id)
                    end
                    
                    -- 清除当前请求数据
                    local expected_len = request.length + MODBUS_TCP_HEADER_LEN - 1
                    instance.recv_buff:del(0, expected_len)
                    -- log.info("exmodbus", "请求处理完毕，清除报文长度:", expected_len)
                else
                    log.warn("exmodbus", "收到主站请求，但未注册回调函数")
                    -- 清除当前请求数据
                    local expected_len = request.length + MODBUS_TCP_HEADER_LEN - 1
                    instance.recv_buff:del(0, expected_len)
                    log.info("exmodbus", "清除报文长度:", expected_len)
                end
            else
                if err == "请求帧长度不足" then
                    -- 请求帧长度不足，等待更多数据
                    -- log.info("exmodbus", "请求帧长度不足，等待更多数据")
                    break
                elseif err == "数据长度与实际长度不匹配" then
                    -- 数据长度与实际长度不匹配，清空缓冲区
                    -- log.warn("exmodbus", "数据长度与实际长度不匹配，清空缓冲区")
                    instance.recv_buff:del()
                    break
                elseif err == "协议 ID 错误" then
                    -- 协议 ID 错误，清空缓冲区
                    -- log.warn("exmodbus", "协议 ID 错误，清空缓冲区")
                    instance.recv_buff:del()
                    break
                end
            end
        else
            -- 没有数据可读
            break
        end
    end

    return true
end

local function tcp_slave_main_task_func(instance)
    local netc = nil
    local result, param

    while true do
        -- 创建 TCP 服务器
        netc = socket.create(instance.adapter, instance.TASK_NAME)
        if not netc then
            log.error("exmodbus", "创建 TCP 服务器失败")
            goto EXCEPTION_PROC
        end

        -- 配置服务器
        result = socket.config(netc, instance.port)
        if not result then
            log.error("exmodbus", "配置 TCP 服务器失败")
            goto EXCEPTION_PROC
        end

        -- 监听端口
        result = libnet.listen(instance.TASK_NAME, 0, netc)
        if not result then
            log.error("exmodbus", "监听端口失败")
            goto EXCEPTION_PROC
        end

        log.info("exmodbus", "TCP 从站已启动，监听端口:", instance.port)

        -- 处理连接和数据
        while true do
            -- 处理接收数据
            if not tcp_receiver(netc, instance) then
                log.info("exmodbus", "接收数据处理失败")
                break
            end

            -- 等待事件
            result, param = libnet.wait(instance.TASK_NAME, 0, netc)
            if not result then
                log.info("exmodbus", "客户端断开连接")
                break
            end
        end

        -- 异常处理
        ::EXCEPTION_PROC::

        -- 关闭连接
        if netc then
            libnet.close(instance.TASK_NAME, 5000, netc)
            socket.release(netc)
            netc = nil
        end

        -- 等待 5 秒后重试
        sys.wait(5000)
    end
end

-- 创建一个新的实例；
local function create(config, exmodbus, gen_request_id)
    exmodbus_ref = exmodbus
    gen_id_func = gen_request_id
    local TASK_NAME = "exmodbus_tcp_task_"..gen_id_func()

    -- 创建一个新的实例；
    local instance = modbus:new(config, TASK_NAME)
    -- 检查实例是否创建成功；
    if not instance then
        log.error("exmodbus", "创建 Modbus 实例失败")
        return false
    end

    -- 根据模式启动不同的任务
    if config.mode == exmodbus_ref.TCP_MASTER then
        -- 启动主站任务
        sys.taskInitEx(tcp_master_main_task_func, TASK_NAME, nil, instance)
        log.info("exmodbus", "TCP 主站任务已启动")
    elseif config.mode == exmodbus_ref.TCP_SLAVE then
        -- 启动从站任务
        sys.taskInitEx(tcp_slave_main_task_func, TASK_NAME, nil, instance)
        log.info("exmodbus", "TCP 从站任务已启动")
    else
        log.error("exmodbus", "不支持的 TCP 模式")
        return false
    end

    -- 返回实例；
    return instance
end

function modbus:destroy()
    -- 停止任务
    sys.taskDel(self.TASK_NAME)
    -- 释放缓冲区
    if self.recv_buff then
        self.recv_buff:free()
        self.recv_buff = nil
    end
end

-- 内部读函数
function modbus:read_internal(config)
    -- 处理响应结果；
    local parsed_data = {}

    -- 检查是否同时指定了 slave_id 和 raw_request
    if config.slave_id and config.raw_request then
        log.error("exmodbus", "禁止同时指定 slave_id 和 raw_request")

        parsed_data.status = exmodbus_ref.STATUS_PARAM_INVALID
        return parsed_data
    end

    if config.slave_id then
        local request_frame, function_code, transaction_id = build_tcp_frame("read", config)
        if not request_frame then
            log.error("exmodbus", "构建 TCP 读取请求失败")
            parsed_data.status = exmodbus_ref.STATUS_PARAM_INVALID
            return parsed_data
        end

        -- 发送请求并等待响应；
        local result, response = sendRequest_waitResponse(self, request_frame, config)
        if not result then
            parsed_data.status = exmodbus_ref.STATUS_TIMEOUT
        else
            -- 解析响应数据；
            parsed_data = parse_tcp_response(response, config, function_code, transaction_id)
        end
    elseif config.raw_request then
        -- 发送请求并等待响应；
        local result, response = sendRequest_waitResponse(self, config.raw_request, config)
        if not result then
            parsed_data.status = exmodbus_ref.STATUS_TIMEOUT
        else
            -- 直接返回响应结果和原始响应数据；
            parsed_data.status = exmodbus_ref.STATUS_SUCCESS
            parsed_data.raw_response = response
        end
    end

    return parsed_data
end

-- 主站写入请求的函数；
function modbus:write_internal(config)
    -- 处理响应结果；
    local parsed_data = {}

    -- 检查是否同时指定了 slave_id 和 raw_request
    if config.slave_id and config.raw_request then
        log.error("exmodbus", "禁止同时指定 slave_id 和 raw_request")

        parsed_data.status = exmodbus_ref.STATUS_PARAM_INVALID
        return parsed_data
    end

    if config.slave_id then
        local request_frame, function_code, transaction_id = build_tcp_frame("write", config)
        if not request_frame then
            log.error("exmodbus", "构建 TCP 写入请求失败")
            parsed_data.status = exmodbus_ref.STATUS_PARAM_INVALID
            return parsed_data
        end

        -- 发送请求并等待响应；
        local result, response = sendRequest_waitResponse(self, request_frame, config)
        if not result then
            parsed_data.status = exmodbus_ref.STATUS_TIMEOUT
        else
            -- 解析响应数据；
            parsed_data = parse_tcp_response(response, config, function_code, transaction_id)
        end
    elseif config.raw_request then
        -- 发送请求并等待响应；
        local result, response = sendRequest_waitResponse(self, config.raw_request, config)
        if not result then
            parsed_data.status = exmodbus_ref.STATUS_TIMEOUT
        else
            -- 直接返回响应结果和原始响应数据；
            parsed_data.status = exmodbus_ref.STATUS_SUCCESS
            parsed_data.raw_response = response
        end
    end

    return parsed_data
end

-- 读函数（主站使用）
function modbus:read(config)
    return exmodbus_ref.enqueue_request(self, config, true)
end

-- 写函数（主站使用）
function modbus:write(config)
    return exmodbus_ref.enqueue_request(self, config, false)
end

-- 注册从站请求处理回调函数；
function modbus:on(callback)
    if type(callback) ~= "function" then
        log.error("exmodbus", "on(callback) 的参数必须是一个函数")
        return false
    end
    self.slaveHandler = callback
    log.info("exmodbus", "已注册从站请求处理回调函数")
    return true
end

return { create = create }