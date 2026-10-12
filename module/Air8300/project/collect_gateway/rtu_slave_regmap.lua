--[[
@module  rtu_slave_regmap
@summary Modbus RTU/TCP从站寄存器映射表
@version 1.1
@date    2026.05.19
@author  马梦阳
@usage
本文件实现Modbus RTU/TCP从站功能，将所有传感器数据和系统数据映射到保持寄存器中，
供电脑端Modbus RTU主站或TCP主站读取。

寄存器映射表：
------------------------------------------------------------------
地址      | 数据类型 | 数据项         | 字节数 | 来源                | 示例值
------------------------------------------------------------------
0x0000-01 | FLOAT    | RTU传感器湿度  | 4      | RS485温湿度传感器   | 65.3
0x0002-03 | FLOAT    | RTU传感器温度  | 4      | RS485温湿度传感器   | 23.5
0x0039    | INT16    | TCP传感器湿度  | 2      | 网口1温湿度传感器   | 653
0x003A    | INT16    | TCP传感器温度  | 2      | 网口1温湿度传感器   | 235
0x0004-05 | FLOAT    | CPU温度        | 4      | 模块内部            | 45.2
0x0006-07 | FLOAT    | VBAT电压       | 4      | 模块内部            | 3.85
0x0008-11 | STRING   | LBS纬度        | 20     | 定位模块            | "34.8074150"
0x0012-1B | STRING   | LBS经度        | 20     | 定位模块            | "114.2941589"
0x001C    | INT16    | 4G信号强度     | 2      | 移动网络            | 25
0x001D-28 | STRING   | 设备IMEI       | 20     | 移动网络            | "861234567890123"
0x0029-36 | STRING   | SIM ICCID      | 24     | 移动网络            | "898606..."
0x0037-38 | INT32    | 时间戳         | 4      | NTP同步            | 1779158409
------------------------------------------------------------------

注意事项：
1、RTU传感器和TCP传感器使用不同的寄存器地址，区分数据来源
2、RTU传感器：0x0000-0x0003 (FLOAT格式，2寄存器)
3、TCP传感器：0x0039-0x003A (INT16格式，单位0.1)
4、读取多个连续寄存器时，需要根据数据类型占用寄存器数量计算

本文件没有对外接口，使用时直接在main.lua中require "rtu_slave_regmap"就可以加载运行；

本文件是被动从站模块，内部订阅以下事件收集数据供 Modbus 主站读取：
1、sys.subscribe("TEMP_HUMIDITY_UPDATE")        -- RTU传感器温湿度
2、sys.subscribe("TCP_TEMP_HUMIDITY_UPDATE")    -- TCP Modbus传感器温湿度
3、sys.subscribe("Airlbs_LOCATION_UPDATE")        -- 经纬度
4、sys.subscribe("NTP_ERROR")                   -- NTP同步状态
对外暴露的是 Modbus 保持寄存器（0x0000~0x0037），供 RTU/TCP 主站读取
]] 

local exmodbus = require("exmodbus")
local led = require("led")

gpio.setup(29, 1, gpio.PULLUP)        -- Air8000 开发板 RS485 芯片供电引脚
local rs485_dir_gpio = 36 -- Air8000 开发板 RS485 方向引脚

pins.setup(27,"GPIO36") 
pins.setup(28,"GPIO37") 
pins.setup(18,"GPIO29")
pins.setup(25,"UART3_RX") 
pins.setup(26,"UART3_TX") 

-- 简化数据存储表（直接使用 sensor_data）
local sensor_data = {
    humidity = 0,              -- RTU传感器环境湿度 (FLOAT, 2 regs)
    temperature = 0,          -- RTU传感器环境温度 (FLOAT, 2 regs)
    tcp_humidity = 0,         -- TCP传感器湿度 (INT16, 1 reg)
    tcp_temperature = 0,      -- TCP传感器温度 (INT16, 1 reg)
    cpu_temperature = 0,      -- CPU温度 (FLOAT, 2 regs)
    vbat_voltage = 0,         -- VBAT电压 (FLOAT, 2 regs)
    latitude = "",            -- LBS纬度 (STRING)
    longitude = "",           -- LBS经度 (STRING)
    signal_strength = 0,      -- 4G信号强度 (INT16)
    imei = "",                -- 设备IMEI (STRING)
    iccid = "",               -- SIM ICCID (STRING)
    timestamp = 0             -- 时间戳 (INT32)
}

-- 寄存器起始地址定义
local REG_ADDR = {
    HUMIDITY = 0x0000,          -- RTU传感器湿度 (FLOAT, 2 regs)
    TEMPERATURE = 0x0002,       -- RTU传感器温度 (FLOAT, 2 regs)
    CPU_TEMP = 0x0004,          -- CPU温度 (FLOAT, 2 regs)
    VBAT_VOLTAGE = 0x0006,      -- VBAT电压 (FLOAT, 2 regs)
    LATITUDE = 0x0008,          -- GNSS纬度 (STRING, 10 regs)
    LONGITUDE = 0x0012,         -- GNSS经度 (STRING, 10 regs)
    SIGNAL_STRENGTH = 0x001C,   -- 4G信号强度 (INT16, 1 reg)
    IMEI = 0x001D,              -- 设备IMEI (STRING, 12 regs)
    ICCID = 0x0029,             -- SIM ICCID (STRING, 10 regs)
    TIMESTAMP = 0x0033,         -- 时间戳 (INT32, 2 regs)
    TCP_TEMPERATURE = 0x0035,   -- TCP Modbus传感器温度 (INT16, 1 reg)
    TCP_HUMIDITY = 0x0036,      -- TCP Modbus传感器湿度 (INT16, 1 reg)
}

-- 创建RTU从站配置
local slave_config = {
    mode = exmodbus.RTU_SLAVE,
    slave_id = 1,
    uart_id = 3,
    baud_rate = 9600,
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
    log.info("rtu_slave", "RTU从站创建成功，从站地址:", slave_config.slave_id)
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

-- NTP时间同步
local function sync_ntp_time()
    -- 等待IP就绪
    while not socket.adapter(socket.dft()) do
        log.info("rtu_slave", "等待网络就绪...")
        sys.waitUntil("IP_READY", 1000)
    end
    log.info("rtu_slave", "网络就绪，开始NTP同步")
    
    -- 调用NTP同步
    socket.sntp()
    
    -- 等待同步结果（5秒超时）
    local sync_success = sys.waitUntil("NTP_UPDATE", 5000)
    
    if sync_success then
        -- NTP同步成功后，系统时间已经自动更新
        -- 直接使用 os.time() 获取正确的Unix时间戳
        local timestamp = os.time()
        log.info("rtu_slave", "NTP同步成功，时间戳:", timestamp)
        log.info("rtu_slave", "当前时间:", os.date("%Y-%m-%d %H:%M:%S", timestamp))
        return timestamp
    else
        log.warn("rtu_slave", "NTP同步超时，使用系统时间")
        return os.time()
    end
end

-- NTP同步任务
local function ntp_sync_loop()
    -- 等待系统初始化
    sys.wait(5000)
    
    while true do
        -- 执行NTP同步
        local timestamp = sync_ntp_time()
        sensor_data.timestamp = timestamp
        
        -- 打印同步后的时间信息
        log.info("rtu_slave", "当前时间:", os.date("%Y-%m-%d %H:%M:%S", timestamp))
        
        -- 每小时同步一次
        sys.wait(3600 * 1000)
    end
end

-- 订阅NTP错误消息
sys.subscribe("NTP_ERROR", function(err_info)
    log.error("rtu_slave", "NTP同步错误:", err_info or "未知错误")
end)

-- 启动NTP同步任务
sys.taskInit(ntp_sync_loop)

-- 将浮点数转换为32位整数（IEEE 754，小端序存储）
local function float_to_bits(f)
    -- 确保f是有效数值
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


-- 读取寄存器值
local function read_register(address)
    local value = 0
    
    -- 环境湿度 (0x0000-0x0001, FLOAT)
    if address == 0x0000 or address == 0x0001 then
        log.info("rtu_slave", "读取湿度, 原始值:", sensor_data.humidity)
        local bits = float_to_bits(sensor_data.humidity)
        log.info("rtu_slave", "湿度bits:", string.format("0x%08X", bits))
        -- 小端序：低字节在前
        if address == 0x0000 then
            value = bits & 0xFFFF  -- 低16位
        else
            value = (bits >> 16) & 0xFFFF  -- 高16位
        end
        log.info("rtu_slave", "湿度寄存器", string.format("0x%04X", address), "=", value)
        
    -- 环境温度 (0x0002-0x0003, FLOAT)
    elseif address == 0x0002 or address == 0x0003 then
        log.info("rtu_slave", "读取温度, 原始值:", sensor_data.temperature)
        local bits = float_to_bits(sensor_data.temperature)
        log.info("rtu_slave", "温度bits:", string.format("0x%08X", bits))
        -- 小端序：低字节在前
        if address == 0x0002 then
            value = bits & 0xFFFF  -- 低16位
        else
            value = (bits >> 16) & 0xFFFF  -- 高16位
        end
        log.info("rtu_slave", "温度寄存器", string.format("0x%04X", address), "=", value)
        
    -- CPU温度 (0x0004-0x0005, FLOAT)
    elseif address == 0x0004 or address == 0x0005 then
        log.info("rtu_slave", "读取CPU温度, 原始值:", sensor_data.cpu_temperature)
        local bits = float_to_bits(sensor_data.cpu_temperature)
        log.info("rtu_slave", "CPU温度bits:", string.format("0x%08X", bits))
        -- 小端序：低字节在前
        if address == 0x0004 then
            value = bits & 0xFFFF  -- 低16位
        else
            value = (bits >> 16) & 0xFFFF  -- 高16位
        end
        log.info("rtu_slave", "CPU温度寄存器", string.format("0x%04X", address), "=", value)
        
    -- VBAT电压 (0x0006-0x0007, FLOAT)
    elseif address == 0x0006 or address == 0x0007 then
        log.info("rtu_slave", "读取VBAT电压, 原始值:", sensor_data.vbat_voltage)
        local bits = float_to_bits(sensor_data.vbat_voltage)
        log.info("rtu_slave", "VBAT电压bits:", string.format("0x%08X", bits))
        -- 小端序：低字节在前
        if address == 0x0006 then
            value = bits & 0xFFFF  -- 低16位
        else
            value = (bits >> 16) & 0xFFFF  -- 高16位
        end
        log.info("rtu_slave", "VBAT电压寄存器", string.format("0x%04X", address), "=", value)
        
    -- LBS纬度 (0x0008-0x0011, STRING, 10 regs, 20字节)
    elseif address >= 0x0008 and address <= 0x0011 then
        local regs = string_to_registers(sensor_data.latitude, 20)
        value = regs[address - 0x0008] or 0
        
    -- LBS经度 (0x0012-0x001B, STRING, 10 regs, 20字节)
    elseif address >= 0x0012 and address <= 0x001B then
        local regs = string_to_registers(sensor_data.longitude, 20)
        value = regs[address - 0x0012] or 0
        
    -- 4G信号强度 (0x001C, INT16)
    elseif address == 0x001C then
        value = sensor_data.signal_strength
        
    -- 设备IMEI (0x001D-0x0028, STRING, 12 regs, 24字节)
    elseif address >= 0x001D and address <= 0x0028 then
        local regs = string_to_registers(sensor_data.imei, 20)
        value = regs[address - 0x001D] or 0
        
    -- SIM ICCID (0x0029-0x0036, STRING, 14 regs, 28字节)
    elseif address >= 0x0029 and address <= 0x0036 then
        local regs = string_to_registers(sensor_data.iccid, 24)
        value = regs[address - 0x0029] or 0
        
    -- 时间戳 (0x0037-0x0038, INT32)
    elseif address == 0x0037 then
        value = sensor_data.timestamp & 0xFFFF
    elseif address == 0x0038 then
        value = (sensor_data.timestamp >> 16) & 0xFFFF
        
    -- TCP传感器湿度 (0x0039, INT16)
    elseif address == 0x0039 then
        value = math.floor(sensor_data.tcp_humidity * 10)
        
    -- TCP传感器温度 (0x003A, INT16)
    elseif address == 0x003A then
        value = math.floor(sensor_data.tcp_temperature * 10)
        if value < 0 then
            value = value + 0x10000
        end
        
    else
        value = 0
    end
    
    log.info("rtu_slave", "读取寄存器:", string.format("0x%04X", address), "=", value)
    return value
end

-- 更新寄存器数据
local function update_sensor_data()
    -- 更新ADC数据
    sensor_data.cpu_temperature = get_cpu_temperature()
    sensor_data.vbat_voltage = get_vbat_voltage()
    
    -- 更新系统数据
    sensor_data.signal_strength = mobile.csq() or 0
    sensor_data.imei = mobile.imei() or ""
    sensor_data.iccid = mobile.iccid() or ""
    sensor_data.timestamp = os.time()
    
    log.info("rtu_slave", "数据更新:", 
        "温度:", sensor_data.temperature,
        "湿度:", sensor_data.humidity,
        "CPU:", sensor_data.cpu_temperature,
        "电压:", sensor_data.vbat_voltage)
end

-- 监听温湿度数据更新 (RTU传感器)
sys.subscribe("TEMP_HUMIDITY_UPDATE", function(temp, humi)
    sensor_data.temperature = temp
    sensor_data.humidity = humi
    led.sensor_ok()
    log.info("rtu_slave", "温湿度更新:", "温度:", temp, "湿度:", humi)
end)

-- 监听TCP传感器温湿度数据更新
sys.subscribe("TCP_TEMP_HUMIDITY_UPDATE", function(temp, humi)
    sensor_data.tcp_temperature = temp
    sensor_data.tcp_humidity = humi
    led.sensor_ok()
    log.info("rtu_slave", "TCP传感器更新:", "温度:", temp, "湿度:", humi)
end)

-- 监听定位数据更新
sys.subscribe("Airlbs_LOCATION_UPDATE", function(new_lat, new_lng)
    sensor_data.latitude = tostring(new_lat) or ""
    sensor_data.longitude = tostring(new_lng) or ""
    log.info("rtu_slave", "定位更新:", "lat:", new_lat, "lng:", new_lng)
end)

-- 主站请求处理回调函数
local function modbus_callback(request)
    log.info("rtu_slave", "收到主站请求，功能码:", request.func_code, "起始地址:", request.start_addr, "数量:", request.reg_count)
    led.rtu_req()
    
    -- 检查从站ID是否匹配
    if request.slave_id ~= slave_config.slave_id then
        led.rtu_done()
        return nil
    end
    
    -- 检查功能码
    if request.func_code == exmodbus.READ_HOLDING_REGISTERS or 
       request.func_code == exmodbus.READ_INPUT_REGISTERS then
        -- 读取保持寄存器/输入寄存器
        -- 注意：exmodbus库要求必须以地址为key返回数据
        -- 例如：读取地址2开始的2个寄存器，应该返回 {[2] = value1, [3] = value2}
        local response = {}
        for i = 0, request.reg_count - 1 do
            local addr = request.start_addr + i
            response[addr] = read_register(addr)
        end
        log.info("rtu_slave", "读取成功，地址:", request.start_addr, "数量:", request.reg_count)
        led.rtu_done()
        return response
        
    else
        log.info("rtu_slave", "不支持的功能码:", request.func_code)
        led.rtu_done()
        return exmodbus.ILLEGAL_FUNCTION
    end
end

-- 注册回调函数
if rtu_slave then
    rtu_slave:on(modbus_callback)
end

-- 定时更新寄存器任务
sys.taskInit(function()
    while true do
        if rtu_slave then
            update_sensor_data()
        end
        sys.wait(5000) -- 每5秒更新一次
    end
end)

-- 导出模块接口供其他模块使用（如 tcp_slave.lua）
local mod = {}

function mod.get_callback()
    return modbus_callback
end

function mod.get_data(addr)
    return sensor_data[addr] or read_register(addr)
end

function mod.get_all_data()
    return sensor_data
end

log.info("rtu_slave", "寄存器映射表加载完成")

return {
    get_callback = function() return modbus_callback end,
    get_data = function(addr) return sensor_data[addr] or read_register(addr) end,
    get_all_data = function() return sensor_data end
}
