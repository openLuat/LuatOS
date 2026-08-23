-- NS2520 压力传感器驱动（基于 NS2520 Datasheet V1.1 修正）
-- 适配 LuatOS I2C API
-- 修正点：
-- 1. 修复 C0/C1 系数位拼接错误（严重）
-- 2. 修复 read_all 测量模式（使用连续测量，确保压力和温度同时更新）
-- 3. 移除 i2c.scan，改用简单通信测试
-- 4. 增强错误重试与超时处理

local ns2520 = {}

-- 设备参数
local i2c_id = 1
local i2c_addr = 0x77          -- 默认地址
local coeff = nil               -- 校准系数
local POWER_PIN = 26            -- NS2520供电使能
local I2C1_PULLUP = 28          -- I2C1总线上拉（与DA267共享，仅置高不置低）
local prs_osr = 0               -- 压力过采样率索引
local tmp_osr = 0               -- 温度过采样率索引
local background_running = false
local background_cb = nil
local background_timer = nil
local powered = false               -- 当前是否已供电

-- 温度偏移校正（单位：摄氏度）
-- 根据实测，NS2520读数偏高约7度，需要减去此偏移
local TEMP_OFFSET = -7.0

-- ============ 寄存器定义（数据手册 Table14） ============
local REG = {
    PRS_MSB   = 0x00,   -- 压力数据 MSB (24位有符号)
    PRS_LSB   = 0x01,
    PRS_XLSB  = 0x02,
    TMP_MSB   = 0x03,   -- 温度数据 MSB (24位有符号)
    TMP_LSB   = 0x04,
    TMP_XLSB  = 0x05,
    PRS_CFG   = 0x06,   -- 压力配置
    TMP_CFG   = 0x07,   -- 温度配置
    MEAS_CFG  = 0x08,   -- 测量模式及状态
    CFG_REG   = 0x09,   -- 中断和FIFO配置
    INT_STS   = 0x0A,   -- 中断状态
    FIFO_STS  = 0x0B,   -- FIFO状态
    RESET     = 0x0C,   -- 软件复位/FIFO刷新
    -- 校准系数（0x10 ~ 0x21）
    COEF_C0      = 0x10,
    COEF_C0_C1   = 0x11,
    COEF_C1      = 0x12,
    COEF_C00     = 0x13,
    COEF_C00_2   = 0x14,
    COEF_C00_C10 = 0x15,
    COEF_C10     = 0x16,
    COEF_C10_2   = 0x17,
    COEF_C01     = 0x18,
    COEF_C01_2   = 0x19,
    COEF_C11     = 0x1A,
    COEF_C11_2   = 0x1B,
    COEF_C20     = 0x1C,
    COEF_C20_2   = 0x1D,
    COEF_C21     = 0x1E,
    COEF_C21_2   = 0x1F,
    COEF_C30     = 0x20,
    COEF_C30_2   = 0x21,
}

-- 测量模式（MEAS_CFG 的 MEAS_CTRL 位）
local MEAS_MODE = {
    STANDBY        = 0x00,
    PRESS_SINGLE   = 0x01,
    TEMP_SINGLE    = 0x02,
    -- 0x03, 0x04 保留
    PRESS_CONT     = 0x05,
    TEMP_CONT      = 0x06,
    BOTH_CONT      = 0x07,
}

-- 状态位（MEAS_CFG）
local STATUS = {
    COEF_RDY   = 0x80,
    SENSOR_RDY = 0x40,
    TMP_RDY    = 0x20,
    PRS_RDY    = 0x10,
}

-- 缩放因子表（数据手册 Table8）
-- 索引：过采样率 0=单次,1=2x,2=4x,3=8x,4=16x,5=32x,6=64x,7=128x
local SCALE_FACTORS = {
    524288,     -- 1x
    1572864,    -- 2x
    3670016,    -- 4x
    7864320,    -- 8x
    253952,     -- 16x
    516096,     -- 32x
    1040384,    -- 64x
    2088960,    -- 128x
}

-- ============ I2C 底层操作 ============
local function read_reg(reg, len, retry_count)
    if not i2c_id then return nil end
    retry_count = retry_count or 3

    for i = 1, retry_count do
        local data = i2c.readReg(i2c_id, i2c_addr, reg, len)
        if data and #data == len then
            return data
        end
        log.warn("ns2520", "读寄存器失败(第" .. i .. "次重试)",
                 string.format("0x%02X", reg), "len:", len)
        sys.wait(10)
    end

    log.error("ns2520", "读寄存器失败(所有重试都已失败)",
             string.format("0x%02X", reg), "len:", len)
    return nil
end

local function write_reg(reg, val, retry_count)
    if not i2c_id then return false end
    retry_count = retry_count or 3

    for i = 1, retry_count do
        local ok = i2c.writeReg(i2c_id, i2c_addr, reg, string.char(val))
        if ok then
            return true
        end
        log.warn("ns2520", "写寄存器失败(第" .. i .. "次重试)",
                 string.format("0x%02X", reg), string.format("0x%02X", val))
        sys.wait(10)
    end

    log.error("ns2520", "写寄存器失败(所有重试都已失败)",
             string.format("0x%02X", reg), string.format("0x%02X", val))
    return false
end

-- ============ 校准系数读取 ============
-- ============ 校准系数读取 ============
local function read_coefficients()
    local c = {}

    -- 读取 C0 (12位), C1 (12位) 正确拼接
    local c0_byte = read_reg(REG.COEF_C0, 1)        -- 0x10
    local c0c1_byte = read_reg(REG.COEF_C0_C1, 1)  -- 0x11
    local c1_byte = read_reg(REG.COEF_C1, 1)        -- 0x12
    if not (c0_byte and c0c1_byte and c1_byte) then return nil end

    -- 调试输出原始字节
    local c0_val = c0_byte:byte(1)
    local c0c1_val = c0c1_byte:byte(1)
    local c1_val = c1_byte:byte(1)
    log.info("ns2520", "系数原始字节",
             "C0=0x" .. string.format("%02X", c0_val),
             "C0_C1=0x" .. string.format("%02X", c0c1_val),
             "C1=0x" .. string.format("%02X", c1_val))

    -- 计算过程调试
    local c0_calc = (c0_val << 4) | (c0c1_val >> 4)
    local c1_calc = ((c0c1_val & 0x0F) << 8) | c1_val
    log.info("ns2520", "系数计算中间值",
             "c0_raw=" .. c0_calc .. "(0x" .. string.format("%04X", c0_calc) .. ")",
             "c1_raw=" .. c1_calc .. "(0x" .. string.format("%04X", c1_calc) .. ")")

    -- C0: 0x10[11:4] | 0x11[7:4]  (高4位来自0x11的高4位)
    c.c0 = c0_calc
    if c.c0 >= 0x800 then c.c0 = c.c0 - 0x1000 end

    -- C1: 0x11[3:0] << 8 | 0x12[7:0]  (低4位来自0x11的低4位)
    c.c1 = c1_calc
    if c.c1 >= 0x800 then c.c1 = c.c1 - 0x1000 end

    log.info("ns2520", "系数最终值", "c0="..c.c0, "c1="..c.c1)

    -- 其余系数不变
    local c00_1 = read_reg(REG.COEF_C00, 1)        -- 0x13
    local c00_2 = read_reg(REG.COEF_C00_2, 1)      -- 0x14
    local c00c10 = read_reg(REG.COEF_C00_C10, 1)   -- 0x15
    if not (c00_1 and c00_2 and c00c10) then return nil end

    c.c00 = (c00_1:byte(1) << 12) | (c00_2:byte(1) << 4) | (c00c10:byte(1) >> 4)
    if c.c00 >= 0x80000 then c.c00 = c.c00 - 0x100000 end

    local c10_1 = read_reg(REG.COEF_C10, 1)        -- 0x16
    local c10_2 = read_reg(REG.COEF_C10_2, 1)      -- 0x17
    if not (c10_1 and c10_2) then return nil end
    c.c10 = ((c00c10:byte(1) & 0x0F) << 16) | (c10_1:byte(1) << 8) | c10_2:byte(1)
    if c.c10 >= 0x80000 then c.c10 = c.c10 - 0x100000 end

    -- 读取 C01, C11, C20, C21, C30 (各16位)
    local c01 = read_reg(REG.COEF_C01, 2)  -- 0x18-0x19
    local c11 = read_reg(REG.COEF_C11, 2)  -- 0x1A-0x1B
    local c20 = read_reg(REG.COEF_C20, 2)  -- 0x1C-0x1D
    local c21 = read_reg(REG.COEF_C21, 2)  -- 0x1E-0x1F
    local c30 = read_reg(REG.COEF_C30, 2)  -- 0x20-0x21
    if not (c01 and c11 and c20 and c21 and c30) then return nil end

    local function bytes_to_int16(b1, b2)
        local v = (b1 << 8) | b2
        if v >= 0x8000 then v = v - 0x10000 end
        return v
    end
    c.c01 = bytes_to_int16(c01:byte(1), c01:byte(2))
    c.c11 = bytes_to_int16(c11:byte(1), c11:byte(2))
    c.c20 = bytes_to_int16(c20:byte(1), c20:byte(2))
    c.c21 = bytes_to_int16(c21:byte(1), c21:byte(2))
    c.c30 = bytes_to_int16(c30:byte(1), c30:byte(2))

    return c
end


-- ============ 补偿计算 ============
local function get_scale_factor(osr_idx)
    if osr_idx < 0 or osr_idx > 7 then osr_idx = 0 end
    return SCALE_FACTORS[osr_idx + 1]
end

local function compensate_temperature(raw_temp, osr_idx, c0, c1)
    local kt = get_scale_factor(osr_idx)
    local t_sc = raw_temp / kt
    local temp = c0 * 0.5 + c1 * t_sc + TEMP_OFFSET
    return temp
end

local function compensate_pressure(raw_press, raw_temp, prs_osr_idx, tmp_osr_idx, c)
    local kp = get_scale_factor(prs_osr_idx)
    local kt = get_scale_factor(tmp_osr_idx)
    local p_sc = raw_press / kp
    local t_sc = raw_temp / kt

    local pa = c.c00 +
               p_sc * (c.c10 + p_sc * (c.c20 + p_sc * c.c30)) +
               t_sc * c.c01 +
               t_sc * p_sc * (c.c11 + p_sc * c.c21)
    return pa
end

-- ============ 读取原始数据（24位有符号） ============
local function read_raw_pressure()
    local data = read_reg(REG.PRS_MSB, 3)
    if not data then return nil end
    local raw = (data:byte(1) << 16) | (data:byte(2) << 8) | data:byte(3)
    if raw >= 0x800000 then raw = raw - 0x1000000 end
    return raw
end

local function read_raw_temperature()
    local data = read_reg(REG.TMP_MSB, 3)
    if not data then return nil end
    local raw = (data:byte(1) << 16) | (data:byte(2) << 8) | data:byte(3)
    if raw >= 0x800000 then raw = raw - 0x1000000 end
    return raw
end

-- 等待单次测量完成（检查 PRS_RDY 或 TMP_RDY）
local function wait_for_measure(timeout_ms)
    timeout_ms = timeout_ms or 1000
    local start = os.time() * 1000

    while (os.time() * 1000 - start) < timeout_ms do
        local st = read_reg(REG.MEAS_CFG, 1)
        if st then
            local s = st:byte(1)
            if (s & STATUS.PRS_RDY) ~= 0 or (s & STATUS.TMP_RDY) ~= 0 then
                return true
            end
        end
        sys.wait(5)
    end

    log.error("ns2520", "测量超时")
    return false
end

-- ============ 公共接口 ============
-- 初始化
-- @param id I2C总线ID
-- @param addr 设备地址（可选，默认0x77）
-- @param prs_cfg 压力配置（0x06寄存器值），如 nil 则使用默认 0x04 (16x OSR, 1Hz)
-- @param tmp_cfg 温度配置（0x07寄存器值），如 nil 则使用默认 0x04 (16x OSR, 1Hz)
-- @return bool 成功返回true
function ns2520.init(id, addr, prs_cfg, tmp_cfg)
    -- id为nil时使用模块级默认i2c_id（默认1），避免调用方忘记传参导致静默失败
    if not id then id = i2c_id end
    i2c_id = id
    if addr then i2c_addr = addr end

    -- 传感器供电使能：NS2520_POWER置高+I2C1上拉，等待电源稳定
    gpio.setup(POWER_PIN, 1)
    gpio.setup(I2C1_PULLUP, 1)
    sys.wait(50)

    -- 初始化I2C总线
    local i2c_setup_ok = i2c.setup(i2c_id, i2c.FAST)
    if not i2c_setup_ok or i2c_setup_ok ~= 1 then
        log.error("ns2520", "I2C总线初始化失败")
        return false
    end

    -- 检查设备是否存在：尝试读取一个寄存器
    local test = read_reg(REG.MEAS_CFG, 1)
    if not test then
        log.error("ns2520", "设备无响应，请检查连接和地址")
        return false
    end

    -- 1. 软件复位
    if not write_reg(REG.RESET, 0x09) then
        log.error("ns2520", "复位失败")
        return false
    end
    sys.wait(50)

    -- 2. 等待传感器就绪和系数可用
    local ok = false
    for i = 1, 30 do
        local st = read_reg(REG.MEAS_CFG, 1)
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
        log.error("ns2520", "传感器就绪超时")
        return false
    end

    -- 3. 配置压力/温度参数
    prs_cfg = prs_cfg or 0x04   -- 默认：16x OSR, 1Hz
    tmp_cfg = tmp_cfg or 0x04
    if not write_reg(REG.PRS_CFG, prs_cfg) then return false end
    if not write_reg(REG.TMP_CFG, tmp_cfg) then return false end

    -- 保存过采样率索引
    prs_osr = (prs_cfg & 0x0F)    -- 低4位是压力过采样率
    tmp_osr = (tmp_cfg & 0x0F)    -- 低4位是温度过采样率
    -- 注意：过采样率超过8x时，需在 CFG_REG 中设置 P_SHIFT / T_SHIFT = 1
    if prs_osr >= 4 then   -- 16x 及以上需要移位
        local cfg = read_reg(REG.CFG_REG, 1)
        if cfg then
            cfg = cfg:byte(1) | 0x04  -- P_SHIFT = 1
            write_reg(REG.CFG_REG, cfg)
        end
    end
    if tmp_osr >= 4 then
        local cfg = read_reg(REG.CFG_REG, 1)
        if cfg then
            cfg = cfg:byte(1) | 0x08  -- T_SHIFT = 1
            write_reg(REG.CFG_REG, cfg)
        end
    end

    -- 诊断：读取并打印CFG_REG最终值
    local cfg_diag = read_reg(REG.CFG_REG, 1)
    if cfg_diag then
        log.info("ns2520", "CFG_REG最终值", "0x" .. string.format("%02X", cfg_diag:byte(1)),
                 "T_SHIFT=" .. (((cfg_diag:byte(1) >> 3) & 1) == 1 and "ON" or "OFF"),
                 "P_SHIFT=" .. (((cfg_diag:byte(1) >> 2) & 1) == 1 and "ON" or "OFF"))
    end

    -- 4. 读取校准系数
    coeff = read_coefficients()
    if not coeff then
        log.error("ns2520", "读取校准系数失败")
        return false
    end

    -- 5. 进入待机模式
    write_reg(REG.MEAS_CFG, MEAS_MODE.STANDBY)

    log.info("ns2520", "初始化成功", "prs_osr=" .. prs_osr, "tmp_osr=" .. tmp_osr)
    powered = true
    return true
end

-- 单次读取压力（补偿后，单位 hPa）
function ns2520.read_pressure()
    if not coeff then return nil end

    -- 启动单次压力测量
    if not write_reg(REG.MEAS_CFG, MEAS_MODE.PRESS_SINGLE) then return nil end
    if not wait_for_measure() then return nil end

    local raw_p = read_raw_pressure()
    local raw_t = read_raw_temperature()   -- 压力补偿需要温度，即使未请求温度测量也读
    if not raw_p or not raw_t then return nil end

    local pa = compensate_pressure(raw_p, raw_t, prs_osr, tmp_osr, coeff)
    return pa / 100.0   -- Pa → hPa
end

-- 单次读取温度（补偿后，单位 ℃）
function ns2520.read_temperature()
    if not coeff then return nil end

    if not write_reg(REG.MEAS_CFG, MEAS_MODE.TEMP_SINGLE) then return nil end
    if not wait_for_measure() then return nil end

    local raw_t = read_raw_temperature()
    if not raw_t then return nil end

    return compensate_temperature(raw_t, tmp_osr, coeff.c0, coeff.c1)
end

-- 单次读取压力+温度（使用连续测量确保数据匹配）
function ns2520.read_all()
    if not coeff then return nil end

    if not write_reg(REG.MEAS_CFG, MEAS_MODE.BOTH_CONT) then
        return nil
    end

    local start = os.time() * 1000
    local prs_rdy = false
    local tmp_rdy = false
    while (os.time() * 1000 - start) < 1000 do
        local st = read_reg(REG.MEAS_CFG, 1)
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
    write_reg(REG.MEAS_CFG, MEAS_MODE.STANDBY)

    if not raw_p or not raw_t then
        log.error("ns2520", "读取原始数据失败")
        return nil
    end

    local pa = compensate_pressure(raw_p, raw_t, prs_osr, tmp_osr, coeff)
    local temp = compensate_temperature(raw_t, tmp_osr, coeff.c0, coeff.c1)

    -- 首次上电温度可能异常（raw_t=0 → 127.5°C），重试一次
    if temp > 85 or temp < -40 then
        log.warn("ns2520", "温度异常重试:", temp, "raw_t:", raw_t)
        sys.wait(100)
        write_reg(REG.MEAS_CFG, MEAS_MODE.BOTH_CONT)
        sys.wait(50)
        local rt = read_raw_temperature()
        if rt then
            raw_t = rt
            temp = compensate_temperature(raw_t, tmp_osr, coeff.c0, coeff.c1)
            log.info("ns2520", "重试后温度:", temp)
        end
        write_reg(REG.MEAS_CFG, MEAS_MODE.STANDBY)
    end

    return { pressure = pa / 100.0, temperature = temp }
end

-- ============ 背景模式（连续测量） ============
-- 注意：此模式下传感器自动更新结果寄存器，用户只需定时读取即可
function ns2520.start_background(callback, interval_ms)
    if background_running then ns2520.stop_background() end

    -- 配置连续测量（压力+温度）
    if not write_reg(REG.MEAS_CFG, MEAS_MODE.BOTH_CONT) then
        log.error("ns2520", "启动连续测量失败")
        return false
    end

    background_running = true
    background_cb = callback

    -- 定时读取最新结果（不触发测量）
    background_timer = sys.timerLoopStart(function()
        if not background_running then return end
        local raw_p = read_raw_pressure()
        local raw_t = read_raw_temperature()
        if raw_p and raw_t then
            local pa = compensate_pressure(raw_p, raw_t, prs_osr, tmp_osr, coeff)
            local temp = compensate_temperature(raw_t, tmp_osr, coeff.c0, coeff.c1)
            if background_cb then
                background_cb(pa / 100.0, temp)
            end
        else
            log.warn("ns2520", "背景读取失败")
        end
    end, interval_ms or 1000)

    log.info("ns2520", "背景模式已启动")
    return true
end

function ns2520.stop_background()
    if background_timer then
        sys.timerStop(background_timer)
        background_timer = nil
    end
    background_running = false
    background_cb = nil
    -- 恢复待机模式
    write_reg(REG.MEAS_CFG, MEAS_MODE.STANDBY)
    log.info("ns2520", "背景模式已停止")
end

-- 设置温度偏移校正值
-- @param offset 偏移量（摄氏度），正值表示读数偏低需要增加，负值表示读数偏高需要减少
function ns2520.set_temp_offset(offset)
    TEMP_OFFSET = offset or 0
    log.info("ns2520", "温度偏移已设置为", TEMP_OFFSET, "°C")
end

-- 获取当前温度偏移值
function ns2520.get_temp_offset()
    return TEMP_OFFSET
end

-- 诊断函数
function ns2520.diagnose()
    local meas = read_reg(REG.MEAS_CFG, 1)
    local prs = read_reg(REG.PRS_CFG, 1)
    local tmp = read_reg(REG.TMP_CFG, 1)
    local cfg = read_reg(REG.CFG_REG, 1)
    log.info("ns2520", "MEAS_CFG: " .. (meas and string.format("%02X", meas:byte(1)) or "ERR"))
    log.info("ns2520", "PRS_CFG : " .. (prs and string.format("%02X", prs:byte(1)) or "ERR"))
    log.info("ns2520", "TMP_CFG : " .. (tmp and string.format("%02X", tmp:byte(1)) or "ERR"))
    log.info("ns2520", "CFG_REG : " .. (cfg and string.format("%02X", cfg:byte(1)) or "ERR"))
end

-- 关闭传感器并切断供电
function ns2520.close()
    if not powered then
        -- 已是断电状态，跳过 I2C 操作（避免对已断电设备写寄存器导致超时）
        log.info("ns2520", "已关闭（无需操作）")
        return
    end

    -- I2C 操作用 pcall 保护，防止总线异常时阻塞
    local ok, err = pcall(ns2520.stop_background, ns2520)
    if not ok then
        log.warn("ns2520", "stop_background 异常:", err)
    end

    -- 切断NS2520供电（I2C1上拉不关，DA267可能还在用）
    gpio.setup(POWER_PIN, 0)
    powered = false

    log.info("ns2520", "已关闭")
end

return ns2520