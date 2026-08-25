--[[
@module  exs_bme680
@summary BME680 四合一环境传感器扩展库（温度/气压/湿度/气体）
@version 1.2
@date    2026.08.20
@author  江访
@usage
本文件为 BME680 四合一环境传感器（Bosch Sensortec 出品）的 LuatOS 扩展库。
通过 I2C 接口读取温度、大气压、湿度和气体电阻（VOC/IAQ），自动进行校准补偿。
BME680 在 BME280 基础上额外集成了 MOX 气体传感器，可用于空气质量检测。

本文件的对外接口有 11 个：
1、exs_bme680.setup(config)：初始化 BME680
2、exs_bme680.get_data()：读取温度、气压、湿度和气体电阻
3、exs_bme680.set_temp_oversampling(os)：设置温度过采样率
4、exs_bme680.set_press_oversampling(os)：设置气压过采样率
5、exs_bme680.set_hum_oversampling(os)：设置湿度过采样率
6、exs_bme680.set_filter(coeff)：设置 IIR 滤波器系数
7、exs_bme680.set_gas_heater(heater_temp, heater_time)：设置气体加热器参数
8、exs_bme680.set_sea_level_pressure(pressure)：设置海平面标准气压
9、exs_bme680.get_altitude(pressure)：计算海拔
10、exs_bme680.close()：关闭传感器
11、exs_bme680.version()：获取版本号

更多说明参考 docs 在线文档

=== 版本更新说明 ===
-- 版本号：202608200000
-- 1、更新时间：2026-08-20
-- 2、更新内容：
--   - 补充 MOX 气体传感器预热说明（首次上电需 20~30 分钟电阻才稳定）
--   - 补充空气质量判断方法（以基线 R0 为基准，电阻下降越多空气越差）
--   - 移除 get_data() 中的气体诊断临时日志，改为有意义的提示输出

-- 版本号：202608080000
-- 1、更新时间：2026-08-08
-- 2、更新内容：
--   - 支持软件 I2C 和硬件 I2C 两种模式
--   - 支持温度、气压、湿度、气体电阻四合一测量
--   - 支持 T/P/H 三路过采样率独立设置
--   - 支持 IIR 滤波器（系数 0~7）
--   - 支持气体加热器温度和时间配置
--   - 支持海拔高度计算（国际气压公式）
--   - 内置 I2C 总线卡死自动检测与恢复
]]

local exs_bme680 = {}

-- ==================== 寄存器地址 ====================

local REG_CHIP_ID           = 0xD0  -- 芯片 ID 寄存器（固定值 0x61）
local REG_SOFT_RESET        = 0xE0  -- 软复位寄存器（写入 0xB6）
local REG_STATUS            = 0x1D  -- 状态寄存器（new_data, gas_measuring）
local REG_CTRL_GAS1         = 0x71  -- 气体测量控制寄存器 1
local REG_CTRL_GAS0         = 0x70  -- 气体测量控制寄存器 0（bit3=1 禁用加热器，bit3=0 使能）
local REG_CTRL_HUM          = 0x72  -- 湿度控制寄存器
local REG_CTRL_MEAS         = 0x74  -- 测量控制寄存器（T/P 过采样 + 模式）
local REG_CONFIG            = 0x75  -- 配置寄存器（IIR 滤波）
local REG_RES_HEAT0         = 0x5A  -- 加热器电阻寄存器
local REG_GAS_WAIT0         = 0x64  -- 加热器等待时间寄存器

-- 数据寄存器（0x1D~0x2B，共 15 字节）
local REG_FIELD0            = 0x1D  -- 数据起始地址

-- 校准参数寄存器
local REG_CALIB_COEFF1      = 0x89  -- 校准参数第 1 段（0x89~0xA1，25 字节，含首字节保留）
local REG_CALIB_COEFF2      = 0xE1  -- 校准参数第 2 段（0xE1~0xF0，16 字节）
local REG_RES_HEAT_RANGE    = 0x02  -- 加热器电阻范围
local REG_RES_HEAT_VAL      = 0x00  -- 加热器电阻值
local REG_RANGE_SW_ERR      = 0x04  -- 量程切换误差

-- ==================== 常量 ====================

local CHIP_ID_BME680        = 0x61  -- BME680 芯片 ID
local DEV_ADDR_LOW          = 0x76  -- I2C 7 位地址（SDO=GND）
local DEV_ADDR_HIGH         = 0x77  -- I2C 7 位地址（SDO=VCC）

-- 过采样率常量
local OS_NONE   = 0
local OS_1X     = 1
local OS_2X     = 2
local OS_4X     = 3
local OS_8X     = 4
local OS_16X    = 5

-- 滤波器系数
local FILTER_COEFF = {0, 1, 3, 7, 15, 31, 63, 127}

-- 工作模式
local SLEEP_MODE    = 0x00
local FORCED_MODE   = 0x01

-- 气体传感器状态
local GAS_HEAT_STAB = 0x10  -- 加热器稳定标志
local GAS_VALID     = 0x20  -- 气体数据有效标志
local NEW_DATA      = 0x80  -- 新数据就绪标志

-- 软复位命令
local SOFT_RESET_CMD = 0xB6

-- 默认海平面气压
local DEFAULT_SEA_LEVEL = 1013.25

-- ==================== 内部状态 ====================

local g_i2c_bus         = 0
local g_is_soft         = false
local g_scl_pin         = nil
local g_sda_pin         = nil
local g_dev_addr        = 0x76
local g_i2c_speed       = i2c.SLOW  -- 保存原始 speed（总线恢复后恢复）
local g_ready           = false

-- 校准参数
local g_par_t1 = 0; local g_par_t2 = 0; local g_par_t3 = 0
local g_par_p1 = 0; local g_par_p2 = 0; local g_par_p3 = 0
local g_par_p4 = 0; local g_par_p5 = 0; local g_par_p6 = 0
local g_par_p7 = 0; local g_par_p8 = 0; local g_par_p9 = 0; local g_par_p10 = 0
local g_par_h1 = 0; local g_par_h2 = 0; local g_par_h3 = 0
local g_par_h4 = 0; local g_par_h5 = 0; local g_par_h6 = 0; local g_par_h7 = 0
local g_par_gh1 = 0; local g_par_gh2 = 0; local g_par_gh3 = 0
local g_res_heat_range = 0; local g_res_heat_val = 0; local g_range_sw_err = 0
local g_t_fine = 0

-- 传感器配置
local g_os_temp = OS_8X     -- 温度过采样率
local g_os_pres = OS_4X     -- 气压过采样率
local g_os_hum  = OS_2X     -- 湿度过采样率
local g_filter  = 3         -- IIR 滤波器系数（默认 FILTER_SIZE_3）
local g_heatr_temp = 320    -- 气体加热器温度（°C）
local g_heatr_dur  = 150    -- 气体加热器持续时间（ms）
local g_sea_level_pressure = DEFAULT_SEA_LEVEL

-- 气体量程查找表
local lookup_table1 = {
    2147483647, 2147483647, 2147483647, 2147483647,
    2147483647, 2126008810, 2147483647, 2130303777,
    2147483647, 2147483647, 2143188679, 2136746228,
    2147483647, 2126008810, 2147483647, 2147483647
}

local lookup_table2 = {
    4096000000, 2048000000, 1024000000, 512000000,
    255744255, 127110228, 64000000, 32258064,
    16016016, 8000000, 4000000, 2000000,
    1000000, 500000, 250000, 125000
}

-- ==================== I2C 总线恢复 ====================

local function i2c_bus_recovery()
    if not g_scl_pin or not g_sda_pin then return false end
    -- 先把引脚设为 GPIO 输出高电平
    gpio.setup(g_scl_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    sys.wait(1)  -- 等待引脚电平稳定，1ms

    -- 产生最多 9 个 SCL 时钟脉冲，每发一个检查 SDA 是否释放
    for i = 1, 9 do
        gpio.set(g_scl_pin, 0)
        sys.wait(1)  -- 等待 SCL 拉低稳定，1ms
        -- 在 SCL 低电平期间检查 SDA
        gpio.setup(g_sda_pin, gpio.INPUT, gpio.PULLUP)
        sys.wait(1)  -- 等待 SDA 电平稳定，1ms
        if gpio.get(g_sda_pin) == 1 then
            -- SDA 已释放，提前结束
            gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
            break
        end
        gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
        gpio.set(g_scl_pin, 1)
        sys.wait(1)  -- 等待 SCL 拉高稳定，1ms
    end

    -- 产生 STOP 条件：SDA 低→高，SCL 高
    gpio.set(g_sda_pin, 0)
    sys.wait(1)  -- 等待 SDA 拉低稳定，1ms
    gpio.set(g_scl_pin, 1)
    sys.wait(1)  -- 等待 SCL 拉高稳定，1ms
    gpio.set(g_sda_pin, 1)
    sys.wait(1)  -- 等待 SDA 拉高（STOP），1ms
    log.info("exs_bme680", "I2C总线恢复完成")
    return true
end

local function try_bus_recovery()
    if not g_scl_pin or not g_sda_pin then return false end
    gpio.setup(g_sda_pin, gpio.INPUT, gpio.PULLUP)
    gpio.setup(g_scl_pin, gpio.INPUT, gpio.PULLUP)
    sys.wait(1)  -- 等待引脚切输入后电平稳定，1ms
    local is_stall = (gpio.get(g_sda_pin) == 0 and gpio.get(g_scl_pin) == 1)
    gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    gpio.setup(g_scl_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    if not is_stall then return false end
    log.warn("exs_bme680", "检测到I2C总线卡死，尝试恢复")
    i2c_bus_recovery()
    if not g_is_soft then i2c.setup(g_i2c_bus, g_i2c_speed) end  -- 硬件 I2C 恢复后重新 setup 并恢复原始 speed
    return true
end

-- ==================== 底层 I2C 读写 ====================

-- 向指定寄存器写入一个字节
-- @return boolean
local function i2c_write(reg, val)
    local ok = i2c.send(g_i2c_bus, g_dev_addr, {reg, val})
    if not ok then
        if try_bus_recovery() then ok = i2c.send(g_i2c_bus, g_dev_addr, {reg, val}) end
    end
    return ok
end

-- 从指定寄存器连续读取 len 个字节
-- @return table or nil 包含每个字节的 table
local function i2c_read(reg, len)
    local ok = i2c.send(g_i2c_bus, g_dev_addr, {reg})
    if not ok then
        if try_bus_recovery() then ok = i2c.send(g_i2c_bus, g_dev_addr, {reg}) end
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

-- 读 16 位有符号（LSB first）
local function read_s16_le(reg)
    local v = read_u16_le(reg)
    if v and v >= 0x8000 then v = v - 0x10000 end
    return v
end

-- 读 8 位无符号
local function read_u8(reg)
    local buf = i2c_read(reg, 1)
    if not buf or #buf < 1 then return nil end
    return buf[1]
end

-- 读 8 位有符号
local function read_s8(reg)
    local v = read_u8(reg)
    if v and v >= 0x80 then v = v - 0x100 end
    return v
end

-- ==================== 芯片检测 ====================

local function chip_detect()
    for _, addr in ipairs({ DEV_ADDR_LOW, DEV_ADDR_HIGH }) do
        if i2c.send(g_i2c_bus, addr, { REG_CHIP_ID }) then
            local data = i2c.recv(g_i2c_bus, addr, 1)
            if data and #data >= 1 then
                local id = data:byte(1)
                if id == CHIP_ID_BME680 then
                    g_dev_addr = addr
                    log.info("exs_bme680", string.format("BME680 @ I2C 0x%02X, CHIP_ID=0x%02X", addr, id))
                    return true
                end
            end
        end
    end
    log.error("exs_bme680", "未检测到 BME680")
    return false
end

-- ==================== 校准数据读取 ====================

local function read_calibration()
    -- 读取第 1 段校准数据（0x89~0xA1，25 字节，Bosch 标准方法）
    -- 首字节 0x89 为保留/填充字节，实际数据从 0x8A 开始
    local coeff1 = i2c_read(REG_CALIB_COEFF1, 25)
    if not coeff1 or #coeff1 < 25 then
        log.error("exs_bme680", "第1段校准数据读取失败")
        return false
    end

    -- 读取第 2 段校准数据（0xE1~0xF0，16 字节）
    local coeff2 = i2c_read(REG_CALIB_COEFF2, 16)
    if not coeff2 or #coeff2 < 16 then
        log.error("exs_bme680", "第2段校准数据读取失败")
        return false
    end

    -- T1 校准数据位于校准参数第2段（coeff2），索引 9~10（1-based）
    -- 对应寄存器 0xE9~0xEA，属于 0xE1~0xF0 连续块
    -- T1 = (coeff2[10] << 8) | coeff2[9]
    local t1 = (coeff2[10] << 8) | coeff2[9]

    -- coeff1 索引（1-based，0x89 对应 coeff1[1]）：
    -- [1]=0x89保留 [2]=0x8A T2_LSB [3]=0x8B T2_MSB [4]=0x8C T3
    -- [5]=0x8D保留 [6]=0x8E P1_LSB [7]=0x8F P1_MSB
    -- [8]=0x90 P2_LSB [9]=0x91 P2_MSB [10]=0x92 P3
    -- [11]=0x93保留 [12]=0x94 P4_LSB [13]=0x95 P4_MSB
    -- [14]=0x96 P5_LSB [15]=0x97 P5_MSB [16]=0x98 P7 [17]=0x99 P6
    -- [18]=0x9A保留 [19]=0x9B保留
    -- [20]=0x9C P8_LSB [21]=0x9D P8_MSB
    -- [22]=0x9E P9_LSB [23]=0x9F P9_MSB
    -- [24]=0xA0 P10 [25]=0xA1 reserved（H2_MSB 位于 coeff2[1]=0xE1）
    -- coeff2 索引（1-based，0xE1 对应 coeff2[1]）：
    -- 对照 bme680_defs.h 0-based 组合数组索引：coeff_array[25..40]=0xE1..0xF0
    -- [1]=0xE1=array[25]=H2_MSB [2]=0xE2=array[26]=H2_LSB+H1_LSB [3]=0xE3=array[27]=H1_MSB
    -- [4]=0xE4=array[28]=H3 [5]=0xE5=array[29]=H4 [6]=0xE6=array[30]=H5
    -- [7]=0xE7=array[31]=H6 [8]=0xE8=array[32]=H7
    -- [9]=0xE9=array[33]=T1_LSB [10]=0xEA=array[34]=T1_MSB
    -- [11]=0xEB=array[35]=GH2_LSB [12]=0xEC=array[36]=GH2_MSB
    -- [13]=0xED=array[37]=GH1 [14]=0xEE=array[38]=GH3
    -- [15]=0xEF=array[39]=reserved [16]=0xF0=array[40]=reserved

    -- 温度校准参数
    local t2 = (coeff1[3] << 8) | coeff1[2]     -- s16 LE
    if t2 >= 0x8000 then t2 = t2 - 0x10000 end
    local t3 = coeff1[4]                          -- s8
    if t3 >= 0x80 then t3 = t3 - 0x100 end

    -- 气压校准参数
    local p1  = (coeff1[7] << 8) | coeff1[6]     -- u16 LE
    local p2  = (coeff1[9] << 8) | coeff1[8]     -- s16 LE
    if p2 >= 0x8000 then p2 = p2 - 0x10000 end
    local p3  = coeff1[10]                         -- s8
    if p3 >= 0x80 then p3 = p3 - 0x100 end
    local p4  = (coeff1[13] << 8) | coeff1[12]   -- s16 LE
    if p4 >= 0x8000 then p4 = p4 - 0x10000 end
    local p5  = (coeff1[15] << 8) | coeff1[14]   -- s16 LE
    if p5 >= 0x8000 then p5 = p5 - 0x10000 end
    local p6  = coeff1[17]                         -- s8
    if p6 >= 0x80 then p6 = p6 - 0x100 end
    local p7  = coeff1[16]                         -- s8
    if p7 >= 0x80 then p7 = p7 - 0x100 end
    local p8  = (coeff1[21] << 8) | coeff1[20]   -- s16 LE
    if p8 >= 0x8000 then p8 = p8 - 0x10000 end
    local p9  = (coeff1[23] << 8) | coeff1[22]   -- s16 LE
    if p9 >= 0x8000 then p9 = p9 - 0x10000 end
    local p10 = coeff1[24]                         -- u8

    -- 湿度校准参数（对照 bme680_defs.h 0-based 组合数组索引）
    -- H1 = (array[27]<<4) | (array[26] & 0x0F) = (coeff2[3]<<4) | (coeff2[2] & 0x0F)
    local h1 = (coeff2[3] << 4) | (coeff2[2] & 0x0F)
    -- H2 = (array[25]<<4) | (array[26] >> 4)   = (coeff2[1]<<4) | (coeff2[2] >> 4)
    local h2 = (coeff2[1] << 4) | (coeff2[2] >> 4)
    -- H3~H7: array[28..32] = coeff2[4..8]
    -- Bosch 定义：H3/H4/H5 为 int8_t（有符号），H6 为 uint8_t（无符号），H7 为 int8_t（有符号）
    local h3 = coeff2[4]; if h3 >= 0x80 then h3 = h3 - 0x100 end  -- s8
    local h4 = coeff2[5]; if h4 >= 0x80 then h4 = h4 - 0x100 end  -- s8
    local h5 = coeff2[6]; if h5 >= 0x80 then h5 = h5 - 0x100 end  -- s8
    local h6 = coeff2[7]     -- u8，无需符号扩展
    local h7 = coeff2[8]; if h7 >= 0x80 then h7 = h7 - 0x100 end  -- s8

    -- 气体校准参数（对照 bme680_defs.h 0-based 组合数组索引）
    -- GH2_LSB=array[35]=coeff2[11], GH2_MSB=array[36]=coeff2[12]
    -- GH1=array[37]=coeff2[13], GH3=array[38]=coeff2[14]
    local gh1 = coeff2[13]                         -- s8
    if gh1 >= 0x80 then gh1 = gh1 - 0x100 end
    local gh2 = (coeff2[12] << 8) | coeff2[11]     -- s16 LE
    if gh2 >= 0x8000 then gh2 = gh2 - 0x10000 end
    local gh3 = coeff2[14]                         -- s8
    if gh3 >= 0x80 then gh3 = gh3 - 0x100 end

    -- 其他校准参数（来自独立寄存器）
    local res_heat_range = read_u8(REG_RES_HEAT_RANGE) or 0
    res_heat_range = (res_heat_range & 0x30) >> 4
    local res_heat_val = read_s8(REG_RES_HEAT_VAL) or 0
    local range_sw_err = read_u8(REG_RANGE_SW_ERR) or 0
    range_sw_err = (range_sw_err & 0xF0) >> 4

    -- 检查校准数据有效性
    log.info("exs_bme680", string.format("raw_T1=%d raw_P1=%d raw_T2=%d raw_P2=%d",
        t1, p1, t2, p2))
    if t1 == 0 or p1 == 0 then
        log.error("exs_bme680", "校准数据无效")
        log.error("exs_bme680", string.format("coeff1字节: %d %d %d %d %d %d %d %d",
            coeff1[1] or 0, coeff1[2] or 0, coeff1[3] or 0, coeff1[4] or 0,
            coeff1[5] or 0, coeff1[6] or 0, coeff1[7] or 0, coeff1[8] or 0))
        return false
    end

    g_par_t1 = t1; g_par_t2 = t2; g_par_t3 = t3
    g_par_p1 = p1; g_par_p2 = p2; g_par_p3 = p3
    g_par_p4 = p4; g_par_p5 = p5; g_par_p6 = p6
    g_par_p7 = p7; g_par_p8 = p8; g_par_p9 = p9; g_par_p10 = p10
    g_par_h1 = h1; g_par_h2 = h2; g_par_h3 = h3
    g_par_h4 = h4; g_par_h5 = h5; g_par_h6 = h6; g_par_h7 = h7
    g_par_gh1 = gh1; g_par_gh2 = gh2; g_par_gh3 = gh3
    g_res_heat_range = res_heat_range; g_res_heat_val = res_heat_val
    g_range_sw_err = range_sw_err

    log.info("exs_bme680", string.format("校准数据: T1=%d T2=%d T3=%d P1=%d P2=%d H1=%d H2=%d GH1=%d GH2=%d GH3=%d",
        g_par_t1, g_par_t2, g_par_t3, g_par_p1, g_par_p2, g_par_h1, g_par_h2, g_par_gh1, g_par_gh2, g_par_gh3))
    return true
end

-- ==================== 补偿算法 ====================
-- 基于 Bosch BME680 数据手册 / bme680.c 公式

-- 温度补偿
-- @param temp_adc number 原始温度 ADC 值
-- @return number 温度值，单位 0.01°C
local function calc_temperature(temp_adc)
    local var1 = math.floor((temp_adc / 8) - (g_par_t1 * 2))
    local var2 = math.floor((var1 * g_par_t2) / 2048)
    local var3 = math.floor(var1 / 2)
    var3 = math.floor((var3 * var3) / 4096)
    var3 = math.floor((var3 * (g_par_t3 * 16)) / 16384)
    g_t_fine = var2 + var3
    return math.floor((g_t_fine * 5 + 128) / 256)  -- 返回 0.01°C
end

-- 气压补偿
-- @param pres_adc number 原始气压 ADC 值
-- @return number 气压值，单位 Pa
local function calc_pressure(pres_adc)
    local var1 = math.floor(g_t_fine / 2) - 64000
    local orig_var1 = var1                -- 保存 var1 原始值供后续使用
    local var1_div_4 = math.floor(var1 / 4)
    local var1_div_4_sq = var1_div_4 * var1_div_4

    local var2 = math.floor(math.floor(var1_div_4_sq) / 2048) * g_par_p6
    var2 = var2 + var1 * g_par_p5 * 2
    var2 = math.floor(var2 / 4) + g_par_p4 * 65536

    var1 = math.floor(math.floor(var1_div_4_sq) / 8192) * (g_par_p3 * 32)
    var1 = math.floor(var1 / 8) + math.floor((g_par_p2 * orig_var1) / 2)
    var1 = math.floor(var1 / 262144)
    var1 = math.floor((32768 + var1) * g_par_p1 / 32768)
    if var1 == 0 then return nil end

    local calc_pres = (1048576 - pres_adc - math.floor(var2 / 4096)) * 3125

    if calc_pres < 0x80000000 then
        calc_pres = math.floor((calc_pres * 2) / var1)
    else
        calc_pres = math.floor(math.floor(calc_pres / var1) * 2)
    end

    var1 = math.floor(g_par_p9 * math.floor(math.floor(math.floor(calc_pres / 8) * math.floor(calc_pres / 8)) / 8192) / 4096)
    var2 = math.floor(math.floor(calc_pres / 4) * g_par_p8 / 8192)
    local cp256 = math.floor(calc_pres / 256)
    local var3 = math.floor(cp256 * cp256 * cp256 * g_par_p10 / 131072)
    calc_pres = math.floor(calc_pres + math.floor((var1 + var2 + var3 + g_par_p7 * 128) / 16))

    return calc_pres  -- 返回 Pa
end

-- 湿度补偿
-- @param hum_adc number 原始湿度 ADC 值
-- @return number 湿度值，单位 0.001%RH
local function calc_humidity(hum_adc)
    local temp_scaled = math.floor((g_t_fine * 5 + 128) / 256)

    -- var1 = hum_adc - (h1 * 16) - ((temp_scaled * h3 / 100) / 2)
    local var1 = hum_adc - g_par_h1 * 16 - math.floor(math.floor(temp_scaled * g_par_h3 / 100) / 2)

    -- var2 = h2 * ((temp_scaled * h4 / 100) + ((temp_scaled * ((temp_scaled * h5 / 100)) / 64) / 100) + 16384) / 1024
    local t_h4 = math.floor(temp_scaled * g_par_h4 / 100)
    local t_h5 = math.floor(math.floor(temp_scaled * math.floor(temp_scaled * g_par_h5 / 100) / 64) / 100)
    local var2 = math.floor(g_par_h2 * (t_h4 + t_h5 + 16384) / 1024)

    local var3 = var1 * var2
    local var4 = g_par_h6 * 128
    var4 = math.floor(math.floor(var4 + math.floor(temp_scaled * g_par_h7 / 100)) / 16)

    local var5 = math.floor(math.floor(math.floor(var3 / 16384) * math.floor(var3 / 16384)) / 1024)
    local var6 = math.floor(math.floor(var4 * var5) / 2)

    local calc_hum = math.floor(math.floor((var3 + var6) / 1024) * 1000 / 4096)

    if calc_hum > 100000 then calc_hum = 100000 end
    if calc_hum < 0 then calc_hum = 0 end

    return calc_hum  -- 返回 0.001%RH
end

-- 气体电阻补偿
-- @param gas_res_adc number 原始气体电阻 ADC
-- @param gas_range number 量程范围
-- @return number 气体电阻，单位 Ω
local function calc_gas_resistance(gas_res_adc, gas_range)
    -- 注意：真机为 32 位 Lua（LUA_32BITS，int32+float32），
    -- 查找表与 var1 的乘积高达 10^12~10^14，int32 整数乘法会溢出导致结果为 0。
    -- 因此大数中间量用浮点计算（结果与 Bosch 官方 int64 算法一致，已验证）
    local var1 = ((1340 + (5 * g_range_sw_err)) * (lookup_table1[gas_range + 1] * 1.0)) / 65536
    local var2 = (gas_res_adc * 32768) - 16777216 + var1
    local var3 = (lookup_table2[gas_range + 1] * var1) / 512
    return math.floor((var3 + (var2 / 2)) / var2)
end

-- 加热器电阻计算
-- @param temp number 目标温度（°C）
-- @return number 加热器电阻寄存器值
local function calc_heater_res(temp)
    if temp < 200 then temp = 200 end
    if temp > 400 then temp = 400 end
    -- 对齐 Bosch bme680.c calc_heater_res():
    -- var1 = amb_temp * gh3 / 1000 * 256        (环境温度项, amb_temp 用 19°C)
    -- var2 = (gh1+784) * (((gh2+154009)*temp*5/100+3276800)/10)  (目标温度项)
    -- var3 = var1 + var2/2
    local var1 = math.floor((19 * g_par_gh3) / 1000) * 256
    local var2 = math.floor((g_par_gh1 + 784) *
        ((((g_par_gh2 + 154009) * temp * 5) / 100 + 3276800) / 10))
    local var3 = math.floor(var1 + var2 / 2)
    local var4 = math.floor(var3 / (g_res_heat_range + 4))
    local var5 = (131 * g_res_heat_val) + 65536
    local heatr_res_x100 = math.floor(((var4 / var5) - 250) * 34)
    return math.floor((heatr_res_x100 + 50) / 100)
end

-- 加热器持续时间计算
-- @param dur number 目标持续时间（ms）
-- @return number 加热器持续时间寄存器值
local function calc_heater_dur(dur)
    if dur >= 0xFC0 then
        return 0xFF  -- 最大持续时间
    end
    local factor = 0
    while dur > 0x3F do
        dur = math.floor(dur / 4)
        factor = factor + 1
    end
    return dur + (factor * 64)
end

-- ==================== 传感器配置 ====================

-- 设置传感器工作模式
-- @param mode number 工作模式（SLEEP_MODE 或 FORCED_MODE）
local function set_sensor_mode(mode)
    -- 循环确认进入睡眠模式（对齐 Bosch 驱动的 do-while 逻辑）
    local pow_mode = SLEEP_MODE
    while pow_mode ~= SLEEP_MODE do
        local reg = read_u8(REG_CTRL_MEAS)
        if not reg then return false end
        pow_mode = reg & 0x03
        if pow_mode ~= SLEEP_MODE then
            i2c_write(REG_CTRL_MEAS, (reg & 0xFC) | SLEEP_MODE)
            sys.wait(10)  -- 等待芯片进入睡眠模式，10ms
        end
    end
    -- 切换到目标模式
    if mode ~= SLEEP_MODE then
        local reg = read_u8(REG_CTRL_MEAS)
        if not reg then return false end
        i2c_write(REG_CTRL_MEAS, (reg & 0xFC) | mode)
    end
    return true
end

-- 应用传感器设置（过采样率、滤波器、气体加热器）
local function apply_sensor_settings()
    -- 设置 T/P 过采样率 + 模式
    local ctrl_meas = (g_os_temp << 5) | (g_os_pres << 2) | SLEEP_MODE
    i2c_write(REG_CTRL_MEAS, ctrl_meas)

    -- 设置湿度过采样率
    i2c_write(REG_CTRL_HUM, g_os_hum & 0x07)

    -- 设置 IIR 滤波器
    i2c_write(REG_CONFIG, (g_filter & 0x07) << 2)

    -- 设置气体加热器
    -- 加热器控制：开启加热器（bit3=0 使能，BME680_ENABLE_HEATER）
    i2c_write(REG_CTRL_GAS0, 0x00)  -- 开启加热器（0x08=禁用，0x00=使能）

    -- 设置加热器电阻值
    local res_heat = calc_heater_res(g_heatr_temp)
    i2c_write(REG_RES_HEAT0, res_heat)

    -- 设置加热器等待时间
    local dur_val = calc_heater_dur(g_heatr_dur)
    i2c_write(REG_GAS_WAIT0, dur_val)

    -- 气体测量控制：启用气体测量 + NB conversion = 0
    i2c_write(REG_CTRL_GAS1, 0x10)  -- run_gas = 1, nb_conv = 0

    return true
end

-- 获取测量持续时间
-- @return number 测量持续时间（ms）
local function get_profile_dur()
    local tph_dur = ((g_os_temp + g_os_pres + g_os_hum) * 1963) + (477 * 4) + (477 * 5) + 500
    tph_dur = math.floor(tph_dur / 1000) + 1  -- 转换为 ms，加 1ms 唤醒时间
    return g_heatr_dur + tph_dur
end

-- ==================== 外部 API ====================

--[[
初始化 BME680 四合一环境传感器

配置 I2C 引脚，读取芯片校准数据，设置测量参数和气体加热器参数。

@api exs_bme680.setup(config)

@table config 配置参数
  scl - SCL 时钟引脚 GPIO 编号（与 sda 一起可选）
  sda - SDA 数据引脚 GPIO 编号（与 scl 一起可选）
  i2c_id - 硬件 I2C 总线 ID（可选，默认 0）
  os_temp - 温度过采样率 0~5（可选，默认 4=8X）
  os_pres - 气压过采样率 0~5（可选，默认 3=4X）
  os_hum - 湿度过采样率 0~5（可选，默认 2=2X）
  filter - IIR 滤波器系数 0~7（可选，默认 3）
  heater_temp - 气体加热器温度 200~400°C（可选，默认 320）
  heater_time - 气体加热器持续时间 1~4032ms（可选，默认 150）

@return boolean

@usage
-- 软件 I2C 模式（默认配置）
local result = exs_bme680.setup({scl = 27, sda = 26})
-- 自定义气体加热器参数
local result = exs_bme680.setup({scl = 27, sda = 26, heater_temp = 300, heater_time = 100})
]]
function exs_bme680.setup(config)
    if type(config) ~= "table" then
        log.error("exs_bme680.setup 参数错误，需传入 table 配置表")
        return false
    end

    -- 记录硬件 I2C 速率（总线恢复后需恢复原始 speed）
    g_i2c_speed = i2c.SLOW

    if config.scl and config.sda then
        g_scl_pin = config.scl; g_sda_pin = config.sda
        if config.i2c_id then
            i2c_bus_recovery()
            if i2c.setup(config.i2c_id, i2c.SLOW) == 0 then log.error("exs_bme680.setup 硬件 I2C 失败"); return false end
            g_i2c_bus = config.i2c_id; g_is_soft = false
        else
            i2c_bus_recovery()
            g_i2c_bus = i2c.createSoft(config.scl, config.sda, 5)
            if not g_i2c_bus then log.error("exs_bme680.setup 软件 I2C 失败"); return false end
            g_is_soft = true
        end
    else
        local i2c_id = config.i2c_id or 0
        if i2c.setup(i2c_id, i2c.SLOW) == 0 then log.error("exs_bme680.setup 硬件 I2C 失败"); return false end
        g_i2c_bus = i2c_id; g_is_soft = false; g_scl_pin = nil; g_sda_pin = nil
    end

    -- 软复位（BME680 需要 20ms 加载 NVM 校准数据到寄存器）
    i2c_write(REG_SOFT_RESET, SOFT_RESET_CMD)
    sys.wait(50)  -- 等待软复位完成、NVM 校准数据加载，50ms

    -- 检测芯片
    if not chip_detect() then return false end

    -- 读取校准数据
    if not read_calibration() then return false end

    -- 设置配置参数（超范围自动裁剪并告警）
    if config.os_temp then
        local v = math.max(0, math.min(5, config.os_temp))
        if v ~= config.os_temp then log.warn("exs_bme680", "os_temp 超范围(" .. config.os_temp .. ")，已裁剪为 " .. v) end
        g_os_temp = v
    end
    if config.os_pres then
        local v = math.max(0, math.min(5, config.os_pres))
        if v ~= config.os_pres then log.warn("exs_bme680", "os_pres 超范围(" .. config.os_pres .. ")，已裁剪为 " .. v) end
        g_os_pres = v
    end
    if config.os_hum then
        local v = math.max(0, math.min(5, config.os_hum))
        if v ~= config.os_hum then log.warn("exs_bme680", "os_hum 超范围(" .. config.os_hum .. ")，已裁剪为 " .. v) end
        g_os_hum = v
    end
    if config.filter then
        local v = math.max(0, math.min(7, config.filter))
        if v ~= config.filter then log.warn("exs_bme680", "filter 超范围(" .. config.filter .. ")，已裁剪为 " .. v) end
        g_filter = v
    end
    if config.heater_temp then
        local v = math.max(200, math.min(400, config.heater_temp))
        if v ~= config.heater_temp then log.warn("exs_bme680", "heater_temp 超范围(" .. config.heater_temp .. "°C)，已裁剪为 " .. v .. "°C") end
        g_heatr_temp = v
    end
    if config.heater_time then
        local v = math.max(1, math.min(4032, config.heater_time))
        if v ~= config.heater_time then log.warn("exs_bme680", "heater_time 超范围(" .. config.heater_time .. "ms)，已裁剪为 " .. v .. "ms") end
        g_heatr_dur = v
    end

    -- 应用传感器设置
    apply_sensor_settings()

    g_ready = true
    log.info("exs_bme680", string.format("BME680 初始化完成, os_temp=%d os_pres=%d os_hum=%d filter=%d heater_temp=%d°C heater_dur=%dms",
        g_os_temp, g_os_pres, g_os_hum, g_filter, g_heatr_temp, g_heatr_dur))
    log.info("exs_bme680", string.format("加热器校准: res_heat_range=%d res_heat_val=%d range_sw_err=%d heatr_res=0x%02X",
        g_res_heat_range, g_res_heat_val, g_range_sw_err, calc_heater_res(g_heatr_temp)))
    -- 气体预热提示：MOX 加热器上电后需一段时间稳定，期间气体电阻读值无参考意义
    log.info("exs_bme680", "气体预热提示: 新板首次上电 MOX 气体传感器需预热 20~30 分钟，")
    log.info("exs_bme680", "电阻会从低值缓慢爬升直至稳定，稳定前 gas_resistance 为 0 或数值不可信")
    return true
end

--[[
读取 BME680 温度、气压、湿度和气体数据

自动进行校准补偿，返回四项环境数据。
气体传感器需要加热器稳定后才返回有效值，否则 gas_resistance 为 0。

注意事项：必须在 sys.taskInit() 创建的协程中调用（内部使用 sys.wait() 阻塞等待测量完成，在 task 外调用会报错）

@api exs_bme680.get_data()
@return table or nil
  data.temperature     - 温度，单位 °C，如 25.12
  data.pressure        - 气压，单位 hPa，如 1013.25
  data.humidity        - 相对湿度，单位 %RH，如 46.33
  data.gas_resistance  - 气体电阻，单位 Ω，如 150000

@usage
local data = exs_bme680.get_data()
if data then
    log.info("exs_bme680", string.format("温度=%.2f°C 气压=%.2fhPa 湿度=%.1f%%RH 气体=%dΩ",
        data.temperature, data.pressure, data.humidity, data.gas_resistance))
end
]]
function exs_bme680.get_data()
    if not g_ready then log.error("exs_bme680.get_data 请先 setup()"); return nil end

    -- 进入强制模式，触发测量
    set_sensor_mode(FORCED_MODE)

    -- 等待测量完成
    local meas_dur = get_profile_dur()
    sys.wait(meas_dur)  -- 阻塞等待测量完成，约 meas_dur ms

    -- 读取传感器数据（15 字节）
    local buf = i2c_read(REG_FIELD0, 15)
    if not buf or #buf < 15 then
        log.error("exs_bme680", "传感器数据读取失败")
        return nil
    end

    -- 解析原始数据
    local status = buf[1]

    -- 检查新数据就绪（Bosch 驱动最多重试 10 次，每次 10ms）
    if (status & NEW_DATA) == 0 then
        local retry = 0
        while retry < 10 do
            sys.wait(10)  -- 数据未就绪，等待重试间隔，10ms
            buf = i2c_read(REG_FIELD0, 15)
            if buf and #buf >= 15 then
                status = buf[1]
                if (status & NEW_DATA) ~= 0 then
                    break
                end
            end
            retry = retry + 1
        end
        if (status & NEW_DATA) == 0 then
            log.warn("exs_bme680", string.format("传感器数据未就绪（重试%d次）", retry))
            return nil
        end
    end

    -- 原始 ADC 值
    -- 寄存器布局（15 字节，0x1D~0x2B，buf 为 1-based）：
    -- buf[1]=0x1D status, buf[2]=0x1E meas_index
    -- buf[3..5]=0x1F..0x21 pres_adc(20bit)
    -- buf[6..8]=0x22..0x24 temp_adc(20bit)
    -- buf[9..10]=0x25..0x26 hum_adc(16bit)
    -- buf[13]=0x29 reserved, buf[14]=0x2A gas_r_msb(8bit), buf[15]=0x2B gas_r_lsb(2bit)+gas_range(4bit)
    local adc_pres = (buf[3] << 12) | (buf[4] << 4) | (buf[5] >> 4)
    local adc_temp = (buf[6] << 12) | (buf[7] << 4) | (buf[8] >> 4)
    local adc_hum  = (buf[9] << 8) | buf[10]
    local adc_gas  = (buf[14] << 2) | ((buf[15] >> 6) & 0x03)  -- 10-bit: MSB(8bit)+LSB(2bit)
    local gas_range = buf[15] & 0x0F

    -- 计算补偿值
    local temperature = calc_temperature(adc_temp) / 100.0  -- 0.01°C -> °C
    local pressure = calc_pressure(adc_pres) / 100.0       -- Pa -> hPa
    local humidity = calc_humidity(adc_hum) / 1000.0       -- 0.001%RH -> %RH

    -- 气体电阻：仅在加热器稳定时有效
    -- 预热说明：MOX 加热器上电后需 20~30 分钟稳定（电阻从低值爬升到基线），
    -- 稳定前 gas_resistance 返回 0（加热器未就绪），读值无参考意义；
    -- 稳定后以干净空气基线 R0 为基准，电阻下降越多说明 VOC 浓度越高、空气越差
    local gas_valid_bit = buf[15] & GAS_VALID
    local heat_stab_bit = buf[15] & GAS_HEAT_STAB
    local gas_status = gas_valid_bit | heat_stab_bit
    local gas_resistance = 0
    if gas_status == (GAS_VALID | GAS_HEAT_STAB) then
        gas_resistance = calc_gas_resistance(adc_gas, gas_range)
    end

    return {
        temperature = temperature,
        pressure = pressure,
        humidity = humidity,
        gas_resistance = gas_resistance
    }
end

--[[
设置温度过采样率

过采样率越高，精度越高但转换时间越长。
设置为 0 则关闭温度测量。

@api exs_bme680.set_temp_oversampling(os)
@number os 过采样率 0~5
  0 = 关闭
  1 = 1X
  2 = 2X
  3 = 4X
  4 = 8X
  5 = 16X
@return nil
]]
function exs_bme680.set_temp_oversampling(os)
    if not g_ready then log.error("exs_bme680.set_temp_oversampling 请先 setup()"); return end
    os = os or 4
    if os < 0 or os > 5 then
        local v = math.max(0, math.min(5, os))
        log.warn("exs_bme680", "温度过采样率超范围(" .. os .. ")，已裁剪为 " .. v)
        os = v
    end
    g_os_temp = os
    apply_sensor_settings()
    log.info("exs_bme680", string.format("温度过采样率设为 %d", g_os_temp))
end

--[[
设置气压过采样率

过采样率越高，精度越高但转换时间越长。
设置为 0 则关闭气压测量。

@api exs_bme680.set_press_oversampling(os)
@number os 过采样率 0~5
@return nil
]]
function exs_bme680.set_press_oversampling(os)
    if not g_ready then log.error("exs_bme680.set_press_oversampling 请先 setup()"); return end
    os = os or 3
    if os < 0 or os > 5 then
        local v = math.max(0, math.min(5, os))
        log.warn("exs_bme680", "气压过采样率超范围(" .. os .. ")，已裁剪为 " .. v)
        os = v
    end
    g_os_pres = os
    apply_sensor_settings()
    log.info("exs_bme680", string.format("气压过采样率设为 %d", g_os_pres))
end

--[[
设置湿度过采样率

过采样率越高，精度越高但转换时间越长。
设置为 0 则关闭湿度测量。

@api exs_bme680.set_hum_oversampling(os)
@number os 过采样率 0~5
@return nil
]]
function exs_bme680.set_hum_oversampling(os)
    if not g_ready then log.error("exs_bme680.set_hum_oversampling 请先 setup()"); return end
    os = os or 2
    if os < 0 or os > 5 then
        local v = math.max(0, math.min(5, os))
        log.warn("exs_bme680", "湿度过采样率超范围(" .. os .. ")，已裁剪为 " .. v)
        os = v
    end
    g_os_hum = os
    apply_sensor_settings()
    log.info("exs_bme680", string.format("湿度过采样率设为 %d", g_os_hum))
end

--[[
设置 IIR 滤波器系数

系数越大，数据越平滑，但对环境变化的响应越慢。

@api exs_bme680.set_filter(coeff)
@number coeff 滤波器系数 0~7
  0 = 关闭
  1 = 2 次平均
  2 = 4 次平均
  3 = 8 次平均
  4 = 16 次平均
  5 = 32 次平均
  6 = 64 次平均
  7 = 128 次平均
@return nil
]]
function exs_bme680.set_filter(coeff)
    if not g_ready then log.error("exs_bme680.set_filter 请先 setup()"); return end
    coeff = coeff or 3
    if coeff < 0 or coeff > 7 then
        local v = math.max(0, math.min(7, coeff))
        log.warn("exs_bme680", "滤波器系数超范围(" .. coeff .. ")，已裁剪为 " .. v)
        coeff = v
    end
    g_filter = coeff
    apply_sensor_settings()
    log.info("exs_bme680", string.format("IIR 滤波器系数设为 %d (%d次平均)", g_filter, FILTER_COEFF[g_filter + 1]))
end

--[[
设置气体加热器参数

气体传感器（MOX）需要加热到指定温度才能正常工作。
不同的加热温度和时间组合适合不同的 VOC 检测场景。

@api exs_bme680.set_gas_heater(heater_temp, heater_time)
@number heater_temp 加热器温度 200~400°C（默认 320）
@number heater_time 加热器持续时间 1~4032ms（默认 150）
@return nil
]]
function exs_bme680.set_gas_heater(heater_temp, heater_time)
    if not g_ready then log.error("exs_bme680.set_gas_heater 请先 setup()"); return end
    if heater_temp then
        if heater_temp < 200 or heater_temp > 400 then
            local v = math.max(200, math.min(400, heater_temp))
            log.warn("exs_bme680", "加热器温度超范围(" .. heater_temp .. "°C)，已裁剪为 " .. v .. "°C")
            heater_temp = v
        end
        g_heatr_temp = heater_temp
    end
    if heater_time then
        if heater_time < 1 or heater_time > 4032 then
            local v = math.max(1, math.min(4032, heater_time))
            log.warn("exs_bme680", "加热器持续时间超范围(" .. heater_time .. "ms)，已裁剪为 " .. v .. "ms")
            heater_time = v
        end
        g_heatr_dur = heater_time
    end
    apply_sensor_settings()
    log.info("exs_bme680", string.format("气体加热器设为 %d°C, %dms", g_heatr_temp, g_heatr_dur))
end

--[[
设置海平面标准气压

用于校准海拔计算精度。

@api exs_bme680.set_sea_level_pressure(pressure)
@number pressure 海平面标准气压，单位 hPa，如 1013.25
@return nil
]]
function exs_bme680.set_sea_level_pressure(pressure)
    if not pressure then return end
    g_sea_level_pressure = pressure
    log.info("exs_bme680", string.format("海平面气压设为 %.2fhPa", g_sea_level_pressure))
end

--[[
计算海拔高度

使用已设置的海平面标准气压（set_sea_level_pressure）计算海拔。

@api exs_bme680.get_altitude(pressure)
@number pressure 当前气压值，单位 hPa
@return number 海拔高度，单位米
@usage
local data = exs_bme680.get_data()
if data then
    local alt = exs_bme680.get_altitude(data.pressure)
    log.info("exs_bme680", string.format("海拔=%.1f 米", alt))
end
]]
function exs_bme680.get_altitude(pressure)
    if not pressure then return nil end
    local ratio = pressure / g_sea_level_pressure
    return 44330 * (1 - ratio ^ 0.190294957)
end

--[[
关闭 BME680 传感器

将传感器切换到睡眠模式，重置内部状态。
close 后需要重新调用 setup() 才能再次使用。

@api exs_bme680.close()
@return nil
]]
function exs_bme680.close()
    if not g_ready then return end
    set_sensor_mode(SLEEP_MODE)
    -- 软件 I2C 不需要手动关闭（gc 自动回收），硬件 I2C 需释放
    if not g_is_soft then i2c.close(g_i2c_bus) end
    g_ready = false; g_i2c_bus = 0; g_is_soft = false
    g_scl_pin = nil; g_sda_pin = nil
    log.info("exs_bme680", "传感器已关闭")
end

--[[
获取 exs_bme680 库的版本号

@api exs_bme680.version()
@return string
]]
function exs_bme680.version()
    return "202608080000"
end

log.debug("exs_bme680", "version -> " .. exs_bme680.version())
return exs_bme680