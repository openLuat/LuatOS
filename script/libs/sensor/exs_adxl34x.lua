--[[
@module  exs_adxl34x
@summary ADXL345/ADXL346 三轴加速度传感器扩展库
@version 1.1
@date    2026.07.17
@author  江访
@usage
本文件为 ADXL345/ADXL346 三轴加速度传感器（ADI 出品）的 LuatOS 扩展库。

=== 对外接口 ===
1、exs_adxl34x.setup(model, config)  初始化 ADXL345/ADXL346
2、exs_adxl34x.get_data()            读取三轴加速度数据
3、exs_adxl34x.set_range(range)      切换量程
4、exs_adxl34x.set_odr(hz)           切换输出速率
5、exs_adxl34x.int_config(int, cfg)  配置中断事件
6、exs_adxl34x.get_int_source()      读取中断源
7、exs_adxl34x.sleep()               进入待机模式
8、exs_adxl34x.wakeup()              从待机模式唤醒
9、exs_adxl34x.close()               关闭传感器
10、exs_adxl34x.version()            获取版本号

=== 版本更新说明 ===
版本号：202607170900
1、更新时间：2026-07-17
2、更新内容：
        i2c_bus_recovery 增加 SDA 释放检测，提前结束脉冲循环
        i2c_write/i2c_read 增加 I2C 总线卡死自动检测与恢复
        硬件 I2C 恢复后自动重新 i2c.setup()
        新增 exs_adxl34x.close() 接口，关闭传感器并释放资源
        新增 exs_adxl34x.sleep()/wakeup() 低功耗接口，替换 soft_reset()

版本号：202607141200
1、更新时间：2026-07-14
2、更新内容：
        初版，实现 ADXL345/ADXL346 驱动所有基础功能
        初始化接口使用 setup 命名，统一 TM16xx 系列命名规范
        支持软件 I2C 和硬件 I2C 两种通信模式（SPI 未适配）
        支持量程切换（±2g / ±4g / ±8g / ±16g）
        支持输出速率切换（0.78Hz~3200Hz）
        支持自动器件地址检测
        支持软件复位

=== 使用示例 ===
-- I2C 软件模式 + 中断
local function adxl34x_cb(data)
    log.info("exs_adxl34x", string.format("X=%.3f Y=%.3f Z=%.3f g", data.x, data.y, data.z))
end
local result = exs_adxl34x.setup("I2C", {
    scl = 31, sda = 30,
    range = "2g", odr = 100,
    int1 = {int_gpio = 10, data_ready = true, cb = adxl34x_cb},
})
]]

local exs_adxl34x                     = {}

-- ==================== 模块常量 ====================

local MODE_I2C                        = 1        -- I2C 通信模式标志
local DEV_ADDR_LOW                    = 0x53     -- I2C 设备地址（SDO=GND）
local DEV_ADDR_HIGH                   = 0x1D     -- I2C 设备地址（SDO=VCC）
local REG_DEVID                       = 0x00     -- 器件 ID 寄存器
local REG_THRESH_TAP                  = 0x1D     -- 敲击阈值寄存器
local REG_OFSX                        = 0x1E     -- X 轴偏移校准
local REG_OFSY                        = 0x1F     -- Y 轴偏移校准
local REG_OFSZ                        = 0x20     -- Z 轴偏移校准
local REG_DUR                         = 0x21     -- 敲击持续时间寄存器
local REG_LATENT                      = 0x22     -- 敲击延迟寄存器
local REG_WINDOW                      = 0x23     -- 敲击窗口寄存器
local REG_THRESH_ACT                  = 0x24     -- 活动检测阈值寄存器
local REG_THRESH_INACT                = 0x25     -- 静止检测阈值寄存器
local REG_TIME_INACT                  = 0x26     -- 静止检测时间寄存器
local REG_ACT_INACT_CTL               = 0x27     -- 活动/静止检测控制寄存器
local REG_THRESH_FF                   = 0x28     -- 自由落体阈值寄存器
local REG_TIME_FF                     = 0x29     -- 自由落体时间寄存器
local REG_TAP_AXES                    = 0x2A     -- 敲击轴选择寄存器
local REG_ACT_TAP_STATUS              = 0x2B     -- 活动/敲击状态寄存器
local REG_BW_RATE                     = 0x2C     -- 输出数据速率（ODR）寄存器
local REG_POWER_CTL                   = 0x2D     -- 电源控制寄存器
local REG_INT_ENABLE                  = 0x2E     -- 中断使能寄存器
local REG_INT_MAP                     = 0x2F     -- 中断映射寄存器
local REG_INT_SOURCE                  = 0x30     -- 中断源寄存器
local REG_DATA_FORMAT                 = 0x31     -- 数据格式寄存器（量程+全分辨率）
local REG_DATAX0                      = 0x32     -- X 轴数据低字节
local REG_DATAX1                      = 0x33     -- X 轴数据高字节
local REG_DATAY0                      = 0x34     -- Y 轴数据低字节
local REG_DATAY1                      = 0x35     -- Y 轴数据高字节
local REG_DATAZ0                      = 0x36     -- Z 轴数据低字节
local REG_DATAZ1                      = 0x37     -- Z 轴数据高字节
local ADXL345_DEVID                   = 0xE5     -- ADXL345 器件 ID 值
local ADXL346_DEVID                   = 0xE6     -- ADXL346 器件 ID 值
local DF_FULL_RES_BIT                 = 3        -- DATA_FORMAT 全分辨率位（bit3）
local INT_DATA_READY                  = 0x80     -- 数据就绪中断位
local INT_SINGLE_TAP                  = 0x40     -- 单击中断位
local INT_DOUBLE_TAP                  = 0x20     -- 双击中断位
local INT_ACTIVITY                    = 0x10     -- 活动检测中断位
local INT_INACTIVITY                  = 0x08     -- 静止检测中断位
local INT_FREE_FALL                   = 0x04     -- 自由落体中断位
local INT_WATERMARK                   = 0x02     -- FIFO 水印中断位
local INT_OVERRUN                     = 0x01     -- FIFO 溢出中断位
local PC_MEASURE                      = 0x08     -- POWER_CTL 测量模式位（bit3）
local RANGE_2G                        = 0x00     -- 量程 ±2g
local RANGE_4G                        = 0x01     -- 量程 ±4g
local RANGE_8G                        = 0x02     -- 量程 ±8g
local RANGE_16G                       = 0x03     -- 量程 ±16g
local SENSITIVITY_2G                  = 256      -- ±2g 灵敏度（LSB/g）
local SENSITIVITY_4G                  = 128      -- ±4g 灵敏度（LSB/g）
local SENSITIVITY_8G                  = 64       -- ±8g 灵敏度（LSB/g）
local SENSITIVITY_16G                 = 32       -- ±16g 灵敏度（LSB/g）
local ODR_0_1HZ                       = 0x00     -- 输出速率 0.1 Hz
local ODR_0_2HZ                       = 0x01     -- 输出速率 0.2 Hz
local ODR_0_39HZ                      = 0x02     -- 输出速率 0.39 Hz
local ODR_0_78HZ                      = 0x03     -- 输出速率 0.78 Hz
local ODR_1_56HZ                      = 0x04     -- 输出速率 1.56 Hz
local ODR_3_13HZ                      = 0x05     -- 输出速率 3.13 Hz
local ODR_6_25HZ                      = 0x06     -- 输出速率 6.25 Hz
local ODR_12_5HZ                      = 0x07     -- 输出速率 12.5 Hz
local ODR_25HZ                        = 0x08     -- 输出速率 25 Hz
local ODR_50HZ                        = 0x09     -- 输出速率 50 Hz
local ODR_100HZ                       = 0x0A     -- 输出速率 100 Hz
local ODR_200HZ                       = 0x0B     -- 输出速率 200 Hz
local ODR_400HZ                       = 0x0C     -- 输出速率 400 Hz
local ODR_800HZ                       = 0x0D     -- 输出速率 800 Hz
local ODR_1600HZ                      = 0x0E     -- 输出速率 1600 Hz
local ODR_3200HZ                      = 0x0F     -- 输出速率 3200 Hz

-- ==================== 内部状态 ====================

local g_mode                          = MODE_I2C
local g_i2c_bus                       = 0
local g_is_soft, g_scl_pin, g_sda_pin = false, nil, nil
local g_dev_addr                      = 0x53
local g_range                         = "2g"; local g_sensitivity = SENSITIVITY_2G
local g_ready                         = false
local g_int1_cb                       = nil; local g_int2_cb = nil
local g_act_couple                    = "AC" -- activity 耦合模式: "AC" 或 "DC"
local g_inact_couple                  = "AC" -- inactivity 耦合模式: "AC" 或 "DC"

-- ==================== I2C 总线恢复 ====================

-- 对 SCL 引脚产生最多 9 个时钟脉冲，强制锁死 SDA 的从机释放总线
-- 每发一个脉冲检测 SDA 是否释放，提前结束
-- 硬件 I2C 场景恢复后需重新 i2c.setup()
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

-- ==================== I2C 总线卡死自动检测 ====================

local function try_bus_recovery()
    if not g_scl_pin or not g_sda_pin then return false end
    -- 切 SDA/SCL 为输入模式读取电平
    gpio.setup(g_sda_pin, gpio.INPUT, gpio.PULLUP)
    gpio.setup(g_scl_pin, gpio.INPUT, gpio.PULLUP)
    sys.wait(1)
    local sda_level = gpio.get(g_sda_pin)
    local scl_level = gpio.get(g_scl_pin)
    local is_stall = (sda_level == 0 and scl_level == 1)
    gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    gpio.setup(g_scl_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    if not is_stall then return false end
    log.warn("exs_adxl34x", "检测到I2C总线卡死，尝试恢复")
    i2c_bus_recovery()
    if not g_is_soft then
        i2c.setup(g_i2c_bus, i2c.SLOW)
    end
    return true
end

-- ==================== 底层读写 ====================

local function i2c_write(reg, val)
    local ok = i2c.send(g_i2c_bus, g_dev_addr, { reg, val })
    if not ok then
        if try_bus_recovery() then
            ok = i2c.send(g_i2c_bus, g_dev_addr, { reg, val })
        end
    end
    return ok
end

local function i2c_read(reg, len)
    local ok = i2c.send(g_i2c_bus, g_dev_addr, { reg })
    if not ok then
        if try_bus_recovery() then
            ok = i2c.send(g_i2c_bus, g_dev_addr, { reg })
        end
        if not ok then return nil end
    end
    local data = i2c.recv(g_i2c_bus, g_dev_addr, len)
    if not data then return nil end
    local t = {}; for i = 1, #data do t[i] = data:byte(i) end; return t
end

local function reg_write(reg, val)
    return i2c_write(reg, val)
end

local function reg_read(reg, len)
    return i2c_read(reg, len)
end

-- ==================== 内部辅助函数 ====================

local function range_to_params(str)
    if str == "2g" then
        return RANGE_2G, SENSITIVITY_2G
    elseif str == "4g" then
        return RANGE_4G, SENSITIVITY_4G
    elseif str == "8g" then
        return RANGE_8G, SENSITIVITY_8G
    elseif str == "16g" then
        return RANGE_16G, SENSITIVITY_16G
    else
        return RANGE_2G, SENSITIVITY_2G
    end
end

local function odr_to_reg(hz)
    if hz >= 3200 then
        return ODR_3200HZ, 3200
    elseif hz >= 1600 then
        return ODR_1600HZ, 1600
    elseif hz >= 800 then
        return ODR_800HZ, 800
    elseif hz >= 400 then
        return ODR_400HZ, 400
    elseif hz >= 200 then
        return ODR_200HZ, 200
    elseif hz >= 100 then
        return ODR_100HZ, 100
    elseif hz >= 50 then
        return ODR_50HZ, 50
    elseif hz >= 25 then
        return ODR_25HZ, 25
    elseif hz >= 12 then
        return ODR_12_5HZ, 12.5
    elseif hz >= 6 then
        return ODR_6_25HZ, 6.25
    elseif hz >= 3 then
        return ODR_3_13HZ, 3.13
    elseif hz >= 1 then
        return ODR_1_56HZ, 1.56
    else
        return ODR_0_78HZ, 0.78
    end
end

-- 将 int1/int2 table 中的事件 boolean 转换为位掩码
local function event_table_to_mask(cfg)
    local m = 0
    if cfg.data_ready then m = m | INT_DATA_READY end
    if cfg.activity then m = m | INT_ACTIVITY end
    if cfg.inactivity then m = m | INT_INACTIVITY end
    if cfg.free_fall then m = m | INT_FREE_FALL end
    if cfg.tap then m = m | INT_SINGLE_TAP | INT_DOUBLE_TAP end
    return m
end

-- 通用中断配置逻辑（setup 和 int_config 共用）
local function apply_int_config(int1_cfg, int2_cfg)
    local int_enable = 0
    local int_map = 0

    -- INT1 事件
    if int1_cfg then
        local m1 = event_table_to_mask(int1_cfg)
        int_enable = int_enable | m1
    end

    -- INT2 事件
    if int2_cfg then
        local m2 = event_table_to_mask(int2_cfg)
        int_enable = int_enable | m2
        int_map = int_map | m2
    end

    if int_enable == 0 then return end

    -- 1. 先关闭所有中断
    reg_write(REG_INT_ENABLE, 0x00); sys.wait(5)

    -- 2. 配置中断相关寄存器
    if int_enable & (INT_ACTIVITY | INT_INACTIVITY) ~= 0 then
        local ctl = (reg_read(REG_ACT_INACT_CTL, 1) or {})[1] or 0
        if int_enable & INT_ACTIVITY ~= 0 then
            if g_act_couple == "DC" then
                ctl = ctl & 0x7F
            else
                ctl = ctl | 0x80
            end
            ctl = ctl | 0x3C
            if (reg_read(REG_THRESH_ACT, 1) or {})[1] == 0 then
                reg_write(REG_THRESH_ACT, 0x05)
            end
        end
        if int_enable & INT_INACTIVITY ~= 0 then
            if g_inact_couple == "DC" then
                ctl = ctl & 0xBF
            else
                ctl = ctl | 0x40
            end
            ctl = ctl | 0x03
            if (reg_read(REG_THRESH_INACT, 1) or {})[1] == 0 then
                reg_write(REG_THRESH_INACT, 0x03)
            end
            if (reg_read(REG_TIME_INACT, 1) or {})[1] == 0 then
                reg_write(REG_TIME_INACT, 4)
            end
        end
        reg_write(REG_ACT_INACT_CTL, ctl); sys.wait(5)
    end

    if int_enable & INT_FREE_FALL ~= 0 then
        reg_write(REG_THRESH_FF, 0x09); sys.wait(5)
        reg_write(REG_TIME_FF, 0x14); sys.wait(5)
    end

    if int_enable & (INT_SINGLE_TAP | INT_DOUBLE_TAP) ~= 0 then
        reg_write(REG_THRESH_TAP, 0x1F); sys.wait(5)
        reg_write(REG_DUR, 0x10); sys.wait(5)
        reg_write(REG_LATENT, 0x20); sys.wait(5)
        reg_write(REG_WINDOW, 0x50); sys.wait(5)
        reg_write(REG_TAP_AXES, 0x07); sys.wait(5)
    end

    -- 3. 配置中断映射
    reg_write(REG_INT_MAP, int_map); sys.wait(5)

    -- 4. 使能中断
    reg_write(REG_INT_ENABLE, int_enable)
end

-- ==================== 器件检测 ====================

local function chip_detect_i2c()
    for _, addr in ipairs({ DEV_ADDR_LOW, DEV_ADDR_HIGH }) do
        if i2c.send(g_i2c_bus, addr, { REG_DEVID }) then
            local data = i2c.recv(g_i2c_bus, addr, 1)
            if data and #data >= 1 then
                local id = data:byte(1)
                if id == ADXL345_DEVID then
                    g_dev_addr = addr; log.info("exs_adxl34x", string.format("ADXL345 @ 0x%02X", addr)); return true
                end
                if id == ADXL346_DEVID then
                    g_dev_addr = addr; log.info("exs_adxl34x", string.format("ADXL346 @ 0x%02X", addr)); return true
                end
            end
        end
    end; return false
end

local function chip_detect_spi()
    log.error("exs_adxl34x", "SPI 模式未适配，请使用 I2C 模式")
    return false
end

-- ==================== 外部 API ====================

--[[
初始化 ADXL345/ADXL346 加速度传感器
@api exs_adxl34x.setup(model, config)
@string model 通信模式，当前仅支持 "I2C"（SPI 未适配）
@return boolean
]]
function exs_adxl34x.setup(model, config)
    if type(model) ~= "string" or type(config) ~= "table" then
        log.error("exs_adxl34x.setup 参数错误"); return false
    end

    if model ~= "I2C" then
        log.error("exs_adxl34x.setup SPI 模式未适配，请使用 I2C 模式"); return false
    else
        g_mode = MODE_I2C
        if config.scl and config.sda then
            g_scl_pin, g_sda_pin = config.scl, config.sda
            if config.i2c_id then
                i2c_bus_recovery()
                if i2c.setup(config.i2c_id, i2c.SLOW) == 0 then
                    log.error("exs_adxl34x.setup I2C 失败"); return false
                end
                g_i2c_bus = config.i2c_id; g_is_soft = false
            else
                i2c_bus_recovery()
                g_i2c_bus = i2c.createSoft(config.scl, config.sda, 5)
                if not g_i2c_bus then
                    log.error("exs_adxl34x.setup 软件 I2C 失败"); return false
                end
                g_is_soft = true
            end
        else
            local i2c_id = config.i2c_id or 0
            if i2c.setup(i2c_id, i2c.SLOW) == 0 then
                log.error("exs_adxl34x.setup I2C 失败"); return false
            end
            g_i2c_bus = i2c_id; g_is_soft = false; g_scl_pin, g_sda_pin = nil, nil
        end; sys.wait(10)
        if not chip_detect_i2c() then
            log.error("exs_adxl34x.setup 未检测到器件"); return false
        end
    end

    local range_str = config.range or "2g"; local odr_hz = config.odr or 100
    local odr_reg, actual_odr = odr_to_reg(odr_hz)
    local range_reg, sensitivity = range_to_params(range_str)

    if not reg_write(REG_BW_RATE, odr_reg) then
        log.error("exs_adxl34x.setup BW_RATE 失败"); return false
    end
    if not reg_write(REG_DATA_FORMAT, (1 << DF_FULL_RES_BIT) | range_reg) then
        log.error("exs_adxl34x.setup DATA_FORMAT 失败"); return false
    end
    if not reg_write(REG_POWER_CTL, PC_MEASURE) then
        log.error("exs_adxl34x.setup POWER_CTL 失败"); return false
    end; sys.wait(20)

    if config.thresh_act then
        local t = math.min(math.floor(config.thresh_act * 256 / 4), 255)
        reg_write(REG_THRESH_ACT, t)
    end
    if config.thresh_inact then
        local t = math.min(math.floor(config.thresh_inact * 256 / 4), 255)
        reg_write(REG_THRESH_INACT, t)
    end
    if config.time_inact then
        reg_write(REG_TIME_INACT, math.floor(config.time_inact / 0.5))
    end

    if config.act_couple then
        g_act_couple = (config.act_couple == "DC") and "DC" or "AC"
    end
    if config.inact_couple then
        g_inact_couple = (config.inact_couple == "DC") and "DC" or "AC"
    end

    local int1_cfg, int2_cfg = nil, nil
    if config.int1 and type(config.int1) == "table" then
        int1_cfg = config.int1; g_int1_cb = config.int1.cb
    end
    if config.int2 and type(config.int2) == "table" then
        int2_cfg = config.int2; g_int2_cb = config.int2.cb
    end
    apply_int_config(int1_cfg, int2_cfg)

    if config.int1 and type(config.int1) == "table" and config.int1.int_gpio then
        gpio.setup(config.int1.int_gpio, function()
            exs_adxl34x.get_int_source()
            local data = exs_adxl34x.get_data()
            if g_int1_cb and data then g_int1_cb(data) end
        end, gpio.PULLUP, gpio.RISING)
        log.info("exs_adxl34x", string.format("INT1 已注册, int_gpio=%d", config.int1.int_gpio))
    end
    if config.int2 and type(config.int2) == "table" and config.int2.int_gpio then
        gpio.setup(config.int2.int_gpio, function()
            exs_adxl34x.get_int_source()
            local data = exs_adxl34x.get_data()
            if g_int2_cb and data then g_int2_cb(data) end
        end, gpio.PULLUP, gpio.RISING)
        log.info("exs_adxl34x", string.format("INT2 已注册, int_gpio=%d", config.int2.int_gpio))
    end

    g_range, g_sensitivity, g_ready = range_str, sensitivity, true
    log.info("exs_adxl34x", string.format("初始化完成 mode=%s range=%s odr=%dHz", model, g_range, actual_odr))
    return true
end

--[[
读取三轴加速度数据
@api exs_adxl34x.get_data()
@return table or nil {x, y, z} 单位 g
]]
function exs_adxl34x.get_data()
    if not g_ready then
        log.error("exs_adxl34x.get_data 请先 setup()"); return nil
    end
    local data = reg_read(REG_DATAX0, 6)
    if not data or #data < 6 then return nil end
    local x = (data[2] << 8) | data[1]; local y = (data[4] << 8) | data[3]; local z = (data[6] << 8) | data[5]
    if x >= 0x8000 then x = x - 0x10000 end; if y >= 0x8000 then y = y - 0x10000 end; if z >= 0x8000 then z = z - 0x10000 end
    return { x = x / g_sensitivity, y = y / g_sensitivity, z = z / g_sensitivity }
end

--[[
切换量程
@api exs_adxl34x.set_range(range)
@string range "2g"、"4g"、"8g"、"16g"
]]
function exs_adxl34x.set_range(str)
    if not g_ready then
        log.error("exs_adxl34x.set_range 请先 setup()"); return
    end
    if str ~= "2g" and str ~= "4g" and str ~= "8g" and str ~= "16g" then
        log.error("exs_adxl34x.set_range 参数错误"); return
    end
    local reg, sens = range_to_params(str)
    local cur = (reg_read(REG_DATA_FORMAT, 1) or {})[1] or 0
    if not reg_write(REG_DATA_FORMAT, (cur & 0xFC) | reg) then return end
    g_range, g_sensitivity = str, sens
    log.info("exs_adxl34x", string.format("量程切换为 %s", str))
end

--[[
切换输出数据速率
@api exs_adxl34x.set_odr(hz)
@number hz 0.78~3200
]]
function exs_adxl34x.set_odr(hz)
    if not g_ready then
        log.error("exs_adxl34x.set_odr 请先 setup()"); return
    end
    local odr_reg, actual_odr = odr_to_reg(hz)
    if not reg_write(REG_BW_RATE, odr_reg) then return end
    log.info("exs_adxl34x", string.format("输出速率切换为 %dHz", actual_odr))
end

--[[
配置中断事件
@api exs_adxl34x.int_config(int, config)
@string int "int1" 或 "int2"
@table  config 事件配置
]]
function exs_adxl34x.int_config(int, config)
    if not g_ready then
        log.error("exs_adxl34x.int_config 请先 setup()"); return
    end
    if type(int) ~= "string" or type(config) ~= "table" then
        log.error("exs_adxl34x.int_config 参数错误"); return
    end
    local int_enable = event_table_to_mask(config)
    if int_enable == 0 then
        log.warn("exs_adxl34x.int_config 未指定事件"); return
    end
    local is_int2 = (int == "int2")
    reg_write(REG_INT_ENABLE, 0x00); sys.wait(5)
    local cur_map = (reg_read(REG_INT_MAP, 1) or {})[1] or 0
    if is_int2 then
        cur_map = cur_map | int_enable
    else
        cur_map = cur_map & (~int_enable)
    end
    reg_write(REG_INT_MAP, cur_map); sys.wait(5)
    local cur_en = (reg_read(REG_INT_ENABLE, 1) or {})[1] or 0
    cur_en = cur_en | int_enable
    reg_write(REG_INT_ENABLE, cur_en)
    log.info("exs_adxl34x", string.format("%s 中断已配置", int))
end

--[[
读取中断源
@api exs_adxl34x.get_int_source()
@return table or nil 事件名称数组
]]
function exs_adxl34x.get_int_source()
    if not g_ready then
        log.error("exs_adxl34x.get_int_source 请先 setup()"); return nil
    end
    local int_data = reg_read(REG_INT_SOURCE, 1)
    if not int_data or #int_data < 1 then return nil end
    local val = int_data[1]; local events = {}
    if val & INT_DATA_READY ~= 0 then table.insert(events, "data_ready") end
    if val & INT_SINGLE_TAP ~= 0 then table.insert(events, "single_tap") end
    if val & INT_DOUBLE_TAP ~= 0 then table.insert(events, "double_tap") end
    if val & INT_ACTIVITY ~= 0 then table.insert(events, "activity") end
    if val & INT_INACTIVITY ~= 0 then table.insert(events, "inactivity") end
    if val & INT_FREE_FALL ~= 0 then table.insert(events, "free_fall") end
    if val & INT_WATERMARK ~= 0 then table.insert(events, "watermark") end
    if val & INT_OVERRUN ~= 0 then table.insert(events, "overrun") end
    return events
end

--[[
进入待机模式（低功耗）
@api exs_adxl34x.sleep()
]]
function exs_adxl34x.sleep()
    if not g_ready then
        log.error("exs_adxl34x.sleep 请先 setup()"); return
    end
    reg_write(REG_POWER_CTL, 0x00)
    log.info("exs_adxl34x", "已进入待机模式")
end

--[[
从待机模式唤醒
@api exs_adxl34x.wakeup()
]]
function exs_adxl34x.wakeup()
    if not g_ready then
        log.error("exs_adxl34x.wakeup 请先 setup()"); return
    end
    reg_write(REG_POWER_CTL, PC_MEASURE)
    log.info("exs_adxl34x", "已从待机模式唤醒")
end

--[[
关闭传感器
@api exs_adxl34x.close()
]]
function exs_adxl34x.close()
    if not g_ready then return end
    reg_write(REG_POWER_CTL, 0x00)
    g_ready = false
    g_i2c_bus = 0
    g_is_soft = false
    g_scl_pin = nil; g_sda_pin = nil
    g_dev_addr = 0x53
    g_int1_cb = nil; g_int2_cb = nil
    log.info("exs_adxl34x", "传感器已关闭")
end

--[[
获取版本号
@api exs_adxl34x.version()
@return string
]]
function exs_adxl34x.version() return "202607170900" end

log.debug("exs_adxl34x", "version -> " .. exs_adxl34x.version())
return exs_adxl34x
