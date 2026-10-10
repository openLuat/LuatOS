--[[
@module  modbus_app
@summary Modbus统一调度模块（完整版）
@version 2.0
@date    2026.09.04
@author  江访
@usage
支持 RS485 主站/从站两种模式，通过配置热切换。
- 主站：自定义hex帧轮询，支持 FC 02/03/04/05/06，CRC校验，响应解析
- 从站：维护内存寄存器表，支持全部标准功能码：
  FC01 读线圈 / FC02 读离散输入 / FC03 读保持寄存器 / FC04 读输入寄存器
  FC05 写单个线圈 / FC06 写单个寄存器 / FC15 写多个线圈 / FC16 写多个寄存器
- 所有端口通过 rs485_app 的消息机制通信，避免 airlink RPC 限制
]]

local modbus_app = {}

local TASK_NAME = "modbus_app"

-- 配置引用
local g_config = nil

-- 当前活跃的子模块
local active_mode = nil
local active_port = nil

-- ==================== CRC16 查表 ====================

local CRC16_TB = {}
do
    for i = 0, 255 do
        local crc = i
        for _ = 1, 8 do
            if crc & 1 == 1 then
                crc = (crc >> 1) ~ 0xA001
            else
                crc = crc >> 1
            end
        end
        CRC16_TB[i] = crc & 0xFFFF
    end
end

--[[
@function crc16
@summary CRC16 Modbus 校验（查表法）
@param data string 字节串
@return number 16位CRC值
]]
local function crc16(data)
    local crc = 0xFFFF
    for i = 1, #data do
        crc = (crc >> 8) ~ CRC16_TB[(crc ~ data:byte(i)) & 0xFF]
    end
    return crc & 0xFFFF
end

--[[
@function format_hex_raw
@summary 格式化原始数据为十六进制字符串
@param data string 原始字节串
@return string 格式化后的十六进制字符串，如 "01 03 00 CD"
]]
function modbus_app.format_hex_raw(data)
    if not data or data == "" then return "" end
    local t = {}
    for i = 1, #data do
        t[i] = string.format("%02X", data:byte(i))
    end
    return table.concat(t, " ")
end

-- ==================== RS485 主站 ====================

local master_running = false
local master_results = {}

--[[
@function hex_to_bytes
@summary 十六进制字符串转字节串
@param hex_str string 如 "010300CD0004"
@return string 字节串
]]
local function hex_to_bytes(hex_str)
    if not hex_str or #hex_str % 2 ~= 0 then return "" end
    local t = {}
    for i = 1, #hex_str, 2 do
        t[#t + 1] = string.char(tonumber(hex_str:sub(i, i + 1), 16))
    end
    return table.concat(t)
end

--[[
@function master_parse_response
@summary 解析主站响应：CRC校验 + 按功能码提取数据
@param raw string 原始响应字节串
@return table|nil 解析结果 {hex, func_code, data, byte_count} 或 nil
]]
local function master_parse_response(raw)
    if not raw or #raw < 5 then return nil end

    local hex = modbus_app.format_hex_raw(raw)

    -- CRC 校验
    local body = raw:sub(1, -3)
    local recv_crc = raw:byte(-2) | (raw:byte(-1) << 8)
    local calc_crc = crc16(body)
    if calc_crc ~= recv_crc then
        log.warn(TASK_NAME, "master CRC error", string.format("%04X!=%04X", calc_crc, recv_crc))
        return nil
    end

    local func_code = raw:byte(2)
    local result = {
        hex = hex,
        func_code = func_code,
        data = {},
        byte_count = 0,
    }

    if func_code == 0x02 or func_code == 0x01 then
        -- 读离散输入/线圈：字节位打包
        local byte_count = raw:byte(3)
        result.byte_count = byte_count
        for b = 1, byte_count do
            local byte_val = raw:byte(3 + b)
            for bit = 0, 7 do
                result.data[#result.data + 1] = (byte_val >> bit) & 1
            end
        end
    elseif func_code == 0x03 or func_code == 0x04 then
        -- 读保持/输入寄存器：大端16位
        local byte_count = raw:byte(3)
        result.byte_count = byte_count
        for i = 0, byte_count - 1, 2 do
            local val = (raw:byte(4 + i) << 8) | raw:byte(5 + i)
            result.data[#result.data + 1] = val
        end
    elseif func_code == 0x05 or func_code == 0x06 then
        -- 写单个线圈/寄存器：回显
        local addr = (raw:byte(3) << 8) | raw:byte(4)
        local val = (raw:byte(5) << 8) | raw:byte(6)
        result.data = {addr = addr, value = val}
    elseif func_code == 0x0F or func_code == 0x10 then
        -- 写多个线圈/寄存器：起始地址 + 数量
        local addr = (raw:byte(3) << 8) | raw:byte(4)
        local count = (raw:byte(5) << 8) | raw:byte(6)
        result.data = {addr = addr, count = count}
    else
        -- 异常响应：功能码最高位置1
        local ex_code = raw:byte(3)
        log.warn(TASK_NAME, "master exception", string.format("FC=0x%02X code=%d", func_code, ex_code))
        result.data = {exception = ex_code}
    end

    return result
end

--[[
@function master_poll_task
@summary 主站轮询协程：遍历配置帧，发送并等待响应
]]
local function master_poll_task()
    local modbus_cfg = g_config and g_config.uart and g_config.uart.modbus
    if not modbus_cfg or not modbus_cfg.frames or #modbus_cfg.frames == 0 then
        log.warn(TASK_NAME, "master: no frames configured")
        return
    end

    local poll_interval = modbus_cfg.poll_interval or 1000

    master_running = true
    log.info(TASK_NAME, "master poll started", "port:", active_port, "interval:", poll_interval, "frames:", #modbus_cfg.frames)

    while master_running do
        for _, frame_hex in ipairs(modbus_cfg.frames) do
            if not master_running then break end

            local frame_bin = hex_to_bytes(frame_hex)
            if #frame_bin < 4 then
                log.warn(TASK_NAME, "invalid frame", frame_hex)
            else
                local slave_addr = frame_bin:byte(1)
                local func_code = frame_bin:byte(2)

                log.info(TASK_NAME, "TX", frame_hex:upper())
                sys.publish("modbus_log", {direction = "tx", message = "[TX] " .. frame_hex:upper()})

                -- 通过 rs485_app 发送并等待响应
                local port_num = active_port == "rs485_1" and 1 or 2
                sys.publish("RS485_SEND_REQUEST", port_num, frame_bin, poll_interval)
                local ok, _, resp_data = sys.waitUntil("RS485_SEND_RESULT", poll_interval + 500)

                if ok and resp_data then
                    local parsed = master_parse_response(resp_data)
                    if parsed then
                        log.info(TASK_NAME, "RX", parsed.hex)
                        sys.publish("modbus_log", {direction = "rx", message = "[RX] " .. parsed.hex})
                        master_results[slave_addr] = parsed
                        sys.publish("modbus_data_update", {
                            direction = "master",
                            slave = slave_addr,
                            func_code = func_code,
                            data = parsed.data,
                        })
                    else
                        log.warn(TASK_NAME, "RX parse failed")
                        sys.publish("modbus_log", {direction = "error", message = "[ERR] CRC mismatch"})
                    end
                else
                    log.warn(TASK_NAME, "timeout", string.format("FC=0x%02X", func_code))
                    sys.publish("modbus_log", {direction = "error", message = "[ERR] timeout"})
                end
            end
        end

        sys.wait(poll_interval)
    end

    log.info(TASK_NAME, "master poll stopped")
end

-- ==================== RS485 从站 ====================

local slave_running = false

-- 从站寄存器表（0~9999 地址范围）
local slave_registers = {
    coils = {},            -- FC01/05/0F: 线圈（位操作，0/1）
    discrete_inputs = {},  -- FC02: 离散输入（位操作，只读）
    holding_regs = {},     -- FC03/06/10: 保持寄存器（16位，可读写）
    input_regs = {},       -- FC04: 输入寄存器（16位，只读）
}

-- 初始化默认寄存器值
local function slave_init_registers()
    for i = 0, 99 do
        slave_registers.coils[i] = 0
        slave_registers.discrete_inputs[i] = 0
        slave_registers.holding_regs[i] = 0
        slave_registers.input_regs[i] = 0
    end
    log.info(TASK_NAME, "slave registers initialized (0-99)")
end

--[[
@function slave_get_self_addr
@summary 获取从站自身地址
@return number 从站地址
]]
local function slave_get_self_addr()
    local modbus_cfg = g_config and g_config.uart and g_config.uart.modbus
    return modbus_cfg and modbus_cfg.slave_addr or 1
end

-- ==================== 从站 FC 处理函数 ====================

--[[
@function slave_handle_fc01
@summary FC01 读线圈（位操作）
@param addr number 从站地址
@param start_reg number 起始地址
@param reg_count number 数量
@return string 响应帧（含CRC）
]]
local function slave_handle_fc01(addr, start_reg, reg_count)
    if addr ~= slave_get_self_addr() then return nil end
    if reg_count < 1 or reg_count > 2000 then return nil end

    local byte_count = math.ceil(reg_count / 8)
    local resp = string.char(addr, 0x01, byte_count)

    for b = 0, byte_count - 1 do
        local byte_val = 0
        for bit = 0, 7 do
            local idx = b * 8 + bit
            if idx < reg_count then
                local reg_addr = start_reg + idx
                if slave_registers.coils[reg_addr] and slave_registers.coils[reg_addr] ~= 0 then
                    byte_val = byte_val | (1 << bit)
                end
            end
        end
        resp = resp .. string.char(byte_val)
    end

    local c = crc16(resp)
    return resp .. string.char(c & 0xFF, (c >> 8) & 0xFF)
end

--[[
@function slave_handle_fc02
@summary FC02 读离散输入（位操作，只读）
@param addr number 从站地址
@param start_reg number 起始地址
@param reg_count number 数量
@return string 响应帧（含CRC）
]]
local function slave_handle_fc02(addr, start_reg, reg_count)
    if addr ~= slave_get_self_addr() then return nil end
    if reg_count < 1 or reg_count > 2000 then return nil end

    local byte_count = math.ceil(reg_count / 8)
    local resp = string.char(addr, 0x02, byte_count)

    for b = 0, byte_count - 1 do
        local byte_val = 0
        for bit = 0, 7 do
            local idx = b * 8 + bit
            if idx < reg_count then
                local reg_addr = start_reg + idx
                if slave_registers.discrete_inputs[reg_addr] and slave_registers.discrete_inputs[reg_addr] ~= 0 then
                    byte_val = byte_val | (1 << bit)
                end
            end
        end
        resp = resp .. string.char(byte_val)
    end

    local c = crc16(resp)
    return resp .. string.char(c & 0xFF, (c >> 8) & 0xFF)
end

--[[
@function slave_handle_fc03
@summary FC03 读保持寄存器（16位，可读写）
@param addr number 从站地址
@param start_reg number 起始地址
@param reg_count number 数量
@return string 响应帧（含CRC）
]]
local function slave_handle_fc03(addr, start_reg, reg_count)
    if addr ~= slave_get_self_addr() then return nil end
    if reg_count < 1 or reg_count > 125 then return nil end

    local resp = string.char(addr, 0x03, reg_count * 2)
    for i = 0, reg_count - 1 do
        local val = slave_registers.holding_regs[start_reg + i] or 0
        resp = resp .. string.char((val >> 8) & 0xFF, val & 0xFF)
    end
    local c = crc16(resp)
    return resp .. string.char(c & 0xFF, (c >> 8) & 0xFF)
end

--[[
@function slave_handle_fc04
@summary FC04 读输入寄存器（16位，只读）
@param addr number 从站地址
@param start_reg number 起始地址
@param reg_count number 数量
@return string 响应帧（含CRC）
]]
local function slave_handle_fc04(addr, start_reg, reg_count)
    if addr ~= slave_get_self_addr() then return nil end
    if reg_count < 1 or reg_count > 125 then return nil end

    local resp = string.char(addr, 0x04, reg_count * 2)
    for i = 0, reg_count - 1 do
        local val = slave_registers.input_regs[start_reg + i] or 0
        resp = resp .. string.char((val >> 8) & 0xFF, val & 0xFF)
    end
    local c = crc16(resp)
    return resp .. string.char(c & 0xFF, (c >> 8) & 0xFF)
end

--[[
@function slave_handle_fc05
@summary FC05 写单个线圈
@param addr number 从站地址
@param coil_addr number 线圈地址
@param coil_value number 线圈值（0xFF00=ON, 0x0000=OFF）
@return string 响应帧（回显请求）
]]
local function slave_handle_fc05(addr, coil_addr, coil_value)
    if addr ~= slave_get_self_addr() then return nil end

    local value = (coil_value == 0xFF00) and 1 or 0
    slave_registers.coils[coil_addr] = value
    log.info(TASK_NAME, "slave FC05", "coil:", coil_addr, "val:", value)

    sys.publish("modbus_data_update", {type = "coil", reg = coil_addr, value = value})

    -- 回显请求帧
    local resp = string.char(addr, 0x05,
        (coil_addr >> 8) & 0xFF, coil_addr & 0xFF,
        (coil_value >> 8) & 0xFF, coil_value & 0xFF)
    local c = crc16(resp)
    return resp .. string.char(c & 0xFF, (c >> 8) & 0xFF)
end

--[[
@function slave_handle_fc06
@summary FC06 写单个保持寄存器
@param addr number 从站地址
@param reg number 寄存器地址
@param value number 寄存器值
@return string 响应帧（回显请求）
]]
local function slave_handle_fc06(addr, reg, value)
    if addr ~= slave_get_self_addr() then return nil end

    slave_registers.holding_regs[reg] = value
    log.info(TASK_NAME, "slave FC06", "reg:", reg, "val:", value)

    sys.publish("modbus_data_update", {type = "holding", reg = reg, value = value})

    local resp = string.char(addr, 0x06,
        (reg >> 8) & 0xFF, reg & 0xFF,
        (value >> 8) & 0xFF, value & 0xFF)
    local c = crc16(resp)
    return resp .. string.char(c & 0xFF, (c >> 8) & 0xFF)
end

--[[
@function slave_handle_fc15
@summary FC15 写多个线圈
@param addr number 从站地址
@param start_reg number 起始地址
@param reg_count number 数量
@param data string 原始数据（字节位打包）
@return string 响应帧（含CRC）
]]
local function slave_handle_fc15(addr, start_reg, reg_count, data)
    if addr ~= slave_get_self_addr() then return nil end
    if reg_count < 1 or reg_count > 1968 then return nil end

    -- 解析位数据并写入线圈表
    for i = 0, reg_count - 1 do
        local byte_idx = math.floor(i / 8)
        local bit_idx = i % 8
        local byte_val = data:byte(byte_idx + 1) or 0
        local coil_val = (byte_val >> bit_idx) & 1
        slave_registers.coils[start_reg + i] = coil_val
    end

    log.info(TASK_NAME, "slave FC15", "start:", start_reg, "count:", reg_count)
    sys.publish("modbus_data_update", {type = "coils", start = start_reg, count = reg_count})

    -- 响应：回显地址 + 功能码 + 起始地址 + 数量
    local resp = string.char(addr, 0x0F,
        (start_reg >> 8) & 0xFF, start_reg & 0xFF,
        (reg_count >> 8) & 0xFF, reg_count & 0xFF)
    local c = crc16(resp)
    return resp .. string.char(c & 0xFF, (c >> 8) & 0xFF)
end

--[[
@function slave_handle_fc16
@summary FC16 写多个保持寄存器
@param addr number 从站地址
@param start_reg number 起始地址
@param reg_count number 数量
@param data string 原始数据（大端16位）
@return string 响应帧（含CRC）
]]
local function slave_handle_fc16(addr, start_reg, reg_count, data)
    if addr ~= slave_get_self_addr() then return nil end
    if reg_count < 1 or reg_count > 123 then return nil end

    -- 解析16位数据并写入保持寄存器表
    for i = 0, reg_count - 1 do
        local hi = data:byte(i * 2 + 1) or 0
        local lo = data:byte(i * 2 + 2) or 0
        local val = (hi << 8) | lo
        slave_registers.holding_regs[start_reg + i] = val
    end

    log.info(TASK_NAME, "slave FC16", "start:", start_reg, "count:", reg_count)
    sys.publish("modbus_data_update", {type = "holding_regs", start = start_reg, count = reg_count})

    -- 响应：回显地址 + 功能码 + 起始地址 + 数量
    local resp = string.char(addr, 0x10,
        (start_reg >> 8) & 0xFF, start_reg & 0xFF,
        (reg_count >> 8) & 0xFF, reg_count & 0xFF)
    local c = crc16(resp)
    return resp .. string.char(c & 0xFF, (c >> 8) & 0xFF)
end

--[[
@function slave_process_frame
@summary 从站帧处理：CRC校验 + 路由到对应FC处理函数
@param raw string 原始接收帧
@return string|nil 响应帧，无效帧返回 nil
]]
local function slave_process_frame(raw)
    if not raw or #raw < 4 then return nil end

    -- CRC 校验
    local body = raw:sub(1, -3)
    local recv_crc = raw:byte(-2) | (raw:byte(-1) << 8)
    local calc_crc = crc16(body)
    if calc_crc ~= recv_crc then
        log.warn(TASK_NAME, "slave CRC error")
        return nil
    end

    local addr = raw:byte(1)
    local fc = raw:byte(2)

    if fc == 0x01 then
        local start = (raw:byte(3) << 8) | raw:byte(4)
        local count = (raw:byte(5) << 8) | raw:byte(6)
        return slave_handle_fc01(addr, start, count)

    elseif fc == 0x02 then
        local start = (raw:byte(3) << 8) | raw:byte(4)
        local count = (raw:byte(5) << 8) | raw:byte(6)
        return slave_handle_fc02(addr, start, count)

    elseif fc == 0x03 then
        local start = (raw:byte(3) << 8) | raw:byte(4)
        local count = (raw:byte(5) << 8) | raw:byte(6)
        return slave_handle_fc03(addr, start, count)

    elseif fc == 0x04 then
        local start = (raw:byte(3) << 8) | raw:byte(4)
        local count = (raw:byte(5) << 8) | raw:byte(6)
        return slave_handle_fc04(addr, start, count)

    elseif fc == 0x05 then
        local coil_addr = (raw:byte(3) << 8) | raw:byte(4)
        local coil_value = (raw:byte(5) << 8) | raw:byte(6)
        return slave_handle_fc05(addr, coil_addr, coil_value)

    elseif fc == 0x06 then
        local reg = (raw:byte(3) << 8) | raw:byte(4)
        local val = (raw:byte(5) << 8) | raw:byte(6)
        return slave_handle_fc06(addr, reg, val)

    elseif fc == 0x0F then
        local start = (raw:byte(3) << 8) | raw:byte(4)
        local count = (raw:byte(5) << 8) | raw:byte(6)
        local byte_count = raw:byte(7)
        local data = raw:sub(8, 7 + byte_count)
        return slave_handle_fc15(addr, start, count, data)

    elseif fc == 0x10 then
        local start = (raw:byte(3) << 8) | raw:byte(4)
        local count = (raw:byte(5) << 8) | raw:byte(6)
        local byte_count = raw:byte(7)
        local data = raw:sub(8, 7 + byte_count)
        return slave_handle_fc16(addr, start, count, data)

    else
        log.warn(TASK_NAME, "unsupported FC", string.format("0x%02X", fc))
        -- 返回异常响应：ILLEGAL_FUNCTION
        local resp = string.char(addr, fc | 0x80, 0x01)
        local c = crc16(resp)
        return resp .. string.char(c & 0xFF, (c >> 8) & 0xFF)
    end
end

-- ==================== 统一调度 ====================

--[[
@function stop_current
@summary 停止当前活跃模式
]]
local function stop_current()
    if active_mode == "master" then
        master_running = false
    elseif active_mode == "slave" then
        slave_running = false
    end
    active_mode = nil
    active_port = nil
end

--[[
@function start_modbus
@summary 根据配置启动 Modbus 主站或从站
]]
local function start_modbus()
    local modbus_cfg = g_config and g_config.uart and g_config.uart.modbus
    if not modbus_cfg or not modbus_cfg.enable then
        log.info(TASK_NAME, "modbus disabled")
        return
    end

    stop_current()

    local mode = modbus_cfg.mode or "master"
    local port = modbus_cfg.port_type or "rs485_1"

    if mode == "master" then
        active_mode = "master"
        active_port = port
        sys.taskInit(master_poll_task)
        log.info(TASK_NAME, "modbus master started on", port)

    elseif mode == "slave" then
        active_mode = "slave"
        active_port = port
        slave_running = true
        slave_init_registers()
        log.info(TASK_NAME, "modbus slave started on", port, "addr:", modbus_cfg.slave_addr or 1)
    end

    sys.publish("modbus_status_changed", {mode = mode, port = port, running = true})
end

-- ==================== 事件订阅 ====================

local function subscribe_events()
    -- RS485 数据接收（从站处理）
    sys.subscribe("RS485_DATA_RECEIVED", function(port, data)
        if active_mode == "slave" then
            local resp = slave_process_frame(data)
            if resp then
                local rx_hex = modbus_app.format_hex_raw(data)
                local tx_hex = modbus_app.format_hex_raw(resp)
                log.info(TASK_NAME, "slave RX:", rx_hex)
                log.info(TASK_NAME, "slave TX:", tx_hex)
                sys.publish("modbus_log", {direction = "rx", port = active_port, message = "[RX] " .. rx_hex})
                sys.publish("modbus_log", {direction = "tx", port = active_port, message = "[TX] " .. tx_hex})

                -- 发回响应
                local port_num = active_port == "rs485_1" and 1 or 2
                sys.publish("RS485_SEND_REQUEST", port_num, resp)
            end
        end
    end)

    -- Modbus 状态查询
    sys.subscribe("MODBUS_QUERY", function()
        sys.publish("MODBUS_STATUS", {
            mode = active_mode,
            port = active_port,
            running = active_mode ~= nil,
            master_results = master_results,
            slave_registers = active_mode == "slave" and slave_registers or nil,
        })
    end)

    -- Modbus 寄存器写入（UI/远程）
    sys.subscribe("MODBUS_WRITE_REG", function(reg_type, reg_addr, value)
        if active_mode == "slave" then
            if reg_type == "coil" then
                slave_registers.coils[reg_addr] = value or 0
            elseif reg_type == "holding" then
                slave_registers.holding_regs[reg_addr] = value or 0
            end
            sys.publish("modbus_data_update", {type = reg_type, reg = reg_addr, value = value})
        end
    end)

    -- 配置热切换
    sys.subscribe("CONFIG_UPDATED", function(new_config)
        if new_config then
            g_config = new_config
            local modbus_cfg = new_config.uart and new_config.uart.modbus
            if modbus_cfg and modbus_cfg.enable then
                start_modbus()
            else
                stop_current()
            end
        end
    end)
end

-- ==================== 对外接口 ====================

--[[
@function modbus_app.init
@summary 初始化Modbus模块
@param config table 完整设备配置
]]
function modbus_app.init(config)
    g_config = config
    subscribe_events()
    start_modbus()
    log.info(TASK_NAME, "init done, version 2.0")
end

--[[
@function modbus_app.get_slave_regs
@summary 获取从站寄存器表引用（供 UI 或其他模块读写）
@return table {coils, discrete_inputs, holding_regs, input_regs}
]]
function modbus_app.get_slave_regs()
    return slave_registers
end

--[[
@function modbus_app.get_master_results
@summary 获取主站最近一次轮询结果
@return table {slave_addr -> {hex, func_code, data}}
]]
function modbus_app.get_master_results()
    return master_results
end

return modbus_app
