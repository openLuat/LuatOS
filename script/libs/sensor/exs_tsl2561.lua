--[[
@module  exs_tsl2561
@summary TSL2561 数字环境光传感器驱动扩展库
@version 1.0
@date    2026.08.26
@author  沈园园
@usage
本文件为 TAOS TSL2561 光数字转换器（环境光传感器）的 LuatOS 扩展库，核心功能为：
1、初始化 TSL2561，配置 I2C 通信参数（默认 I2C1，400kHz 快速模式），读取 ID 寄存器验证芯片型号；
2、支持双通道（CH0 可见光+红外、CH1 仅红外）16 位原始数据读取；
3、支持增益（1x/16x）和积分时间（13.7ms/101ms/402ms/手动）配置；
4、支持 lux 照度计算（T/FN/CL 封装系数，自动红外补偿）；
5、支持阈值中断（基于 CH0）设置与清除；
6、支持上电、断电、复位等电源管理功能。

本文件的对外接口有 14 个：
1、exs_tsl2561.init(i2c_id, slave_address)：初始化 TSL2561
2、exs_tsl2561.deinit()：关闭 TSL2561 通信
3、exs_tsl2561.set_timing(gain, integ)：设置增益和积分时间
4、exs_tsl2561.get_lux()：读取照度 lux 值
5、exs_tsl2561.get_data()：读取 CH0/CH1 双通道原始数据
6、exs_tsl2561.manual_start()：手动积分开始
7、exs_tsl2561.manual_stop()：手动积分停止
8、exs_tsl2561.set_interrupt(low, high, persist)：设置阈值中断
9、exs_tsl2561.clear_interrupt()：清除中断
10、exs_tsl2561.get_id()：读取 ID 寄存器
11、exs_tsl2561.power_up()：上电
12、exs_tsl2561.power_down()：断电
13、exs_tsl2561.reset()：复位（恢复默认配置）
14、exs_tsl2561.version()：获取版本号

-- 版本更新说明
-- 版本号：202608262000
-- 1、更新时间：2026-08-26 20:00
-- 2、更新内容
  - 第一版，实现 TSL2561 基础驱动功能
  - 支持 I2C 通信（Air780EHV I2C1：SCL=67，SDA=66），默认从机地址 0x39（ADDR SEL 悬空）
  - 支持双通道 16 位原始数据读取（CH0 可见光+红外 / CH1 仅红外）
  - 支持增益（1x/16x）和积分时间（13.7ms/101ms/402ms/手动）配置
  - 支持 lux 照度计算（T/FN/CL 封装分段公式，自动红外补偿）
  - 支持阈值中断（基于 CH0）设置与清除
  - 支持上电、断电、复位电源管理
]]

local exs_tsl2561 = {}

-- ==================== 模块常量 ====================

-- TSL2561 I2C 从机地址（由 ADDR SEL 引脚决定，数据手册 Table 1）
local DEV_ADDR_GND   = 0x29  -- ADDR SEL 接地
local DEV_ADDR_FLOAT = 0x39  -- ADDR SEL 悬空（默认）
local DEV_ADDR_VDD   = 0x49  -- ADDR SEL 接 VDD

-- 命令字节位定义（数据手册 Table 3）
local CMD_BASE      = 0x80  -- CMD 位（bit7），必须为 1
local CMD_CLEAR     = 0x40  -- CLEAR 位（bit6），清除中断（自清零）
local CMD_WORD      = 0x20  -- WORD 位（bit5），字协议（16 位）
local CMD_BLOCK     = 0x10  -- BLOCK 位（bit4），块协议（32 位）

-- 寄存器地址（数据手册 Table 2）
local REG_CONTROL     = 0x00  -- 控制寄存器
local REG_TIMING      = 0x01  -- 积分时间/增益控制寄存器
local REG_THRESH_LOW  = 0x02  -- 低阈值低字节
local REG_THRESH_HIGH = 0x04  -- 高阈值低字节
local REG_INTERRUPT   = 0x06  -- 中断控制寄存器
local REG_ID          = 0x0A  -- ID 寄存器
local REG_DATA0       = 0x0C  -- ADC 通道 0 数据寄存器（低字节）
local REG_DATA1       = 0x0E  -- ADC 通道 1 数据寄存器（低字节）

-- 控制寄存器值（数据手册 Table 4）
local CTRL_POWER_UP   = 0x03  -- 上电
local CTRL_POWER_DOWN = 0x00  -- 断电

-- 时序寄存器位定义（数据手册 Table 5）
local TIMING_GAIN_16X   = 0x10  -- 高增益 16x（bit4=1）
local TIMING_MANUAL     = 0x08  -- 手动积分控制位（bit3）
local TIMING_INTEG_MASK = 0x03  -- 积分时间字段掩码（bit1:0）

-- 积分时间字段值（数据手册 Table 6）
local INTEG_13MS   = 0  -- 13.7ms
local INTEG_101MS  = 1  -- 101ms
local INTEG_402MS  = 2  -- 402ms
local INTEG_MANUAL = 3  -- 手动积分

-- 积分时间对应毫秒数（用于 lux 计算归一化，13.7ms 取整为 14ms，Arduino 库惯例）
local INTEG_MS_TABLE = {14, 101, 402, 0}

-- 中断控制寄存器位定义（数据手册 Table 8/9/10）
local INTR_LEVEL    = 0x10  -- INTR=01 电平中断（bit5:4 = 01）
local INTR_DISABLED = 0x00  -- INTR=00 中断禁用

-- ID 寄存器期望值（数据手册 Table 11）：PARTNO=0001 表示 TSL2561
local ID_PARTNO_MASK = 0xF0  -- PARTNO 位掩码（bit7:4）
local ID_PARTNO_2561 = 0x10  -- TSL2561 的 PARTNO 值

-- 默认 I2C 参数
local DEFAULT_I2C_ID = 1              -- I2C1（Air780EHV：SCL=67，SDA=66）
local DEFAULT_ADDR   = DEV_ADDR_FLOAT -- 默认从机地址 0x39（ADDR SEL 悬空）

-- 默认时序参数
local DEFAULT_GAIN  = 0    -- 默认低增益 1x（对应 exs_tsl2561.GAIN_1X）
local DEFAULT_INTEG = INTEG_402MS  -- 默认积分时间 402ms（数据手册默认值）

-- ==================== 对外常量 ====================

-- 从机地址常量（由 ADDR SEL 引脚决定）
exs_tsl2561.ADDR_GND   = DEV_ADDR_GND   -- ADDR SEL 接地，地址 0x29
exs_tsl2561.ADDR_FLOAT = DEV_ADDR_FLOAT -- ADDR SEL 悬空，地址 0x39（默认）
exs_tsl2561.ADDR_VDD   = DEV_ADDR_VDD   -- ADDR SEL 接 VDD，地址 0x49

-- 增益常量
exs_tsl2561.GAIN_1X  = 0  -- 低增益 1x
exs_tsl2561.GAIN_16X = 1  -- 高增益 16x

-- 积分时间常量
exs_tsl2561.INTEG_13MS   = INTEG_13MS   -- 13.7ms（满量程 5047）
exs_tsl2561.INTEG_101MS  = INTEG_101MS  -- 101ms（满量程 37177）
exs_tsl2561.INTEG_402MS  = INTEG_402MS  -- 402ms（满量程 65535）
exs_tsl2561.INTEG_MANUAL = INTEG_MANUAL -- 手动积分（Manual 位控制启停）

-- 中断持久次数（PERSIST 字段，0~15）
exs_tsl2561.PERSIST_EVERY = 0  -- 每次 ADC 积分周期都产生中断
exs_tsl2561.PERSIST_ONCE  = 1  -- 超出阈值 1 次即产生中断
exs_tsl2561.PERSIST_3     = 3  -- 连续 3 次超出阈值才产生中断

-- ==================== 内部状态 ====================

exs_tsl2561.i2c_id        = nil  -- I2C 总线 ID
exs_tsl2561.slave_address = nil  -- 从设备地址
exs_tsl2561.gain          = DEFAULT_GAIN   -- 当前增益（0=1x，1=16x）
exs_tsl2561.integ         = DEFAULT_INTEG  -- 当前积分时间字段值
exs_tsl2561.powered       = false -- 当前是否处于上电状态

-- ==================== I2C 底层操作 ====================

-- 构造命令字节
-- @param reg 寄存器地址（0~15）
-- @param word 是否使用字协议（16 位）
-- @return number 命令字节
local function build_cmd(reg, word)
    local cmd = bit.bor(CMD_BASE, bit.band(reg, 0x0F))
    if word then
        cmd = bit.bor(cmd, CMD_WORD)
    end
    return cmd
end

-- 写寄存器（单字节）
-- @param reg 寄存器地址
-- @param value 写入值
-- @return boolean 成功返回 true，失败返回 false
local function write_reg(reg, value)
    if not exs_tsl2561.i2c_id or not exs_tsl2561.slave_address then
        log.error("exs_tsl2561", "设备未初始化")
        return false
    end
    local cmd = build_cmd(reg, false)
    local result = i2c.send(exs_tsl2561.i2c_id, exs_tsl2561.slave_address, string.char(cmd, value))
    if not result then
        log.error("exs_tsl2561", string.format("I2C 写寄存器失败, reg=0x%02X", reg))
        return false
    end
    return true
end

-- 读寄存器（单字节）
-- @param reg 寄存器地址
-- @return number 成功返回寄存器值，失败返回 nil
local function read_reg(reg)
    if not exs_tsl2561.i2c_id or not exs_tsl2561.slave_address then
        log.error("exs_tsl2561", "设备未初始化")
        return nil
    end
    local cmd = build_cmd(reg, false)
    if not i2c.send(exs_tsl2561.i2c_id, exs_tsl2561.slave_address, cmd) then
        log.error("exs_tsl2561", string.format("I2C 发送命令失败, reg=0x%02X", reg))
        return nil
    end
    local data = i2c.recv(exs_tsl2561.i2c_id, exs_tsl2561.slave_address, 1)
    if not data or #data ~= 1 then
        log.error("exs_tsl2561", string.format("I2C 读寄存器失败, reg=0x%02X", reg))
        return nil
    end
    return data:byte(1)
end

-- 读 16 位数据（字协议）
-- TSL2561 字协议低字节在前：先输出 DATAxLOW，再输出 DATAxHIGH（数据手册 Figure 15）
-- @param reg 寄存器地址（低字节地址）
-- @return number 成功返回 16 位值，失败返回 nil
local function read_word(reg)
    if not exs_tsl2561.i2c_id or not exs_tsl2561.slave_address then
        log.error("exs_tsl2561", "设备未初始化")
        return nil
    end
    local cmd = build_cmd(reg, true)  -- 设置 WORD 位
    if not i2c.send(exs_tsl2561.i2c_id, exs_tsl2561.slave_address, cmd) then
        log.error("exs_tsl2561", string.format("I2C 发送命令失败, reg=0x%02X", reg))
        return nil
    end
    local data = i2c.recv(exs_tsl2561.i2c_id, exs_tsl2561.slave_address, 2)
    if not data or #data ~= 2 then
        log.error("exs_tsl2561", string.format("I2C 读字失败, reg=0x%02X", reg))
        return nil
    end
    -- 字协议：第一个字节为低字节，第二个字节为高字节
    local low = data:byte(1)
    local high = data:byte(2)
    return high * 256 + low
end

-- 写 16 位数据（字协议，低字节在前）
-- @param reg 寄存器地址（低字节地址）
-- @param value 16 位值
-- @return boolean 成功返回 true，失败返回 false
local function write_word(reg, value)
    if not exs_tsl2561.i2c_id or not exs_tsl2561.slave_address then
        log.error("exs_tsl2561", "设备未初始化")
        return false
    end
    local cmd = build_cmd(reg, true)
    local low = bit.band(value, 0xFF)
    local high = bit.rshift(value, 8)
    local result = i2c.send(exs_tsl2561.i2c_id, exs_tsl2561.slave_address, string.char(cmd, low, high))
    if not result then
        log.error("exs_tsl2561", string.format("I2C 写字失败, reg=0x%02X", reg))
        return false
    end
    return true
end

-- 获取当前积分时间对应的毫秒数（用于 lux 计算归一化）
-- @return number 积分时间毫秒数
local function get_integ_ms()
    return INTEG_MS_TABLE[exs_tsl2561.integ + 1] or 402
end

-- 计算照度 lux 值（T/FN/CL 封装分段公式）
-- 参考数据手册第 23 页 + SFE_TSL2561.cpp getLux() 浮点实现：
--   ratio 使用原始 CH1/CH0 比值（归一化前计算）
--   d0/d1 归一化到 402ms 基准，低增益（1x）时放大 16 倍
-- @param ch0 通道 0 原始值（可见光+红外）
-- @param ch1 通道 1 原始值（仅红外）
-- @return number 照度 lux 值（饱和或无意义时为 0）
local function calc_lux(ch0, ch1)
    -- 饱和检查：任一通道为 0xFFFF 表示 ADC 饱和，lux 记为 0
    if ch0 == 0xFFFF or ch1 == 0xFFFF then
        log.warn("exs_tsl2561", string.format("ADC 饱和（CH0=0x%04X, CH1=0x%04X），lux 记为 0", ch0, ch1))
        return 0
    end
    -- 原始比例（归一化前计算）
    local ratio = 0
    if ch0 > 0 then
        ratio = ch1 / ch0
    end
    -- 归一化积分时间（以 402ms 为基准）
    local ms = get_integ_ms()
    local d0 = ch0 * (402.0 / ms)
    local d1 = ch1 * (402.0 / ms)
    -- 归一化增益（低增益 1x 时放大 16 倍）
    if exs_tsl2561.gain == exs_tsl2561.GAIN_1X then
        d0 = d0 * 16
        d1 = d1 * 16
    end
    -- 分段公式（T/FN/CL 封装）
    local lux = 0
    if ratio < 0.5 then
        lux = 0.0304 * d0 - 0.062 * d0 * (ratio ^ 1.4)
    elseif ratio < 0.61 then
        lux = 0.0224 * d0 - 0.031 * d1
    elseif ratio < 0.80 then
        lux = 0.0128 * d0 - 0.0153 * d1
    elseif ratio < 1.30 then
        lux = 0.00146 * d0 - 0.00112 * d1
    else
        lux = 0
    end
    if lux < 0 then
        lux = 0
    end
    return lux
end

-- ==================== 对外接口 ====================

-- 初始化 TSL2561
-- 流程：初始化 I2C → 上电 → 读取 ID 验证芯片型号（PARTNO=0001）→ 设置默认时序
-- @param i2c_id I2C 总线 ID，默认 1（Air780EHV：SCL=67，SDA=66）
-- @param slave_address 从机地址，默认 0x39（ADDR SEL 悬空），可选 0x29（接地）/0x49（接 VDD）
-- @return boolean 成功返回 true，失败返回 false
function exs_tsl2561.init(i2c_id, slave_address)
    -- 参数默认值
    if i2c_id == nil then i2c_id = DEFAULT_I2C_ID end
    if slave_address == nil then slave_address = DEFAULT_ADDR end

    -- 参数校验
    if slave_address ~= DEV_ADDR_GND and slave_address ~= DEV_ADDR_FLOAT and slave_address ~= DEV_ADDR_VDD then
        log.error("exs_tsl2561.init", string.format("无效的从机地址: 0x%02X（应为 0x29/0x39/0x49）", slave_address))
        return false
    end

    -- 初始化 I2C（400kHz 快速模式）
    if i2c.setup(i2c_id, i2c.FAST) ~= 1 then
        log.error("exs_tsl2561.init", "I2C 初始化失败, i2c_id=", i2c_id)
        return false
    end
    exs_tsl2561.i2c_id = i2c_id
    exs_tsl2561.slave_address = slave_address
    exs_tsl2561.gain = DEFAULT_GAIN
    exs_tsl2561.integ = DEFAULT_INTEG
    exs_tsl2561.powered = false

    -- 上电（写 CONTROL=0x03，若设备不在线则写失败，可据此判断接线/供电/地址）
    if not exs_tsl2561.power_up() then
        log.error("exs_tsl2561.init", string.format("指定从设备地址无响应: 0x%02X，请检查接线/供电/地址配置", slave_address))
        return false
    end

    -- 读取 ID 寄存器验证芯片型号（PARTNO=0001 表示 TSL2561）
    local id = exs_tsl2561.get_id()
    if not id then
        log.error("exs_tsl2561.init", "读取 ID 寄存器失败")
        return false
    end
    if bit.band(id, ID_PARTNO_MASK) ~= ID_PARTNO_2561 then
        log.error("exs_tsl2561.init", string.format("芯片型号不匹配: ID=0x%02X（PARTNO 应为 0001=TSL2561）", id))
        return false
    end

    -- 设置默认时序（低增益 1x + 402ms）
    if not exs_tsl2561.set_timing(exs_tsl2561.gain, exs_tsl2561.integ) then
        log.error("exs_tsl2561.init", "时序设置失败")
        return false
    end

    log.info("exs_tsl2561.init", "初始化完成, i2c=", i2c_id, "addr=0x" .. string.format("%02X", slave_address), "id=0x" .. string.format("%02X", id), "gain=1x, integ=402ms")
    return true
end

-- 关闭 TSL2561 通信，释放 I2C 总线
-- @return boolean 成功返回 true
function exs_tsl2561.deinit()
    if not exs_tsl2561.i2c_id or not exs_tsl2561.slave_address then
        log.warn("exs_tsl2561.deinit", "设备未初始化")
        return false
    end
    -- 断电，进入低功耗
    exs_tsl2561.power_down()
    -- 关闭 I2C 总线
    i2c.close(exs_tsl2561.i2c_id)
    -- 重置内部状态
    exs_tsl2561.i2c_id = nil
    exs_tsl2561.slave_address = nil
    exs_tsl2561.gain = DEFAULT_GAIN
    exs_tsl2561.integ = DEFAULT_INTEG
    exs_tsl2561.powered = false
    log.info("exs_tsl2561.deinit", "已关闭")
    return true
end

-- 设置增益和积分时间
-- @param gain 增益常量（exs_tsl2561.GAIN_1X=0 / GAIN_16X=1）
-- @param integ 积分时间常量（exs_tsl2561.INTEG_13MS / INTEG_101MS / INTEG_402MS / INTEG_MANUAL）
-- @return boolean 成功返回 true，失败返回 false
function exs_tsl2561.set_timing(gain, integ)
    if not exs_tsl2561.i2c_id or not exs_tsl2561.slave_address then
        log.warn("exs_tsl2561.set_timing", "设备未初始化")
        return false
    end
    if gain ~= exs_tsl2561.GAIN_1X and gain ~= exs_tsl2561.GAIN_16X then
        log.error("exs_tsl2561.set_timing", "无效的增益: ", gain, "（应为 0=1x 或 1=16x）")
        return false
    end
    if integ < INTEG_13MS or integ > INTEG_MANUAL then
        log.error("exs_tsl2561.set_timing", "无效的积分时间: ", integ, "（应为 0~3）")
        return false
    end

    -- 读取当前 TIMING 寄存器（保留其他位）
    local timing = read_reg(REG_TIMING)
    if not timing then
        log.error("exs_tsl2561.set_timing", "读取 TIMING 寄存器失败")
        return false
    end

    -- 设置增益位（bit4）：1=高增益 16x，0=低增益 1x
    if gain == exs_tsl2561.GAIN_16X then
        timing = bit.bor(timing, TIMING_GAIN_16X)
    else
        timing = bit.band(timing, bit.bnot(TIMING_GAIN_16X))
    end

    -- 设置积分时间字段（bit1:0）
    timing = bit.band(timing, bit.bnot(TIMING_INTEG_MASK))
    timing = bit.bor(timing, bit.band(integ, TIMING_INTEG_MASK))

    -- 写回 TIMING 寄存器
    if not write_reg(REG_TIMING, timing) then
        log.error("exs_tsl2561.set_timing", "写 TIMING 寄存器失败")
        return false
    end

    exs_tsl2561.gain = gain
    exs_tsl2561.integ = integ
    log.info("exs_tsl2561.set_timing", "设置时序成功, gain=", gain, "integ=", integ)
    return true
end

-- 读取照度 lux 值
-- 自动完成：读取 CH0/CH1 双通道原始数据 → 按当前增益/积分时间归一化 → 分段公式计算 lux
-- @return number 成功返回照度 lux 值（浮点数），失败返回 nil
function exs_tsl2561.get_lux()
    if not exs_tsl2561.i2c_id or not exs_tsl2561.slave_address then
        log.warn("exs_tsl2561.get_lux", "设备未初始化")
        return nil
    end
    local data = exs_tsl2561.get_data()
    if not data then
        return nil
    end
    local lux = calc_lux(data.ch0, data.ch1)
    log.info("exs_tsl2561.get_lux", "照度读取成功, ch0=", data.ch0, "ch1=", data.ch1, "lux=", string.format("%.1f", lux))
    return lux
end

-- 读取 CH0/CH1 双通道原始测量数据（16 位）
-- @return table 成功返回 {ch0=通道0原始值, ch1=通道1原始值}，失败返回 nil
function exs_tsl2561.get_data()
    if not exs_tsl2561.i2c_id or not exs_tsl2561.slave_address then
        log.warn("exs_tsl2561.get_data", "设备未初始化")
        return nil
    end
    if not exs_tsl2561.powered then
        log.warn("exs_tsl2561.get_data", "设备未上电，请先调用 power_up")
        return nil
    end
    -- 读取通道 0 和通道 1（字协议，低字节在前）
    local ch0 = read_word(REG_DATA0)
    if not ch0 then
        return nil
    end
    local ch1 = read_word(REG_DATA1)
    if not ch1 then
        return nil
    end
    return {ch0 = ch0, ch1 = ch1}
end

-- 手动积分开始
-- 将 INTEG 字段置为 11（手动积分模式），再置 Manual 位为 1 开始积分
-- @return boolean 成功返回 true，失败返回 false
function exs_tsl2561.manual_start()
    if not exs_tsl2561.i2c_id or not exs_tsl2561.slave_address then
        log.warn("exs_tsl2561.manual_start", "设备未初始化")
        return false
    end
    local timing = read_reg(REG_TIMING)
    if not timing then
        log.error("exs_tsl2561.manual_start", "读取 TIMING 寄存器失败")
        return false
    end
    -- 设置 INTEG=11（手动积分模式）
    timing = bit.bor(timing, TIMING_INTEG_MASK)
    if not write_reg(REG_TIMING, timing) then
        log.error("exs_tsl2561.manual_start", "设置手动积分模式失败")
        return false
    end
    -- 设置 Manual=1 开始积分
    timing = bit.bor(timing, TIMING_MANUAL)
    if not write_reg(REG_TIMING, timing) then
        log.error("exs_tsl2561.manual_start", "启动手动积分失败")
        return false
    end
    log.info("exs_tsl2561.manual_start", "手动积分已开始")
    return true
end

-- 手动积分停止
-- 清除 Manual 位停止积分，积分结果保留在 DATA0/DATA1 寄存器中
-- @return boolean 成功返回 true，失败返回 false
function exs_tsl2561.manual_stop()
    if not exs_tsl2561.i2c_id or not exs_tsl2561.slave_address then
        log.warn("exs_tsl2561.manual_stop", "设备未初始化")
        return false
    end
    local timing = read_reg(REG_TIMING)
    if not timing then
        log.error("exs_tsl2561.manual_stop", "读取 TIMING 寄存器失败")
        return false
    end
    -- 清除 Manual 位停止积分
    timing = bit.band(timing, bit.bnot(TIMING_MANUAL))
    if not write_reg(REG_TIMING, timing) then
        log.error("exs_tsl2561.manual_stop", "停止手动积分失败")
        return false
    end
    log.info("exs_tsl2561.manual_stop", "手动积分已停止")
    return true
end

-- 设置阈值中断（电平中断模式）
-- 中断基于通道 0（CH0）的值：低于低阈值或高于高阈值时触发，INT 引脚拉低
-- @param low 低阈值（16 位，基于 CH0 原始值）
-- @param high 高阈值（16 位，基于 CH0 原始值）
-- @param persist 中断持久次数（0~15）：0=每次 ADC 周期都触发；N=连续 N 次超出阈值才触发
-- @return boolean 成功返回 true，失败返回 false
function exs_tsl2561.set_interrupt(low, high, persist)
    if not exs_tsl2561.i2c_id or not exs_tsl2561.slave_address then
        log.warn("exs_tsl2561.set_interrupt", "设备未初始化")
        return false
    end
    if persist == nil then persist = 1 end
    if persist < 0 or persist > 15 then
        log.error("exs_tsl2561.set_interrupt", "无效的持久次数: ", persist, "（应为 0~15）")
        return false
    end
    -- 写低阈值（字协议，低字节在前）
    if not write_word(REG_THRESH_LOW, low) then
        log.error("exs_tsl2561.set_interrupt", "写低阈值失败")
        return false
    end
    -- 写高阈值（字协议，低字节在前）
    if not write_word(REG_THRESH_HIGH, high) then
        log.error("exs_tsl2561.set_interrupt", "写高阈值失败")
        return false
    end
    -- 设置中断控制：电平中断（INTR=01）+ PERSIST
    local int_ctl = bit.bor(INTR_LEVEL, bit.band(persist, 0x0F))
    if not write_reg(REG_INTERRUPT, int_ctl) then
        log.error("exs_tsl2561.set_interrupt", "写中断控制寄存器失败")
        return false
    end
    log.info("exs_tsl2561.set_interrupt", "阈值中断设置成功, low=", low, "high=", high, "persist=", persist)
    return true
end

-- 清除中断
-- 通过向命令字节写入 CLEAR 位（0xC0）清除挂起的中断，INT 引脚释放
-- @return boolean 成功返回 true，失败返回 false
function exs_tsl2561.clear_interrupt()
    if not exs_tsl2561.i2c_id or not exs_tsl2561.slave_address then
        log.warn("exs_tsl2561.clear_interrupt", "设备未初始化")
        return false
    end
    local result = i2c.send(exs_tsl2561.i2c_id, exs_tsl2561.slave_address, CMD_CLEAR)
    if not result then
        log.error("exs_tsl2561.clear_interrupt", "清除中断失败")
        return false
    end
    log.info("exs_tsl2561.clear_interrupt", "中断已清除")
    return true
end

-- 读取 ID 寄存器
-- ID 寄存器 bit7:4=PARTNO（0001=TSL2561），bit3:0=REVNO 版本号
-- @return number 成功返回 ID 寄存器值，失败返回 nil
function exs_tsl2561.get_id()
    return read_reg(REG_ID)
end

-- 上电（Power Up）
-- 写 CONTROL=0x03，设备上电后开始 ADC 积分转换
-- @return boolean 成功返回 true，失败返回 false
function exs_tsl2561.power_up()
    if not exs_tsl2561.i2c_id or not exs_tsl2561.slave_address then
        log.warn("exs_tsl2561.power_up", "设备未初始化")
        return false
    end
    if not write_reg(REG_CONTROL, CTRL_POWER_UP) then
        log.error("exs_tsl2561.power_up", "上电失败")
        return false
    end
    exs_tsl2561.powered = true
    log.info("exs_tsl2561.power_up", "上电成功")
    return true
end

-- 断电（Power Down），进入低功耗状态
-- 写 CONTROL=0x00，断电后 ADC 停止转换，功耗降至 3.2~15μA
-- @return boolean 成功返回 true，失败返回 false
function exs_tsl2561.power_down()
    if not exs_tsl2561.i2c_id or not exs_tsl2561.slave_address then
        log.warn("exs_tsl2561.power_down", "设备未初始化")
        return false
    end
    if not write_reg(REG_CONTROL, CTRL_POWER_DOWN) then
        log.error("exs_tsl2561.power_down", "断电失败")
        return false
    end
    exs_tsl2561.powered = false
    log.info("exs_tsl2561.power_down", "断电成功")
    return true
end

-- 复位（恢复默认配置）
-- TSL2561 无硬件复位指令，通过断电→上电→恢复默认时序（低增益 1x + 402ms）实现
-- @return boolean 成功返回 true，失败返回 false
function exs_tsl2561.reset()
    if not exs_tsl2561.i2c_id or not exs_tsl2561.slave_address then
        log.warn("exs_tsl2561.reset", "设备未初始化")
        return false
    end
    -- 断电
    if not exs_tsl2561.power_down() then
        log.error("exs_tsl2561.reset", "断电失败")
        return false
    end
    sys.wait(10)
    -- 上电
    if not exs_tsl2561.power_up() then
        log.error("exs_tsl2561.reset", "上电失败")
        return false
    end
    -- 恢复默认时序（低增益 1x + 402ms）
    exs_tsl2561.gain = DEFAULT_GAIN
    exs_tsl2561.integ = DEFAULT_INTEG
    if not exs_tsl2561.set_timing(DEFAULT_GAIN, DEFAULT_INTEG) then
        log.error("exs_tsl2561.reset", "恢复默认时序失败")
        return false
    end
    log.info("exs_tsl2561.reset", "复位成功, 恢复默认配置（增益 1x, 积分 402ms）")
    return true
end

-- 获取扩展库版本号
-- @return string 版本号
function exs_tsl2561.version()
    return "202608262000"
end

return exs_tsl2561
