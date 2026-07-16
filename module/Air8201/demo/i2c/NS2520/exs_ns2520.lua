--[[
@module  exs_ns2520
@summary NS2520 压力传感器扩展库（NS2520）
@version 1.0
@date    2026.07.16
@author  王世豪
@usage
本文件为 NS2520 压力传感器的 LuatOS 扩展库，核心功能为：
1、初始化 NS2520，配置 I2C 通信参数和过采样率
2、读取压力和温度数据，自动完成补偿计算
3、动态调整过采样率
4、关闭传感器（进入待机）

本文件的对外接口有 7 个：
1、exs_ns2520.setup(init_cfg)：初始化 NS2520
2、exs_ns2520.get_data()：读取压力和温度
3、exs_ns2520.get_pressure()：单次读取压力（hPa）
4、exs_ns2520.get_temperature()：单次读取温度（℃）
5、exs_ns2520.set_osr(prs_osr, tmp_osr)：设置过采样率
6、exs_ns2520.close()：关闭传感器（进入待机）
7、exs_ns2520.version()：获取版本号

-- 版本更新说明
-- 版本号：202607161400
-- 1、更新时间：2026-07-16 14:00
-- 2、更新内容
--    初版，实现 NS2520 驱动所有基础功能
--    遵循 exs_ 扩展库设计规范
--    支持 I2C 通信重试机制
--    支持校准系数自动读取和补偿计算
--    支持过采样率动态配置（0~7 共 8 级）
--    支持单次读取压力/温度，支持同时读取两项数据
--    支持关闭/待机模式
]]

local exs_ns2520 = {}

-- ==================== 模块常量 ====================

-- 寄存器定义（NS2520 Datasheet V1.1 Table14）
local REG_PRS_MSB     = 0x00
local REG_PRS_LSB     = 0x01
local REG_PRS_XLSB    = 0x02
local REG_TMP_MSB     = 0x03
local REG_TMP_LSB     = 0x04
local REG_TMP_XLSB    = 0x05
local REG_PRS_CFG     = 0x06
local REG_TMP_CFG     = 0x07
local REG_MEAS_CFG    = 0x08
local REG_CFG_REG     = 0x09
local REG_RESET       = 0x0C

-- 校准系数寄存器
local REG_COEF_C0       = 0x10
local REG_COEF_C0_C1    = 0x11
local REG_COEF_C1       = 0x12
local REG_COEF_C00      = 0x13
local REG_COEF_C00_2    = 0x14
local REG_COEF_C00_C10  = 0x15
local REG_COEF_C10      = 0x16
local REG_COEF_C10_2    = 0x17
local REG_COEF_C01      = 0x18
local REG_COEF_C11      = 0x1A
local REG_COEF_C20      = 0x1C
local REG_COEF_C21      = 0x1E
local REG_COEF_C30      = 0x20

-- 测量模式（MEAS_CFG 寄存器 MEAS_CTRL 位）
local MEAS_MODE = {
    STANDBY      = 0x00,
    PRESS_SINGLE = 0x01,
    TEMP_SINGLE  = 0x02,
    BOTH_CONT    = 0x07,
}

-- 状态位（MEAS_CFG 寄存器）
local STATUS = {
    COEF_RDY   = 0x80,
    SENSOR_RDY = 0x40,
    TMP_RDY    = 0x20,
    PRS_RDY    = 0x10,
}

-- 缩放因子表（数据手册 Table8），索引 = 过采样率 (0~7)
local SCALE_FACTORS = {
    524288,      -- 1x
    1572864,     -- 2x
    3670016,     -- 4x
    7864320,     -- 8x
    253952,      -- 16x
    516096,      -- 32x
    1040384,     -- 64x
    2088960,     -- 128x
}

-- ==================== 内部状态 ====================

local g_i2c_id     = nil        -- I2C 总线编号
local g_i2c_addr   = 0x77       -- I2C 设备地址
local g_coeff      = nil        -- 校准系数表
local g_prs_osr    = 0          -- 压力过采样率索引
local g_tmp_osr    = 0          -- 温度过采样率索引
local g_temp_offset = 0         -- 温度偏移校正（℃）
local g_ready      = false      -- 初始化完成标志

-- ==================== I2C 底层操作 ====================

-- I2C 读寄存器（带重试）
-- @return string|nil 返回原始字节串，失败返回 nil
local function read_reg(reg, len, retry_count)
    if not g_i2c_id then return nil end
    retry_count = retry_count or 3
    for i = 1, retry_count do
        local data = i2c.readReg(g_i2c_id, g_i2c_addr, reg, len)
        if data and #data == len then
            return data
        end
        log.warn("exs_ns2520", "读寄存器失败(第" .. i .. "次重试)", string.format("0x%02X", reg))
        sys.wait(10)
    end
    log.error("exs_ns2520", "读寄存器失败(已达最大重试)", string.format("0x%02X", reg))
    return nil
end

-- I2C 写寄存器（带重试）
-- @return boolean 成功返回 true
local function write_reg(reg, val, retry_count)
    if not g_i2c_id then return false end
    retry_count = retry_count or 3
    for i = 1, retry_count do
        local ok = i2c.writeReg(g_i2c_id, g_i2c_addr, reg, string.char(val))
        if ok then return true end
        log.warn("exs_ns2520", "写寄存器失败(第" .. i .. "次重试)", string.format("0x%02X", reg))
        sys.wait(10)
    end
    log.error("exs_ns2520", "写寄存器失败(已达最大重试)", string.format("0x%02X", reg))
    return false
end

-- ==================== 校准系数读取 ====================

local function read_coefficients()
    local c = {}

    local c0_byte = read_reg(REG_COEF_C0, 1)
    local c0c1_byte = read_reg(REG_COEF_C0_C1, 1)
    local c1_byte = read_reg(REG_COEF_C1, 1)
    if not (c0_byte and c0c1_byte and c1_byte) then return nil end

    -- C0(12位): 0x10[11:4] | 0x11[7:4]
    c.c0 = ((c0_byte:byte(1) << 4) | (c0c1_byte:byte(1) >> 4))
    if c.c0 >= 0x800 then c.c0 = c.c0 - 0x1000 end

    -- C1(12位): 0x11[3:0] << 8 | 0x12[7:0]
    c.c1 = ((c0c1_byte:byte(1) & 0x0F) << 8) | c1_byte:byte(1)
    if c.c1 >= 0x800 then c.c1 = c.c1 - 0x1000 end

    -- C00(20位), C10(20位)
    local c00_1 = read_reg(REG_COEF_C00, 1)
    local c00_2 = read_reg(REG_COEF_C00_2, 1)
    local c00c10 = read_reg(REG_COEF_C00_C10, 1)
    if not (c00_1 and c00_2 and c00c10) then return nil end

    c.c00 = (c00_1:byte(1) << 12) | (c00_2:byte(1) << 4) | (c00c10:byte(1) >> 4)
    if c.c00 >= 0x80000 then c.c00 = c.c00 - 0x100000 end

    local c10_1 = read_reg(REG_COEF_C10, 1)
    local c10_2 = read_reg(REG_COEF_C10_2, 1)
    if not (c10_1 and c10_2) then return nil end
    c.c10 = ((c00c10:byte(1) & 0x0F) << 16) | (c10_1:byte(1) << 8) | c10_2:byte(1)
    if c.c10 >= 0x80000 then c.c10 = c.c10 - 0x100000 end

    -- C01, C11, C20, C21, C30（各16位有符号）
    local function bytes_to_int16(b1, b2)
        local v = (b1 << 8) | b2
        if v >= 0x8000 then v = v - 0x10000 end
        return v
    end

    local r01 = read_reg(REG_COEF_C01, 2)
    local r11 = read_reg(REG_COEF_C11, 2)
    local r20 = read_reg(REG_COEF_C20, 2)
    local r21 = read_reg(REG_COEF_C21, 2)
    local r30 = read_reg(REG_COEF_C30, 2)
    if not (r01 and r11 and r20 and r21 and r30) then return nil end

    c.c01 = bytes_to_int16(r01:byte(1), r01:byte(2))
    c.c11 = bytes_to_int16(r11:byte(1), r11:byte(2))
    c.c20 = bytes_to_int16(r20:byte(1), r20:byte(2))
    c.c21 = bytes_to_int16(r21:byte(1), r21:byte(2))
    c.c30 = bytes_to_int16(r30:byte(1), r30:byte(2))

    return c
end

-- ==================== 补偿计算 ====================

local function get_scale_factor(osr_idx)
    if osr_idx < 0 or osr_idx > 7 then osr_idx = 0 end
    return SCALE_FACTORS[osr_idx + 1]
end

local function compensate_temperature(raw_temp, osr_idx, c0, c1)
    local kt = get_scale_factor(osr_idx)
    return c0 * 0.5 + c1 * raw_temp / kt
end

local function compensate_pressure(raw_press, raw_temp, prs_idx, tmp_idx, c)
    local kp = get_scale_factor(prs_idx)
    local kt = get_scale_factor(tmp_idx)
    local p_sc = raw_press / kp
    local t_sc = raw_temp / kt
    return c.c00 + p_sc * (c.c10 + p_sc * (c.c20 + p_sc * c.c30))
         + t_sc * c.c01
         + t_sc * p_sc * (c.c11 + p_sc * c.c21)
end

-- ==================== 读取原始数据 ====================

local function read_raw_pressure()
    local data = read_reg(REG_PRS_MSB, 3)
    if not data then return nil end
    local raw = (data:byte(1) << 16) | (data:byte(2) << 8) | data:byte(3)
    if raw >= 0x800000 then raw = raw - 0x1000000 end
    return raw
end

local function read_raw_temperature()
    local data = read_reg(REG_TMP_MSB, 3)
    if not data then return nil end
    local raw = (data:byte(1) << 16) | (data:byte(2) << 8) | data:byte(3)
    if raw >= 0x800000 then raw = raw - 0x1000000 end
    return raw
end

local function wait_for_measure(timeout_ms)
    timeout_ms = timeout_ms or 1000
    local start = os.time() * 1000
    while (os.time() * 1000 - start) < timeout_ms do
        local st = read_reg(REG_MEAS_CFG, 1)
        if st then
            local s = st:byte(1)
            if (s & STATUS.PRS_RDY) ~= 0 or (s & STATUS.TMP_RDY) ~= 0 then
                return true
            end
        end
        sys.wait(5)
    end
    log.error("exs_ns2520", "测量超时")
    return false
end

-- ==================== 外部 API ====================

--[[
初始化 NS2520 压力传感器，配置 I2C 通信参数和过采样率
@api exs_ns2520.setup(init_cfg)
@table init_cfg 初始化配置表
    i2c_id:number, I2C总线编号，例如i2c1为1，必选
    addr:number, I2C设备地址（7位），默认0x77，可选
    prs_osr:number, 压力过采样率0~7，默认4(16x)，可选，0=1x/1=2x/2=4x/3=8x/4=16x/5=32x/6=64x/7=128x，过采样率越高精度越高但测量时间越长
    tmp_osr:number, 温度过采样率0~7，默认4(16x)，可选
    temp_offset:number, 温度偏移校正值（℃），默认-7.0，可选。NS2520普遍读数偏高约7℃，设-7.0可校准到真实温度
@return boolean 成功返回true，失败返回false
@usage
-- 最小化初始化（默认-7.0温度偏移）
local result = exs_ns2520.setup({i2c_id = 1})
-- 自定义过采样率 + 关闭温度偏移
local result = exs_ns2520.setup({i2c_id = 1, prs_osr = 6, tmp_osr = 6, temp_offset = 0})
]]
function exs_ns2520.setup(init_cfg)
    -- 参数类型检查
    if type(init_cfg) ~= "table" then
        log.error("exs_ns2520.setup 参数错误：init_cfg 应为 table 类型")
        return false
    end
    if not init_cfg.i2c_id then
        log.error("exs_ns2520.setup 参数错误：i2c_id 为必填")
        return false
    end

    g_i2c_id = init_cfg.i2c_id
    g_i2c_addr = init_cfg.addr or 0x77

    -- 1. 初始化 I2C 总线
    local ret = i2c.setup(g_i2c_id, i2c.FAST)
    if not ret or ret ~= 1 then
        log.error("exs_ns2520.setup I2C 总线初始化失败, id=" .. g_i2c_id)
        return false
    end

    -- 2. 检测设备
    local test = read_reg(REG_MEAS_CFG, 1)
    if not test then
        log.error("exs_ns2520.setup 设备无响应，请检查连接和 I2C 地址")
        return false
    end

    -- 3. 软件复位
    if not write_reg(REG_RESET, 0x09) then
        log.error("exs_ns2520.setup 复位失败")
        return false
    end
    sys.wait(50)

    -- 4. 等待传感器就绪
    local ok = false
    for i = 1, 30 do
        local st = read_reg(REG_MEAS_CFG, 1)
        if st then
            local s = st:byte(1)
            if (s & STATUS.SENSOR_RDY) ~= 0 and (s & STATUS.COEF_RDY) ~= 0 then
                ok = true
                break
            end
        end
        sys.wait(10)
    end
    if not ok then
        log.error("exs_ns2520.setup 传感器就绪超时")
        return false
    end

    -- 5. 配置过采样率
    local prs_cfg = init_cfg.prs_osr or 4
    local tmp_cfg = init_cfg.tmp_osr or 4
    if not write_reg(REG_PRS_CFG, prs_cfg) then return false end
    if not write_reg(REG_TMP_CFG, tmp_cfg) then return false end
    g_prs_osr = (prs_cfg & 0x0F)
    g_tmp_osr = (tmp_cfg & 0x0F)
    g_temp_offset = init_cfg.temp_offset or -7.0

    -- 过采样率超过 8x 时设置 P_SHIFT / T_SHIFT
    if g_prs_osr >= 4 then
        local cfg = read_reg(REG_CFG_REG, 1)
        if cfg then write_reg(REG_CFG_REG, cfg:byte(1) | 0x04) end
    end
    if g_tmp_osr >= 4 then
        local cfg = read_reg(REG_CFG_REG, 1)
        if cfg then write_reg(REG_CFG_REG, cfg:byte(1) | 0x08) end
    end

    -- 6. 读取校准系数
    g_coeff = read_coefficients()
    if not g_coeff then
        log.error("exs_ns2520.setup 校准系数读取失败")
        return false
    end

    -- 7. 进入待机
    write_reg(REG_MEAS_CFG, MEAS_MODE.STANDBY)
    g_ready = true

    log.info("exs_ns2520", string.format("初始化完成, prs_osr=%d tmp_osr=%d", g_prs_osr, g_tmp_osr))
    return true
end

--[[
读取压力和温度数据，一次I2C通信获取两项数据
@api exs_ns2520.get_data()
@return table/nil 成功返回{pressure:补偿后的压力值(hPa),temperature:补偿后的温度值(℃)}，失败返回nil
@usage
local data = exs_ns2520.get_data()
if data then
    log.info("ns2520", string.format("压力:%.2f hPa, 温度:%.2f ℃", data.pressure, data.temperature))
end
]]
function exs_ns2520.get_data()
    if not g_ready then
        log.error("exs_ns2520.get_data 请先调用 setup()")
        return nil
    end

    if not write_reg(REG_MEAS_CFG, MEAS_MODE.BOTH_CONT) then return nil end

    local start = os.time() * 1000
    local prs_rdy, tmp_rdy = false, false
    while (os.time() * 1000 - start) < 1000 do
        local st = read_reg(REG_MEAS_CFG, 1)
        if st then
            local s = st:byte(1)
            if (s & STATUS.PRS_RDY) ~= 0 then prs_rdy = true end
            if (s & STATUS.TMP_RDY) ~= 0 then tmp_rdy = true end
            if prs_rdy and tmp_rdy then break end
        end
        sys.wait(5)
    end

    local raw_p = read_raw_pressure()
    local raw_t = read_raw_temperature()

    -- 读完数据立即切回待机，避免连续模式干扰后续单次测量
    write_reg(REG_MEAS_CFG, MEAS_MODE.STANDBY)

    if not raw_p or not raw_t then
        log.error("exs_ns2520.get_data 读取原始数据失败")
        return nil
    end

    local temp = compensate_temperature(raw_t, g_tmp_osr, g_coeff.c0, g_coeff.c1)

    -- 首次上电温度可能异常（raw_t=0 → 127.5℃），重试一次
    if temp > 85 or temp < -40 then
        log.warn("exs_ns2520", "温度异常重试", string.format("%.2f℃", temp), "raw_t:", raw_t)
        sys.wait(100)
        write_reg(REG_MEAS_CFG, MEAS_MODE.BOTH_CONT)
        sys.wait(50)
        local rt = read_raw_temperature()
        write_reg(REG_MEAS_CFG, MEAS_MODE.STANDBY)
        if rt then
            raw_t = rt
            temp = compensate_temperature(raw_t, g_tmp_osr, g_coeff.c0, g_coeff.c1)
            log.info("exs_ns2520", "重试后温度:", string.format("%.2f℃", temp))
        end
    end

    return {
        pressure = compensate_pressure(raw_p, raw_t, g_prs_osr, g_tmp_osr, g_coeff) / 100.0,
        temperature = temp + g_temp_offset,
    }
end

--[[
单次读取压力值
@api exs_ns2520.get_pressure()
@return number/nil 补偿后的压力值(hPa)，失败返回nil
@usage
local pressure = exs_ns2520.get_pressure()
if pressure then
    log.info("ns2520", string.format("压力:%.2f hPa", pressure))
end
]]
function exs_ns2520.get_pressure()
    if not g_ready then
        log.error("exs_ns2520.get_pressure 请先调用 setup()")
        return nil
    end

    if not write_reg(REG_MEAS_CFG, MEAS_MODE.PRESS_SINGLE) then return nil end
    if not wait_for_measure() then return nil end

    local raw_p = read_raw_pressure()
    local raw_t = read_raw_temperature()
    if not raw_p or not raw_t then return nil end

    return compensate_pressure(raw_p, raw_t, g_prs_osr, g_tmp_osr, g_coeff) / 100.0
end

--[[
单次读取温度值
@api exs_ns2520.get_temperature()
@return number/nil 补偿后的温度值(℃)，失败返回nil
@usage
local temp = exs_ns2520.get_temperature()
if temp then
    log.info("ns2520", string.format("温度:%.2f ℃", temp))
end
]]
function exs_ns2520.get_temperature()
    if not g_ready then
        log.error("exs_ns2520.get_temperature 请先调用 setup()")
        return nil
    end

    if not write_reg(REG_MEAS_CFG, MEAS_MODE.TEMP_SINGLE) then return nil end
    if not wait_for_measure() then return nil end

    local raw_t = read_raw_temperature()
    if not raw_t then return nil end

    return compensate_temperature(raw_t, g_tmp_osr, g_coeff.c0, g_coeff.c1) + g_temp_offset
end

--[[
设置过采样率，在线修改压力和温度的过采样率，无需重新初始化
@api exs_ns2520.set_osr(prs_osr, tmp_osr)
@param prs_osr number 压力过采样率0~7，可选，不传则保持当前值，0=1x/1=2x/2=4x/3=8x/4=16x/5=32x/6=64x/7=128x
@param tmp_osr number 温度过采样率0~7，可选，不传则保持当前值
@return nil
@usage
exs_ns2520.set_osr(6, 6)   -- 压力温度均设为64x过采样（高精度）
exs_ns2520.set_osr(0, 0)   -- 压力温度均设为1x过采样（低功耗快速）
]]
function exs_ns2520.set_osr(p_osr, t_osr)
    if not g_ready then
        log.error("exs_ns2520.set_osr 请先调用 setup()")
        return
    end
    if p_osr then
        if p_osr < 0 then p_osr = 0 elseif p_osr > 7 then p_osr = 7 end
        write_reg(REG_PRS_CFG, p_osr)
        g_prs_osr = (p_osr & 0x0F)
        -- 过采样率超过8x时需设置 P_SHIFT
        if g_prs_osr >= 4 then
            local cfg = read_reg(REG_CFG_REG, 1)
            if cfg then write_reg(REG_CFG_REG, cfg:byte(1) | 0x04) end
        end
        log.info("exs_ns2520", "压力OSR", p_osr)
    end
    if t_osr then
        if t_osr < 0 then t_osr = 0 elseif t_osr > 7 then t_osr = 7 end
        write_reg(REG_TMP_CFG, t_osr)
        g_tmp_osr = (t_osr & 0x0F)
        -- 过采样率超过8x时需设置 T_SHIFT
        if g_tmp_osr >= 4 then
            local cfg = read_reg(REG_CFG_REG, 1)
            if cfg then write_reg(REG_CFG_REG, cfg:byte(1) | 0x08) end
        end
        log.info("exs_ns2520", "温度OSR", t_osr)
    end
end

--[[
关闭传感器（进入待机模式），关闭后需重新setup才能使用
@api exs_ns2520.close()
@return nil
@usage
exs_ns2520.close()
]]
function exs_ns2520.close()
    if not g_ready then return end
    write_reg(REG_MEAS_CFG, MEAS_MODE.STANDBY)
    g_ready = false
    log.info("exs_ns2520", "已关闭")
end

--[[
获取 exs_ns2520 库的版本号
@api exs_ns2520.version()
@return string 版本号字符串，格式为 "yyyymmddhhmm"
@usage
local ver = exs_ns2520.version()
log.info("exs_ns2520", "版本号:", ver)
]]
function exs_ns2520.version()
    return "202607161400"
end

log.debug("exs_ns2520", "version -> " .. exs_ns2520.version())

return exs_ns2520
