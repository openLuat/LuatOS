--[[
@module  modbus_tcp_slave
@summary TCP 从站应用模块
@version 1.0
@date    2026.05.11
@author  马梦阳
@usage
本模块实现 TCP 从站功能：
1、作为 Modbus TCP 从站响应主站请求
2、维护线圈、离散输入、保持寄存器、输入寄存器数据
3、通过事件机制与上层模块通信
]]

local modbus_tcp_slave = {}

local exmodbus = require("exmodbus")

-- 任务名称（用于日志）
local TASK_NAME = "modbus_tcp_slave"
-- 实例字典（key=port_type, value=instance）
local instances = {}
-- 配置文件路径
local CONFIG_FILE = "/modbus_tcp_config.json"
-- 默认配置参数
local DEFAULT_CONFIG = {
    self_addr = 1,
    listen_port = 502
}

--=========================================
-- 寄存器注册表（地址 -> {name, value}）
--=========================================
local registered_registers = {}

--[[
@function modbus_tcp_slave.add_register
@summary 注册寄存器
@param addr number 寄存器地址
@param name string 功能名称
@param value number 初始值
]]
function modbus_tcp_slave.add_register(addr, name, value)
    registered_registers[addr] = {
        name = name,
        value = value or 0
    }
end

--[[
@function modbus_tcp_slave.remove_register
@summary 移除寄存器
@param addr number 寄存器地址
]]
function modbus_tcp_slave.remove_register(addr)
    registered_registers[addr] = nil
end

--[[
@function modbus_tcp_slave.get_register_value
@summary 获取寄存器值（读取时调用）
@param addr number 寄存器地址
@return number 寄存器值
]]
function modbus_tcp_slave.get_register_value(addr)
    local reg = registered_registers[addr]
    return reg and reg.value or 0
end

--[[
@function modbus_tcp_slave.set_register_value
@summary 设置寄存器值（写入时调用）
@param addr number 寄存器地址
@param value number 寄存器值
]]
function modbus_tcp_slave.set_register_value(addr, value)
    if registered_registers[addr] then
        registered_registers[addr].value = value
        sys.publish("modbus_register_update", {port_type = "tcp_slave", addr = addr, value = value})
    end
end

--[[
@function modbus_tcp_slave.format_hex_raw
@summary 格式化原始数据为十六进制字符串
@param data table|string 原始数据
@return string 格式化后的十六进制字符串
]]
function modbus_tcp_slave.format_hex_raw(data)
    if not data then
        return ""
    elseif data == "" then
        return ""
    elseif type(data) == "string" then
        local t = {}
        for i = 1, #data do
            t[i] = string.format("%02X", string.byte(data, i))
        end
        return table.concat(t, " ")
    elseif type(data) == "table" then
        local t = {}
        for i, v in ipairs(data) do
            t[i] = string.format("%02X", v)
        end
        return table.concat(t, " ")
    else
        return tostring(data)
    end
end

--[[
@function modbus_tcp_slave.start
@summary 启动TCP从站
@param port_type string 端口类型
@return boolean, string|nil 是否启动成功及错误原因
]]
function modbus_tcp_slave.start(port_type)
    if instances[port_type] then
        log.warn(TASK_NAME, "instance already exists", port_type)
        return false, "instance_already_exists"
    end

    local config = modbus_tcp_slave.get_config()

    log.info(TASK_NAME, "starting", "port=" .. port_type, "listen_port=" .. (config.listen_port or 502), "addr=" .. config.self_addr)

    local tcp_config = {
        mode = exmodbus.TCP_SLAVE,
        adapter = socket.LWIP_STA,
        port = config.listen_port or 502,
    }

    local modbus = exmodbus.create(tcp_config)
    if not modbus then
        log.error(TASK_NAME, "exmodbus create failed")
        return false, "exmodbus_create_failed"
    end
    log.info(TASK_NAME, "exmodbus created successfully")

    local instance = {
        running = true,
        modbus = modbus,
    }

    local self_addr = config.self_addr

    --[[
    @function build_request_frame
    @summary 内部函数：构建请求帧
    ]]
    local function build_request_frame(request)
        local frame = string.pack(">I2", request.transaction_id)
            .. string.pack(">I2", request.protocol_id)
            .. string.pack(">I2", request.length)
            .. string.char(request.slave_id, request.func_code)
        if request.func_code == 0x03 or request.func_code == 0x04 then
            frame = frame .. string.pack(">I2", request.start_addr) .. string.pack(">I2", request.reg_count)
        elseif request.func_code == 0x06 then
            frame = frame .. string.pack(">I2", request.start_addr) .. string.pack(">I2", request.data[request.start_addr])
        elseif request.func_code == 0x10 then
            frame = frame .. string.pack(">I2", request.start_addr) .. string.pack(">I2", request.reg_count)
        end
        return frame
    end

    local function build_response_frame(func_code, data, reg_count, start_addr)
        local body = string.char(self_addr, func_code)
        if func_code == 0x01 or func_code == 0x02 then
            -- 读线圈(01)/离散输入(02)：位操作
            local byte_count = math.ceil(reg_count / 8)
            body = body .. string.char(byte_count)
            local byte_val = 0
            for i = 0, reg_count - 1 do
                local addr = start_addr + i
                if data[addr] and data[addr] ~= 0 then
                    byte_val = byte_val | (1 << (i % 8))
                end
            end
            body = body .. string.char(byte_val)
        elseif func_code == 0x03 or func_code == 0x04 then
            body = body .. string.char(reg_count * 2)
            for i = 0, reg_count - 1 do
                local addr = start_addr + i
                body = body .. string.pack(">I2", data[addr] or 0)
            end
        elseif func_code == 0x06 then
            body = body .. string.pack(">I2", start_addr) .. string.pack(">I2", data[start_addr] or 0)
        elseif func_code == 0x10 then
            body = body .. string.pack(">I2", start_addr) .. string.pack(">I2", reg_count)
        end
        return body
    end

    local function callback(request)
        if request.slave_id ~= self_addr then
            return nil
        end

        local rx_frame = build_request_frame(request)
        local rx_hex = modbus_tcp_slave.format_hex_raw(rx_frame)
        log.info(TASK_NAME, "RX", rx_hex)
        sys.publish("modbus_log", {port_type = "tcp_slave", message = "[RX] " .. rx_hex})

        local is_write = false

        -- 判断是否为写操作
        if request.func_code == exmodbus.WRITE_SINGLE_COIL or request.func_code == exmodbus.WRITE_MULTIPLE_COILS then
            is_write = true
        elseif request.func_code == exmodbus.WRITE_SINGLE_HOLDING_REGISTER or request.func_code == exmodbus.WRITE_MULTIPLE_HOLDING_REGISTERS then
            is_write = true
        elseif request.func_code == exmodbus.READ_COILS
            or request.func_code == exmodbus.READ_DISCRETE_INPUTS
            or request.func_code == exmodbus.READ_HOLDING_REGISTERS
            or request.func_code == exmodbus.READ_INPUT_REGISTERS then
            is_write = false
        else
            log.warn(TASK_NAME, "unsupported func_code", request.func_code)
            return exmodbus.ILLEGAL_FUNCTION
        end

        if not is_write then
            -- 读取操作：根据功能码转换地址
            local base_addr = 1
            if request.func_code == exmodbus.READ_COILS then
                base_addr = 1  -- 线圈 00001-09999
            elseif request.func_code == exmodbus.READ_DISCRETE_INPUTS then
                base_addr = 10001  -- 离散输入 10001-19999
            elseif request.func_code == exmodbus.READ_HOLDING_REGISTERS then
                base_addr = 40001  -- 保持寄存器 40001-49999
            elseif request.func_code == exmodbus.READ_INPUT_REGISTERS then
                base_addr = 30001  -- 输入寄存器 30001-39999
            end

            -- 检查所有请求的地址是否都已注册
            for i = 0, request.reg_count - 1 do
                local absolute_addr = base_addr + request.start_addr + i
                if not registered_registers[absolute_addr] then
                    log.warn(TASK_NAME, "地址未注册", absolute_addr)
                    return exmodbus.ILLEGAL_DATA_ADDRESS
                end
            end

            local response = {}
            for i = 0, request.reg_count - 1 do
                local relative_addr = request.start_addr + i
                local absolute_addr = base_addr + relative_addr
                response[relative_addr] = modbus_tcp_slave.get_register_value(absolute_addr)
            end
            log.info(TASK_NAME, "read success", "addr=" .. request.start_addr, "count=" .. request.reg_count)

            local tx_frame = build_response_frame(request.func_code, response, request.reg_count, request.start_addr)
            local tx_hex = modbus_tcp_slave.format_hex_raw(tx_frame)
            log.info(TASK_NAME, "TX", tx_hex)
            sys.publish("modbus_log", {port_type = "tcp_slave", message = "[TX] " .. tx_hex})

            local event_data = {
                slave = self_addr,
                func_code = request.func_code,
                start_addr = request.start_addr,
                reg_count = request.reg_count,
                data = response,
            }
            sys.publish("modbus_data_update", {port_type = "tcp_slave", data = event_data})

            return response
        end

        if is_write then
            -- 写入操作：根据功能码转换地址
            local base_addr = 1
            if request.func_code == exmodbus.WRITE_SINGLE_COIL or request.func_code == exmodbus.WRITE_MULTIPLE_COILS then
                base_addr = 1  -- 线圈 00001-09999
            elseif request.func_code == exmodbus.WRITE_SINGLE_HOLDING_REGISTER or request.func_code == exmodbus.WRITE_MULTIPLE_HOLDING_REGISTERS then
                base_addr = 40001  -- 保持寄存器 40001-49999
            end

            -- 检查所有请求的地址是否都已注册
            for i = 0, request.reg_count - 1 do
                local absolute_addr = base_addr + request.start_addr + i
                if not registered_registers[absolute_addr] then
                    log.warn(TASK_NAME, "地址未注册", absolute_addr)
                    return exmodbus.ILLEGAL_DATA_ADDRESS
                end
            end

            for i = 0, request.reg_count - 1 do
                local relative_addr = request.start_addr + i
                local absolute_addr = base_addr + relative_addr
                local value = request.data[relative_addr]
                modbus_tcp_slave.set_register_value(absolute_addr, value)
                log.info(TASK_NAME, "write success", "addr=" .. absolute_addr, "val=" .. value)
            end

            local tx_frame = build_response_frame(request.func_code, request.data, request.reg_count, request.start_addr)
            local tx_hex = modbus_tcp_slave.format_hex_raw(tx_frame)
            log.info(TASK_NAME, "TX", tx_hex)
            sys.publish("modbus_log", {port_type = "tcp_slave", message = "[TX] " .. tx_hex})

            local event_data = {
                slave = self_addr,
                func_code = request.func_code,
                start_addr = request.start_addr,
                reg_count = request.reg_count,
                data = request.data,
            }

            sys.publish("modbus_data_update", {port_type = "tcp_slave", data = event_data})

            return {}
        end
    end

    modbus:on(callback)

    instances[port_type] = instance

    log.info(TASK_NAME, "TCP Slave running, addr=" .. config.self_addr)

    return true, nil
end

--[[
@function modbus_tcp_slave.stop
@summary 停止TCP从站
@param port_type string 端口类型
@return boolean, string|nil 是否停止成功及错误原因
]]
function modbus_tcp_slave.stop(port_type)
    local instance = instances[port_type]
    if not instance then
        log.warn(TASK_NAME, "instance not found", port_type)
        return false, "instance_not_found"
    end

    log.info(TASK_NAME, "stopping", port_type)
    instance.running = false

    if instance.modbus then
        instance.modbus:destroy()
        instance.modbus = nil
    end

    instances[port_type] = nil
    log.info(TASK_NAME, "stopped", port_type)
    return true, nil
end

--[[
@function modbus_tcp_slave.get_config
@summary 获取配置
@return table 配置表
]]
function modbus_tcp_slave.get_config()
    if not io.exists(CONFIG_FILE) then
        log.info(TASK_NAME, "配置文件不存在，使用默认配置")
        return DEFAULT_CONFIG
    end

    local file = io.open(CONFIG_FILE, "r")
    if not file then
        log.error(TASK_NAME, "读取配置文件失败：无法打开文件")
        return DEFAULT_CONFIG
    end

    local content = file:read("*a")
    file:close()

    local config = json.decode(content)
    return config or DEFAULT_CONFIG
end


--[[
@function modbus_tcp_slave.save_config
@summary 保存配置（支持部分更新）
@param config table 配置表，支持完整配置或部分字段更新
@return boolean 是否保存成功
]]
function modbus_tcp_slave.save_config(config)
    local existing_config = modbus_tcp_slave.get_config()
    
    for key, value in pairs(config) do
        existing_config[key] = value
    end
    
    local file = io.open(CONFIG_FILE, "wb")
    if not file then
        log.error(TASK_NAME, "保存配置失败：无法打开文件")
        return false
    end

    local content = json.encode(existing_config)
    file:write(content)
    file:close()

    log.info(TASK_NAME, "配置已保存")
    return true
end

return modbus_tcp_slave
