--[[
@module  exs_bmp180
@summary BMP180 数字气压传感器扩展库
@version 1.0
@date    2026.07.22
@author  江访
@usage
本文件为 BMP180 数字气压传感器（Bosch Sensortec 出品）的 LuatOS 扩展库。
通过 I2C 接口读取大气压和温度，自动进行校准补偿。

本文件的对外接口有 5 个：
1、exs_bmp180.setup(config)：初始化 BMP180
2、exs_bmp180.get_data()：读取气压和温度
3、exs_bmp180.set_oss(oss)：切换过采样率
4、exs_bmp180.get_altitude(pressure, sea_level_pressure)：计算海拔
5、exs_bmp180.version()：获取版本号

更多说明参考 docs 在线文档

=== 版本更新说明 ===
-- 版本号：202607220900（初版）
-- 1、更新时间：2026-07-22
-- 2、更新内容
--   - 支持 I2C 通信（软件 I2C / 硬件 I2C）
--   - 支持气压和温度读取，自动 E2PROM 校准补偿
--   - 支持过采样率切换（OSS=0/1/2/3）
--   - 支持海拔高度计算
--   - 内置 I2C 总线卡死自动检测与恢复功能
]]

local exs_bmp180 = {}

-- ==================== 寄存器地址 ====================

local REG_CHIP_ID       = 0xD0      -- 芯片 ID 寄存器（固定值 0x55）
local REG_SOFT_RESET    = 0xE0      -- 软复位寄存器（写入 0xB6）
local REG_CTRL          = 0xF4      -- 控制寄存器
local REG_ADC_MSB       = 0xF6      -- ADC 数据高字节
local REG_ADC_LSB       = 0xF7      -- ADC 数据低字节
local REG_ADC_XLSB      = 0xF8      -- ADC 数据扩展低字节

-- E2PROM 校准寄存器地址（0xAA~0xBF，11 个 16 位参数）
local REG_CAL_AC1       = 0xAA      -- AC1 校准参数（signed short）
local REG_CAL_AC2       = 0xAC      -- AC2 校准参数（signed short）
local REG_CAL_AC3       = 0xAE      -- AC3 校准参数（signed short）
local REG_CAL_AC4       = 0xB0      -- AC4 校准参数（unsigned short）
local REG_CAL_AC5       = 0xB2      -- AC5 校准参数（unsigned short）
local REG_CAL_AC6       = 0xB4      -- AC6 校准参数（unsigned short）
local REG_CAL_B1        = 0xB6      -- B1 校准参数（signed short）
local REG_CAL_B2        = 0xB8      -- B2 校准参数（signed short）
local REG_CAL_MB        = 0xBA      -- MB 校准参数（signed short）
local REG_CAL_MC        = 0xBC      -- MC 校准参数（signed short）
local REG_CAL_MD        = 0xBE      -- MD 校准参数（signed short）

-- 控制寄存器（0xF4）命令
local CMD_TEMP          = 0x2E      -- 温度测量
local CMD_PRESS_BASE    = 0x34      -- 气压测量基础值（+ oss<<6）

-- ==================== 常量 ====================

local CHIP_ID_BMP180    = 0x55      -- BMP180 芯片 ID
local DEV_ADDR          = 0x77      -- I2C 7 位地址（0xEE 写 / 0xEF 读）

-- ==================== 内部状态 ====================

local g_i2c_bus         = 0         -- I2C 总线 ID
local g_is_soft         = false     -- 是否为软件 I2C
local g_scl_pin         = nil       -- SCL 引脚号
local g_sda_pin         = nil       -- SDA 引脚号
local g_ready           = false     -- 初始化完成标志
local g_oss             = 0         -- 过采样率（0~3）

-- 校准参数（从 E2PROM 读取）
local g_ac1 = 0; local g_ac2 = 0; local g_ac3 = 0
local g_ac4 = 0; local g_ac5 = 0; local g_ac6 = 0
local g_b1  = 0; local g_b2  = 0; local g_mb  = 0
local g_mc  = 0; local g_md  = 0

-- ==================== I2C 总线恢复 ====================
-- 对 SCL 引脚产生最多 9 个时钟脉冲，释放被从机锁死的 SDA

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
    log.warn("exs_bmp180", "检测到I2C总线卡死，尝试恢复")
    i2c_bus_recovery()
    if not g_is_soft then i2c.setup(g_i2c_bus, i2c.SLOW) end
    return true
end

-- ==================== 底层 I2C 读写 ====================

-- 写寄存器
-- @return boolean
local function i2c_write(reg, val)
    local ok = i2c.send(g_i2c_bus, DEV_ADDR, {reg, val})
    if not ok then
        if try_bus_recovery() then ok = i2c.send(g_i2c_bus, DEV_ADDR, {reg, val}) end
    end
    return ok
end

-- 读指定地址连续 len 个字节
-- @return table or nil
local function i2c_read(reg, len)
    local addr_byte = (len > 1) and (reg | 0x80) or reg
    local ok = i2c.send(g_i2c_bus, DEV_ADDR, {addr_byte})
    if not ok then
        if try_bus_recovery() then ok = i2c.send(g_i2c_bus, DEV_ADDR, {addr_byte}) end
        if not ok then return nil end
    end
    local data = i2c.recv(g_i2c_bus, DEV_ADDR, len)
    if not data then return nil end
    local t = {}
    for i = 1, #data do t[i] = data:byte(i) end
    return t
end

-- 读 16 位有符号值（MSB first）
local function read_s16(reg)
    local buf = i2c_read(reg, 2)
    if not buf or #buf < 2 then return nil end
    local v = (buf[1] << 8) | buf[2]
    if v >= 0x8000 then v = v - 0x10000 end
    return v
end

-- 读 16 位无符号值（MSB first）
local function read_u16(reg)
    local buf = i2c_read(reg, 2)
    if not buf or #buf < 2 then return nil end
    return (buf[1] << 8) | buf[2]
end

-- ==================== 内部函数 ====================

-- 启动测量并等待完成
-- @return boolean 成功返回 true
local function start_measurement(cmd, wait_ms)
    if not i2c_write(REG_CTRL, cmd) then return false end
    sys.wait(wait_ms)
    return true
end

-- 读取原始温度值 UT（16 位）
-- @return number or nil
local function read_ut()
    if not start_measurement(CMD_TEMP, 5) then return nil end
    return read_u16(REG_ADC_MSB)
end

-- 读取原始气压值 UP（16~19 位，取决于 OSS）
-- @return number or nil
local function read_up()
    local wait_times = {5, 8, 14, 26}  -- OSS 0~3 对应等待时间（ms）
    local cmd = CMD_PRESS_BASE | (g_oss << 6)
    if not start_measurement(cmd, wait_times[g_oss + 1]) then return nil end
    local buf = i2c_read(REG_ADC_MSB, 3)
    if not buf or #buf < 3 then return nil end
    local up = (buf[1] << 16) | (buf[2] << 8) | buf[3]
    up = up >> (8 - g_oss)
    return up
end

-- ==================== 校准补偿算法 ====================
-- 基于 BMP180 数据手册第 3.5 节公式，使用 32 位整数计算

-- 补偿温度计算
-- @return number or nil 温度值，单位 0.1°C（如 251 = 25.1°C）
local function calc_temperature(ut)
    if not ut then return nil end
    local x1 = math.floor(((ut - g_ac6) * g_ac5) / 32768)  -- / 2^15
    local x2 = math.floor((g_mc * 2048) / (x1 + g_md))     -- * 2^11
    local b5 = x1 + x2
    return math.floor((b5 + 8) / 16), b5  -- / 2^4
end

-- 补偿气压计算
-- @return number or nil 气压值，单位 Pa
local function calc_pressure(up, b5)
    if not up or not b5 then return nil end
    local b6 = b5 - 4000
    local x1 = math.floor((g_b2 * math.floor(b6 * b6 / 4096)) / 2048)  -- / 2^12 then / 2^11
    local x2 = math.floor((g_ac2 * b6) / 2048)
    local x3 = x1 + x2
    local b3 = math.floor(((g_ac1 * 4 + x3) * (1 << g_oss) + 2) / 4)
    x1 = math.floor((g_ac3 * b6) / 8192)   -- / 2^13
    x2 = math.floor((g_b1 * math.floor(b6 * b6 / 4096)) / 65536)  -- / 2^12 then / 2^16
    x3 = math.floor((x1 + x2 + 2) / 4)     -- / 2^2
    local b4 = math.floor((g_ac4 * (x3 + 32768)) / 32768)  -- / 2^15
    local b7 = (up - b3) * (50000 >> g_oss)
    local p
    if b7 < 0x80000000 then
        p = math.floor((b7 * 2) / b4)
    else
        p = math.floor((b7 / b4) * 2)
    end
    x1 = math.floor((p >> 8) * (p >> 8))
    x1 = math.floor((x1 * 3038) / 65536)   -- / 2^16
    x2 = math.floor((-7357 * p) / 65536)
    p = p + math.floor((x1 + x2 + 3791) / 16)  -- / 2^4
    return p
end

-- ==================== 器件检测与校准数据读取 ====================

local function chip_detect()
    local buf = i2c_read(REG_CHIP_ID, 1)
    if not buf or #buf < 1 or buf[1] ~= CHIP_ID_BMP180 then
        log.error("exs_bmp180", "未检测到 BMP180，CHIP_ID=" .. (buf and buf[1] or "nil"))
        return false
    end
    log.info("exs_bmp180", string.format("BMP180 @ I2C 0x%02X, CHIP_ID=0x%02X", DEV_ADDR, buf[1]))
    return true
end

local function read_calibration()
    g_ac1 = read_s16(REG_CAL_AC1); g_ac2 = read_s16(REG_CAL_AC2); g_ac3 = read_s16(REG_CAL_AC3)
    g_ac4 = read_u16(REG_CAL_AC4); g_ac5 = read_u16(REG_CAL_AC5); g_ac6 = read_u16(REG_CAL_AC6)
    g_b1  = read_s16(REG_CAL_B1);  g_b2  = read_s16(REG_CAL_B2)
    g_mb  = read_s16(REG_CAL_MB);  g_mc  = read_s16(REG_CAL_MC);  g_md  = read_s16(REG_CAL_MD)

    -- 验证校准数据是否有效（AC1~AC6 应非零）
    if g_ac4 == 0 or g_ac5 == 0 or g_ac6 == 0 then
        log.error("exs_bmp180", "校准数据读取失败，AC4/AC5/AC6 为零")
        return false
    end
    log.info("exs_bmp180", string.format("校准数据: AC1=%d AC2=%d AC3=%d AC4=%d AC5=%d AC6=%d",
        g_ac1, g_ac2, g_ac3, g_ac4, g_ac5, g_ac6))
    return true
end

-- ==================== 外部 API ====================

--[[
初始化 BMP180 气压传感器

配置 I2C 引脚，读取芯片校准数据。

@api exs_bmp180.setup(config)

@table config 配置参数（可选，见下方）

scl
SCL 时钟引脚 GPIO 编号；
与 sda 一起传入时用于总线恢复；
无 i2c_id 时自动创建软件 I2C；
数据类型：number
是否必选：与 sda 一起可选

sda
SDA 数据引脚 GPIO 编号；
数据类型：number
是否必选：与 scl 一起可选

i2c_id
硬件 I2C 总线 ID；
与 scl/sda 一起传时使用硬件 I2C + 引脚恢复；
不传 scl/sda 时使用硬件 I2C，无总线恢复；
数据类型：number
是否必选：可选（默认 0）

oss
过采样率，可选 0~3，默认 0；
0=ultra low power（4.5ms，0.06hPa 噪声）
1=standard（7.5ms）
2=high resolution（13.5ms）
3=ultra high resolution（25.5ms，0.02hPa 噪声）
数据类型：number
是否必选：可选

@return boolean
初始化成功返回 true，失败返回 false

@usage
-- 方式一：软件 I2C 模式
local result = exs_bmp180.setup({
    scl = 27,
    sda = 26,
})

-- 方式二：硬件 I2C 模式 + 总线恢复
local result = exs_bmp180.setup({
    i2c_id = 0,
    scl = 27,
    sda = 26,
})

-- 方式三：超高分辨率模式
local result = exs_bmp180.setup({
    scl = 27,
    sda = 26,
    oss = 3,
})
]]
function exs_bmp180.setup(config)
    if type(config) ~= "table" then config = {} end

    -- 初始化 I2C 总线
    if config.scl and config.sda then
        g_scl_pin = config.scl; g_sda_pin = config.sda
        if config.i2c_id then
            i2c_bus_recovery()
            if i2c.setup(config.i2c_id, i2c.SLOW) == 0 then
                log.error("exs_bmp180.setup 硬件 I2C 初始化失败")
                return false
            end
            g_i2c_bus = config.i2c_id; g_is_soft = false
        else
            i2c_bus_recovery()
            g_i2c_bus = i2c.createSoft(config.scl, config.sda, 5)
            if not g_i2c_bus then
                log.error("exs_bmp180.setup 软件 I2C 创建失败")
                return false
            end
            g_is_soft = true
        end
    else
        local i2c_id = config.i2c_id or 0
        if i2c.setup(i2c_id, i2c.SLOW) == 0 then
            log.error("exs_bmp180.setup 硬件 I2C 初始化失败")
            return false
        end
        g_i2c_bus = i2c_id; g_is_soft = false; g_scl_pin = nil; g_sda_pin = nil
    end

    -- 检测芯片
    if not chip_detect() then return false end

    -- 读取校准数据
    if not read_calibration() then return false end

    g_oss = config.oss or 0
    if g_oss < 0 then g_oss = 0 elseif g_oss > 3 then g_oss = 3 end

    g_ready = true
    log.info("exs_bmp180", string.format("初始化完成, oss=%d", g_oss))
    return true
end

--[[
读取 BMP180 气压和温度数据

自动进行校准补偿，返回温度和气压值。
温度精度 0.1°C，气压精度 1Pa（0.01hPa）。

@api exs_bmp180.get_data()

@return table or nil
成功返回包含 temperature 和 pressure 键的 table：
  data.temperature - 温度，单位 °C，如 25.1
  data.pressure    - 气压，单位 Pa，如 101325

@usage
local data = exs_bmp180.get_data()
if data then
    log.info("exs_bmp180", string.format("温度=%.1f°C 气压=%.1fPa", data.temperature, data.pressure))
end
]]
function exs_bmp180.get_data()
    if not g_ready then log.error("exs_bmp180.get_data 请先 setup()"); return nil end

    -- 读取原始温度
    local ut = read_ut()
    if not ut then
        log.error("exs_bmp180", "温度测量失败")
        return nil
    end

    -- 计算温度，同时得到 b5 用于气压补偿
    local temp_c1, b5 = calc_temperature(ut)
    if not temp_c1 then
        log.error("exs_bmp180", "温度补偿计算失败")
        return nil
    end
    local temperature = temp_c1 / 10

    -- 读取原始气压
    local up = read_up()
    if not up then
        log.error("exs_bmp180", "气压测量失败")
        return nil
    end

    -- 计算气压
    local pressure_pa = calc_pressure(up, b5)
    if not pressure_pa then
        log.error("exs_bmp180", "气压补偿计算失败")
        return nil
    end

    return {temperature = temperature, pressure = pressure_pa}
end

--[[
切换过采样率

过采样率越高，精度越高但转换时间越长。

@api exs_bmp180.set_oss(oss)

@number oss
过采样率，可选 0~3：
0=ultra low power（4.5ms，0.06hPa 噪声）
1=standard（7.5ms）
2=high resolution（13.5ms）
3=ultra high resolution（25.5ms，0.02hPa 噪声）

@return nil

@usage
exs_bmp180.set_oss(3)
]]
function exs_bmp180.set_oss(oss)
    if not g_ready then log.error("exs_bmp180.set_oss 请先 setup()"); return end
    oss = math.max(0, math.min(3, oss or 0))
    g_oss = oss
    log.info("exs_bmp180", string.format("过采样率切换为 oss=%d", oss))
end

--[[
计算海拔高度

使用国际气压公式计算海拔高度。

@api exs_bmp180.get_altitude(pressure, sea_level_pressure)

@number pressure 当前气压值，单位 Pa（来自 get_data() 返回的 data.pressure）
@number sea_level_pressure 海平面标准气压，单位 Pa，默认 101325

@return number 海拔高度，单位米

@usage
local data = exs_bmp180.get_data()
if data then
    local alt = exs_bmp180.get_altitude(data.pressure)
    log.info("exs_bmp180", string.format("海拔=%.1f 米", alt))
end
]]
function exs_bmp180.get_altitude(pressure, sea_level_pressure)
    if not pressure then return nil end
    sea_level_pressure = sea_level_pressure or 101325
    -- 国际气压公式：altitude = 44330 * (1 - (p/p0)^(1/5.255))
    local ratio = pressure / sea_level_pressure
    return 44330 * (1 - ratio ^ 0.190294957)
end

--[[
获取 exs_bmp180 库的版本号

@api exs_bmp180.version()

@return string

@usage
local ver = exs_bmp180.version()
]]
function exs_bmp180.version()
    return "202607220900"
end

log.debug("exs_bmp180", "version -> " .. exs_bmp180.version())
return exs_bmp180
