--[[
@module  exs_sc7a20h
@summary SC7A20H 三轴加速度传感器扩展库
@version 1.0
@date    2026.07.17
@author  江访
@usage
本文件为 SC7A20H 三轴加速度传感器（士兰微电子出品）的 LuatOS 扩展库。
通过 I2C 接口读取加速度、设备朝向，支持中断和轮询两种方式。

本文件的对外接口有 11 个：
1、exs_sc7a20h.setup(model, config)：初始化 SC7A20H
2、exs_sc7a20h.get_data()：读取三轴加速度数据
3、exs_sc7a20h.set_range(range)：切换量程
4、exs_sc7a20h.set_odr(hz)：切换输出数据速率
5、exs_sc7a20h.set_powermode(mode)：切换功耗模式
6、exs_sc7a20h.get_int_flag()：查询中断触发标志
7、exs_sc7a20h.get_int_src()：读取中断触发源
8、exs_sc7a20h.get_orientation()：获取设备当前朝向（方向检测）
9、exs_sc7a20h.sleep()：进入 power-down 待机模式
10、exs_sc7a20h.wakeup()：从待机模式唤醒
11、exs_sc7a20h.close()：关闭传感器

更多说明参考 docs 在线文档
]]

local exs_sc7a20h                        = {}

-- ==================== 寄存器地址 ====================

local REG_WHO_AM_I                        = 0x0F      -- 器件 ID 寄存器（固定值 0x11）
local REG_CTRL1                           = 0x20      -- ODR + LPen + X/Y/Z 使能
local REG_CTRL2                           = 0x21      -- 高通滤波配置
local REG_CTRL3                           = 0x22      -- INT1 中断路由
local REG_CTRL4                           = 0x23      -- BDU + 量程 + HR/自测
local REG_CTRL5                           = 0x24      -- 6D/4D 选择 + 中断锁存 + FIFO
local REG_CTRL6                           = 0x25      -- INT2 中断路由
local REG_STATUS                          = 0x27      -- 数据状态（ZYXDA 等）
local REG_OUT_X_L                         = 0x28      -- X 轴加速度低字节
local REG_OUT_X_H                         = 0x29      -- X 轴加速度高字节
local REG_OUT_Y_L                         = 0x2A      -- Y 轴加速度低字节
local REG_OUT_Y_H                         = 0x2B      -- Y 轴加速度高字节
local REG_OUT_Z_L                         = 0x2C      -- Z 轴加速度低字节
local REG_OUT_Z_H                         = 0x2D      -- Z 轴加速度高字节
local REG_FIFO_CTRL                       = 0x2E      -- FIFO 控制
local REG_FIFO_SRC                        = 0x2F      -- FIFO 状态
local REG_INT1_CFG                        = 0x30      -- INT1 中断事件配置
local REG_INT1_SRC                        = 0x31      -- INT1 中断源（读后自动清标志）
local REG_INT1_THS                        = 0x32      -- INT1 阈值
local REG_INT1_DURATION                   = 0x33      -- INT1 持续时间
local REG_INT2_CFG                        = 0x34      -- INT2 中断事件配置
local REG_INT2_SRC                        = 0x35      -- INT2 中断源
local REG_INT2_THS                        = 0x36      -- INT2 阈值
local REG_INT2_DURATION                   = 0x37      -- INT2 持续时间
local REG_CLICK_CFG                       = 0x38      -- 敲击检测配置
local REG_CLICK_SRC                       = 0x39      -- 敲击中断源
local REG_CLICK_THS                       = 0x3A      -- 敲击阈值
local REG_TIME_LIMIT                      = 0x3B      -- 敲击时间限制
local REG_TIME_LATENCY                    = 0x3C      -- 敲击间隔时间
local REG_TIME_WINDOW                     = 0x3D      -- 敲击时间窗口

-- ==================== 寄存器位常量 ====================

-- CTRL_REG1 (0x20)
local CTRL1_LPen_BIT                      = 0x08      -- 1=低功耗模式, 0=正常或高精度
local CTRL1_AXES_EN                       = 0x07      -- X/Y/Z 轴使能

-- CTRL_REG2 (0x21)
local CTRL2_HPIS1_BIT                     = 0x01      -- 高通滤波使能 - AOI1（活动/自由落体检测建议启用）
local CTRL2_HPIS2_BIT                     = 0x02      -- 高通滤波使能 - AOI2

-- ODR 值 (CTRL_REG1[7:4])
local ODR_1_56HZ                          = 0x10      -- 1.56 Hz
local ODR_12_5HZ                          = 0x20      -- 12.5 Hz
local ODR_25HZ                            = 0x30      -- 25 Hz
local ODR_50HZ                            = 0x40      -- 50 Hz
local ODR_100HZ                           = 0x50      -- 100 Hz（默认）
local ODR_200HZ                           = 0x60      -- 200 Hz
local ODR_400HZ                           = 0x70      -- 400 Hz
local ODR_800HZ                           = 0x80      -- 800 Hz
local ODR_1K48HZ                          = 0x90      -- 1.48 kHz（高性能模式）
local ODR_2K66HZ                          = 0xA0      -- 2.66 kHz（高性能模式）
local ODR_4K434HZ                         = 0xB0      -- 4.434 kHz（高性能模式）

-- CTRL_REG3 (0x22) INT1 路由
local CTRL3_I1_CLICK_BIT                  = 0x80      -- 敲击中断 → INT1
local CTRL3_I1_IA1_BIT                    = 0x40      -- IA1 中断 → INT1
local CTRL3_I1_ZYXDA_BIT                  = 0x10      -- data_ready → INT1

-- CTRL_REG4 (0x23)
local CTRL4_BDU_BIT                       = 0x80      -- 数据更新锁定（防止高/低字节错位）
local CTRL4_HR_BIT                        = 0x08      -- 1=高精度(12-bit), 0=正常(10-bit)
local CTRL4_FS_MASK                       = 0x30      -- 量程选择位掩码

-- 量程值 (CTRL_REG4[5:4])
local FS_2G                               = 0x00      -- +/-2g（默认）
local FS_4G                               = 0x10      -- +/-4g
local FS_8G                               = 0x20      -- +/-8g
local FS_16G                              = 0x30      -- +/-16g

-- 灵敏度 (16-bit 左对齐，LSB/g)
local SENSITIVITY_2G                      = 16384     -- +/-2g  每 g 16384 LSB
local SENSITIVITY_4G                      = 8192      -- +/-4g  每 g 8192 LSB
local SENSITIVITY_8G                      = 4096      -- +/-8g  每 g 4096 LSB
local SENSITIVITY_16G                     = 2048      -- +/-16g 每 g 2048 LSB

-- CTRL_REG5 (0x24)
local CTRL5_D4D_INT1_BIT                  = 0x04      -- 1=4D 方向检测使能(INT1), 0=6D（手册 D4D_INT1 位）
local CTRL5_D4D_INT2_BIT                  = 0x01      -- 1=4D 方向检测使能(INT2), 0=6D（手册 D4D_INT2 位）
local CTRL5_LIR_INT1_BIT                  = 0x08      -- INT1 中断锁存（读 INT1_SRC 后清除）
local CTRL5_LIR_INT2_BIT                  = 0x02      -- INT2 中断锁存

-- CTRL_REG6 (0x25) INT2 路由
local CTRL6_I2_CLICK_BIT                  = 0x80      -- 敲击中断 → INT2
local CTRL6_I2_IA2_BIT                    = 0x20      -- IA2 中断 → INT2
local CTRL6_I2_DRDY_BIT                   = 0x08      -- data_ready → INT2

-- INTx_CFG (0x30/0x34)
local INT_CFG_AOI_BIT                     = 0x80      -- 0=OR 组合, 1=AND 组合（方向检测用）
local INT_CFG_6D_BIT                      = 0x40      -- 6D 方向检测使能
local INT_CFG_ZHIE_BIT                    = 0x20      -- Z 轴正方向阈值使能
local INT_CFG_ZLIE_BIT                    = 0x10      -- Z 轴负方向阈值使能
local INT_CFG_YHIE_BIT                    = 0x08      -- Y 轴正方向阈值使能
local INT_CFG_YLIE_BIT                    = 0x04      -- Y 轴负方向阈值使能
local INT_CFG_XHIE_BIT                    = 0x02      -- X 轴正方向阈值使能
local INT_CFG_XLIE_BIT                    = 0x01      -- X 轴负方向阈值使能

-- I2C 地址
local DEV_ADDR_LOW                        = 0x18      -- SA0=GND
local DEV_ADDR_HIGH                       = 0x19      -- SA0=VCC
local SC7A20H_DEVID                      = 0x11      -- WHO_AM_I 固定值（0x11）

-- ==================== 内部状态变量 ====================

local g_i2c_bus                           = 0         -- I2C 总线 ID
local g_is_soft, g_scl_pin, g_sda_pin     = false, nil, nil  -- 软件 I2C 引脚
local g_dev_addr                          = 0x18      -- 检测到的器件 I2C 地址
local g_range                             = "2g"      -- 当前量程
local g_sensitivity                       = SENSITIVITY_2G  -- 当前灵敏度
local g_odr_hz                            = 100       -- 当前输出速率
local g_ready                             = false     -- 是否已初始化
local g_direction_enabled                 = nil       -- 方向检测：nil/关闭, "6d"/6D, "4d"/4D
local g_int1_pending                      = false     -- 中断标志（无 cb 模式用）
local g_int2_pending                      = false
local g_int1_gpio                         = nil       -- INT1 GPIO 引脚号（用于 close 时注销）
local g_int2_gpio                         = nil       -- INT2 GPIO 引脚号（用于 close 时注销）

-- ==================== I2C 总线恢复 ====================
-- I2C 总线恢复：用 GPIO 模拟最多 9 个 SCL 脉冲，释放被从机锁死的 SDA
-- 每发一个脉冲检测 SDA 是否释放，提前结束
-- 适用于软件 I2C 和硬件 I2C 两种模式（有引脚号就可以操作）
-- 硬件 I2C 场景恢复后需重新 i2c.setup()
-- 注意：SCL 低电平时检查 SDA 电平，避免引脚模式切换毛刺干扰从机状态机

local function i2c_bus_recovery()
    if not g_scl_pin or not g_sda_pin then return end
    gpio.setup(g_scl_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    sys.wait(1)
    for i = 1, 9 do
        gpio.set(g_scl_pin, 0); sys.wait(1)
        gpio.set(g_scl_pin, 1); sys.wait(1)
        -- 切 SDA 为输入模式检查电平
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
end

-- ==================== I2C 总线卡死自动检测与恢复 ====================
-- 通信失败后检查 SDA/SCL 电平，确认死锁后自动恢复并重试

local function try_bus_recovery()
    if not g_scl_pin or not g_sda_pin then return false end
    gpio.setup(g_sda_pin, gpio.INPUT, gpio.PULLUP)
    gpio.setup(g_scl_pin, gpio.INPUT, gpio.PULLUP)
    sys.wait(1)
    local sda_level = gpio.get(g_sda_pin)
    local scl_level = gpio.get(g_scl_pin)
    local is_stall = (sda_level == 0 and scl_level == 1)
    gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    gpio.setup(g_scl_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    if not is_stall then return false end
    log.warn("exs_sc7a20h", "检测到I2C总线卡死，尝试恢复")
    i2c_bus_recovery()
    if not g_is_soft then
        i2c.setup(g_i2c_bus, i2c.SLOW)
    end
    return true
end

-- ==================== 底层 I2C 读写 ====================

-- 写一个寄存器（reg 地址 + 1 字节数据，带自动卡死检测恢复）
-- @return boolean 成功返回 true
local function i2c_write(reg, val)
    local ok = i2c.send(g_i2c_bus, g_dev_addr, { reg, val })
    if not ok then
        if try_bus_recovery() then
            ok = i2c.send(g_i2c_bus, g_dev_addr, { reg, val })
        end
    end
    return ok
end

-- 从指定地址读连续 len 个字节（带自动卡死检测恢复）
-- len>1 时自动使能地址自增（寄存器地址 OR 0x80，SC7A20H I2C 协议要求）
-- @return table or nil 返回字节数组，失败返回 nil
local function i2c_read(reg, len)
    -- 批量读时需要设 MSB=1 使能地址自增（手册 I2C 操作说明）
    local addr_byte = (len > 1) and (reg | 0x80) or reg
    local ok = i2c.send(g_i2c_bus, g_dev_addr, { addr_byte })
    if not ok then
        if try_bus_recovery() then
            ok = i2c.send(g_i2c_bus, g_dev_addr, { addr_byte })
        end
        if not ok then return nil end
    end
    local data = i2c.recv(g_i2c_bus, g_dev_addr, len)
    if not data then return nil end
    local t = {}
    for i = 1, #data do t[i] = data:byte(i) end
    return t
end

-- 统一读写接口（后续加 SPI 时在此切换）
local function reg_write(reg, val) return i2c_write(reg, val) end
local function reg_read(reg, len) return i2c_read(reg, len) end

-- ==================== 内部辅助函数 ====================

-- 量程字符串 → 寄存器值 + 灵敏度系数
-- @return number, number 寄存器值, 灵敏度(LSB/g)
local function range_to_params(str)
    if str == "2g" then return FS_2G, SENSITIVITY_2G
    elseif str == "4g" then return FS_4G, SENSITIVITY_4G
    elseif str == "8g" then return FS_8G, SENSITIVITY_8G
    elseif str == "16g" then return FS_16G, SENSITIVITY_16G
    else return FS_2G, SENSITIVITY_2G end
end

-- 目标 Hz → 寄存器值 + 实际速率（向下取到最近的可用值）
-- @return number, number 寄存器值, 实际速率(Hz)
local function odr_to_reg(hz)
    if hz >= 4000 then return ODR_4K434HZ, 4434
    elseif hz >= 2000 then return ODR_2K66HZ, 2660
    elseif hz >= 1000 then return ODR_1K48HZ, 1480
    elseif hz >= 600 then return ODR_800HZ, 800
    elseif hz >= 400 then return ODR_400HZ, 400
    elseif hz >= 200 then return ODR_200HZ, 200
    elseif hz >= 100 then return ODR_100HZ, 100
    elseif hz >= 50 then return ODR_50HZ, 50
    elseif hz >= 25 then return ODR_25HZ, 25
    elseif hz >= 12.5 then return ODR_12_5HZ, 12.5
    else return ODR_1_56HZ, 1.56 end
end

-- 根据三轴加速度值判断设备朝向（软件算法）
-- 哪个轴的重力分量最大，设备就朝哪个方向
local function calc_orientation(ax, ay, az)
    local abs_x, abs_y, abs_z = math.abs(ax), math.abs(ay), math.abs(az)
    if abs_x > abs_y and abs_x > abs_z then return ax > 0 and "back" or "front" end
    if abs_y > abs_x and abs_y > abs_z then return ay > 0 and "left" or "right" end
    if abs_z > abs_x and abs_z > abs_y then return az > 0 and "down" or "up" end
    return nil
end

-- ==================== 器件检测 ====================
-- 遍历 0x18 和 0x19 两个地址，读 WHO_AM_I 确认是否是 SC7A20H

local function chip_detect_i2c()
    for _, addr in ipairs({ DEV_ADDR_LOW, DEV_ADDR_HIGH }) do
        if i2c.send(g_i2c_bus, addr, { REG_WHO_AM_I }) then
            local data = i2c.recv(g_i2c_bus, addr, 1)
            if data and #data >= 1 then
                local id = data:byte(1)
                if id == SC7A20H_DEVID then
                    g_dev_addr = addr
                    log.info("exs_sc7a20h", string.format("SC7A20H @ I2C 0x%02X", addr))
                    return true
                end
            end
        end
    end
    return false
end

-- ==================== 初始化配置写入 ====================

-- 写入 CTRL_REG1（ODR + 功耗模式 + 三轴使能）
-- 写入 CTRL_REG4（BDU + 量程 + 精度模式）
-- 可选配置：方向检测
-- 最后读回验证写入是否成功
local function apply_init_config(config)
    -- 参考驱动：先发 BOOT=1 从 NVM 重载修调值（校准补偿），写 CTRL5=0x80
    reg_write(REG_CTRL5, 0x80)
    sys.wait(10)

    local range_str = config.range or "2g"
    local odr_hz = config.odr or 100
    local mode = config.powermode or "highres"
    local odr_reg, actual_odr = odr_to_reg(odr_hz)
    local fs_reg, sensitivity = range_to_params(range_str)
    local lpen = 0; local hr = 0
    if mode == "lowpower" then lpen = 1; hr = 0
    elseif mode == "normal" then lpen = 0; hr = 0
    else lpen = 0; hr = 1 end

    local ctrl1 = odr_reg | (lpen == 1 and CTRL1_LPen_BIT or 0) | CTRL1_AXES_EN
    if not reg_write(REG_CTRL1, ctrl1) then log.error("exs_sc7a20h.setup CTRL_REG1 失败"); return false end

    local ctrl4 = CTRL4_BDU_BIT | (hr == 1 and CTRL4_HR_BIT or 0) | fs_reg
    if not reg_write(REG_CTRL4, ctrl4) then log.error("exs_sc7a20h.setup CTRL_REG4 失败"); return false end

    if config.enable_direction then
        local c5 = (reg_read(REG_CTRL5, 1) or {})[1] or 0
        -- D4D_INT1=1 使能4D, D4D_INT1=0 使能6D（手册CTRL_REG5 bit2）
        c5 = config.enable_direction == "6d" and (c5 & ~CTRL5_D4D_INT1_BIT) or (c5 | CTRL5_D4D_INT1_BIT)
        c5 = config.enable_direction == "6d" and (c5 & ~CTRL5_D4D_INT2_BIT) or (c5 | CTRL5_D4D_INT2_BIT)
        reg_write(REG_CTRL5, c5)
        g_direction_enabled = config.enable_direction
    end

    -- 读回验证
    local r1 = reg_read(REG_CTRL1, 1); local r4 = reg_read(REG_CTRL4, 1)
    local status = reg_read(REG_STATUS, 1); local icfg = reg_read(REG_INT1_CFG, 1)
    log.info("exs_sc7a20h", string.format("REG读回 CTRL1=0x%02X CTRL4=0x%02X STATUS=0x%02X INT1_CFG=0x%02X",
        (r1 or {})[1] or 0, (r4 or {})[1] or 0, (status or {})[1] or 0, (icfg or {})[1] or 0))

    g_range, g_sensitivity = range_str, sensitivity; g_odr_hz = actual_odr
    return true
end

-- ==================== 中断配置 ====================

-- 根据 int1/int2 配置表，写入 CTRL_REG3/6（中断路由）、INT1_CFG/INT2_CFG（触发事件）
-- 可选额外参数：threshold_mg（阈值 mg）、duration_ms（持续时间 ms）
local function apply_int_config(int1_cfg, int2_cfg)
    local ctrl2 = 0; local ctrl3 = 0; local ctrl6 = 0; local ctrl5 = 0
    local int1_act_cfg = 0; local int2_act_cfg = 0
    local need_int1_gen = false; local need_int2_gen = false
    ctrl5 = (reg_read(REG_CTRL5, 1) or {})[1] or 0

    if int1_cfg then
        if int1_cfg.data_ready then ctrl3 = ctrl3 | CTRL3_I1_ZYXDA_BIT end
        if int1_cfg.activity then
            int1_act_cfg = int1_act_cfg | INT_CFG_ZHIE_BIT | INT_CFG_YHIE_BIT | INT_CFG_XHIE_BIT
            ctrl3 = ctrl3 | CTRL3_I1_IA1_BIT; need_int1_gen = true
        end
        if int1_cfg.free_fall then
            int1_act_cfg = int1_act_cfg | INT_CFG_AOI_BIT | INT_CFG_ZLIE_BIT | INT_CFG_YLIE_BIT | INT_CFG_XLIE_BIT
            ctrl3 = ctrl3 | CTRL3_I1_IA1_BIT; need_int1_gen = true
        end
    end

    if int2_cfg then
        if int2_cfg.activity then
            int2_act_cfg = int2_act_cfg | INT_CFG_ZHIE_BIT | INT_CFG_YHIE_BIT | INT_CFG_XHIE_BIT
            ctrl6 = ctrl6 | CTRL6_I2_IA2_BIT; need_int2_gen = true
        end
        if int2_cfg.free_fall then
            int2_act_cfg = int2_act_cfg | INT_CFG_AOI_BIT | INT_CFG_ZLIE_BIT | INT_CFG_YLIE_BIT | INT_CFG_XLIE_BIT
            ctrl6 = ctrl6 | CTRL6_I2_IA2_BIT; need_int2_gen = true
        end
        if int2_cfg.data_ready then ctrl6 = ctrl6 | CTRL6_I2_DRDY_BIT end
    end

    -- 活动检测建议启用高通滤波（滤除重力直流分量，手册建议）
    -- 注意：free_fall 不用高通滤波（会滤掉重力导致三轴近零，AND 模式下持续触发）
    if int1_cfg and (int1_cfg.activity) then ctrl2 = ctrl2 | CTRL2_HPIS1_BIT end
    if int2_cfg and (int2_cfg.activity) then ctrl2 = ctrl2 | CTRL2_HPIS2_BIT end

-- 阈值配置
    -- threshold_mg → 寄存器值，duration_ms → 采样数
    local odr_hz = g_odr_hz or 100
    local fs_g = 2
    if g_range == "4g" then fs_g = 4 elseif g_range == "8g" then fs_g = 8 elseif g_range == "16g" then fs_g = 16 end
    local lsb_mg = 16 * (fs_g / 2)  -- 手册: +/-2g=16mg/LSB, +/-4g=32mg/LSB, +/-8g=64mg/LSB, +/-16g=128mg/LSB

    if need_int1_gen then
        reg_write(REG_INT1_CFG, int1_act_cfg)
        if int1_cfg then
            if int1_cfg.free_fall and not int1_cfg.threshold_mg then
                reg_write(REG_INT1_THS, math.max(math.min(math.floor(500 / lsb_mg), 127), 1))
            end
            if int1_cfg.threshold_mg then
                reg_write(REG_INT1_THS, math.max(math.min(math.floor(int1_cfg.threshold_mg / lsb_mg), 127), 1))
            end
            if int1_cfg.duration_ms then
                reg_write(REG_INT1_DURATION, math.min(math.max(math.floor(int1_cfg.duration_ms * odr_hz / 1000), 1), 127))
            end
        end
    end
    if need_int2_gen then
        reg_write(REG_INT2_CFG, int2_act_cfg)
        if int2_cfg then
            if int2_cfg.free_fall and not int2_cfg.threshold_mg then
                reg_write(REG_INT2_THS, math.max(math.min(math.floor(500 / lsb_mg), 127), 1))
            end
            if int2_cfg.threshold_mg then
                reg_write(REG_INT2_THS, math.max(math.min(math.floor(int2_cfg.threshold_mg / lsb_mg), 127), 1))
            end
            if int2_cfg.duration_ms then
                reg_write(REG_INT2_DURATION, math.min(math.max(math.floor(int2_cfg.duration_ms * odr_hz / 1000), 1), 127))
            end
        end
    end

    if ctrl2 ~= 0 then reg_write(REG_CTRL2, ctrl2) end
    -- 路由 CTRL_REG3/6 必须在清除中断标志之后，否则已挂起的中断会直接拉高 INT 引脚
    if ctrl3 ~= 0 then reg_write(REG_CTRL3, ctrl3) end
    if ctrl6 ~= 0 then reg_write(REG_CTRL6, ctrl6) end
    if need_int1_gen and (int1_cfg and int1_cfg.latched ~= false) then ctrl5 = ctrl5 | CTRL5_LIR_INT1_BIT end
    if need_int2_gen and (int2_cfg and int2_cfg.latched ~= false) then ctrl5 = ctrl5 | CTRL5_LIR_INT2_BIT end
    if ctrl5 ~= 0 then reg_write(REG_CTRL5, ctrl5) end
end

-- ==================== GPIO 中断注册 ====================
-- 低频中断（tap/activity/free_fall）：传 cb 自动回调，data 含 x/y/z/dir
-- 高频中断（data_ready 100Hz+）：不传 cb，用 get_int_flag() 轮询
-- GPIO 回调中先读中断标志寄存器清标志，再做数据读取

-- 中断回调状态表（避免闭包/匿名函数）
local g_int_cfg_tab = { {}, {} }  -- idx=1->INT1, idx=2->INT2

local function gpio_int1_handler()
    local cfg = g_int_cfg_tab[1]
    reg_read(REG_INT1_SRC, 1)
    if cfg.cb then
        local data = exs_sc7a20h.get_data()
        if data then cfg.cb(data) end
    else
        g_int1_pending = true
    end
end

local function gpio_int2_handler()
    local cfg = g_int_cfg_tab[2]
    reg_read(REG_INT2_SRC, 1)
    if cfg.cb then
        local data = exs_sc7a20h.get_data()
        if data then cfg.cb(data) end
    else
        g_int2_pending = true
    end
end

local function register_gpio_interrupt(int_cfg, idx)
    if not int_cfg or not int_cfg.int_gpio then return end
    g_int_cfg_tab[idx] = { cb = int_cfg.cb }
    local handler = (idx == 1) and gpio_int1_handler or gpio_int2_handler
    gpio.setup(int_cfg.int_gpio, handler, gpio.PULLUP, gpio.RISING)
    log.info("exs_sc7a20h", string.format("INT%d 已注册, gpio=%d", idx, int_cfg.int_gpio))
end

--[[
查询中断触发标志

无 cb 模式时，中断触发后通过本函数轮询。
@api exs_sc7a20h.get_int_flag()
@return boolean, boolean int1是否触发, int2是否触发
]]
function exs_sc7a20h.get_int_flag()
    local f1, f2 = g_int1_pending, g_int2_pending
    g_int1_pending = false; g_int2_pending = false
    return f1, f2
end

-- ==================== 外部 API ====================

--[[
初始化 SC7A20H 加速度传感器

配置通信接口（I2C）、采样参数、功耗模式、中断事件。

@api exs_sc7a20h.setup(model, config)
@string model 通信模式，当前仅支持 "I2C"
@table config 配置参数
  scl/sda   - 软件 I2C 引脚（与 i2c_id 二选一）
  i2c_id    - 硬件 I2C 总线 ID（与 scl/sda 二选一，默认 0）
  range     - 量程 "2g"/"4g"/"8g"/"16g"，默认 "2g"
  odr       - 输出速率 1.56~4434 Hz，默认 100
  powermode - 功耗模式 "highres"/"normal"/"lowpower"，默认 "highres"
  enable_direction- 方向检测 "6d" 或 "4d"
  int1/int2 - 中断配置表（见文档）
@return boolean
]]
function exs_sc7a20h.setup(model, config)
    if type(model) ~= "string" or type(config) ~= "table" then log.error("exs_sc7a20h.setup 参数错误"); return false end

    if model == "I2C" then
        -- 软件 I2C：指定 scl/sda 引脚
        if config.scl and config.sda then
            g_scl_pin, g_sda_pin = config.scl, config.sda
            if config.i2c_id then
                i2c_bus_recovery()
                if i2c.setup(config.i2c_id, i2c.SLOW) == 0 then log.error("exs_sc7a20h.setup I2C 失败"); return false end
                g_i2c_bus = config.i2c_id; g_is_soft = false
            else
                i2c_bus_recovery()
                g_i2c_bus = i2c.createSoft(config.scl, config.sda, 5)
                if not g_i2c_bus then log.error("exs_sc7a20h.setup 软件 I2C 失败"); return false end
                g_is_soft = true
            end
        -- 硬件 I2C：仅指定 i2c_id
        else
            local i2c_id = config.i2c_id or 0
            if i2c.setup(i2c_id, i2c.SLOW) == 0 then log.error("exs_sc7a20h.setup I2C 失败"); return false end
            g_i2c_bus = i2c_id; g_is_soft = false; g_scl_pin, g_sda_pin = nil, nil
        end
        if not chip_detect_i2c() then log.error("exs_sc7a20h.setup 未检测到 SC7A20H"); return false end
    else
        log.error("exs_sc7a20h.setup 不支持的模式，当前仅支持 I2C"); return false
    end

    if not apply_init_config(config) then return false end

    -- 中断配置和 GPIO 注册
    local int1_cfg = config.int1; local int2_cfg = config.int2
    apply_int_config(int1_cfg, int2_cfg)
    register_gpio_interrupt(config.int1, 1)
    register_gpio_interrupt(config.int2, 2)
    -- 保存 GPIO 引脚号，用于 close 时注销中断
    if config.int1 and config.int1.int_gpio then g_int1_gpio = config.int1.int_gpio end
    if config.int2 and config.int2.int_gpio then g_int2_gpio = config.int2.int_gpio end

    g_ready = true
    log.info("exs_sc7a20h", string.format("初始化完成 mode=%s range=%s odr=%sHz mode=%s", model, g_range, tostring(g_odr_hz), config.powermode or "highres"))
    return true
end

--[[
读取三轴加速度数据

读取 SC7A20H 三轴加速度数据，根据当前量程自动计算 g 值。
启用方向检测后 data.dir 自动附带朝向。

@api exs_sc7a20h.get_data()
@return table or nil
  data.x/y/z - 加速度值，单位 g
  data.dir   - 设备朝向（仅 enable_direction 开启时），"up"/"down"/"left"/"right"/"front"/"back"
]]
function exs_sc7a20h.get_data()
    if not g_ready then log.error("exs_sc7a20h.get_data 请先 setup()"); return nil end
    -- 批量读 6 字节（0x28-0x2D），减少 I2C 总线交互次数和中断干扰
    local buf = reg_read(REG_OUT_X_L, 6)
    if not buf or #buf < 6 then return nil end
    local x = (buf[2] << 8) | buf[1]; local y = (buf[4] << 8) | buf[3]; local z = (buf[6] << 8) | buf[5]
    if x >= 0x8000 then x = x - 0x10000 end; if y >= 0x8000 then y = y - 0x10000 end; if z >= 0x8000 then z = z - 0x10000 end
    local ax, ay, az = x / g_sensitivity, y / g_sensitivity, z / g_sensitivity
    local dir = g_direction_enabled and calc_orientation(ax, ay, az) or nil
    return { x = ax, y = ay, z = az, dir = dir }
end

--[[
切换量程

@api exs_sc7a20h.set_range(range)
@string range "2g"、"4g"、"8g"、"16g"
]]
function exs_sc7a20h.set_range(str)
    if not g_ready then log.error("exs_sc7a20h.set_range 请先 setup()"); return end
    if str ~= "2g" and str ~= "4g" and str ~= "8g" and str ~= "16g" then log.error("exs_sc7a20h.set_range 参数错误"); return end
    local fs_reg, sens = range_to_params(str)
    local cur = (reg_read(REG_CTRL4, 1) or {})[1] or 0
    cur = (cur & 0xCF) | fs_reg
    if not reg_write(REG_CTRL4, cur) then return end
    g_range, g_sensitivity = str, sens
    log.info("exs_sc7a20h", string.format("量程切换为 %s", str))
end

--[[
切换输出数据速率

@api exs_sc7a20h.set_odr(hz)
@number hz 目标速率，可选值 1.56/12.5/25/50/100/200/400/800/1480/2660/4434 Hz
]]
function exs_sc7a20h.set_odr(hz)
    if not g_ready then log.error("exs_sc7a20h.set_odr 请先 setup()"); return end
    local odr_reg, actual_odr = odr_to_reg(hz)
    local cur = (reg_read(REG_CTRL1, 1) or {})[1] or 0
    cur = (cur & 0x0F) | odr_reg
    if not reg_write(REG_CTRL1, cur) then return end
    g_odr_hz = actual_odr
    log.info("exs_sc7a20h", string.format("输出速率切换为 %sHz", tostring(actual_odr)))
end

--[[
切换功耗模式

@api exs_sc7a20h.set_powermode(mode)
@string mode "highres"(12-bit)、"normal"(10-bit)、"lowpower"(8-bit)
]]
function exs_sc7a20h.set_powermode(mode)
    if not g_ready then log.error("exs_sc7a20h.set_powermode 请先 setup()"); return end
    local lpen = 0; local hr = 0
    if mode == "lowpower" then lpen = 1; hr = 0
    elseif mode == "normal" then lpen = 0; hr = 0
    elseif mode == "highres" then lpen = 0; hr = 1
    else log.error("exs_sc7a20h.set_powermode 参数错误"); return end
    local c1 = (reg_read(REG_CTRL1, 1) or {})[1] or 0
    reg_write(REG_CTRL1, lpen == 1 and (c1 | CTRL1_LPen_BIT) or (c1 & ~CTRL1_LPen_BIT))
    local c4 = (reg_read(REG_CTRL4, 1) or {})[1] or 0
    reg_write(REG_CTRL4, hr == 1 and (c4 | CTRL4_HR_BIT) or (c4 & ~CTRL4_HR_BIT))
    log.info("exs_sc7a20h", string.format("功耗模式切换为 %s", mode))
end

--[[
进入待机模式（低功耗）

将传感器切换到 power-down 模式（ODR=0），保持内部配置状态。
调用 wakeup() 可快速恢复工作，无需重新 setup()。

@api exs_sc7a20h.sleep()

@return nil

@usage
exs_sc7a20h.sleep()
]]
function exs_sc7a20h.sleep()
    if not g_ready then
        log.error("exs_sc7a20h.sleep 请先 setup()"); return
    end
    -- ODR=0 进入 power-down 模式，其余位保留
    local cur = (reg_read(REG_CTRL1, 1) or {})[1] or 0
    reg_write(REG_CTRL1, cur & 0x0F)
    log.info("exs_sc7a20h", "已进入 power-down 模式")
end

--[[
从待机模式唤醒

恢复传感器到之前的 ODR 和功耗模式，保持休眠前的配置。
无需重新调用 setup()。

@api exs_sc7a20h.wakeup()

@return nil

@usage
exs_sc7a20h.wakeup()
]]
function exs_sc7a20h.wakeup()
    if not g_ready then
        log.error("exs_sc7a20h.wakeup 请先 setup()"); return
    end
    local odr_reg = odr_to_reg(g_odr_hz)
    local cur = (reg_read(REG_CTRL1, 1) or {})[1] or 0
    -- 恢复 ODR 位（[7:4]），保留 LPen 和 X/Y/Z 使能位
    cur = (cur & 0x0F) | odr_reg
    reg_write(REG_CTRL1, cur)
    log.info("exs_sc7a20h", string.format("已从 power-down 模式唤醒，ODR=%sHz", tostring(g_odr_hz)))
end

--[[
获取中断源详情

读 INT1_SRC 和 INT2_SRC，返回触发的中断事件。读后自动清标志。
用于排查中断触发原因。

@api exs_sc7a20h.get_int_src()
@return table or nil {int1 = {...}, int2 = {...}}
  事件: "ia"(中断激活) "zh"/"zl"(Z轴) "yh"/"yl"(Y轴) "xh"/"xl"(X轴)
]]
function exs_sc7a20h.get_int_src()
    if not g_ready then log.error("exs_sc7a20h.get_int_src 请先 setup()"); return nil end
    local result = {}
    local src1 = reg_read(REG_INT1_SRC, 1)
    if src1 and #src1 >= 1 then
        local v = src1[1]; local ev = {}
        if v & 0x40 ~= 0 then table.insert(ev, "ia") end
        if v & 0x20 ~= 0 then table.insert(ev, "zh") end
        if v & 0x10 ~= 0 then table.insert(ev, "zl") end
        if v & 0x08 ~= 0 then table.insert(ev, "yh") end
        if v & 0x04 ~= 0 then table.insert(ev, "yl") end
        if v & 0x02 ~= 0 then table.insert(ev, "xh") end
        if v & 0x01 ~= 0 then table.insert(ev, "xl") end
        result.int1 = ev
    end
    local src2 = reg_read(REG_INT2_SRC, 1)
    if src2 and #src2 >= 1 then
        local v = src2[1]; local ev = {}
        if v & 0x40 ~= 0 then table.insert(ev, "ia") end
        if v & 0x20 ~= 0 then table.insert(ev, "zh") end
        if v & 0x10 ~= 0 then table.insert(ev, "zl") end
        if v & 0x08 ~= 0 then table.insert(ev, "yh") end
        if v & 0x04 ~= 0 then table.insert(ev, "yl") end
        if v & 0x02 ~= 0 then table.insert(ev, "xh") end
        if v & 0x01 ~= 0 then table.insert(ev, "xl") end
        result.int2 = ev
    end
    return result
end

--[[
获取设备当前朝向

需 enable_direction 已开启。读加速度数据后计算朝向，与 data.dir 一致。

@api exs_sc7a20h.get_orientation()
@return string or nil "up"/"down"/"left"/"right"/"front"/"back"
]]
function exs_sc7a20h.get_orientation()
    if not g_ready then log.error("exs_sc7a20h.get_orientation 请先 setup()"); return nil end
    if not g_direction_enabled then log.warn("exs_sc7a20h.get_orientation 方向检测未使能"); return nil end
    local data = exs_sc7a20h.get_data()
    return data and data.dir or nil
end

--[[
打印关键寄存器值（调试用）

@api exs_sc7a20h.dump_regs()
]]
function exs_sc7a20h.dump_regs()
    local regs = { REG_CTRL1, REG_CTRL2, REG_CTRL3, REG_CTRL4, REG_CTRL5, REG_CTRL6,
        REG_STATUS, REG_INT1_SRC, REG_INT2_SRC, REG_FIFO_SRC }
    local names = { "CTRL1", "CTRL2", "CTRL3", "CTRL4", "CTRL5", "CTRL6",
        "STATUS", "INT1_SRC", "INT2_SRC", "FIFO_SRC" }
    local sb = {}
    for i, r in ipairs(regs) do
        local d = reg_read(r, 1); local v = (d and #d >= 1) and d[1] or 0xFF
        table.insert(sb, string.format("%s=0x%02X", names[i], v))
    end
    log.info("exs_sc7a20h", table.concat(sb, " "))
end

--[[
关闭 SC7A20H 传感器

将所有关键寄存器写回默认值，重置内部状态。
close 后需要重新调用 setup() 才能再次使用。

@api exs_sc7a20h.close()

@return nil

@usage
exs_sc7a20h.close()
]]
function exs_sc7a20h.close()
    if not g_ready then return end
    -- 先注销 GPIO 中断（防止 close 后 INT 引脚变化触发回调导致死机）
    if g_int1_gpio then gpio.setup(g_int1_gpio, nil) end
    if g_int2_gpio then gpio.setup(g_int2_gpio, nil) end
    reg_write(REG_CTRL1, 0x00); reg_write(REG_CTRL2, 0x00); reg_write(REG_CTRL3, 0x00)
    reg_write(REG_CTRL4, 0x00); reg_write(REG_CTRL5, 0x00); reg_write(REG_CTRL6, 0x00)
    g_ready = false; g_i2c_bus = 0; g_is_soft = false
    g_scl_pin = nil; g_sda_pin = nil; g_dev_addr = 0x18
    g_direction_enabled = nil
    g_int1_pending = false; g_int2_pending = false
    g_int1_gpio = nil; g_int2_gpio = nil
    g_int_cfg_tab[1] = {}; g_int_cfg_tab[2] = {}
    log.info("exs_sc7a20h", "传感器已关闭")
end

--[[
获取 exs_sc7a20h 库的版本号

@api exs_sc7a20h.version()

@return string

@usage
local ver = exs_sc7a20h.version()
]]
function exs_sc7a20h.version() return "202607180900" end

log.debug("exs_sc7a20h", "version -> " .. exs_sc7a20h.version())
return exs_sc7a20h