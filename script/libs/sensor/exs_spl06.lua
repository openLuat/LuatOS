--[[
@module  exs_spl06
@summary SPL06-001 气压传感器驱动扩展库
@version(1.0)
@date    2026.08.21
@author  江访
@usage
本扩展库提供歌尔微电子 SPL06-001 数字气压传感器的 LuatOS 驱动，支持功能如下：

1、初始化：I2C 地址自动探测（0x76/0x77 双地址）-> 芯片 ID 校验 -> 校准系数读取 -> 过采样率配置 -> 缩放基准建立
2、数据读取：气压/温度自动校准补偿（get_data/get_pressure/get_temperature）
3、过采样率在线切换：0~7 档（1x~128x），切换时自动完成缩放因子动态自校准
4、海拔高度计算：国际气压测高公式，支持自定义海平面气压
5、测量模式切换：待机 / 单次气压 / 连续气压+温度
6、休眠唤醒：sleep/wakeup 低功耗管理
7、I2C 总线卡死自动检测与恢复

对外接口 11 个：
- exs_spl06.setup(config)：初始化传感器
- exs_spl06.get_data()：读取气压和温度
- exs_spl06.get_pressure()：单次读取气压（hPa）
- exs_spl06.get_temperature()：单次读取温度（℃）
- exs_spl06.set_osr(prs_osr, tmp_osr)：设置过采样率
- exs_spl06.get_altitude(pressure, sea_level_pressure)：海拔计算
- exs_spl06.set_mode(mode)：切换测量模式
- exs_spl06.sleep()：进入待机（等效睡眠）
- exs_spl06.wakeup()：从待机唤醒
- exs_spl06.close()：关闭传感器（进入待机）
- exs_spl06.version()：获取版本号
]]

local exs_spl06 = {}

-- ==================== 模块常量 ====================

-- I2C 设备地址（由 SDO 引脚决定，见数据手册 6.2 节）
local DEV_ADDR_0 = 0x76   -- SDO 接 GND 时
local DEV_ADDR_1 = 0x77   -- SDO 悬空或接高电平时（默认）

-- 芯片 ID 寄存器（数据手册 8.10 节）
local REG_ID     = 0x0D   -- bit[7:4]=PROD_ID, bit[3:0]=REV_ID，复位值 0x10
local CHIP_ID_VAL = 0x10  -- PROD_ID 固定为 0x1，仅匹配高 4 位（兼容不同 REV_ID）

-- 测量结果寄存器（数据手册 8.1/8.2 节，24 位补码，高位在前）
local REG_PRS_B2 = 0x00   -- 气压最高字节
local REG_PRS_B1 = 0x01   -- 气压中间字节
local REG_PRS_B0 = 0x02   -- 气压最低字节
local REG_TMP_B2 = 0x03   -- 温度最高字节
local REG_TMP_B1 = 0x04   -- 温度中间字节
local REG_TMP_B0 = 0x05   -- 温度最低字节

-- 配置寄存器（数据手册 8.3/8.4 节）
local REG_PRS_CFG = 0x06  -- bit[6:4]=PM_RATE, bit[3:0]=PM_PRC(气压过采样率)
local REG_TMP_CFG = 0x07  -- bit7=TMP_EXT(必须为1), bit[6:4]=TMP_RATE, bit[2:0]=TMP_PRC
-- 背景模式测量速率：000=1次/秒, 001=2次/秒, ...（数据手册 8.3/8.4 节）
local PM_RATE     = 0x01  -- 气压测量速率：001=2 次/秒
local TMP_RATE    = 0x01  -- 温度测量速率：001=2 次/秒（与气压一致，保证 TMP_RDY 每 500ms 置位，
                          --   若用 000=1 次/秒则与 1s 等待超时同周期，模式切换后可能相位错过致读取超时）

-- 工作模式与状态寄存器（数据手册 8.5 节）
local REG_MEAS_CFG = 0x08 -- bit[7]=COEF_RDY, bit[6]=SENSOR_RDY, bit[5]=TMP_RDY, bit[4]=PRS_RDY, bit[2:0]=MEAS_CTRL

-- 测量模式（MEAS_CFG 寄存器 MEAS_CTRL 位，含字符串别名供 set_mode 使用）
local MEAS_CTRL = {
    STANDBY       = 0x00,  -- 待机 / 停止背景测量
    PRESS_SINGLE  = 0x01,  -- 单次气压测量
    PRESSURE      = 0x01,  -- 同上（别名）
    TEMP_SINGLE   = 0x02,  -- 单次温度测量
    TEMPERATURE   = 0x02,  -- 同上（别名）
    BOTH_CONT     = 0x07,  -- 连续气压+温度测量
    BOTH          = 0x07,  -- 同上（别名）
}

-- 状态位（MEAS_CFG 寄存器）
local STATUS = {
    COEF_RDY   = 0x80,     -- 校准系数就绪
    SENSOR_RDY = 0x40,     -- 传感器自检完成
    TMP_RDY    = 0x20,     -- 温度测量完成
    PRS_RDY    = 0x10,     -- 气压测量完成
}

-- 中断/FIFO 配置寄存器（数据手册 8.6 节）
local REG_CFG_REG = 0x09   -- bit[3]=T_SHIFT, bit[2]=P_SHIFT, bit[1]=FIFO_EN
local P_SHIFT     = 0x04   -- 气压结果右移（过采样 >=16x 时必须置 1）
local T_SHIFT     = 0x08   -- 温度结果右移（过采样 >=16x 时必须置 1）

-- 校准系数寄存器（数据手册 8.11 节）
local REG_COEF_C0      = 0x10
local REG_COEF_C0_C1   = 0x11
local REG_COEF_C1      = 0x12
local REG_COEF_C00     = 0x13
local REG_COEF_C00_2   = 0x14
local REG_COEF_C00_C10 = 0x15
local REG_COEF_C10     = 0x16
local REG_COEF_C10_2   = 0x17
local REG_COEF_C01     = 0x18
local REG_COEF_C11     = 0x1A
local REG_COEF_C20     = 0x1C
local REG_COEF_C21     = 0x1E
local REG_COEF_C30     = 0x20

-- 缩放因子表（数据手册 Table 4，索引 = 过采样率 0~7）
-- 仅作为默认过采样（16x 气压、8x 温度）的基准锚点与退化备用；
-- 高过采样（32x/64x/128x）该表值真机实测不准，由动态自校准覆盖
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

-- 默认过采样（16x 气压/8x 温度为真机实测准确的缩放锚点）
local DEFAULT_PRS_OSR = 4     -- 气压默认 16x（标准精度）
local DEFAULT_TMP_OSR = 3     -- 温度默认 8x

-- ==================== 内部状态 ====================

local g_i2c_bus      = nil       -- I2C 总线 id
local g_is_soft      = false     -- 是否软件 I2C
local g_scl_pin      = nil       -- SCL 引脚（总线恢复用）
local g_sda_pin      = nil       -- SDA 引脚（总线恢复用）
local g_i2c_speed    = i2c.SLOW  -- 保存原始 speed（总线恢复后恢复）
local g_dev_addr     = nil       -- 探测成功后锁定的 I2C 地址
local g_coeff        = nil       -- 校准系数表
local g_prs_osr      = DEFAULT_PRS_OSR  -- 当前气压过采样率索引（0~7）
local g_tmp_osr      = DEFAULT_TMP_OSR  -- 当前温度过采样率索引（0~7）
local g_kp           = SCALE_FACTORS[DEFAULT_PRS_OSR + 1]  -- 气压缩放因子（动态自校准）
local g_kt           = SCALE_FACTORS[DEFAULT_TMP_OSR + 1]  -- 温度缩放因子（动态自校准）
local g_base_prs_raw = nil       -- 基准气压原始值（setup 以 16x 建立）
local g_base_tmp_raw = nil       -- 基准温度原始值（setup 以 8x 建立）
local g_mode         = "both"    -- 当前测量模式（standby/pressure/temperature/both）
local g_ready        = false     -- 初始化完成标志

-- 前向声明：以下函数在本文件后部定义，但 calibrate_osr/setup/get_data 等
-- 在定义前即被引用。Lua 词法作用域中，后声明需先用 local 占位（否则引用解析为全局 nil）
local wait_for_measure
local read_raw_pressure
local read_raw_temperature

-- ==================== I2C 操作 ====================

-- I2C 总线硬件恢复：9 个 SCL 脉冲 + 每脉冲检测 SDA 释放 + STOP 信号
-- 锁死判据：SDA=0, SCL=1（从机锁死 SDA）
local function i2c_bus_recovery()
    if not g_scl_pin or not g_sda_pin then return false end
    gpio.setup(g_scl_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    sys.wait(1)     -- 等待电平稳定，1ms
    for i = 1, 9 do
        gpio.set(g_scl_pin, 0); sys.wait(1)                          -- SCL 拉低
        gpio.setup(g_sda_pin, gpio.INPUT, gpio.PULLUP); sys.wait(1)  -- 检测 SDA 释放
        if gpio.get(g_sda_pin) == 1 then
            gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
            break
        end
        gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
        gpio.set(g_scl_pin, 1); sys.wait(1)                          -- SCL 拉高
    end
    gpio.set(g_sda_pin, 0); sys.wait(1)    -- 起始条件
    gpio.set(g_scl_pin, 1); sys.wait(1)    -- 结束条件前半
    gpio.set(g_sda_pin, 1); sys.wait(1)    -- 结束条件后半
    return true
end

-- 检测总线是否卡死，卡死后调用 i2c_bus_recovery 恢复
local function try_bus_recovery()
    if not g_scl_pin or not g_sda_pin then return false end
    gpio.setup(g_sda_pin, gpio.INPUT, gpio.PULLUP)
    gpio.setup(g_scl_pin, gpio.INPUT, gpio.PULLUP); sys.wait(1)
    local is_stall = (gpio.get(g_sda_pin) == 0 and gpio.get(g_scl_pin) == 1)
    gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    gpio.setup(g_scl_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    if not is_stall then return false end  -- 总线未卡死，无需恢复
    log.warn("exs_spl06", "检测到I2C总线卡死，尝试恢复")
    i2c_bus_recovery()
    if not g_is_soft then i2c.setup(g_i2c_bus, g_i2c_speed) end  -- 硬件 I2C 恢复后重新 setup 并恢复原始 speed
    return true
end

-- 写单字节寄存器（8 位寄存器地址）
local function wr8(reg, val)
    local ok = i2c.send(g_i2c_bus, g_dev_addr, {reg, val})
    if not ok and try_bus_recovery() then
        ok = i2c.send(g_i2c_bus, g_dev_addr, {reg, val})
    end
    return ok
end

-- 读单字节寄存器（8 位寄存器地址）
local function rd8(reg)
    local ok = i2c.send(g_i2c_bus, g_dev_addr, {reg})
    if not ok then
        if try_bus_recovery() then ok = i2c.send(g_i2c_bus, g_dev_addr, {reg}) end
        if not ok then return nil end
    end
    local d = i2c.recv(g_i2c_bus, g_dev_addr, 1)
    if not d or #d < 1 then return nil end
    return d:byte(1)
end

-- 连续读多字节寄存器（寄存器地址自增）
-- len：读取字节数
-- 返回 string 或 nil
local function read_bytes(reg, len)
    local ok = i2c.send(g_i2c_bus, g_dev_addr, {reg})
    if not ok then
        if try_bus_recovery() then ok = i2c.send(g_i2c_bus, g_dev_addr, {reg}) end
        if not ok then return nil end
    end
    local d = i2c.recv(g_i2c_bus, g_dev_addr, len)
    if not d or #d < len then return nil end
    return d
end

-- ==================== 校准系数读取 ====================

-- 两个字节合成 16 位有符号整数（高位在前）
local function bytes_to_int16(b1, b2)
    local v = (b1 << 8) | b2
    if v >= 0x8000 then v = v - 0x10000 end
    return v
end

-- 读取芯片出厂校准系数（数据手册 8.11 节）
-- 返回系数表或 nil
local function read_coefficients()
    local c = {}

    -- c0(12 位有符号): 0x10[11:4] | 0x11[7:4]
    local c0_byte = rd8(REG_COEF_C0)
    local c0c1_byte = rd8(REG_COEF_C0_C1)
    local c1_byte = rd8(REG_COEF_C1)
    if not (c0_byte and c0c1_byte and c1_byte) then return nil end

    c.c0 = ((c0_byte << 4) | (c0c1_byte >> 4))
    if c.c0 >= 0x800 then c.c0 = c.c0 - 0x1000 end

    -- c1(12 位有符号): 0x11[3:0] << 8 | 0x12[7:0]
    c.c1 = ((c0c1_byte & 0x0F) << 8) | c1_byte
    if c.c1 >= 0x800 then c.c1 = c.c1 - 0x1000 end

    -- c00(20 位有符号): 0x13[19:12] | 0x14[11:4] | 0x15[7:4]
    local c00_1 = rd8(REG_COEF_C00)
    local c00_2 = rd8(REG_COEF_C00_2)
    local c00c10 = rd8(REG_COEF_C00_C10)
    if not (c00_1 and c00_2 and c00c10) then return nil end

    c.c00 = (c00_1 << 12) | (c00_2 << 4) | (c00c10 >> 4)
    if c.c00 >= 0x80000 then c.c00 = c.c00 - 0x100000 end

    -- c10(20 位有符号): 0x15[3:0] << 16 | 0x16[15:8] | 0x17[7:0]
    local c10_1 = rd8(REG_COEF_C10)
    local c10_2 = rd8(REG_COEF_C10_2)
    if not (c10_1 and c10_2) then return nil end
    c.c10 = ((c00c10 & 0x0F) << 16) | (c10_1 << 8) | c10_2
    if c.c10 >= 0x80000 then c.c10 = c.c10 - 0x100000 end

    -- c01/c11/c20/c21/c30（各 16 位有符号，高位在前）
    local r01 = read_bytes(REG_COEF_C01, 2)
    local r11 = read_bytes(REG_COEF_C11, 2)
    local r20 = read_bytes(REG_COEF_C20, 2)
    local r21 = read_bytes(REG_COEF_C21, 2)
    local r30 = read_bytes(REG_COEF_C30, 2)
    if not (r01 and r11 and r20 and r21 and r30) then return nil end

    c.c01 = bytes_to_int16(r01:byte(1), r01:byte(2))
    c.c11 = bytes_to_int16(r11:byte(1), r11:byte(2))
    c.c20 = bytes_to_int16(r20:byte(1), r20:byte(2))
    c.c21 = bytes_to_int16(r21:byte(1), r21:byte(2))
    c.c30 = bytes_to_int16(r30:byte(1), r30:byte(2))

    return c
end

-- ==================== 过采样配置与动态校准 ====================

-- 按各通道过采样率计算 CFG_REG 的 P_SHIFT/T_SHIFT 位（统一入口）
-- 规则：通道过采样 >=16x（osr>=4）时必须设对应 SHIFT 位；<16x 时对应位必须为 0，
--       否则低过采样的原始值会被芯片错误缩放（真机验证关键点）
local function build_cfg_reg(prs_osr, tmp_osr)
    local cfg = 0
    if prs_osr >= 4 then cfg = cfg | P_SHIFT end
    if tmp_osr >= 4 then cfg = cfg | T_SHIFT end
    return cfg
end

-- 写过采样配置（PRS_CFG/TMP_CFG/CFG_REG 统一入口）
-- TMP_EXT=1：SPL06-001 必须使用外部 MEMS 温度传感器（数据手册要求），否则温度读错
local function write_osr_cfg(prs_osr, tmp_osr)
    -- PRS_CFG：PM_RATE=001(2次/秒) | PM_PRC
    if not wr8(REG_PRS_CFG, (PM_RATE << 4) | prs_osr) then return false end
    -- TMP_CFG：TMP_EXT=1 | TMP_RATE=001(2次/秒) | TMP_PRC
    if not wr8(REG_TMP_CFG, 0x80 | (TMP_RATE << 4) | tmp_osr) then return false end
    -- CFG_REG：P_SHIFT/T_SHIFT 按各通道 OSR 统一计算
    return wr8(REG_CFG_REG, build_cfg_reg(prs_osr, tmp_osr))
end

-- 原始值合理性校验（动态校准用）
-- 与基准 base 同号且量级在 [min_ratio, max_ratio] 倍范围内
-- 同号判断用浮点除法（raw/base > 0），避免 32 位整数乘法溢出导致符号翻转
-- 压力/温度通道原始值随过采样变化规律不同，需分别设范围：
--   压力 64x 约 4×16x 基准（0.2~8 倍覆盖）
--   温度 32x 约 0.066×8x 基准（真机实测 151643 vs 2312254，远小于 0.2 倍；
--   128x 估约 0.004~0.066 倍，故下限放宽至 0.002；异常小值 157 等 <0.001 倍仍可拦截）
local function is_valid_raw(raw, base, min_ratio, max_ratio)
    return raw and base
        and raw / base > 0
        and math.abs(raw) > math.abs(base) * min_ratio
        and math.abs(raw) < math.abs(base) * max_ratio
end

-- 动态自校准缩放因子（连续测量模式适配）
-- 原理：同一物理量下 Praw_sc/Traw_sc 应恒定，即 k ∝ raw。
--       切换过采样后读取新原始值，按 "新raw/基准raw × 基准k" 更新缩放因子。
-- 规避规格书 Table 4 高过采样（32x/64x/128x）缩放因子真机实测不准的问题。
-- 注意：1) 计算必须用浮点"先除后乘"（LuatOS 整数 32 位，kp_base*raw 最大 ±2.13e12
--          会溢出为负数）；
--       2) 切换后必须重启连续测量（STANDBY→BOTH_CONT）并消费残留旧数据，
--          否则会读到配置切换过渡期的异常原始值（真机实测 64x 压力 +22578、
--          温度 149805 等均为无效值）；
--       3) 校验：原始值与基准同号且量级在通道合理范围内（压力 0.2~8 倍、
--          温度 0.002~32 倍，32x 温度稳态值仅约 8x 基准的 6.6%）。
-- 返回 true 校准成功；false 重试 3 次仍失败（内部已回退默认过采样并重建基准）
local function calibrate_osr()
    -- 1) 重启连续测量，消除配置切换过渡期残留异常数据
    wr8(REG_MEAS_CFG, MEAS_CTRL.STANDBY)
    sys.wait(20)
    wr8(REG_MEAS_CFG, MEAS_CTRL.BOTH_CONT)
    g_mode = "both"
    -- 2) 消费重启瞬间残留的旧数据/RDY（真机实测重启后第一次读取仍是切换前残留）
    read_bytes(REG_PRS_B2, 3)
    read_bytes(REG_TMP_B2, 3)
    -- 3) 独立重试读取有效原始值（最多 3 次，间隔 100ms 等下一轮连续测量更新）
    local p_raw, t_raw
    local p_ok, t_ok = false, false
    for i = 1, 3 do
        if not p_ok then
            local v = read_raw_pressure()
            if is_valid_raw(v, g_base_prs_raw, 0.2, 8) then
                p_raw = v
                p_ok = true
            else
                log.warn("exs_spl06", "气压原始值异常(" .. tostring(v) .. ")，重试", i)
            end
        end
        if not t_ok then
            local v = read_raw_temperature()
            if is_valid_raw(v, g_base_tmp_raw, 0.002, 32) then
                t_raw = v
                t_ok = true
            else
                log.warn("exs_spl06", "温度原始值异常(" .. tostring(v) .. ")，重试", i)
            end
        end
        if p_ok and t_ok then break end
        sys.wait(100)   -- 等待下一轮测量完成，100ms
    end
    -- 4) 任一通道重试 3 次仍失败：回退默认过采样（16x/8x，实测验证准确）并重建基准
    if not p_ok or not t_ok then
        log.error("exs_spl06", "高过采样动态校准失败(P", tostring(p_ok), "T", tostring(t_ok), ")，回退默认 16x/8x")
        write_osr_cfg(DEFAULT_PRS_OSR, DEFAULT_TMP_OSR)
        g_prs_osr = DEFAULT_PRS_OSR
        g_tmp_osr = DEFAULT_TMP_OSR
        g_kp = SCALE_FACTORS[DEFAULT_PRS_OSR + 1]
        g_kt = SCALE_FACTORS[DEFAULT_TMP_OSR + 1]
        wr8(REG_MEAS_CFG, MEAS_CTRL.STANDBY)
        sys.wait(20)
        wr8(REG_MEAS_CFG, MEAS_CTRL.BOTH_CONT)
        g_mode = "both"
        read_bytes(REG_PRS_B2, 3)
        read_bytes(REG_TMP_B2, 3)
        g_base_prs_raw = read_raw_pressure()
        g_base_tmp_raw = read_raw_temperature()
        if g_base_prs_raw and g_base_tmp_raw then
            log.info("exs_spl06", "缩放基准原始值已重建: P", g_base_prs_raw, "T", g_base_tmp_raw)
        end
        return false
    end
    -- 浮点先除后乘避免 32 位整数溢出
    g_kp = SCALE_FACTORS[DEFAULT_PRS_OSR + 1] / g_base_prs_raw * p_raw
    g_kt = SCALE_FACTORS[DEFAULT_TMP_OSR + 1] / g_base_tmp_raw * t_raw
    log.info("exs_spl06", "缩放因子动态校准: kP", string.format("%.0f", g_kp), "kT", string.format("%.0f", g_kt))
    return true
end

-- ==================== 补偿计算 ====================

-- 温度补偿（数据手册 5.6.2 节）：Tcomp = c0*0.5 + c1*Traw_sc，Traw_sc = raw/g_kt
local function compensate_temperature(raw_temp, c0, c1)
    return c0 * 0.5 + c1 * raw_temp / g_kt
end

-- 气压补偿（数据手册 5.6.1 节）：结果为 Pa
local function compensate_pressure(raw_press, raw_temp, c)
    local p_sc = raw_press / g_kp
    local t_sc = raw_temp / g_kt
    return c.c00 + p_sc * (c.c10 + p_sc * (c.c20 + p_sc * c.c30))
         + t_sc * c.c01
         + t_sc * p_sc * (c.c11 + p_sc * c.c21)
end

-- ==================== 读取原始数据 ====================

-- 读取气压原始值（24 位补码）
-- 先等待 PRS_RDY 就绪（连续测量模式下周期置位，一定能等到），再读取新数据；
-- 读结果寄存器后芯片自动清除 PRS_RDY
read_raw_pressure = function()
    if not wait_for_measure(STATUS.PRS_RDY) then return nil end
    local data = read_bytes(REG_PRS_B2, 3)
    if not data then return nil end
    local raw = (data:byte(1) << 16) | (data:byte(2) << 8) | data:byte(3)
    if raw >= 0x800000 then raw = raw - 0x1000000 end
    return raw
end

-- 读取温度原始值（24 位补码）
read_raw_temperature = function()
    if not wait_for_measure(STATUS.TMP_RDY) then return nil end
    local data = read_bytes(REG_TMP_B2, 3)
    if not data then return nil end
    local raw = (data:byte(1) << 16) | (data:byte(2) << 8) | data:byte(3)
    if raw >= 0x800000 then raw = raw - 0x1000000 end
    return raw
end

-- 等待测量就绪位（轮询 MEAS_CFG）
-- rdy_bit：等待的状态位（STATUS.PRS_RDY / STATUS.TMP_RDY）
-- timeout_ms：超时毫秒，默认 1000
-- 返回 true 就绪，false 超时
-- 注意：计时用自增计数，不能用 os.time()*1000（os.time 只有秒精度，
--       秒翻转前差值恒为 0 会提前误判超时，真机验证关键点）
wait_for_measure = function(rdy_bit, timeout_ms)
    timeout_ms = timeout_ms or 1000
    local elapsed = 0
    while elapsed < timeout_ms do
        local st = rd8(REG_MEAS_CFG)
        if st and (st & rdy_bit) ~= 0 then return true end
        sys.wait(5)     -- 每 5ms 检测一次
        elapsed = elapsed + 5
    end
    log.warn("exs_spl06", "测量等待超时")
    return false
end

-- ==================== 对外 API ====================

--[[
初始化 SPL06-001 气压传感器，配置 I2C 通信参数，自动探测并锁定芯片地址，
等待校准系数就绪并读取，配置过采样率并建立缩放校准基准

@api exs_spl06.setup(config)
@param table config
参数含义：初始化配置表
数据类型：table
取值范围：
{
    参数含义：SCL 时钟引脚 GPIO 编号（与 sda 同时传入时使用软件 I2C）
    数据类型：number
    取值范围：有效的 GPIO 编号
    是否必选：否
    注意事项：与 sda 需同时传入；再传 i2c_id 则走硬件 I2C 并附带总线恢复
    参数示例：31
    config.scl ,

    参数含义：SDA 数据引脚 GPIO 编号
    数据类型：number
    取值范围：有效的 GPIO 编号
    是否必选：否
    注意事项：该引脚需外接 4.7kΩ~10kΩ 上拉电阻到 VCC
    参数示例：30
    config.sda ,

    参数含义：硬件 I2C 总线 id
    数据类型：number
    取值范围：0 ~ 1，具体取决于硬件支持
    是否必选：否
    注意事项：仅传 i2c_id 时不具总线自动恢复能力
    参数示例：0
    config.i2c_id ,

    参数含义：I2C 设备地址（芯片支持多个地址，可不传，自动探测）
    数据类型：number
    取值范围：0x77 / 0x76（由 SDO 引脚决定：SDO 悬空或接高电平 = 0x77，
              SDO 接 GND = 0x76）
    是否必选：否
    注意事项：不传时扩展库自动探测两个地址并校验芯片 ID，命中后锁定；
              传了则直接使用该地址并跳过探测
    参数示例：0x76
    config.addr ,

    参数含义：气压过采样率
    数据类型：number
    取值范围：0~7，对应 1x/2x/4x/8x/16x/32x/64x/128x
    是否必选：否
    注意事项：默认 4（16x），适合大多数场景；低功耗选 0~1，
              高精度气象站选 6~7
    参数示例：6
    config.prs_osr ,

    参数含义：温度过采样率
    数据类型：number
    取值范围：0~7，对应 1x/2x/4x/8x/16x/32x/64x/128x
    是否必选：否
    注意事项：默认 3（8x）；温度测量功耗极低，一般保持默认即可
    参数示例：4
    config.tmp_osr ,
}
是否必选：是
参数示例：
    -- 软件 I2C 模式（推荐）
    exs_spl06.setup({scl = 31, sda = 30})

    -- 硬件 I2C + 总线恢复
    exs_spl06.setup({i2c_id = 0, scl = 31, sda = 30})

    -- 指定地址 + 高精度过采样
    exs_spl06.setup({scl = 31, sda = 30, addr = 0x76, prs_osr = 6})
@return boolean
含义说明：初始化是否成功
数据类型：boolean
取值范围：true（成功），false（失败）
注意事项：失败时请检查接线、供电和 I2C 地址
]]
function exs_spl06.setup(config)
    if type(config) ~= "table" then
        log.error("exs_spl06.setup 参数错误")
        return false
    end

    -- 记录硬件 I2C 速率（总线恢复后需恢复原始 speed）
    g_i2c_speed = i2c.SLOW

    -- I2C 初始化
    if config.scl and config.sda then
        g_scl_pin = config.scl; g_sda_pin = config.sda
        if config.i2c_id then
            i2c_bus_recovery()
            if i2c.setup(config.i2c_id, i2c.SLOW) == 0 then
                log.error("exs_spl06.setup 硬件 I2C 失败"); return false
            end
            g_i2c_bus = config.i2c_id; g_is_soft = false
        else
            i2c_bus_recovery()
            g_i2c_bus = i2c.createSoft(config.scl, config.sda, 5)
            if not g_i2c_bus then log.error("exs_spl06.setup 软件 I2C 失败"); return false end
            g_is_soft = true
        end
    else
        local id = config.i2c_id or 0
        if i2c.setup(id, i2c.SLOW) == 0 then
            log.error("exs_spl06.setup I2C 失败"); return false
        end
        g_i2c_bus = id; g_is_soft = false; g_scl_pin = nil; g_sda_pin = nil
    end

    -- 芯片地址校验：不传 addr 时自动探测两个地址，按 PROD_ID 校验锁定
    -- SPL06-001 的 PROD_ID 固定为 0x1（寄存器高 4 位），REV_ID 可能不同
    local addr_list = {DEV_ADDR_0, DEV_ADDR_1}
    if config.addr then addr_list = {config.addr} end
    local ok_addr = nil
    for i = 1, #addr_list do
        g_dev_addr = addr_list[i]
        local prod_id = rd8(REG_ID)
        if prod_id and (prod_id & 0xF0) == CHIP_ID_VAL then
            ok_addr = g_dev_addr
            log.info("exs_spl06", string.format("芯片地址自适应：0x%02X", g_dev_addr))
            break
        end
    end
    if not ok_addr then
        local hexs = {}
        for i = 1, #addr_list do hexs[i] = string.format("0x%02X", addr_list[i]) end
        log.error("exs_spl06", "芯片识别失败：地址探测无命中（" .. table.concat(hexs, "/") .. "）")
        return false
    end

    -- 等待传感器自检完成、校准系数就绪（数据手册：12ms/40ms）
    local ok = false
    for i = 1, 50 do
        local st = rd8(REG_MEAS_CFG)
        if st then
            if (st & STATUS.SENSOR_RDY) ~= 0 and (st & STATUS.COEF_RDY) ~= 0 then
                ok = true
                break
            end
        end
        sys.wait(10)    -- 每 10ms 检测一次
    end
    if not ok then
        log.error("exs_spl06.setup 传感器就绪超时")
        return false
    end

    -- 读取校准系数
    g_coeff = read_coefficients()
    if not g_coeff then
        log.error("exs_spl06.setup 校准系数读取失败")
        return false
    end

    -- 写默认过采样配置（16x 气压/8x 温度，实测准确锚点）
    if not write_osr_cfg(DEFAULT_PRS_OSR, DEFAULT_TMP_OSR) then
        log.error("exs_spl06.setup 过采样配置失败")
        return false
    end
    g_prs_osr = DEFAULT_PRS_OSR
    g_tmp_osr = DEFAULT_TMP_OSR
    g_kp = SCALE_FACTORS[DEFAULT_PRS_OSR + 1]
    g_kt = SCALE_FACTORS[DEFAULT_TMP_OSR + 1]

    -- 启动连续气压+温度测量，建立缩放基准原始值（用于过采样切换时的动态自校准）
    -- 连续测量模式下 PRS_RDY/TMP_RDY 周期置位，read_raw_* 一定能等到新数据
    wr8(REG_MEAS_CFG, MEAS_CTRL.BOTH_CONT)
    g_mode = "both"
    g_base_prs_raw = read_raw_pressure()
    g_base_tmp_raw = read_raw_temperature()
    if g_base_prs_raw and g_base_tmp_raw then
        log.info("exs_spl06", "缩放基准原始值: P", g_base_prs_raw, "T", g_base_tmp_raw)
    else
        log.warn("exs_spl06", "缩放基准原始值读取失败，高过采样切换将退化为规格书查表")
    end

    -- 用户指定了其他过采样率则切换并动态校准；校准失败回退默认配置，初始化仍可用
    local cfg_prs = config.prs_osr or DEFAULT_PRS_OSR
    local cfg_tmp = config.tmp_osr or DEFAULT_TMP_OSR
    if cfg_prs ~= DEFAULT_PRS_OSR or cfg_tmp ~= DEFAULT_TMP_OSR then
        if write_osr_cfg(cfg_prs, cfg_tmp) then
            g_prs_osr = cfg_prs
            g_tmp_osr = cfg_tmp
            if g_base_prs_raw and g_base_tmp_raw then
                if not calibrate_osr() then
                    log.warn("exs_spl06", "自定义过采样动态校准失败，已回退默认 16x/8x")
                end
            else
                g_kp = SCALE_FACTORS[cfg_prs + 1]
                g_kt = SCALE_FACTORS[cfg_tmp + 1]
            end
        end
    end

    -- 保持连续测量模式（get_data 直接读最新数据）
    g_ready = true

    log.info("exs_spl06", string.format("初始化完成, prs_osr=%d tmp_osr=%d", g_prs_osr, g_tmp_osr))
    return true
end

--[[
读取气压和温度数据，自动完成校准补偿计算
采用连续测量模式：内部维持 BOTH_CONT 连续测量，直接等待最新数据就绪后读取；
若当前处于待机/单次模式（如 sleep 后），会自动恢复连续测量

注意事项：必须在 sys.taskInit() 创建的协程中调用（内部使用 sys.wait() 轮询等待测量完成，在 task 外调用会报错）

@api exs_spl06.get_data()
@param none
@return table/nil
含义说明：气压和温度数据表，失败返回 nil
数据类型：table 或 nil
取值范围：
    data.pressure    - 气压，单位 hPa，范围 300.00~1100.00
    data.temperature - 温度，单位 ℃，范围 -40.0~+85.0
注意事项：等待最新数据时间取决于过采样率（16x 约 27.6ms，64x 约 104ms）
]]
function exs_spl06.get_data()
    if not g_ready then
        log.error("exs_spl06.get_data 请先调用 setup()")
        return nil
    end
    -- 若当前不在连续测量模式（如 sleep/standby 后），自动恢复连续测量
    if g_mode ~= "both" then
        exs_spl06.set_mode("both")
    end

    -- 连续测量模式下等待最新气压/温度数据就绪并读取（RDY 周期置位）
    local raw_p = read_raw_pressure()
    local raw_t = read_raw_temperature()
    if not raw_p or not raw_t then
        log.error("exs_spl06.get_data 读取原始数据失败")
        return nil
    end

    local temp = compensate_temperature(raw_t, g_coeff.c0, g_coeff.c1)
    local p_hpa = compensate_pressure(raw_p, raw_t, g_coeff) / 100.0

    -- 输出合理性校验（最后防线）：补偿链路异常（缩放因子错误/数据污染）时拒绝输出
    if p_hpa < 300 or p_hpa > 1100 or temp < -40 or temp > 85 then
        log.warn("exs_spl06", "补偿结果超合理范围(气压", string.format("%.2f", p_hpa), "hPa 温度", string.format("%.2f", temp), "℃)，已丢弃")
        return nil
    end

    return {
        pressure = p_hpa,
        temperature = temp,
    }
end

--[[
单次读取气压值（hPa），自动完成补偿计算
内部基于 get_data() 读取，连续测量模式下直接取最新数据

注意事项：必须在 sys.taskInit() 创建的协程中调用（内部使用 sys.wait() 轮询等待测量完成，在 task 外调用会报错）

@api exs_spl06.get_pressure()
@param none
@return number/nil
含义说明：补偿后的气压值，失败返回 nil
数据类型：number 或 nil
取值范围：300.00~1100.00（单位 hPa）
]]
function exs_spl06.get_pressure()
    local d = exs_spl06.get_data()
    if d then return d.pressure end
    return nil
end

--[[
单次读取温度值（℃），自动完成补偿计算
内部基于 get_data() 读取，连续测量模式下直接取最新数据

注意事项：必须在 sys.taskInit() 创建的协程中调用（内部使用 sys.wait() 轮询等待测量完成，在 task 外调用会报错）

@api exs_spl06.get_temperature()
@param none
@return number/nil
含义说明：补偿后的温度值，失败返回 nil
数据类型：number 或 nil
取值范围：-40.0~+85.0（单位 ℃）
]]
function exs_spl06.get_temperature()
    local d = exs_spl06.get_data()
    if d then return d.temperature end
    return nil
end

--[[
设置过采样率，在线修改气压和温度的过采样率，无需重新初始化
切换后自动触发缩放因子动态自校准（以 16x 气压/8x 温度为基准按比例校准 kP/kT）

注意事项：必须在 sys.taskInit() 创建的协程中调用（内部使用 sys.wait() 轮询等待测量完成，在 task 外调用会报错）

@api exs_spl06.set_osr(prs_osr, tmp_osr)
@param number prs_osr
参数含义：气压目标过采样率
数据类型：number
取值范围：0~7，对应 1x/2x/4x/8x/16x/32x/64x/128x
是否必选：否
注意事项：不传则保持当前气压过采样率。超范围自动裁剪到 0~7
参数示例：6
@param number tmp_osr
参数含义：温度目标过采样率
数据类型：number
取值范围：0~7，对应 1x/2x/4x/8x/16x/32x/64x/128x
是否必选：否
注意事项：不传则保持当前温度过采样率。超范围自动裁剪到 0~7
参数示例：3
@return boolean
含义说明：切换是否成功
数据类型：boolean
取值范围：true（成功），false（失败）
注意事项：高过采样（32x/64x/128x）动态校准失败时自动回退默认 16x/8x 并返回 false
]]
function exs_spl06.set_osr(prs_osr, tmp_osr)
    if not g_ready then
        log.error("exs_spl06.set_osr 请先调用 setup()")
        return false
    end

    local new_prs = g_prs_osr
    local new_tmp = g_tmp_osr
    if prs_osr then
        if prs_osr < 0 then prs_osr = 0 elseif prs_osr > 7 then prs_osr = 7 end
        new_prs = prs_osr
    end
    if tmp_osr then
        if tmp_osr < 0 then tmp_osr = 0 elseif tmp_osr > 7 then tmp_osr = 7 end
        new_tmp = tmp_osr
    end

    -- 写新过采样配置
    if not write_osr_cfg(new_prs, new_tmp) then return false end
    g_prs_osr = new_prs
    g_tmp_osr = new_tmp

    -- 动态自校准缩放因子；基准未建立时退化为规格书查表
    -- 校准失败时 calibrate_osr 内部已回退默认过采样并重建基准，这里直接返回 false
    if g_base_prs_raw and g_base_tmp_raw then
        if not calibrate_osr() then
            return false
        end
    else
        g_kp = SCALE_FACTORS[g_prs_osr + 1]
        g_kt = SCALE_FACTORS[g_tmp_osr + 1]
    end
    log.info("exs_spl06", string.format("过采样切换成功, prs_osr=%d tmp_osr=%d", g_prs_osr, g_tmp_osr))
    return true
end

--[[
根据气压值计算海拔高度（国际气压测高公式：h = 44330*(1-(P/P0)^(1/5.255))）

@api exs_spl06.get_altitude(pressure, sea_level_pressure)
@param number pressure
参数含义：实测气压值（hPa）
数据类型：number
取值范围：300.00~1100.00（单位 hPa）
是否必选：是
参数示例：1002.80
@param number sea_level_pressure
参数含义：海平面气压（hPa），用于海拔计算基准
数据类型：number
取值范围：900.00~1100.00（单位 hPa）
是否必选：否
注意事项：不传时默认 1013.25 hPa（标准大气压）
参数示例：1005
@return number
含义说明：海拔高度
数据类型：number
取值范围：-500~9000（单位 米，粗略）
返回示例：87.4
]]
function exs_spl06.get_altitude(pressure, sea_level_pressure)
    local p0 = sea_level_pressure or 1013.25
    if not pressure or pressure <= 0 or p0 <= 0 then return 0 end
    return 44330 * (1 - (pressure / p0) ^ (1 / 5.255))
end

--[[
切换测量模式（写 MEAS_CFG 的 MEAS_CTRL 位）

@api exs_spl06.set_mode(mode)
@param string mode
参数含义：目标测量模式
数据类型：string
取值范围："standby"（待机，电流<1µA）/ "pressure"（单次气压，测完自动回待机）/
          "temperature"（单次温度，测完自动回待机）/ "both"（连续气压+温度）
是否必选：是
注意事项：不区分大小写
参数示例："both"
@return boolean
含义说明：切换是否成功
数据类型：boolean
取值范围：true（成功），false（失败）
]]
function exs_spl06.set_mode(mode)
    if not g_ready then
        log.error("exs_spl06.set_mode 请先调用 setup()")
        return false
    end
    mode = mode or ""
    local ctrl = MEAS_CTRL[mode:upper()]
    if not ctrl then
        log.error("exs_spl06", "非法测量模式", mode, "可选 standby/pressure/temperature/both")
        return false
    end
    if not wr8(REG_MEAS_CFG, ctrl) then return false end
    g_mode = mode:lower()
    return true
end

--[[
进入低功耗待机（等效睡眠，电流 < 1µA，校准系数不丢失）
与 close 的区别：sleep 不释放 I2C 资源，wakeup 可直接恢复测量

@api exs_spl06.sleep()
@param none
@return nil
]]
function exs_spl06.sleep()
    if not g_ready then return end
    exs_spl06.set_mode("standby")
    log.info("exs_spl06", "已进入待机（睡眠）")
end

--[[
从待机唤醒，恢复连续气压+温度测量（无需重新读取校准系数）

@api exs_spl06.wakeup()
@param none
@return nil
]]
function exs_spl06.wakeup()
    if not g_ready then return end
    exs_spl06.set_mode("both")
    log.info("exs_spl06", "已唤醒，恢复连续测量")
end

--[[
关闭 SPL06-001 传感器，令芯片进入待机模式（功耗小于 1μA），
并释放 I2C 资源、重置内部状态。
close 后需要重新调用 setup() 才能再次使用。

@api exs_spl06.close()
@param none
@return nil
]]
function exs_spl06.close()
    if not g_ready then return end
    wr8(REG_MEAS_CFG, MEAS_CTRL.STANDBY)
    -- 软件 I2C 不需要手动关闭（gc 自动回收），硬件 I2C 需释放
    if not g_is_soft and g_i2c_bus then i2c.close(g_i2c_bus) end
    g_ready = false; g_i2c_bus = nil; g_coeff = nil
    g_base_prs_raw = nil; g_base_tmp_raw = nil
    g_mode = "standby"
    log.info("exs_spl06", "传感器已关闭")
end

--[[
获取 exs_spl06 库的版本号

@api exs_spl06.version()
@param none
@return string
含义说明：扩展库版本号
数据类型：string
取值范围：固定格式 "主版本.次版本.修订号"
]]
function exs_spl06.version()
    return "1.0.0"
end

-- ==================== 常量导出 ====================

-- I2C 从机地址（由 SDO 引脚决定）
exs_spl06.I2C_ADDR_H = DEV_ADDR_1   -- 0x77，SDO 悬空或接高电平（默认）
exs_spl06.I2C_ADDR_L = DEV_ADDR_0   -- 0x76，SDO 接 GND

-- 过采样率常量（供 set_osr / setup 的 config 使用）
exs_spl06.OSR_1X   = 0
exs_spl06.OSR_2X   = 1
exs_spl06.OSR_4X   = 2
exs_spl06.OSR_8X   = 3
exs_spl06.OSR_16X  = 4
exs_spl06.OSR_32X  = 5
exs_spl06.OSR_64X  = 6
exs_spl06.OSR_128X = 7

log.debug("exs_spl06", "version -> " .. exs_spl06.version())

return exs_spl06
