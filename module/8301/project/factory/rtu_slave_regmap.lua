--[[
@module  rtu_slave_regmap
@summary Modbus RTU/TCP从站寄存器映射表（8301出厂固件）
@version 1.1
@date    2026.09.24
@author  江访
@usage
本文件实现Modbus RTU/TCP从站功能，将所有业务数据和系统数据映射到保持寄存器中，
供电脑端Modbus RTU主站（485串口板）或TCP主站读取。

寄存器映射表：
------------------------------------------------------------------
地址      | 类型    | 数据项            | 字节数 | 来源
------------------------------------------------------------------
0x0000    | INT16   | 继电器状态位掩码   | 2      | 485继电器模块（bit0=通道0）
0x0001    | INT16   | 继电器通道0开关    | 2      | 485继电器模块（读=状态，写=开关）
0x0002    | INT16   | 继电器通道1开关    | 2      | 485继电器模块（读=状态，写=开关）
0x0003    | INT16   | 继电器通道2开关    | 2      | 485继电器模块（读=状态，写=开关）
0x0004    | INT16   | 继电器通道3开关    | 2      | 485继电器模块（读=状态，写=开关）
0x0005-06 | FLOAT   | CPU温度           | 4      | 模块内部
0x0007-08 | FLOAT   | VBAT电压          | 4      | 模块内部
0x0009-12 | STRING  | LBS纬度           | 20     | 定位模块
0x0013-1C | STRING  | LBS经度           | 20     | 定位模块
0x001D    | INT16   | 4G信号强度         | 2      | 移动网络
0x001E-29 | STRING  | 设备IMEI          | 24     | 移动网络
0x002A-37 | STRING  | SIM ICCID         | 28     | 移动网络
0x0038-39 | INT32   | 时间戳            | 4      | NTP同步
0x003A-3B | FLOAT   | 温湿度传感器-温度   | 4      | 网口TCP主站（建大仁科传感器）
0x003C-3D | FLOAT   | 温湿度传感器-湿度   | 4      | 网口TCP主站（建大仁科传感器）
------------------------------------------------------------------
控制寄存器（可写）：
0x0001~04 | INT16   | 每路继电器开关（通道0~3，最直观的写法）
                   读：返回该路当前实际状态（0=断开 / 1=接通）
                   写：0 = 断开该路；非 0（如 1）= 接通该路
0x0050    | INT16   | 继电器控制字
                   0x0000=全关 / 0xFFFF=全开
                   0x0001~0x0004=开通道N（N=1~4）
                   0x0101~0x0104=关通道N
                   0x0201~0x0204=翻转通道N
------------------------------------------------------------------

本文件是被动从站模块，内部订阅以下事件收集数据供 Modbus 主站读取：
1、sys.subscribe("RELAY_STATUS_UPDATE")       -- 继电器状态（relay_ctrl 发布）
2、sys.subscribe("Airlbs_LOCATION_UPDATE")    -- 经纬度
3、sys.subscribe("NTP_ERROR")                 -- NTP同步状态
4、sys.subscribe("TEMP_HUMIDITY_UPDATE")      -- 网口TCP主站读到的温湿度（tcp_modbus_master 发布）

对外暴露保持寄存器（0x0000~0x0050），供 RTU/TCP 主站读取与写入：
- 读：0x0000 状态位掩码、0x0001~0x0004 每路实际状态、0x0005 起的系统数据区、0x0050 控制字回读；
- 写：0x0001~0x0004 每路继电器开关（0=断开 / 非 0=接通）、0x0050 控制字（全开全关 / 单路开、关、翻转）。
]]

local exmodbus = require("exmodbus")
local relay_ctrl = require("relay_ctrl")

-- Air8301 RS485_1（UART1，隔离口）：方向脚 RE/DE = GPIO2，供电脚 GPIO29（由 board_init 拉高）
-- 注意：GPIO2 ≤ 128，由 exmodbus 内部（uart.setup 的 pin485）按普通 GPIO 手动方向控制处理
local rs485_dir_gpio = 2

-- 简化数据存储表
local sensor_data = {
    relay_state = {},          -- 继电器状态（1-based，元素 i 对应通道 i-1）
    cpu_temperature = 0,       -- CPU温度 (FLOAT, 2 regs)
    vbat_voltage = 0,          -- VBAT电压 (FLOAT, 2 regs)
    latitude = "",             -- LBS纬度 (STRING)
    longitude = "",            -- LBS经度 (STRING)
    signal_strength = 0,       -- 4G信号强度 (INT16)
    imei = "",                 -- 设备IMEI (STRING)
    iccid = "",                -- SIM ICCID (STRING)
    timestamp = 0,             -- 时间戳 (INT32)
    temperature = 0,           -- 温湿度传感器-温度 (FLOAT, 2 regs，来源网口TCP主站)
    humidity = 0               -- 温湿度传感器-湿度 (FLOAT, 2 regs，来源网口TCP主站)
}

-- 继电器路数（唯一来源：relay_ctrl）
local CH_COUNT = relay_ctrl.get_channel_count()
for i = 1, CH_COUNT do sensor_data.relay_state[i] = 0 end

-- 寄存器起始地址定义
local REG_ADDR = {
    RELAY_MASK = 0x0000,        -- 继电器状态位掩码 (INT16, 1 reg)
    RELAY_CH_BASE = 0x0001,     -- 继电器各通道状态起始 (CH_COUNT regs)
    CPU_TEMP = 0x0005,          -- CPU温度 (FLOAT, 2 regs)
    VBAT_VOLTAGE = 0x0007,      -- VBAT电压 (FLOAT, 2 regs)
    LATITUDE = 0x0009,          -- LBS纬度 (STRING, 10 regs)
    LONGITUDE = 0x0013,         -- LBS经度 (STRING, 10 regs)
    SIGNAL_STRENGTH = 0x001D,   -- 4G信号强度 (INT16, 1 reg)
    IMEI = 0x001E,              -- 设备IMEI (STRING, 12 regs)
    ICCID = 0x002A,             -- SIM ICCID (STRING, 14 regs)
    TIMESTAMP = 0x0038,         -- 时间戳 (INT32, 2 regs)
    TEMP_SENSOR = 0x003A,       -- 温湿度传感器-温度 (FLOAT, 2 regs)
    HUMIDITY = 0x003C,          -- 温湿度传感器-湿度 (FLOAT, 2 regs)
    RELAY_CTRL = 0x0050,        -- 继电器控制字（可写）
}

-- 从站地址（与继电器主站一致）
local SLAVE_ID = 1

-- 从站配置（RTU从站 / UART1 / 115200-8-N-1 / 方向脚 GPIO2）
local slave_config = {
    mode = exmodbus.RTU_SLAVE,
    slave_id = SLAVE_ID,
    uart_id = 1,
    baud_rate = 115200,
    data_bits = 8,
    stop_bits = 1,
    parity_bits = uart.None,
    byte_order = uart.LSB,
    rs485_dir_gpio = rs485_dir_gpio,
    rs485_dir_rx_level = 0
}

-- 创建RTU从站实例
local rtu_slave = exmodbus.create(slave_config)

if not rtu_slave then
    log.info("rtu_slave", "RTU从站创建失败")
else
    log.info("rtu_slave", "RTU从站创建成功，从站地址:", slave_config.slave_id, "uart_id:", slave_config.uart_id)
end

-- 获取CPU温度
local function get_cpu_temperature()
    adc.open(adc.CH_CPU)
    local temp = adc.get(adc.CH_CPU)
    adc.close(adc.CH_CPU)
    return temp / 1000 or 0
end

-- 获取VBAT电压
local function get_vbat_voltage()
    adc.open(adc.CH_VBAT)
    local vbat = adc.get(adc.CH_VBAT)
    adc.close(adc.CH_VBAT)
    return vbat / 1000 or 3.3
end

-- 将浮点数转换为32位整数（IEEE 754，小端序存储）
local function float_to_bits(f)
    if not f or type(f) ~= "number" then
        log.warn("rtu_slave", "float_to_bits收到无效值:", f, "使用默认值0")
        f = 0
    end
    local str = string.pack("f", f)
    local b1, b2, b3, b4 = string.byte(str, 1, 4)
    -- 小端序：低字节在前
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

-- 字符串转寄存器数据（每个寄存器存2个字节）
local function string_to_registers(str, max_len)
    if not str then str = "" end
    str = string.sub(str, 1, max_len or 64)
    local regs = {}
    for i = 1, math.ceil(#str / 2) do
        local char1 = string.byte(str, i * 2 - 1) or 0
        local char2 = string.byte(str, i * 2) or 0
        regs[i - 1] = char1 * 256 + char2
    end
    -- 不足部分补0
    for i = #regs, max_len - 1 do
        regs[i] = 0
    end
    return regs
end

--[[
计算继电器状态位掩码

@local
@function relay_mask
@return number 位掩码（bit0=通道0）
]]
local function relay_mask()
    local mask = 0
    for i = 1, CH_COUNT do
        if sensor_data.relay_state[i] == 1 then
            mask = mask | (1 << (i - 1))
        end
    end
    return mask
end

-- 读取寄存器值
local function read_register(address)
    local value = 0

    -- 继电器状态位掩码 (0x0000, INT16)
    if address == REG_ADDR.RELAY_MASK then
        value = relay_mask()

    -- 继电器各通道状态 (0x0001 ~ 0x0001+CH_COUNT-1, INT16)
    elseif address >= REG_ADDR.RELAY_CH_BASE and address < REG_ADDR.RELAY_CH_BASE + CH_COUNT then
        local idx = address - REG_ADDR.RELAY_CH_BASE + 1
        value = sensor_data.relay_state[idx] or 0

    -- CPU温度 (0x0005-0x0006, FLOAT)
    elseif address == REG_ADDR.CPU_TEMP or address == REG_ADDR.CPU_TEMP + 1 then
        local bits = float_to_bits(sensor_data.cpu_temperature)
        if address == REG_ADDR.CPU_TEMP then
            value = bits & 0xFFFF
        else
            value = (bits >> 16) & 0xFFFF
        end

    -- VBAT电压 (0x0007-0x0008, FLOAT)
    elseif address == REG_ADDR.VBAT_VOLTAGE or address == REG_ADDR.VBAT_VOLTAGE + 1 then
        local bits = float_to_bits(sensor_data.vbat_voltage)
        if address == REG_ADDR.VBAT_VOLTAGE then
            value = bits & 0xFFFF
        else
            value = (bits >> 16) & 0xFFFF
        end

    -- LBS纬度 (0x0009-0x0012, STRING, 10 regs, 20字节)
    elseif address >= REG_ADDR.LATITUDE and address <= REG_ADDR.LATITUDE + 9 then
        local regs = string_to_registers(sensor_data.latitude, 20)
        value = regs[address - REG_ADDR.LATITUDE] or 0

    -- LBS经度 (0x0013-0x001C, STRING, 10 regs, 20字节)
    elseif address >= REG_ADDR.LONGITUDE and address <= REG_ADDR.LONGITUDE + 9 then
        local regs = string_to_registers(sensor_data.longitude, 20)
        value = regs[address - REG_ADDR.LONGITUDE] or 0

    -- 4G信号强度 (0x001D, INT16)
    elseif address == REG_ADDR.SIGNAL_STRENGTH then
        value = sensor_data.signal_strength

    -- 设备IMEI (0x001E-0x0029, STRING, 12 regs, 24字节)
    elseif address >= REG_ADDR.IMEI and address <= REG_ADDR.IMEI + 11 then
        local regs = string_to_registers(sensor_data.imei, 24)
        value = regs[address - REG_ADDR.IMEI] or 0

    -- SIM ICCID (0x002A-0x0037, STRING, 14 regs, 28字节)
    elseif address >= REG_ADDR.ICCID and address <= REG_ADDR.ICCID + 13 then
        local regs = string_to_registers(sensor_data.iccid, 28)
        value = regs[address - REG_ADDR.ICCID] or 0

    -- 时间戳 (0x0038-0x0039, INT32)
    elseif address == REG_ADDR.TIMESTAMP then
        value = sensor_data.timestamp & 0xFFFF
    elseif address == REG_ADDR.TIMESTAMP + 1 then
        value = (sensor_data.timestamp >> 16) & 0xFFFF

    -- 温湿度传感器-温度 (0x003A-0x003B, FLOAT)
    elseif address == REG_ADDR.TEMP_SENSOR or address == REG_ADDR.TEMP_SENSOR + 1 then
        local bits = float_to_bits(sensor_data.temperature)
        if address == REG_ADDR.TEMP_SENSOR then
            value = bits & 0xFFFF
        else
            value = (bits >> 16) & 0xFFFF
        end

    -- 温湿度传感器-湿度 (0x003C-0x003D, FLOAT)
    elseif address == REG_ADDR.HUMIDITY or address == REG_ADDR.HUMIDITY + 1 then
        local bits = float_to_bits(sensor_data.humidity)
        if address == REG_ADDR.HUMIDITY then
            value = bits & 0xFFFF
        else
            value = (bits >> 16) & 0xFFFF
        end

    -- 继电器控制字（读回当前控制字语义：返回状态掩码）
    elseif address == REG_ADDR.RELAY_CTRL then
        value = relay_mask()

    else
        value = 0
    end

    log.info("rtu_slave", "读取寄存器:", string.format("0x%04X", address), "=", value)
    return value
end

--[[
处理继电器控制字写入

背景（实测踩坑点）：本函数被 Modbus RTU/TCP 从站的请求处理回调（modbus_callback）调用，
该回调运行在 socket 回调上下文（非协程）。若在此直接调用 relay_ctrl.open()/close()/
toggle()/all_open()/all_close()，其内部会走 comm_core → exmodbus → sys.waitUntil
等待 485 主站应答，在非协程中 yield 会触发：
  attempt to yield from outside a coroutine
进而 Lua VM 退出并重启。
对策：本函数只做"指令投递"，通过 sys.publish 发布 RELAY_SET_REQ
（relay_ctrl 已在协程上下文中订阅该消息并执行），并立即向 Modbus 主站正常应答；
继电器实际动作在随后几十毫秒内完成，主站可稍后读取 0x0000 状态寄存器确认。

@local
@function handle_relay_ctrl
@param ctrl number 控制字
@return boolean 是否识别并受理
]]
local function handle_relay_ctrl(ctrl)
    if ctrl == 0x0000 then
        sys.publish("RELAY_SET_REQ", nil, "all_close")
        return true
    elseif ctrl == 0xFFFF then
        sys.publish("RELAY_SET_REQ", nil, "all_open")
        return true
    end

    local op = (ctrl >> 8) & 0xFF    -- 0x00=开, 0x01=关, 0x02=翻转
    local ch = (ctrl & 0xFF) - 1     -- 通道号（1~4 → 0~3）
    if ch < 0 or ch >= CH_COUNT then
        log.warn("rtu_slave", "继电器控制字通道非法:", ctrl)
        return false
    end
    if op == 0x00 then
        sys.publish("RELAY_SET_REQ", ch, "open")
    elseif op == 0x01 then
        sys.publish("RELAY_SET_REQ", ch, "close")
    elseif op == 0x02 then
        sys.publish("RELAY_SET_REQ", ch, "toggle")
    else
        log.warn("rtu_slave", "继电器控制字操作码非法:", ctrl)
        return false
    end
    return true
end

--[[
处理"每路继电器开关"寄存器写入（通道0~3 → 寄存器 0x0001~0x0004）

写入值 0 = 断开该路，非 0（如 1）= 接通该路；读回值为该路当前实际状态。
与 0x0050 控制字一致，本函数只做"指令投递"（sys.publish），
由 relay_ctrl 的常驻协程在协程上下文中执行，避免在从站回调（非协程）里 yield 导致重启。

@local
@function handle_relay_ch_write
@param addr number 寄存器地址
@param val number 写入值
@return boolean true=该地址属于通道开关寄存器且已受理
]]
local function handle_relay_ch_write(addr, val)
    -- 通道0 → 0x0001，通道3 → 0x0004
    local ch = addr - REG_ADDR.RELAY_CH_BASE
    if ch < 0 or ch >= CH_COUNT then
        return false
    end
    local action = (val ~= 0) and "open" or "close"
    sys.publish("RELAY_SET_REQ", ch, action)
    log.info("rtu_slave", "通道开关写入: 通道" .. ch .. " → " .. ((val ~= 0) and "接通" or "断开"))
    return true
end

-- 更新寄存器数据（定时刷新系统数据）
local function update_sensor_data()
    sensor_data.cpu_temperature = get_cpu_temperature()
    sensor_data.vbat_voltage = get_vbat_voltage()
    sensor_data.signal_strength = mobile.csq() or 0
    sensor_data.imei = mobile.imei() or ""
    sensor_data.iccid = mobile.iccid() or ""
    sensor_data.timestamp = os.time()
end

-- 监听继电器状态更新（relay_ctrl 发布）
sys.subscribe("RELAY_STATUS_UPDATE", function(new_state)
    if type(new_state) == "table" then
        for i = 1, CH_COUNT do
            sensor_data.relay_state[i] = new_state[i] or 0
        end
        log.info("rtu_slave", "继电器状态更新:", table.concat(sensor_data.relay_state, ","))
    end
end)

--[[
监听温湿度传感器数据更新（tcp_modbus_master 发布）

背景（实测踩坑点）：本模块此前既没有 temperature/humidity 字段，也没有订阅
TEMP_HUMIDITY_UPDATE，导致温湿度数据卡在 tcp_modbus_master 模块里出不来：
网页（/api/status、/api/sensor、/api/temp）与 Modbus 从站寄存器恒为 0，
而 AirCloud 因自行订阅了该消息所以云端有值（表现为"云端有、网页为 0"）。
补齐订阅后，网页 / Modbus从站 / 云端 三条通道数据一致。

@local
@function on_temp_humidity_update
@param temp number 温度值（℃，如 28.8）
@param humi number 湿度值（%RH，如 57.2）
]]
local function on_temp_humidity_update(temp, humi)
    sensor_data.temperature = temp or 0
    sensor_data.humidity = humi or 0
    log.info("rtu_slave", "温湿度更新:", "温度", temp, "℃", "湿度", humi, "%RH")
end

sys.subscribe("TEMP_HUMIDITY_UPDATE", on_temp_humidity_update)

-- 监听定位数据更新
sys.subscribe("Airlbs_LOCATION_UPDATE", function(new_lat, new_lng)
    sensor_data.latitude = tostring(new_lat) or ""
    sensor_data.longitude = tostring(new_lng) or ""
    log.info("rtu_slave", "定位更新:", "lat:", new_lat, "lng:", new_lng)
end)

-- 订阅NTP错误消息
sys.subscribe("NTP_ERROR", function(err_info)
    log.error("rtu_slave", "NTP同步错误:", err_info or "未知错误")
end)

--[[
主站请求处理回调函数（RTU/TCP 从站共用）

@local
@function modbus_callback
@param request table 主站请求
@return table 响应数据表 / number 异常码
]]
local function modbus_callback(request)
    log.info("rtu_slave", "收到主站请求，功能码:", request.func_code,
        "起始地址:", request.start_addr, "数量:", request.reg_count)

    -- 检查从站ID是否匹配
    if request.slave_id ~= slave_config.slave_id then
        return nil
    end

    -- 读保持寄存器 / 读输入寄存器
    if request.func_code == exmodbus.READ_HOLDING_REGISTERS or
       request.func_code == exmodbus.READ_INPUT_REGISTERS then
        local response = {}
        for i = 0, request.reg_count - 1 do
            local addr = request.start_addr + i
            response[addr] = read_register(addr)
        end
        log.info("rtu_slave", "读取成功，地址:", request.start_addr, "数量:", request.reg_count)
        -- 请求 hex
        local req_hex = string.format("%02X %02X %02X %02X %02X %02X",
            request.slave_id, request.func_code,
            (request.start_addr >> 8) & 0xFF, request.start_addr & 0xFF,
            (request.reg_count >> 8) & 0xFF, request.reg_count & 0xFF)
        -- 回复 hex
        local resp_vals = {}
        for i = 0, request.reg_count - 1 do
            local addr = request.start_addr + i
            local v = response[addr] & 0xFFFF
            table.insert(resp_vals, string.format("%02X %02X", (v >> 8) & 0xFF, v & 0xFF))
        end
        local resp_hex = string.format("%02X %02X %02X %s",
            request.slave_id, request.func_code,
            request.reg_count * 2, table.concat(resp_vals, " "))
        sys.publish("MODBUS_RTU_REQ", string.format("[RTU] 请求:%s  应答:%s", req_hex, resp_hex))
        return response

    -- 写单个保持寄存器（支持继电器控制字）
    elseif request.func_code == exmodbus.WRITE_SINGLE_HOLDING_REGISTER then
        local addr = request.start_addr
        local val = request.data and request.data[addr] or 0
        if addr == REG_ADDR.RELAY_CTRL then
            if handle_relay_ctrl(val) then
                sys.publish("MODBUS_RTU_REQ", string.format("[RTU] 写控制字:0x%04X", val))
                return {}
            end
            return exmodbus.ILLEGAL_DATA_VALUE
        end
        -- 每路继电器开关（0x0001~0x0004）：写 0 断开、非 0 接通
        if handle_relay_ch_write(addr, val) then
            sys.publish("MODBUS_RTU_REQ", string.format("[RTU] 写通道开关:0x%04X=0x%04X", addr, val))
            return {}
        end
        log.info("rtu_slave", "写入保持寄存器:", string.format("0x%04X", addr), "=", val)
        return {}

    -- 写多个保持寄存器
    elseif request.func_code == exmodbus.WRITE_MULTIPLE_HOLDING_REGISTERS then
        for i = 0, request.reg_count - 1 do
            local addr = request.start_addr + i
            local val = request.data and request.data[addr] or 0
            if addr == REG_ADDR.RELAY_CTRL then
                handle_relay_ctrl(val)
            else
                -- 支持一次性写入 0x0001~0x0004（每路继电器开关）
                handle_relay_ch_write(addr, val)
            end
        end
        sys.publish("MODBUS_RTU_REQ", string.format("[RTU] 多寄存器写入，起始:0x%04X 数量:%d",
            request.start_addr, request.reg_count))
        return {}

    else
        log.info("rtu_slave", "不支持的功能码:", request.func_code)
        sys.publish("MODBUS_RTU_REQ", string.format("[RTU] 不支持的功能码:0x%02X", request.func_code))
        return exmodbus.ILLEGAL_FUNCTION
    end
end

-- 注册回调函数
if rtu_slave then
    rtu_slave:on(modbus_callback)
end

--[[
定时更新寄存器数据任务（每5秒刷新系统数据）

@local
@function task_update_data
]]
local function task_update_data()
    while true do
        if rtu_slave then
            update_sensor_data()
        end
        sys.wait(5000) -- 每5秒更新一次
    end
end

sys.taskInit(task_update_data)

-- 导出模块接口供其他模块使用（如 tcp_slave.lua）
log.info("rtu_slave", "寄存器映射表加载完成")

return {
    get_callback = function() return modbus_callback end,
    get_data = function(addr) return sensor_data[addr] or read_register(addr) end,
    get_all_data = function() return sensor_data end
}
