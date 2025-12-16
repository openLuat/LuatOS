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

    -- 从站请求处理回调函数；
    obj.slaveHandler = nil
    -- 任务名称
    obj.TASK_NAME = TASK_NAME
    -- 接收数据缓冲区
    obj.recv_buff = nil

    -- 设置原表；
    setmetatable(obj, modbus)
    -- 返回实例；
    return obj
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

    -- 启动任务
    sys.taskInitEx(tcp_slave_main_task_func, TASK_NAME, nil, instance)

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