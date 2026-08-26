--[[
@module  exs_bh1750
@summary BH1750 数字环境光传感器驱动扩展库
@version 1.0
@date    2026.08.26
@author  沈园园
@usage
本文件为 BH1750 数字环境光传感器的 LuatOS 扩展库，核心功能为：
1、初始化 BH1750，配置 I2C 通信参数（默认 I2C1，400kHz 快速模式）；
2、支持连续测量和单次测量两种模式，H/H2/L 三种分辨率；
3、支持测量时间寄存器（MTreg）调整（31~254，默认 69）；
4、支持断电、上电、复位等电源管理功能。

本文件的对外接口有 10 个：
1、exs_bh1750.init(i2c_id, slave_address, mode)：初始化 BH1750
2、exs_bh1750.deinit()：关闭 BH1750 通信
3、exs_bh1750.set_mode(mode)：设置测量模式
4、exs_bh1750.get_lux()：读取照度 lux 值
5、exs_bh1750.get_raw()：读取原始 16 位数据
6、exs_bh1750.set_mtreg(mtreg)：设置测量时间寄存器
7、exs_bh1750.power_down()：断电（进入低功耗）
8、exs_bh1750.power_on()：上电（恢复测量）
9、exs_bh1750.reset()：复位（恢复默认配置）
10、exs_bh1750.version()：获取版本号

-- 版本更新说明
-- 版本号：202608262000
-- 1、更新时间：2026-08-26 20:00
-- 2、更新内容
  - 第一版，实现 BH1750 基础驱动功能
  - 支持连续测量（H/H2/L 分辨率）和单次测量（H/H2/L 分辨率）
  - 支持测量时间寄存器（MTreg）调整（31~254，默认 69）
  - 支持断电、上电、复位电源管理
  - 使用 Air780EHV I2C1（SCL=67，SDA=66），默认从机地址 0x23（ADDR 接地）
]]

local exs_bh1750 = {}

-- ==================== 模块常量 ====================

-- BH1750 I2C 从机地址（由 ADDR 引脚决定）
-- ADDR 引脚接地（GND）：地址 0x23
-- ADDR 引脚接电源（VCC）：地址 0x5C
local DEV_ADDR_0 = 0x23
local DEV_ADDR_1 = 0x5C

-- BH1750 指令集（ROHM BH1750FVI 数据手册）
local CMD_POWER_DOWN        = 0x00  -- 断电（Power Down）
local CMD_POWER_ON          = 0x01  -- 上电（Power On）
local CMD_RESET             = 0x02  -- 复位（Reset）
local CMD_CONT_H_RES_MODE   = 0x03  -- 连续 H 分辨率模式（1 lux，120ms）
local CMD_CONT_H_RES_MODE_2 = 0x04  -- 连续 H 分辨率模式2（0.5 lux，120ms）
local CMD_CONT_L_RES_MODE   = 0x05  -- 连续 L 分辨率模式（4 lux，16ms）
local CMD_ONCE_H_RES_MODE   = 0x10  -- 单次 H 分辨率模式（1 lux，120ms）
local CMD_ONCE_H_RES_MODE_2 = 0x11  -- 单次 H 分辨率模式2（0.5 lux，120ms）
local CMD_ONCE_L_RES_MODE   = 0x13  -- 单次 L 分辨率模式（4 lux，16ms）

-- 测量时间寄存器（MTreg）指令基地址
-- 高 3 位（MT[7:5]）：0x40 | (mtreg >> 5)，范围 0x40~0x47
-- 低 5 位（MT[4:0]）：0x60 | (mtreg & 0x1F)，范围 0x60~0x7F
local MTREG_HIGH_BASE = 0x40
local MTREG_LOW_BASE  = 0x60

-- MTreg 范围与默认值
local MTREG_MIN = 31       -- 最小测量时间（31）
local MTREG_MAX = 254      -- 最大测量时间（254）
local MTREG_DEFAULT = 69   -- 默认测量时间（69）

-- 测量时间（MTreg=69 时的典型值，单位 ms）
local MEASURE_TIME_H = 120  -- H/H2 分辨率模式典型测量时间
local MEASURE_TIME_L = 16   -- L 分辨率模式典型测量时间

-- 默认 I2C 参数
local DEFAULT_I2C_ID = 1          -- I2C1（Air780EHV：SCL=67，SDA=66）
local DEFAULT_ADDR   = DEV_ADDR_0 -- 默认从机地址 0x23（ADDR 接地）

-- 单次测量模式指令表（用于判断当前模式是否为单次测量）
local ONCE_MODE_CMDS = {
    [CMD_ONCE_H_RES_MODE]   = true,
    [CMD_ONCE_H_RES_MODE_2] = true,
    [CMD_ONCE_L_RES_MODE]   = true,
}

-- 全部测量模式指令表（用于 set_mode 参数校验）
local ALL_MODE_CMDS = {
    [CMD_CONT_H_RES_MODE]   = true,
    [CMD_CONT_H_RES_MODE_2] = true,
    [CMD_CONT_L_RES_MODE]   = true,
    [CMD_ONCE_H_RES_MODE]   = true,
    [CMD_ONCE_H_RES_MODE_2] = true,
    [CMD_ONCE_L_RES_MODE]   = true,
}

-- H2 分辨率模式指令表（lux 计算需除以 2，分辨率 0.5 lux）
local H2_MODE_CMDS = {
    [CMD_CONT_H_RES_MODE_2] = true,
    [CMD_ONCE_H_RES_MODE_2] = true,
}

-- ==================== 测量模式常量（对外） ====================

-- 连续测量模式
exs_bh1750.MODE_CONT_H  = CMD_CONT_H_RES_MODE    -- 连续 H 分辨率（1 lux，120ms）
exs_bh1750.MODE_CONT_H2 = CMD_CONT_H_RES_MODE_2  -- 连续 H 分辨率2（0.5 lux，120ms）
exs_bh1750.MODE_CONT_L  = CMD_CONT_L_RES_MODE    -- 连续 L 分辨率（4 lux，16ms）
-- 单次测量模式
exs_bh1750.MODE_ONCE_H  = CMD_ONCE_H_RES_MODE    -- 单次 H 分辨率（1 lux，120ms）
exs_bh1750.MODE_ONCE_H2 = CMD_ONCE_H_RES_MODE_2  -- 单次 H 分辨率2（0.5 lux，120ms）
exs_bh1750.MODE_ONCE_L  = CMD_ONCE_L_RES_MODE    -- 单次 L 分辨率（4 lux，16ms）

-- ==================== 内部状态 ====================

exs_bh1750.i2c_id        = nil            -- I2C 总线 ID
exs_bh1750.slave_address = nil            -- 从设备地址
exs_bh1750.mode          = nil            -- 当前测量模式指令
exs_bh1750.mtreg         = MTREG_DEFAULT  -- 当前测量时间寄存器值

-- ==================== I2C 底层操作 ====================

-- 发送指令到 BH1750
-- @param cmd 指令字节
-- @return boolean 成功返回 true，失败返回 false
local function send_command(cmd)
    if not exs_bh1750.i2c_id or not exs_bh1750.slave_address then
        log.error("exs_bh1750", "设备未初始化")
        return false
    end
    local result = i2c.send(exs_bh1750.i2c_id, exs_bh1750.slave_address, cmd)
    if not result then
        log.error("exs_bh1750", "I2C 发送指令失败, cmd=0x%02X", cmd)
        return false
    end
    return true
end

-- 读取 2 字节测量数据
-- @return string 成功返回 2 字节字符串，失败返回 nil
local function read_measure_data()
    if not exs_bh1750.i2c_id or not exs_bh1750.slave_address then
        log.error("exs_bh1750", "设备未初始化")
        return nil
    end
    local data = i2c.recv(exs_bh1750.i2c_id, exs_bh1750.slave_address, 2)
    if not data or data == "" or #data ~= 2 then
        log.error("exs_bh1750", "I2C 读取数据失败")
        return nil
    end
    return data
end

-- 获取当前模式的测量等待时间
-- 测量时间与 MTreg 成正比：典型值 × (mtreg / 69)，再加余量确保测量完成
-- @return number 等待时间（ms）
local function get_measure_time()
    if exs_bh1750.mode == CMD_CONT_L_RES_MODE or exs_bh1750.mode == CMD_ONCE_L_RES_MODE then
        -- L 分辨率模式：典型 16ms，加 10ms 余量
        return math.floor(MEASURE_TIME_L * exs_bh1750.mtreg / MTREG_DEFAULT) + 10
    else
        -- H/H2 分辨率模式：典型 120ms，加 20ms 余量
        return math.floor(MEASURE_TIME_H * exs_bh1750.mtreg / MTREG_DEFAULT) + 20
    end
end

-- 判断当前模式是否为单次测量模式
-- @return boolean 单次测量返回 true
local function is_once_mode()
    return ONCE_MODE_CMDS[exs_bh1750.mode] == true
end

-- 判断当前模式是否为 H2 分辨率模式（lux 计算需除以 2）
-- @return boolean H2 模式返回 true
local function is_h2_mode()
    return H2_MODE_CMDS[exs_bh1750.mode] == true
end

-- 计算照度 lux 值
-- H 模式：lux = raw / 1.2 × (69 / mtreg)
-- H2 模式：lux = raw / 1.2 × (69 / mtreg) / 2 = raw / 2.4 × (69 / mtreg)（分辨率 0.5 lux）
-- L 模式：lux = raw / 1.2 × (69 / mtreg)（原始值低 2 位为 0，步进 4 lux）
-- @param raw 16 位原始测量值
-- @return number 照度 lux 值
local function calc_lux(raw)
    local lux = raw / 1.2 * (MTREG_DEFAULT / exs_bh1750.mtreg)
    if is_h2_mode() then
        lux = lux / 2
    end
    return lux
end

-- ==================== 对外接口 ====================

-- 初始化 BH1750
-- @param i2c_id I2C 总线 ID，默认 1（Air780EHV：SCL=67，SDA=66）
-- @param slave_address 从机地址，默认 0x23（ADDR 接地），ADDR 接 VCC 时为 0x5C
-- @param mode 测量模式，默认连续 H 分辨率模式（exs_bh1750.MODE_CONT_H）
-- @return boolean 成功返回 true，失败返回 false
function exs_bh1750.init(i2c_id, slave_address, mode)
    -- 参数默认值
    if i2c_id == nil then i2c_id = DEFAULT_I2C_ID end
    if slave_address == nil then slave_address = DEFAULT_ADDR end
    if mode == nil then mode = CMD_CONT_H_RES_MODE end

    -- 参数校验
    if slave_address ~= DEV_ADDR_0 and slave_address ~= DEV_ADDR_1 then
        log.error("exs_bh1750.init", "无效的从机地址: 0x%02X（应为 0x23 或 0x5C）", slave_address)
        return false
    end
    if not ALL_MODE_CMDS[mode] then
        log.error("exs_bh1750.init", "无效的测量模式: 0x%02X", mode)
        return false
    end

    -- 初始化 I2C（400kHz 快速模式）
    if i2c.setup(i2c_id, i2c.FAST) ~= 1 then
        log.error("exs_bh1750.init", "I2C 初始化失败, i2c_id=", i2c_id)
        return false
    end
    exs_bh1750.i2c_id = i2c_id
    exs_bh1750.slave_address = slave_address
    exs_bh1750.mode = mode
    exs_bh1750.mtreg = MTREG_DEFAULT

    -- 验证从设备地址：发送复位指令，设备在线则返回 ACK
    if not i2c.send(i2c_id, slave_address, CMD_RESET) then
        log.error("exs_bh1750.init", "指定从设备地址无响应: 0x%02X，请检查接线/供电/地址配置", slave_address)
        return false
    end
    sys.wait(10)

    -- 设置测量时间寄存器为默认值（69）
    if not exs_bh1750.set_mtreg(MTREG_DEFAULT) then
        log.error("exs_bh1750.init", "MTreg 设置失败")
        return false
    end

    -- 启动测量（发送测量模式指令）
    if not send_command(mode) then
        log.error("exs_bh1750.init", "启动测量失败, mode=0x%02X", mode)
        return false
    end

    log.info("exs_bh1750.init", "初始化完成, i2c=", i2c_id, "addr=0x" .. string.format("%02X", slave_address), "mode=0x" .. string.format("%02X", mode))
    return true
end

-- 关闭 BH1750 通信，释放 I2C 总线
-- @return boolean 成功返回 true
function exs_bh1750.deinit()
    if not exs_bh1750.i2c_id or not exs_bh1750.slave_address then
        log.warn("exs_bh1750.deinit", "设备未初始化")
        return false
    end
    -- 断电，进入低功耗
    exs_bh1750.power_down()
    -- 关闭 I2C 总线
    i2c.close(exs_bh1750.i2c_id)
    -- 重置内部状态
    exs_bh1750.i2c_id = nil
    exs_bh1750.slave_address = nil
    exs_bh1750.mode = nil
    exs_bh1750.mtreg = MTREG_DEFAULT
    log.info("exs_bh1750.deinit", "已关闭")
    return true
end

-- 设置测量模式
-- @param mode 测量模式常量（exs_bh1750.MODE_CONT_H / MODE_ONCE_H 等 6 种）
-- @return boolean 成功返回 true，失败返回 false
function exs_bh1750.set_mode(mode)
    if not exs_bh1750.i2c_id or not exs_bh1750.slave_address then
        log.warn("exs_bh1750.set_mode", "设备未初始化")
        return false
    end
    if not ALL_MODE_CMDS[mode] then
        log.error("exs_bh1750.set_mode", "无效的测量模式: 0x%02X", mode)
        return false
    end
    -- 先上电（若处于断电状态）
    if not send_command(CMD_POWER_ON) then
        log.error("exs_bh1750.set_mode", "上电失败")
        return false
    end
    sys.wait(10)
    -- 发送测量模式指令
    if not send_command(mode) then
        log.error("exs_bh1750.set_mode", "设置测量模式失败, mode=0x%02X", mode)
        return false
    end
    exs_bh1750.mode = mode
    log.info("exs_bh1750.set_mode", "设置测量模式成功, mode=0x%02X", mode)
    return true
end

-- 读取照度 lux 值
-- 连续测量模式：直接读取最新测量数据；
-- 单次测量模式：先发送测量指令触发一次测量，等待测量完成后再读取。
-- @return number 成功返回照度 lux 值（浮点数），失败返回 nil
function exs_bh1750.get_lux()
    if not exs_bh1750.i2c_id or not exs_bh1750.slave_address then
        log.warn("exs_bh1750.get_lux", "设备未初始化")
        return nil
    end
    local raw = nil
    if is_once_mode() then
        -- 单次测量：每次读取前先发送测量指令触发一次测量
        if not send_command(exs_bh1750.mode) then
            log.error("exs_bh1750.get_lux", "触发单次测量失败")
            return nil
        end
        -- 等待测量完成
        sys.wait(get_measure_time())
        raw = exs_bh1750.get_raw()
    else
        -- 连续测量：直接读取最新测量数据
        raw = exs_bh1750.get_raw()
    end
    if not raw then
        return nil
    end
    local lux = calc_lux(raw)
    log.info("exs_bh1750.get_lux", "照度读取成功, raw=", raw, "lux=", string.format("%.1f", lux))
    return lux
end

-- 读取原始 16 位测量数据
-- 注意：本接口仅读取原始数据，不触发测量。单次测量模式下需先调用 get_lux() 或手动触发测量。
-- @return number 成功返回 16 位原始测量值，失败返回 nil
function exs_bh1750.get_raw()
    if not exs_bh1750.i2c_id or not exs_bh1750.slave_address then
        log.warn("exs_bh1750.get_raw", "设备未初始化")
        return nil
    end
    local data = read_measure_data()
    if not data then
        return nil
    end
    -- 高字节在前，合成 16 位原始值
    local raw = bit.bor(bit.lshift(data:byte(1), 8), data:byte(2))
    return raw
end

-- 设置测量时间寄存器（MTreg）
-- MTreg 范围 31~254，默认 69。MTreg 越大测量时间越长、灵敏度越高。
-- @param mtreg 测量时间寄存器值（31~254）
-- @return boolean 成功返回 true，失败返回 false
function exs_bh1750.set_mtreg(mtreg)
    if not exs_bh1750.i2c_id or not exs_bh1750.slave_address then
        log.warn("exs_bh1750.set_mtreg", "设备未初始化")
        return false
    end
    if mtreg < MTREG_MIN or mtreg > MTREG_MAX then
        log.error("exs_bh1750.set_mtreg", "MTreg 超出范围: ", mtreg, "（31~254）")
        return false
    end
    -- 发送 MTreg 高 3 位指令：0x40 | (mtreg >> 5)
    local high_cmd = bit.bor(MTREG_HIGH_BASE, bit.rshift(mtreg, 5))
    if not send_command(high_cmd) then
        log.error("exs_bh1750.set_mtreg", "设置 MTreg 高 3 位失败, cmd=0x%02X", high_cmd)
        return false
    end
    -- 发送 MTreg 低 5 位指令：0x60 | (mtreg & 0x1F)
    local low_cmd = bit.bor(MTREG_LOW_BASE, bit.band(mtreg, 0x1F))
    if not send_command(low_cmd) then
        log.error("exs_bh1750.set_mtreg", "设置 MTreg 低 5 位失败, cmd=0x%02X", low_cmd)
        return false
    end
    exs_bh1750.mtreg = mtreg
    log.info("exs_bh1750.set_mtreg", "设置测量时间成功, mtreg=", mtreg)
    return true
end

-- 断电（Power Down），进入低功耗状态
-- @return boolean 成功返回 true，失败返回 false
function exs_bh1750.power_down()
    if not exs_bh1750.i2c_id or not exs_bh1750.slave_address then
        log.warn("exs_bh1750.power_down", "设备未初始化")
        return false
    end
    if not send_command(CMD_POWER_DOWN) then
        log.error("exs_bh1750.power_down", "断电失败")
        return false
    end
    log.info("exs_bh1750.power_down", "断电成功")
    return true
end

-- 上电（Power On），恢复测量能力
-- 注意：上电后需重新发送测量模式指令才能继续测量。
-- @return boolean 成功返回 true，失败返回 false
function exs_bh1750.power_on()
    if not exs_bh1750.i2c_id or not exs_bh1750.slave_address then
        log.warn("exs_bh1750.power_on", "设备未初始化")
        return false
    end
    if not send_command(CMD_POWER_ON) then
        log.error("exs_bh1750.power_on", "上电失败")
        return false
    end
    log.info("exs_bh1750.power_on", "上电成功")
    return true
end

-- 复位（Reset），恢复默认配置（MTreg 恢复为 69）
-- 注意：复位后需重新发送测量模式指令才能继续测量。
-- @return boolean 成功返回 true，失败返回 false
function exs_bh1750.reset()
    if not exs_bh1750.i2c_id or not exs_bh1750.slave_address then
        log.warn("exs_bh1750.reset", "设备未初始化")
        return false
    end
    if not send_command(CMD_RESET) then
        log.error("exs_bh1750.reset", "复位失败")
        return false
    end
    sys.wait(10)
    exs_bh1750.mtreg = MTREG_DEFAULT
    log.info("exs_bh1750.reset", "复位成功, mtreg 恢复为默认值 ", MTREG_DEFAULT)
    return true
end

-- 获取扩展库版本号
-- @return string 版本号
function exs_bh1750.version()
    return "202608262000"
end

return exs_bh1750
