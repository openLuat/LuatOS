--[[
@module  exs_bmx280
@summary BMP280/BME280 数字气压传感器扩展库
@version 1.0
@date    2026.07.24
@author  江访
@usage
本文件为 BMP280/BME280 数字气压传感器（Bosch Sensortec 出品）的 LuatOS 扩展库。
通过 I2C 接口读取大气压和温度，自动进行校准补偿。
BME280 额外支持湿度测量。

本文件的对外接口有 8 个：
1、exs_bmx280.setup(model, config)：初始化 BMP280/BME280
2、exs_bmx280.get_data()：读取气压、温度和湿度（BME280）
3、exs_bmx280.set_filter(coeff)：设置 IIR 滤波器系数
4、exs_bmx280.set_sea_level_pressure(pressure)：设置海平面标准气压
5、exs_bmx280.get_humidity()：单独读取湿度值（仅 BME280）
6、exs_bmx280.get_altitude(pressure)：计算海拔
7、exs_bmx280.close()：关闭传感器
8、exs_bmx280.version()：获取版本号

更多说明参考 docs 在线文档

=== 版本更新说明 ===
-- 版本号：202607240000（初版）
-- 1、更新时间：2026-07-24
-- 2、更新内容
--   - 支持软件 I2C 和硬件 I2C 两种模式
--   - 支持 BMP280/BME280 自动识别
--   - 支持 IIR 滤波器（系数 0~4）
--   - 支持 BME280 湿度读取（get_data() 返回 humidity，单独 get_humidity()）
--   - 支持海拔高度计算（国际气压公式）
--   - 内置 I2C 总线卡死自动检测与恢复
]]

local exs_bmx280 = {}

-- ==================== 寄存器地址 ====================

local REG_CHIP_ID       = 0xD0      -- 芯片 ID 寄存器（BMP280=0x58, BME280=0x60）
local REG_SOFT_RESET    = 0xE0      -- 软复位寄存器（写入 0xB6）
local REG_CTRL_HUM      = 0xF2      -- 湿度过采样控制（仅 BME280）
local REG_CTRL_MEAS     = 0xF4      -- 测量控制寄存器
local REG_CONFIG        = 0xF5      -- 配置寄存器（待机时间 + IIR 滤波）
local REG_PRESS_MSB     = 0xF7      -- 气压数据高字节
local REG_PRESS_LSB     = 0xF8      -- 气压数据中字节
local REG_PRESS_XLSB    = 0xF9      -- 气压数据低字节
local REG_TEMP_MSB      = 0xFA      -- 温度数据高字节
local REG_TEMP_LSB      = 0xFB      -- 温度数据中字节
local REG_TEMP_XLSB     = 0xFC      -- 温度数据低字节
local REG_HUM_MSB       = 0xFD      -- 湿度数据高字节（仅 BME280）
local REG_HUM_LSB       = 0xFE      -- 湿度数据低字节（仅 BME280）
local REG_CALIB_START   = 0x88      -- 校准参数起始地址（0x88~0xA1 共 26 字节）
local REG_CALIB_HUM_START = 0xE1    -- 湿度校准参数起始（0xE1~0xE7 共 7 字节）

-- ==================== 常量 ====================

local CHIP_ID_BMP280    = 0x58      -- BMP280 芯片 ID
local CHIP_ID_BME280    = 0x60      -- BME280 芯片 ID
local DEV_ADDR_LOW      = 0x76      -- I2C 7 位地址（SDO=GND）
local DEV_ADDR_HIGH     = 0x77      -- I2C 7 位地址（SDO=VCC）

-- 芯片型号常量
local CHIP_TYPE_BMP280  = "BMP280"
local CHIP_TYPE_BME280  = "BME280"

-- ==================== 内部状态 ====================

local g_i2c_bus         = 0
local g_is_soft         = false
local g_scl_pin         = nil
local g_sda_pin         = nil
local g_dev_addr        = 0x76      -- 检测到的器件地址
local g_ready           = false
local g_chip_type       = CHIP_TYPE_BMP280  -- 检测到的芯片型号

-- 校准参数
local dig_t1 = 0; local dig_t2 = 0; local dig_t3 = 0
local dig_p1 = 0; local dig_p2 = 0; local dig_p3 = 0
local dig_p4 = 0; local dig_p5 = 0; local dig_p6 = 0
local dig_p7 = 0; local dig_p8 = 0; local dig_p9 = 0
-- BME280 湿度校准参数
local dig_h1 = 0; local dig_h2 = 0; local dig_h3 = 0
local dig_h4 = 0; local dig_h5 = 0; local dig_h6 = 0
local t_fine = 0
local g_sea_level_pressure = 1013.25  -- 默认海平面标准气压，单位 hPa

-- ==================== I2C 总线恢复 ====================

local function i2c_bus_recovery()
    if not g_scl_pin or not g_sda_pin then return false end
    gpio.setup(g_scl_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    sys.wait(1)
    for i = 1, 9 do
        gpio.set(g_scl_pin, 0); sys.wait(1)
        gpio.set(g_scl_pin, 1); sys.wait(1)
        gpio.setup(g_sda_pin, gpio.INPUT, gpio.PULLUP); sys.wait(1)
        if gpio.get(g_sda_pin) == 1 then
            gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
            break
        end
        gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    end
    gpio.set(g_sda_pin, 0); sys.wait(1)
    gpio.set(g_scl_pin, 1); sys.wait(1)
    gpio.set(g_sda_pin, 1); sys.wait(1)
    return true
end

-- ==================== I2C 总线卡死自动检测 ====================

local function try_bus_recovery()
    if not g_scl_pin or not g_sda_pin then return false end
    gpio.setup(g_sda_pin, gpio.INPUT, gpio.PULLUP)
    gpio.setup(g_scl_pin, gpio.INPUT, gpio.PULLUP)
    sys.wait(1)
    local is_stall = (gpio.get(g_sda_pin) == 0 and gpio.get(g_scl_pin) == 1)
    gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    gpio.setup(g_scl_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    if not is_stall then return false end
    log.warn("exs_bmx280", "检测到I2C总线卡死，尝试恢复")
    i2c_bus_recovery()
    if not g_is_soft then i2c.setup(g_i2c_bus, i2c.SLOW) end
    return true
end

-- ==================== 底层 I2C 读写 ====================

local function i2c_write(reg, val)
    local ok = i2c.send(g_i2c_bus, g_dev_addr, {reg, val})
    if not ok then
        if try_bus_recovery() then ok = i2c.send(g_i2c_bus, g_dev_addr, {reg, val}) end
    end
    return ok
end

local function i2c_read(reg, len)
    local addr_byte = (len > 1) and (reg | 0x80) or reg
    local ok = i2c.send(g_i2c_bus, g_dev_addr, {addr_byte})
    if not ok then
        if try_bus_recovery() then ok = i2c.send(g_i2c_bus, g_dev_addr, {addr_byte}) end
        if not ok then return nil end
    end
    local data = i2c.recv(g_i2c_bus, g_dev_addr, len)
    if not data then return nil end
    local t = {}
    for i = 1, #data do t[i] = data:byte(i) end
    return t
end

-- 读 16 位无符号（LSB first）
local function read_u16_le(reg)
    local buf = i2c_read(reg, 2)
    if not buf or #buf < 2 then return nil end
    return (buf[2] << 8) | buf[1]
end

-- 读 16 位无符号（MSB first）
local function read_u16_be(reg)
    local buf = i2c_read(reg, 2)
    if not buf or #buf < 2 then return nil end
    return (buf[1] << 8) | buf[2]
end

-- 读 16 位有符号（LSB first）
local function read_s16_le(reg)
    local v = read_u16_le(reg)
    if v and v >= 0x8000 then v = v - 0x10000 end
    return v
end

-- 读 8 位有符号
local function read_s8(reg)
    local buf = i2c_read(reg, 1)
    if not buf or #buf < 1 then return nil end
    local v = buf[1]
    if v >= 0x80 then v = v - 0x100 end
    return v
end

-- 读 8 位无符号
local function read_u8(reg)
    local buf = i2c_read(reg, 1)
    if not buf or #buf < 1 then return nil end
    return buf[1]
end

-- 读 20 位温度/气压 ADC 值
local function read_adc20(reg)
    local buf = i2c_read(reg, 3)
    if not buf or #buf < 3 then return nil end
    return (buf[1] << 12) | (buf[2] << 4) | (buf[3] >> 4)
end

-- 读 16 位湿度 ADC 值（MSB first）
local function read_hum_adc()
    return read_u16_be(REG_HUM_MSB)
end

-- ==================== 芯片检测与校准数据读取 ====================

local function chip_detect()
    for _, addr in ipairs({ DEV_ADDR_LOW, DEV_ADDR_HIGH }) do
        if i2c.send(g_i2c_bus, addr, { REG_CHIP_ID }) then
            local data = i2c.recv(g_i2c_bus, addr, 1)
            if data and #data >= 1 then
                local id = data:byte(1)
                if id == CHIP_ID_BMP280 then
                    g_dev_addr = addr; g_chip_type = CHIP_TYPE_BMP280
                    log.info("exs_bmx280", string.format("%s @ I2C 0x%02X", g_chip_type, addr))
                    return true
                elseif id == CHIP_ID_BME280 then
                    g_dev_addr = addr; g_chip_type = CHIP_TYPE_BME280
                    log.info("exs_bmx280", string.format("%s @ I2C 0x%02X", g_chip_type, addr))
                    return true
                end
            end
        end
    end
    log.error("exs_bmx280", "未检测到 BMP280/BME280")
    return false
end

local function read_calibration()
    dig_t1 = read_u16_le(REG_CALIB_START)
    dig_t2 = read_s16_le(REG_CALIB_START + 2)
    dig_t3 = read_s16_le(REG_CALIB_START + 4)
    dig_p1 = read_u16_le(REG_CALIB_START + 6)
    dig_p2 = read_s16_le(REG_CALIB_START + 8)
    dig_p3 = read_s16_le(REG_CALIB_START + 10)
    dig_p4 = read_s16_le(REG_CALIB_START + 12)
    dig_p5 = read_s16_le(REG_CALIB_START + 14)
    dig_p6 = read_s16_le(REG_CALIB_START + 16)
    dig_p7 = read_s16_le(REG_CALIB_START + 18)
    dig_p8 = read_s16_le(REG_CALIB_START + 20)
    dig_p9 = read_s16_le(REG_CALIB_START + 22)

    if dig_t1 == 0 or dig_p1 == 0 then
        log.error("exs_bmx280", "校准数据读取失败")
        return false
    end

    -- 如果是 BME280，读取湿度校准参数
    if g_chip_type == CHIP_TYPE_BME280 then
        dig_h1 = read_u8(0xA1)
        dig_h2 = read_s16_le(REG_CALIB_HUM_START)
        dig_h3 = read_u8(REG_CALIB_HUM_START + 2)
        -- dig_H4: 0xE4[7:0] 对应 [11:4], 0xE5[3:0] 对应 [3:0]，signed 12bit
        local e4 = read_u8(REG_CALIB_HUM_START + 3)
        local e5 = read_u8(REG_CALIB_HUM_START + 4)
        dig_h4 = (e4 << 4) | (e5 & 0x0F)
        if dig_h4 >= 0x800 then dig_h4 = dig_h4 - 0x1000 end
        -- dig_H5: 0xE5[7:4] 对应 [3:0], 0xE6[7:0] 对应 [11:4]，signed 12bit
        local e6 = read_u8(REG_CALIB_HUM_START + 5)
        dig_h5 = (e6 << 4) | (e5 >> 4)
        if dig_h5 >= 0x800 then dig_h5 = dig_h5 - 0x1000 end
        -- dig_H6: signed char
        dig_h6 = read_s8(REG_CALIB_HUM_START + 6)
        log.info("exs_bmx280", string.format("湿度校准: H1=%d H2=%d H3=%d H4=%d H5=%d H6=%d", dig_h1, dig_h2, dig_h3, dig_h4, dig_h5, dig_h6))
    end

    log.info("exs_bmx280", string.format("校准数据: T1=%d T2=%d T3=%d P1=%d P2=%d", dig_t1, dig_t2, dig_t3, dig_p1, dig_p2))
    return true
end

-- ==================== 补偿算法（浮点公式） ====================
-- 来自 BMP280 数据手册 8.1 节 double 精度公式
-- Lua 的 number 是双精度浮点（64-bit double），天然匹配

local function compensate_temperature(adc_t)
    if not adc_t then return nil end
    -- var1 = (adc_T/16384 - dig_T1/1024) * dig_T2
    local var1 = (adc_t / 16384.0 - dig_t1 / 1024.0) * dig_t2
    -- var2 = ((adc_T/131072 - dig_T1/8192)^2) * dig_T3
    local var2 = (adc_t / 131072.0 - dig_t1 / 8192.0)
    var2 = var2 * var2 * dig_t3
    t_fine = math.floor(var1 + var2)
    -- T = (var1 + var2) / 5120.0
    return (var1 + var2) / 5120.0
end

local function compensate_pressure(adc_p)
    if not adc_p or t_fine == 0 then return nil end
    -- var1 = t_fine/2 - 64000
    local var1 = t_fine / 2.0 - 64000.0
    -- var2 = var1^2 * dig_P6 / 32768
    local var2 = var1 * var1 * dig_p6 / 32768.0
    -- var2 = var2 + var1 * dig_P5 * 2
    var2 = var2 + var1 * dig_p5 * 2.0
    -- var2 = var2/4 + dig_P4 * 65536
    var2 = var2 / 4.0 + dig_p4 * 65536.0
    -- var1 = (dig_P3 * var1^2 / 524288 + dig_P2 * var1) / 524288
    var1 = (dig_p3 * var1 * var1 / 524288.0 + dig_p2 * var1) / 524288.0
    -- var1 = (1 + var1/32768) * dig_P1
    var1 = (1.0 + var1 / 32768.0) * dig_p1
    if var1 == 0 then return nil end
    -- p = 1048576 - adc_P
    local p = 1048576.0 - adc_p
    -- p = (p - var2/4096) * 6250 / var1
    p = (p - var2 / 4096.0) * 6250.0 / var1
    -- var1 = dig_P9 * p^2 / 2147483648
    var1 = dig_p9 * p * p / 2147483648.0
    -- var2 = p * dig_P8 / 32768
    var2 = p * dig_p8 / 32768.0
    -- p = p + (var1 + var2 + dig_P7) / 16
    p = p + (var1 + var2 + dig_p7) / 16.0
    return math.floor(p / 100.0 + 0.5)  -- Pa → hPa
end

-- BME280 湿度补偿（数据手册 8.1 节 double 公式）
-- @return number or nil 湿度值，单位 %RH
local function compensate_humidity(adc_h)
    if not adc_h or t_fine == 0 then return nil end
    -- var_H = t_fine - 76800
    local var_h = t_fine - 76800.0
    -- var_H = (adc_H - (dig_H4*64 + dig_H5/16384 * var_H)) *
    --   dig_H2/65536 * (1 + dig_H6/67108864 * var_H * (1 + dig_H3/67108864 * var_H))
    var_h = (adc_h - (dig_h4 * 64.0 + dig_h5 / 16384.0 * var_h)) *
            (dig_h2 / 65536.0 * (1.0 + dig_h6 / 67108864.0 * var_h * (1.0 + dig_h3 / 67108864.0 * var_h)))
    -- var_H = var_H * (1 - dig_H1 * var_H / 524288)
    var_h = var_h * (1.0 - dig_h1 * var_h / 524288.0)
    if var_h > 100.0 then var_h = 100.0
    elseif var_h < 0.0 then var_h = 0.0 end
    return var_h
end

-- ==================== 外部 API ====================

--[[
初始化 BMP280/BME280 气压传感器

配置 I2C 引脚，读取芯片校准数据，设置测量模式和 IIR 滤波器。
自动识别芯片型号（BMP280: 0x58, BME280: 0x60）。

@api exs_bmx280.setup(model, config)

@string model 通信模式，当前仅支持 "I2C"（SPI 预留）
@table config 配置参数
  scl - SCL 时钟引脚 GPIO 编号（与 sda 一起可选）
  sda - SDA 数据引脚 GPIO 编号（与 scl 一起可选）
  i2c_id - 硬件 I2C 总线 ID（可选，默认 0）
  filter - IIR 滤波器系数 0~4（可选，默认 0=关闭）

@return boolean

@usage
-- 软件 I2C 模式
local result = exs_bmx280.setup("I2C", {scl = 27, sda = 26})
-- 打开 IIR 滤波
local result = exs_bmx280.setup("I2C", {scl = 27, sda = 26, filter = 4})
]]
function exs_bmx280.setup(model, config)
    if type(model) ~= "string" or type(config) ~= "table" then
        if type(model) == "table" then
            config = model; model = "I2C"
        else
            log.error("exs_bmx280.setup 参数错误"); return false
        end
    end
    if model ~= "I2C" then log.error("exs_bmx280.setup 不支持的模式，当前仅支持 I2C"); return false end

    if config.scl and config.sda then
        g_scl_pin = config.scl; g_sda_pin = config.sda
        if config.i2c_id then
            i2c_bus_recovery()
            if i2c.setup(config.i2c_id, i2c.SLOW) == 0 then log.error("exs_bmx280.setup 硬件 I2C 失败"); return false end
            g_i2c_bus = config.i2c_id; g_is_soft = false
        else
            i2c_bus_recovery()
            g_i2c_bus = i2c.createSoft(config.scl, config.sda, 5)
            if not g_i2c_bus then log.error("exs_bmx280.setup 软件 I2C 失败"); return false end
            g_is_soft = true
        end
    else
        local i2c_id = config.i2c_id or 0
        if i2c.setup(i2c_id, i2c.SLOW) == 0 then log.error("exs_bmx280.setup 硬件 I2C 失败"); return false end
        g_i2c_bus = i2c_id; g_is_soft = false; g_scl_pin = nil; g_sda_pin = nil
    end

    if not chip_detect() then return false end
    i2c_write(REG_SOFT_RESET, 0xB6); sys.wait(20)
    if not read_calibration() then return false end

    local filter = config.filter or 0
    if filter < 0 then filter = 0 elseif filter > 4 then filter = 4 end
    i2c_write(REG_CONFIG, filter << 2)

    -- BME280 需要先写 ctrl_hum，再写 ctrl_meas（数据手册要求）
    if g_chip_type == CHIP_TYPE_BME280 then
        i2c_write(REG_CTRL_HUM, 0x05)  -- osrs_h = ×1
    end
    i2c_write(REG_CTRL_MEAS, 0x3F)

    g_ready = true
    log.info("exs_bmx280", string.format("%s 初始化完成, filter=%d", g_chip_type, filter))
    return true
end

--[[
读取 BMP280/BME280 气压和温度数据

自动进行校准补偿，返回温度和气压值。
如果是 BME280，额外返回湿度值。

@api exs_bmx280.get_data()
@return table or nil
  data.temperature - 温度，单位 °C，如 25.12
  data.pressure    - 气压，单位 hPa，如 1013.25
  data.humidity    - 相对湿度，单位 %RH（仅 BME280 有），如 46.33

@usage
local data = exs_bmx280.get_data()
if data then
    log.info("exs_bmx280", string.format("温度=%.2f°C 气压=%.2fhPa", data.temperature, data.pressure))
end
]]
function exs_bmx280.get_data()
    if not g_ready then log.error("exs_bmx280.get_data 请先 setup()"); return nil end
    local adc_t = read_adc20(REG_TEMP_MSB)
    if not adc_t then log.error("exs_bmx280", "温度读数失败"); return nil end
    local temperature_c = compensate_temperature(adc_t)
    if not temperature_c then log.error("exs_bmx280", "温度补偿失败"); return nil end
    local adc_p = read_adc20(REG_PRESS_MSB)
    if not adc_p then log.error("exs_bmx280", "气压读数失败"); return nil end
    local pressure_pa = compensate_pressure(adc_p)
    if not pressure_pa then log.error("exs_bmx280", "气压补偿失败"); return nil end
    local result = {temperature = temperature_c, pressure = pressure_pa}
    -- BME280 额外读取湿度
    if g_chip_type == CHIP_TYPE_BME280 then
        local adc_h = read_hum_adc()
        if adc_h then
            result.humidity = compensate_humidity(adc_h)
        end
    end
    return result
end

--[[
设置 IIR 滤波器系数

@api exs_bmx280.set_filter(coeff)
@number coeff 滤波器系数 0~4
@return nil
]]
function exs_bmx280.set_filter(coeff)
    if not g_ready then log.error("exs_bmx280.set_filter 请先 setup()"); return end
    coeff = math.max(0, math.min(4, coeff or 0))
    local cur = (i2c_read(REG_CONFIG, 1) or {})[1] or 0
    cur = (cur & 0xE3) | (coeff << 2)
    i2c_write(REG_CONFIG, cur)
    log.info("exs_bmx280", string.format("IIR 滤波器系数设为 %d", coeff))
end

--[[
设置海平面标准气压

@api exs_bmx280.set_sea_level_pressure(pressure)
@number pressure 海平面标准气压，单位 hPa，如 1013.25
@return nil
]]
function exs_bmx280.set_sea_level_pressure(pressure)
    if not pressure then return end
    g_sea_level_pressure = pressure
    log.info("exs_bmx280", string.format("海平面气压设为 %.2fhPa", g_sea_level_pressure))
end

--[[
计算海拔高度

使用已设置的海平面标准气压（set_sea_level_pressure）计算海拔。

@api exs_bmx280.get_altitude(pressure)

@number pressure 当前气压值，单位 hPa

@return number 海拔高度，单位米（小数点后一位）

@usage
local data = exs_bmx280.get_data()
if data then
    local alt = exs_bmx280.get_altitude(data.pressure)
    log.info("exs_bmx280", string.format("海拔=%.1f 米", alt))
end
]]
function exs_bmx280.get_altitude(pressure)
    if not pressure then return nil end
    local p0 = g_sea_level_pressure
    return 44330 * (1 - (pressure / p0) ^ 0.190294957)
end

--[[
读取 BME280 湿度值

仅 BME280 支持此功能，BMP280 调用会提示并返回 nil。

@api exs_bmx280.get_humidity()
@return number or nil 相对湿度，单位 %RH，如 46.33

@usage
local hum = exs_bmx280.get_humidity()
if hum then
    log.info("exs_bmx280", string.format("湿度=%.1f%%RH", hum))
end
]]
function exs_bmx280.get_humidity()
    if not g_ready then log.error("exs_bmx280.get_humidity 请先 setup()"); return nil end
    if g_chip_type ~= CHIP_TYPE_BME280 then
        log.warn("exs_bmx280", "BMP280 不支持湿度测量")
        return nil
    end
    local adc_h = read_hum_adc()
    if not adc_h then log.error("exs_bmx280", "湿度读数失败"); return nil end
    local hum = compensate_humidity(adc_h)
    if not hum then log.error("exs_bmx280", "湿度补偿失败"); return nil end
    return hum
end

--[[
关闭 BMP280/BME280 传感器

@api exs_bmx280.close()
@return nil
]]
function exs_bmx280.close()
    if not g_ready then return end
    i2c_write(REG_CTRL_MEAS, 0x00)
    g_ready = false; g_i2c_bus = 0; g_is_soft = false
    g_scl_pin = nil; g_sda_pin = nil
    log.info("exs_bmx280", "传感器已关闭")
end

--[[
获取 exs_bmx280 库的版本号

@api exs_bmx280.version()
@return string
]]
function exs_bmx280.version() return "202607240000" end

log.debug("exs_bmx280", "version -> " .. exs_bmx280.version())
return exs_bmx280
