-- 定义类结构；
local modbus = {}                            -- 定义 modbus 实例的元表；
modbus.__index = modbus                      -- 定义 modbus 实例的索引元方法，用于访问实例的属性；
modbus.__metatable = "instance is protected" -- 定义 modbus 实例的元表，防止外部修改；

-- 模块级变量：依赖注入的引用；
local exmodbus_ref -- 主模块引用，用于访问enqueue_request等核心功能；
local gen_id_func  -- ID生成函数引用，用于生成唯一请求ID；
local read_buf = "" -- 接收缓冲区；

-- 创建 modbus 实例的构造函数；
function modbus:new(config)
    local obj = {
        mode = config.mode,                             -- 通信模式
        uart_id = config.uart_id,                       -- 串口 ID
        baud_rate = config.baud_rate,                   -- 波特率
        data_bits = config.data_bits,                   -- 数据位
        stop_bits = config.stop_bits,                   -- 停止位
        parity_bits = config.parity_bits,               -- 校验位
        byte_order = config.byte_order,                 -- 字节序
        rs485_dir_gpio = config.rs485_dir_gpio,         -- RS485 方向控制 GPIO 引脚
        rs485_dir_rx_level = config.rs485_dir_rx_level, -- RS485 方向控制接收电平
    }

    -- 串口是否已初始化；
    obj.uart_initialized = false
    -- 当前等待的主题；
    obj.current_wait_request_id = nil
    -- 从站请求处理回调函数；
    obj.slaveHandler = nil
    -- 字符拼接超时定时器；
    -- 在数据拼接过程中，等待后续数据片段到达的最大时间间隔；
    obj.concat_timeout = nil

    -- 设置原表；
    setmetatable(obj, modbus)
    -- 返回实例；
    return obj
end

-- 解析 Modbus RTU 请求帧（从站使用）；
local function parse_rtu_request(frame)
    -- 校验请求帧长度是否至少为 4 字节（包含从站地址、功能码和 CRC）；
    local frame_len = #frame
    if frame_len < 4 then
        return nil
    end

    -- 仅校验 CRC（格式基础校验）；
    local calc_crc = crypto.crc16_modbus(frame:sub(1, -3))
    local recv_crc = string.byte(frame, -2) + bit.lshift(string.byte(frame, -1), 8)
    if calc_crc ~= recv_crc then
        -- log.warn("exmodbus", "请求帧 CRC 校验失败")
        return nil
    end

    -- 提取从站地址和功能码；
    local slave_id = string.byte(frame, 1)
    local func_code = string.byte(frame, 2)

    -- 所有字段尽可能提取，即使值可能非法；
    local request_data = {
        slave_id = slave_id,
        func_code = func_code,
        reg_type = nil,
        start_addr = nil,
        reg_count = nil,
        data = {},
    }

    -- 读请求和单写请求；
    -- 校验请求帧长度是否为 8 字节（包含从站地址、功能码、起始地址、寄存器数量/寄存器值和 CRC）；
    if frame_len == 8 then
        request_data.start_addr = bit.lshift(string.byte(frame, 3), 8) + string.byte(frame, 4)
        request_data.reg_count = bit.lshift(string.byte(frame, 5), 8) + string.byte(frame, 6)

        -- 写单个线圈；
        if func_code == exmodbus_ref.WRITE_SINGLE_COIL then
            local coil_val = bit.lshift(string.byte(frame, 5), 8) + string.byte(frame, 6)
            request_data.reg_count = 1
            request_data.data[request_data.start_addr] = (coil_val == 0xFF00) and 1 or 0
        -- 写单个保持寄存器；
        elseif func_code == exmodbus_ref.WRITE_SINGLE_HOLDING_REGISTER then
            local reg_val = bit.lshift(string.byte(frame, 5), 8) + string.byte(frame, 6)
            request_data.reg_count = 1
            request_data.data[request_data.start_addr] = reg_val
        end
    -- 多写请求；
    -- 校验请求帧长度是否至少为 9 字节（包含从站地址、功能码、起始地址、寄存器数量、字节数量、数据和 CRC）；
    elseif frame_len >= 9 then
        request_data.start_addr = bit.lshift(string.byte(frame, 3), 8) + string.byte(frame, 4)
        request_data.reg_count = bit.lshift(string.byte(frame, 5), 8) + string.byte(frame, 6)

        -- 写多个线圈；
        if func_code == exmodbus_ref.WRITE_MULTIPLE_COILS then
            for i = 0, request_data.reg_count - 1 do
                local byte_idx = 8 + math.floor(i / 8)
                if byte_idx > frame_len - 2 then break end -- 防止越界；
                local bit_idx = i % 8
                local byte_val = string.byte(frame, byte_idx)
                local bit_val = bit.band(byte_val, bit.lshift(1, bit_idx)) ~= 0 and 1 or 0
                request_data.data[request_data.start_addr + i] = bit_val
            end
        -- 写多个保持寄存器；
        elseif func_code == exmodbus_ref.WRITE_MULTIPLE_HOLDING_REGISTERS then
            for i = 0, request_data.reg_count - 1 do
                local pos = 8 + i * 2
                if pos + 1 > frame_len - 2 then break end -- 防止越界；
                local val = bit.lshift(string.byte(frame, pos), 8) + string.byte(frame, pos + 1)
                request_data.data[request_data.start_addr + i] = val
            end
        end
    end

    -- 对于读请求，data 为 nil，由用户处理读逻辑；
    if not request_data.data and (
        func_code == exmodbus_ref.READ_COILS or
        func_code == exmodbus_ref.READ_DISCRETE_INPUTS or
        func_code == exmodbus_ref.READ_HOLDING_REGISTERS or
        func_code == exmodbus_ref.READ_INPUT_REGISTERS
    ) then
        request_data.data = nil -- request_data.data 保持 nil，由用户处理读逻辑；
    end

    return request_data
end

-- 构建 Modbus RTU 响应帧（从站使用）；
local function build_rtu_response(request, user_return)
    local slave_id = request.slave_id
    local func_code = request.func_code

    -- 用户返回异常码 -> 异常响应；
    if type(user_return) == "number" then
        local exception_code = user_return
        local frame = string.char(slave_id, bit.bor(func_code, 0x80), exception_code)
        local crc = crypto.crc16_modbus(frame)
        return frame .. string.char(crc & 0xFF, (crc >> 8) & 0xFF)
    end

    -- 用户返回表 -> 正常响应；
    if type(user_return) ~= "table" then
        log.error("exmodbus", "从站回调必须返回 table 或 number，实际类型: ", type(user_return))
        return nil
    end

    local data_bytes = ""

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

        data_bytes = string.char(byte_count)
        for i = 0, byte_count - 1 do
            data_bytes = data_bytes .. string.char(values[i] or 0)
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
        data_bytes = string.char(#values) .. values
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
        data_bytes = string.char(
            (addr >> 8) & 0xFF, addr & 0xFF,
            (resp_val >> 8) & 0xFF, resp_val & 0xFF
        )
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
        data_bytes = string.char(
            (addr >> 8) & 0xFF, addr & 0xFF,
            (reg_val >> 8) & 0xFF, reg_val & 0xFF
        )
    -- 处理写多个线圈/保持寄存器响应；
    elseif func_code == exmodbus_ref.WRITE_MULTIPLE_COILS or func_code == exmodbus_ref.WRITE_MULTIPLE_HOLDING_REGISTERS then
        local start_addr = request.start_addr
        local reg_count = request.reg_count
        -- 校验 start_addr 和 reg_count 是否有效；
        if not start_addr or not reg_count or reg_count <= 0 then
            log.error("exmodbus", "请求中 start_addr 或 reg_count 无效")
            return nil
        end
        data_bytes = string.char(
            (start_addr >> 8) & 0xFF, start_addr & 0xFF,
            (reg_count >> 8) & 0xFF, reg_count & 0xFF
        )
    -- 处理未知功能码，视为错误；
    else
        log.error("exmodbus", "不支持的功能码，且未返回异常码: ", func_code)
        return nil
    end

    local frame = string.char(slave_id, func_code) .. data_bytes
    local crc = crypto.crc16_modbus(frame)
    return frame .. string.char(crc & 0xFF, (crc >> 8) & 0xFF)
end

-- 初始化串口；
local function init_uart(instance)
    -- 检查串口是否已被初始化；
    if instance.uart_initialized then
        log.warn("exmodbus", "串口 ", instance.uart_id, " 已经初始化，无需重复初始化")
        return true
    end

    -- 配置串口参数，并开启串口功能；
    local result = uart.setup(
        instance.uart_id,           -- 串口 ID
        instance.baud_rate,         -- 波特率
        instance.data_bits,         -- 数据位
        instance.stop_bits,         -- 停止位
        instance.parity_bits,       -- 校验位
        instance.byte_order,        -- 字节序
        nil,                        -- 缓冲区大小
        instance.rs485_dir_gpio,    -- RS485 方向控制 GPIO 引脚
        instance.rs485_dir_rx_level -- RS485 方向控制接收电平
    )
    -- 检查串口是否初始化成功；
    -- 成功时返回 0，其他返回值表示失败；
    if result ~= 0 then
        log.error("exmodbus", "串口 ", instance.uart_id, " 初始化失败")
        return false
    end

    -- 定义发送完成回调函数；
    -- 当串口发送完成时，发布一个主题，通知其他任务；
    local function on_sent(uart_id)
        sys.publish("exmodbus/sent/" .. uart_id, true)
    end

    -- 当一包数据被拆分为多个小包时，此函数用于拼接这些小包；
    local function concat_timeout_func()
        if read_buf:len() > 0 then
            -- 处理 RTU 主站模式下的接收数据；
            if instance.mode == exmodbus_ref.RTU_MASTER then
                -- 校验等待主题是否存在；
                if instance.current_wait_request_id then
                    -- 发布主题，通知其他任务；
                    sys.publish("exmodbus/rtu_resp/" .. instance.current_wait_request_id, read_buf)
                    -- 发布后，清除等待主题；
                    instance.current_wait_request_id = nil
                end
            -- 处理 RTU 从站模式下的接收数据；
            elseif instance.mode == exmodbus_ref.RTU_SLAVE then
                -- 解析 RTU 请求帧；
                local request = parse_rtu_request(read_buf)
                if request then
                    -- 广播地址（0）不响应；
                    if request.slave_id == 0 then
                        -- 调用回调以允许用户记录或处理广播命令（如写寄存器）；
                        if instance.slaveHandler then
                            instance.slaveHandler(request)
                            -- 注意：即使回调返回数据，也不发送响应；
                        end
                        -- 广播请求处理完毕，不回复；
                    end
                    if instance.slaveHandler then
                        local user_return = instance.slaveHandler(request)
                        local response_frame = build_rtu_response(request, user_return)
                        if response_frame then
                            uart.write(uart_id, response_frame)
                        else
                            log.error("exmodbus", "构建响应帧失败，从站地址:", request.slave_id)
                        end
                    else
                        log.warn("exmodbus", "收到主站请求，但未注册回调函数")
                    end
                else
                    log.debug("exmodbus", "无效 RTU 请求帧（CRC 或格式错误）")
                end
            end
        end

        read_buf = ""
    end

    -- 定义接收完成回调函数；
    -- 当串口接收完成时，对接收数据进行处理；
    -- 处理成功时，发布一个主题，通知其他任务；
    -- 处理失败时，不做任何处理；
    local function on_receive(uart_id, data_len)
        local data
        while true do
            data = uart.read(uart_id, data_len)

            if not data or #data == 0 then
                if instance.concat_timeout and type(instance.concat_timeout) == "number" then
                    -- 启动50毫秒的定时器，如果50毫秒内没收到新的数据，则处理当前收到的所有数据
                    -- 这样处理是为了防止将一大包数据拆分成多个小包来处理
                    -- 例如pc端串口工具下发1100字节的数据，可能会产生将近20次的中断进入到read函数，才能读取完整
                    -- 此处的50毫秒可以根据自己项目的需求做适当修改，在满足整包拼接完整的前提下，时间越短，处理越及时
                    sys.timerStart(concat_timeout_func, instance.concat_timeout)
                else
                    concat_timeout_func()
                end
                return
            end

            -- log.info("exmodbus", "收到串口 ", uart_id, " 数据: ", data:toHex())

            read_buf = read_buf .. data
        end
    end

    -- 注册发送完成和接收完成回调函数；
    uart.on(instance.uart_id, "sent", on_sent)
    uart.on(instance.uart_id, "receive", on_receive)

    -- 初始化成功，设置标志位为 true；
    instance.uart_initialized = true
    log.info("exmodbus", "串口 " .. instance.uart_id .. " 初始化成功，波特率 " .. instance.baud_rate)
    return true
end

-- 创建一个新的实例；
local function create(config, exmodbus, gen_request_id)
    exmodbus_ref = exmodbus
    gen_id_func = gen_request_id

    -- 创建一个新的实例；
    local instance = modbus:new(config)
    -- 检查实例是否创建成功；
    if not instance then
        log.error("exmodbus", "创建 Modbus 实例失败")
        return false
    end

    -- 初始化串口；
    local result = init_uart(instance)
    -- 检查串口初始化结果；
    if not result then
        -- 销毁已创建的实例，释放资源；
        instance:destroy()
        return false
    end

    -- 返回实例；
    return instance
end

-- 销毁已创建的实例，释放资源；
function modbus:destroy()
    -- 检查实例是否已被销毁；
    if not self then
        log.error("exmodbus", "实例对象已被销毁，无需重复销毁")
        return
    end

    -- 关闭串口；
    if self.uart_initialized then
        uart.close(self.uart_id)
        uart.on(self.uart_id, "sent", nil)
        uart.on(self.uart_id, "receive", nil)
    end

    -- 释放GPIO资源；
    if self.rs485_dir_gpio then
        gpio.close(self.rs485_dir_gpio)
    end

    -- 销毁已创建的实例；
    setmetatable(self, nil)

    log.info("exmodbus", "实例对象已销毁")
end

-- 构建 Modbus RTU 帧的函数，支持读取和写入操作；（主站使用）
local function build_rtu_frame(opt_type, config)
    -- 参数验证；
    if not config or type(config) ~= "table" then
        log.error("exmodbus", "配置必须是表格类型")
        return false
    end

    -- 验证必要参数；
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

    if opt_type == "write" then
        if not config.data then
            log.error("exmodbus", "缺少写入请求必要参数: data")
            return false
        end
    end

    -- 参数范围验证；
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

    -- 根据操作类型和寄存器类型确定功能码；
    local function_code
    if opt_type == "write" then
        -- 校验每一个地址是否有数据，且数据是否为数字类型；
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

        -- 判断是否强制使用写多个功能码；
        local use_multiple = config.force_multiple

        if config.reg_count == 1 then
            -- 写入单个线圈或单个保持寄存器；
            if not use_multiple then -- 使用写单个功能码；
                if config.reg_type == exmodbus_ref.COIL_STATUS then
                    function_code = exmodbus_ref.WRITE_SINGLE_COIL
                elseif config.reg_type == exmodbus_ref.HOLDING_REGISTER then
                    function_code = exmodbus_ref.WRITE_SINGLE_HOLDING_REGISTER
                end
            else -- 使用写多个功能码；
                if config.reg_type == exmodbus_ref.COIL_STATUS then
                    function_code = exmodbus_ref.WRITE_MULTIPLE_COILS
                elseif config.reg_type == exmodbus_ref.HOLDING_REGISTER then
                    function_code = exmodbus_ref.WRITE_MULTIPLE_HOLDING_REGISTERS
                end
            end
        elseif config.reg_count > 1 then
            -- 写入多个线圈或寄存器；
            if config.reg_type == exmodbus_ref.COIL_STATUS then
                function_code = exmodbus_ref.WRITE_MULTIPLE_COILS
            elseif config.reg_type == exmodbus_ref.HOLDING_REGISTER then
                function_code = exmodbus_ref.WRITE_MULTIPLE_HOLDING_REGISTERS
            end
        end
    elseif opt_type == "read" then
        -- 读线圈状态；
        if config.reg_type == exmodbus_ref.COIL_STATUS then
            function_code = exmodbus_ref.READ_COILS
        -- 读离散输入状态；
        elseif config.reg_type == exmodbus_ref.INPUT_STATUS then
            function_code = exmodbus_ref.READ_DISCRETE_INPUTS
        -- 读保持寄存器；
        elseif config.reg_type == exmodbus_ref.HOLDING_REGISTER then
            function_code = exmodbus_ref.READ_HOLDING_REGISTERS
        -- 读输入寄存器；
        elseif config.reg_type == exmodbus_ref.INPUT_REGISTER then
            function_code = exmodbus_ref.READ_INPUT_REGISTERS
        end
    end

    local data_bytes
    -- 功能码 0x01 和 0x02：读取线圈状态和离散输入状态；
    if function_code == exmodbus_ref.READ_COILS or function_code == exmodbus_ref.READ_DISCRETE_INPUTS then
        -- 验证数量范围；
        if config.reg_count < 1 or config.reg_count > 2000 then
            log.error("exmodbus", "线圈/离散输入读取数量超出范围: " .. config.reg_count .. " (范围: 1-2000)")
            return false
        end
        
        -- 构建数据部分（起始地址 + 数量）（大端序）；
        data_bytes = string.char(
            (config.start_addr >> 8) & 0xFF, config.start_addr & 0xFF,
            (config.reg_count >> 8) & 0xFF, config.reg_count & 0xFF
        )

    -- 功能码 0x03 和 0x04：读取保持寄存器和输入寄存器；
    elseif function_code == exmodbus_ref.READ_HOLDING_REGISTERS or function_code == exmodbus_ref.READ_INPUT_REGISTERS then
        -- 验证数量范围；
        if config.reg_count < 1 or config.reg_count > 125 then
            log.error("exmodbus", "寄存器读取数量超出范围: " .. config.reg_count .. " (范围: 1-125)")
            return false
        end

        -- 构建数据部分（起始地址 + 数量）（字节序为大端序）；
        data_bytes = string.char(
            (config.start_addr >> 8) & 0xFF, config.start_addr & 0xFF,
            (config.reg_count >> 8) & 0xFF, config.reg_count & 0xFF
        )

    -- 功能码 0x05：写入单个线圈；
    elseif function_code == exmodbus_ref.WRITE_SINGLE_COIL then
        -- 写入单个线圈，值必须是 0xFF00 (ON) 或 0x0000 (OFF)；
        local value = config.data[config.start_addr] ~= 0 and 0xFF00 or 0x0000
        
        -- 构建数据部分（起始地址 + 值）（字节序为大端序）；
        data_bytes = string.char(
            (config.start_addr >> 8) & 0xFF, config.start_addr & 0xFF,
            (value >> 8) & 0xFF, value & 0xFF
        )

    -- 功能码 0x06：写入单个保持寄存器；
    elseif function_code == exmodbus_ref.WRITE_SINGLE_HOLDING_REGISTER then
        -- 写入单个保持寄存器；
        local value = config.data[config.start_addr]

        -- 验证寄存器值范围（16 位无符号整数）；
        if value < 0 or value > 65535 or value ~= math.floor(value) then
            log.error("exmodbus", "寄存器值必须是 0~65535 范围内的整数，实际值: ", value)
            return false
        end
        
        -- 构建数据部分（起始地址 + 值）（字节序为大端序）；
        data_bytes = string.char(
            (config.start_addr >> 8) & 0xFF, config.start_addr & 0xFF,
            (value >> 8) & 0xFF, value & 0xFF
        )

    -- 功能码 0x0F：写入多个线圈；
    elseif function_code == exmodbus_ref.WRITE_MULTIPLE_COILS then
        -- 验证数量范围；
        if config.reg_count < 1 or config.reg_count > 1968 then
            log.error("exmodbus", "线圈写入数量超出范围: " .. config.reg_count .. " (范围: 1-1968)")
            return false
        end

        -- 计算字节数；
        local byte_count = math.ceil(config.reg_count / 8)
        local values_bytes = ""

        -- 构建线圈数据（字节序为大端序）；
        for i = 0, byte_count - 1 do
            local byte_value = 0
            -- 遍历当前字节的 8 个位；
            for j = 0, 7 do
                local bit_index = i * 8 + j -- 计算当前比特在整个线圈序列中的全局索引（从 0 开始）；
                -- 检查当前比特是否在有效范围内；
                if bit_index < config.reg_count then
                    local addr = config.start_addr + bit_index -- 根据起始地址和全局索引计算实际的线圈地址；
                    local bit_val = config.data[addr] -- 获取当前线圈的状态值（0 或 1）；
                    if bit_val ~= nil and bit_val ~= 0 then
                        byte_value = byte_value | (1 << j) -- 如果状态为 1，则将当前位设置为 1；
                    end
                end
            end
            values_bytes = values_bytes .. string.char(byte_value)
        end

        -- 构建数据部分（起始地址 + 数量 + 字节数 + 线圈数据）（字节序为大端序）；
        data_bytes = string.char(
            (config.start_addr >> 8) & 0xFF, config.start_addr & 0xFF,
            (config.reg_count >> 8) & 0xFF, config.reg_count & 0xFF,
            byte_count
        ) .. values_bytes

    -- 功能码 0x10：写入多个保持寄存器；
    elseif function_code == exmodbus_ref.WRITE_MULTIPLE_HOLDING_REGISTERS then
        -- 验证数量范围；
        if config.reg_count < 1 or config.reg_count > 123 then
            log.error("exmodbus", "寄存器写入数量超出范围: " .. config.reg_count .. " (范围: 1-123)")
            return false
        end

        -- 计算字节数；
        local byte_count = config.reg_count * 2
        local values_bytes = ""

        -- 构建寄存器数据（字节序为大端序）；
        for i = 0, config.reg_count - 1 do
            local addr = config.start_addr + i
            local value = config.data[addr]
            values_bytes = values_bytes .. string.char(
                (value >> 8) & 0xFF, value & 0xFF
            )
        end

        -- 构建数据部分（起始地址 + 数量 + 字节数 + 寄存器数据）（字节序为大端序）；
        data_bytes = string.char(
            (config.start_addr >> 8) & 0xFF, config.start_addr & 0xFF,
            (config.reg_count >> 8) & 0xFF, config.reg_count & 0xFF,
            byte_count
        ) .. values_bytes

    -- 未知功能码；
    else
        log.error("exmodbus", "不支持的功能码构建: " .. function_code)
        return false
    end

    -- 构建 Modbus RTU 帧（从站地址 + 功能码 + 数据）；
    local frame = string.char(config.slave_id, function_code) .. data_bytes

    -- 计算 CRC16 校验并添加到帧末尾（小端序）；
    local crc = crypto.crc16_modbus(frame)
    frame = frame .. string.char(crc & 0xFF, (crc >> 8) & 0xFF)

    return frame, function_code
end

-- 发送 Modbus 请求并等待响应；
local function sendRequest_waitResponse(instance, request_frame, config)
    -- 生成唯一请求ID；
    local req_id = gen_id_func()
    instance.current_wait_request_id = req_id

    -- 执行发送请求；
    uart.write(instance.uart_id, request_frame)

    -- 等待发送完成；
    local sent_ok = sys.waitUntil("exmodbus/sent/" .. instance.uart_id, 200)
    if not sent_ok then
        log.error("exmodbus", "数据发送失败")
        instance.current_wait_request_id = nil
        return false, nil
    end

    -- -- 显示发送的HEX数据；
    -- local hex_str = ""
    -- for i = 1, #request_frame do
    --     hex_str = hex_str .. string.format("%02X ", string.byte(request_frame, i))
    -- end
    -- log.info("exmodbus", "发送请求命令成功, HEX: " .. hex_str:sub(1, -2))

    -- 等待接收响应；
    local ok, response = sys.waitUntil("exmodbus/rtu_resp/" .. req_id, config.timeout or 1000)

    -- 清除当前等待的请求ID；
    instance.current_wait_request_id = nil

    -- 显示接收的HEX数据；
    if ok then
        -- hex_str = ""
        -- for i = 1, #response do
        --     hex_str = hex_str .. string.format("%02X ", string.byte(response, i))
        -- end
        -- log.info("exmodbus", "接收响应成功, HEX: " .. hex_str:sub(1, -2))
        return true, response
    else
        -- log.error("exmodbus", "接收响应失败或超时")
        return false, nil
    end
end

-- 解析 Modbus RTU 响应报文（主站使用）；
local function parse_rtu_response(response, config, function_code)
    -- 定义返回数据结构；
    local return_data = {
        status = false,
        execption_code = nil,
        data = {},
    }

    -- 验证响应是否为空；
    if not response or #response == 0 then
        log.error("exmodbus", "响应报文为空")
        return_data.status = exmodbus_ref.STATUS_DATA_INVALID
        return return_data
    end

    -- 验证响应长度（最小长度：从站地址 + 功能码 + CRC = 4 字节）；
    if not response or #response < 4 then
        log.error("exmodbus", "响应报文长度不足")
        return_data.status = exmodbus_ref.STATUS_DATA_INVALID
        return return_data
    end

    -- 提取响应中的字段；
    local actual_slave_id = string.byte(response, 1)
    local actual_function_code = string.byte(response, 2)
    local response_length = #response

    -- 验证从站地址是否匹配；
    if actual_slave_id ~= config.slave_id then
        log.error("exmodbus", "从站地址不匹配，期望:", config.slave_id, "实际:", actual_slave_id)
        return_data.status = exmodbus_ref.STATUS_DATA_INVALID
        return return_data
    end

    -- 检查是否为异常响应（功能码最高位为 1）；
    if bit.band(actual_function_code, 0x80) ~= 0 then
        -- 异常响应格式：从站地址(1 字节) + 功能码(1 字节) + 异常码(1 字节) + CRC(2 字节)；
        if response_length ~= 5 then
            log.error("exmodbus", "异常响应报文长度不正确，期望: 5 字节，实际:", response_length, "字节")
            return_data.status = exmodbus_ref.STATUS_DATA_INVALID
            return return_data
        end

        -- 提取异常码（第 3 字节）；
        local exception_code = string.byte(response, 3)
        log.error("exmodbus", "接收到 Modbus 异常响应，功能码:", actual_function_code, "异常码:", exception_code)

        return_data.status = exmodbus_ref.STATUS_EXCEPTION
        return_data.execption_code = exception_code
        return return_data
    end

    -- 验证功能码是否匹配；
    if actual_function_code ~= function_code then
        log.error("exmodbus", "功能码不匹配，期望:", function_code, "实际:", actual_function_code)
        return_data.status = exmodbus_ref.STATUS_DATA_INVALID
        return return_data
    end

    -- 根据不同的功能码解析数据；
    local parsed_data = {}

    -- 功能码 0x01 和 0x02：读取线圈状态和离散输入状态；
    if function_code == exmodbus_ref.READ_COILS or function_code == exmodbus_ref.READ_DISCRETE_INPUTS then
        -- 提取数据部分（不包括CRC）；
        local data_length = string.byte(response, 3)
        local data_start_pos = 4
        local data_end_pos = response_length - 2 -- 减去CRC长度

        -- 验证数据长度是否正确；
        -- 注意：这里只验证响应报文中声明的数据长度与实际数据长度是否一致；
        if data_end_pos - data_start_pos + 1 ~= data_length then
            log.error("exmodbus", "数据长度不匹配，期望:", data_length, "实际:", data_end_pos - data_start_pos + 1)
            return_data.status = exmodbus_ref.STATUS_DATA_INVALID
            return return_data
        end

        -- 验证字节数是否足够表示指定数量的位；
        local expected_bytes = math.ceil(config.reg_count / 8)
        if data_length < expected_bytes then
            log.error("exmodbus", "数据字节数不足，无法表示所有位")
            return_data.status = exmodbus_ref.STATUS_DATA_INVALID
            return return_data
        end

        -- 解析位数据；
        for i = 0, config.reg_count - 1 do
            local modbus_addr = config.start_addr + i           -- 计算当前位对应的 Modbus 地址；
            local byte_pos = data_start_pos + math.floor(i / 8) -- 计算当前位对应的字节位置；
            local bit_pos = i % 8                               -- 计算当前位对应的位位置；
            local byte_value = string.byte(response, byte_pos)
            parsed_data[modbus_addr] = bit.band(byte_value, bit.lshift(1, bit_pos)) ~= 0 and 1 or 0
        end

    -- 功能码 0x03 和 0x04：读取保持寄存器和输入寄存器；
    elseif function_code == exmodbus_ref.READ_HOLDING_REGISTERS or function_code == exmodbus_ref.READ_INPUT_REGISTERS then
        -- 提取数据部分（不包括CRC）；
        local data_length = string.byte(response, 3)
        local data_start_pos = 4
        local data_end_pos = response_length - 2 -- 减去CRC长度

        -- 验证数据长度是否正确；
        if data_end_pos - data_start_pos + 1 ~= data_length then
            log.error("exmodbus", "数据长度不匹配，期望:", data_length, "实际:", data_end_pos - data_start_pos + 1)
            return_data.status = exmodbus_ref.STATUS_DATA_INVALID
            return return_data
        end

        -- 验证字节数是否足够表示指定数量的寄存器；
        local expected_bytes = config.reg_count * 2
        if data_length < expected_bytes then
            log.error("exmodbus", "数据字节数不足，无法表示所有寄存器")
            return_data.status = exmodbus_ref.STATUS_DATA_INVALID
            return return_data
        end

        -- 解析寄存器数据（大端序）；
        for i = 0, config.reg_count - 1 do
            local modbus_addr = config.start_addr + i -- 计算当前寄存器对应的 Modbus 地址；
            local reg_pos = data_start_pos + i * 2    -- 计算当前寄存器对应的字节位置；
            parsed_data[modbus_addr] = bit.lshift(string.byte(response, reg_pos), 8) + string.byte(response, reg_pos + 1)
        end

    -- 功能码 0x05：写入单个线圈；
    elseif function_code == exmodbus_ref.WRITE_SINGLE_COIL then
        -- 写入单个线圈响应格式：从站地址(1 字节) + 功能码(1 字节) + 线圈地址(2 字节) + 线圈值(2 字节) + CRC(2 字节)；
        if response_length ~= 8 then
            log.error("exmodbus", "写入单个线圈响应报文长度不正确")
            return_data.status = exmodbus_ref.STATUS_DATA_INVALID
            return return_data
        end

        -- 解析线圈地址和值；
        local coil_addr = bit.lshift(string.byte(response, 3), 8) + string.byte(response, 4)
        local coil_value = bit.lshift(string.byte(response, 5), 8) + string.byte(response, 6)

        -- 验证地址是否匹配请求；
        if config.start_addr and coil_addr ~= config.start_addr then
            log.error("exmodbus", "线圈地址不匹配，期望:", config.start_addr, "实际:", coil_addr)
            return_data.status = exmodbus_ref.STATUS_DATA_INVALID
            return return_data
        end

        -- 线圈值应该是 0x0000(OFF) 或 0xFF00(ON)；
        local normalized_value = (coil_value == 0x0000) and 0 or 1
        parsed_data[coil_addr] = normalized_value

    -- 功能码 0x06：写入单个保持寄存器；
    elseif function_code == exmodbus_ref.WRITE_SINGLE_HOLDING_REGISTER then
        -- 写入单个保持寄存器响应格式：从站地址(1 字节) + 功能码(1 字节) + 寄存器地址(2 字节) + 寄存器值(2 字节) + CRC(2 字节)；
        if response_length ~= 8 then
            log.error("exmodbus", "写入单个保持寄存器响应报文长度不正确")
            return_data.status = exmodbus_ref.STATUS_DATA_INVALID
            return return_data
        end

        -- 解析寄存器地址和值；
        local reg_addr = bit.lshift(string.byte(response, 3), 8) + string.byte(response, 4)
        local reg_value = bit.lshift(string.byte(response, 5), 8) + string.byte(response, 6)

        -- 验证地址是否匹配请求；
        if config.start_addr and reg_addr ~= config.start_addr then
            log.error("exmodbus", "单个保持寄存器地址不匹配，期望:", config.start_addr, "实际:", reg_addr)
            return_data.status = exmodbus_ref.STATUS_DATA_INVALID
            return return_data
        end

        parsed_data[reg_addr] = reg_value

    -- 功能码 0x0F：写入多个线圈；
    elseif function_code == exmodbus_ref.WRITE_MULTIPLE_COILS then
        -- 写入多个线圈响应格式：从站地址(1 字节) + 功能码(1 字节) + 起始地址(2 字节) + 线圈数量(2 字节) + CRC(2 字节)；
        if response_length ~= 8 then
            log.error("exmodbus", "写入多个线圈响应报文长度不正确")
            return_data.status = exmodbus_ref.STATUS_DATA_INVALID
            return return_data
        end

        -- 解析起始地址和线圈数量；
        local start_addr = bit.lshift(string.byte(response, 3), 8) + string.byte(response, 4)
        local coil_count = bit.lshift(string.byte(response, 5), 8) + string.byte(response, 6)

        -- 验证地址和数量是否匹配请求；
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

        -- 在返回数据中记录操作成功的起始地址和数量；
        parsed_data.start_addr = start_addr
        parsed_data.count = coil_count

    -- 功能码 0x10：写入多个保持寄存器；
    elseif function_code == exmodbus_ref.WRITE_MULTIPLE_HOLDING_REGISTERS then
        -- 写入多个保持寄存器响应格式：从站地址(1 字节) + 功能码(1 字节) + 起始地址(2 字节) + 寄存器数量(2 字节) + CRC(2 字节)；
        if response_length ~= 8 then
            log.error("exmodbus", "写入多个保持寄存器响应报文长度不正确")
            return_data.status = exmodbus_ref.STATUS_DATA_INVALID
            return return_data
        end

        -- 解析起始地址和寄存器数量；
        local start_addr = bit.lshift(string.byte(response, 3), 8) + string.byte(response, 4)
        local reg_count = bit.lshift(string.byte(response, 5), 8) + string.byte(response, 6)

        -- 验证地址和数量是否匹配请求；
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

        -- 在返回数据中记录操作成功的起始地址和数量；
        parsed_data.start_addr = start_addr
        parsed_data.count = reg_count

    -- 未知功能码；
    else
        log.error("exmodbus", "不支持的功能码解析:", function_code)
        return_data.status = exmodbus_ref.STATUS_DATA_INVALID
        return return_data
    end

    -- 成功解析响应数据；
    -- log.info("exmodbus", "响应解析成功，功能码:", function_code, "数据:", json.encode(parsed_data))
    return_data.status = exmodbus_ref.STATUS_SUCCESS
    return_data.data = parsed_data
    return return_data
end

-- 主站读取请求函数；（内部使用）
function modbus:read_internal(config)
    -- 处理响应结果；
    local parsed_data = {}

    -- 检查通信模式是否有效；
    if self.mode == exmodbus_ref.RTU_MASTER then

        -- 检查是否同时指定了 slave_id 和 raw_request；
        if config.slave_id and config.raw_request then
            log.error("exmodbus", "禁止同时指定 slave_id 和 raw_request")
            return false
        end

        -- 用户传入字段式请求帧；
        if config.slave_id then
            -- 构建 Modbus RTU 帧；
            local request_frame, function_code = build_rtu_frame("read", config)
            if not request_frame then
                parsed_data.status = exmodbus_ref.STATUS_DATA_INVALID
                return parsed_data
            end

            -- 发送请求并等待响应；
            local result, response = sendRequest_waitResponse(self, request_frame, config)
            if not result then
                parsed_data.status = exmodbus_ref.STATUS_TIMEOUT
            else
                -- 解析响应数据；
                parsed_data = parse_rtu_response(response, config, function_code)
            end

        -- 用户传入原始请求帧；
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
    else
        log.error("exmodbus", "通信模式不支持")
        return false
    end
end

-- 主站写入请求的函数；
function modbus:write_internal(config)

    -- 处理响应结果；
    local parsed_data = {}

    -- 检查通信模式是否有效；
    if self.mode == exmodbus_ref.RTU_MASTER then

        -- 检查是否同时指定了 slave_id 和 raw_request；
        if config.slave_id and config.raw_request then
            log.error("exmodbus", "禁止同时指定 slave_id 和 raw_request")
            return false
        end

        -- 用户传入字段式请求帧；
        if config.slave_id then
            -- 构建 Modbus RTU 帧；
            local request_frame, function_code = build_rtu_frame("write", config)
            if not request_frame then
                parsed_data.status = exmodbus_ref.STATUS_DATA_INVALID
                return parsed_data
            end

            -- 发送请求并等待响应；
            local result, response = sendRequest_waitResponse(self, request_frame, config)
            if not result then
                -- log.error("exmodbus", "接收响应失败或超时")
                parsed_data.status = exmodbus_ref.STATUS_TIMEOUT
            else
                -- 解析响应数据；
                parsed_data = parse_rtu_response(response, config, function_code)
            end

        -- 用户传入原始请求帧；
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
    else
        log.error("exmodbus", "通信模式不支持")
        return false
    end
end

-- 主站读取请求的函数；
function modbus:read(config)
    return exmodbus_ref.enqueue_request(self, config, true)
end

-- 主站写入请求的函数；
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
