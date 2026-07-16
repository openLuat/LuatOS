--[[
@module  exs_adxl34x
@summary ADXL345/ADXL346 三轴加速度传感器扩展库
@version 202607141200
@date    2026.07.14
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
7、exs_adxl34x.soft_reset()          软件复位
8、exs_adxl34x.version()             获取版本号

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

local MODE_I2C                        = 1
local DEV_ADDR_LOW                    = 0x53
local DEV_ADDR_HIGH                   = 0x1D
local REG_DEVID                       = 0x00
local REG_THRESH_TAP                  = 0x1D
local REG_OFSX                        = 0x1E;
local REG_OFSY                        = 0x1F;
local REG_OFSZ                        = 0x20
local REG_DUR                         = 0x21;
local REG_LATENT                      = 0x22;
local REG_WINDOW                      = 0x23
local REG_THRESH_ACT                  = 0x24;
local REG_THRESH_INACT                = 0x25;
local REG_TIME_INACT                  = 0x26
local REG_ACT_INACT_CTL               = 0x27
local REG_THRESH_FF                   = 0x28;
local REG_TIME_FF                     = 0x29
local REG_TAP_AXES                    = 0x2A;
local REG_ACT_TAP_STATUS              = 0x2B
local REG_BW_RATE                     = 0x2C;
local REG_POWER_CTL                   = 0x2D
local REG_INT_ENABLE                  = 0x2E;
local REG_INT_MAP                     = 0x2F;
local REG_INT_SOURCE                  = 0x30
local REG_DATA_FORMAT                 = 0x31
local REG_DATAX0                      = 0x32;
local REG_DATAX1                      = 0x33
local REG_DATAY0                      = 0x34;
local REG_DATAY1                      = 0x35
local REG_DATAZ0                      = 0x36;
local REG_DATAZ1                      = 0x37
local ADXL345_DEVID                   = 0xE5;
local ADXL346_DEVID                   = 0xE6
local DF_FULL_RES_BIT                 = 3
local INT_DATA_READY                  = 0x80;
local INT_SINGLE_TAP                  = 0x40;
local INT_DOUBLE_TAP                  = 0x20
local INT_ACTIVITY                    = 0x10;
local INT_INACTIVITY                  = 0x08;
local INT_FREE_FALL                   = 0x04
local INT_WATERMARK                   = 0x02;
local INT_OVERRUN                     = 0x01
local PC_MEASURE                      = 0x08
local RANGE_2G                        = 0x00;
local RANGE_4G                        = 0x01;
local RANGE_8G                        = 0x02;
local RANGE_16G                       = 0x03
local SENSITIVITY_2G                  = 256;
local SENSITIVITY_4G                  = 128;
local SENSITIVITY_8G                  = 64;
local SENSITIVITY_16G                 = 32
local ODR_0_1HZ                       = 0x00;
local ODR_0_2HZ                       = 0x01;
local ODR_0_39HZ                      = 0x02;
local ODR_0_78HZ                      = 0x03
local ODR_1_56HZ                      = 0x04;
local ODR_3_13HZ                      = 0x05;
local ODR_6_25HZ                      = 0x06;
local ODR_12_5HZ                      = 0x07
local ODR_25HZ                        = 0x08;
local ODR_50HZ                        = 0x09;
local ODR_100HZ                       = 0x0A;
local ODR_200HZ                       = 0x0B
local ODR_400HZ                       = 0x0C;
local ODR_800HZ                       = 0x0D;
local ODR_1600HZ                      = 0x0E;
local ODR_3200HZ                      = 0x0F

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

local function i2c_bus_recovery()
    if not g_scl_pin or not g_sda_pin then return end
    gpio.setup(g_scl_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    sys.wait(1)
    for i = 1, 9 do
        gpio.set(g_scl_pin, 0); sys.wait(1)
        gpio.set(g_scl_pin, 1); sys.wait(1)
    end
    gpio.set(g_sda_pin, 0); sys.wait(1)
    gpio.set(g_scl_pin, 1); sys.wait(1)
    gpio.set(g_sda_pin, 1); sys.wait(1)
end

-- ==================== 底层读写 ====================

local function i2c_write(reg, val) return i2c.send(g_i2c_bus, g_dev_addr, { reg, val }) end

local function i2c_read(reg, len)
    if not i2c.send(g_i2c_bus, g_dev_addr, { reg }) then return nil end
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

    -- 2. 配置中断相关寄存器（ACT_INACT_CTL / THRESH_FF / THRESH_TAP 等）
    --    这些寄存器必须在使能中断之前配置好
    if int_enable & (INT_ACTIVITY | INT_INACTIVITY) ~= 0 then
        local ctl = (reg_read(REG_ACT_INACT_CTL, 1) or {})[1] or 0
        if int_enable & INT_ACTIVITY ~= 0 then
            -- AC 耦合：以当前加速度为参考值，检测变化量，静止时不会误触发（推荐）
            -- DC 耦合：直接比较绝对加速度与阈值。Z 轴 1g 重力可能导致静止时持续触发
            -- 默认 AC 耦合（ACT_DC=1），可通过 act_dc = "DC" 切换为 DC 耦合
            if g_act_couple == "DC" then
                ctl = ctl & 0x7F                -- ACT_DC=0, DC coupled
            else
                ctl = ctl | 0x80                -- ACT_DC=1, AC coupled
            end
            ctl = ctl | 0x3C                    -- 使能 X/Y/Z 活动检测
            if (reg_read(REG_THRESH_ACT, 1) or {})[1] == 0 then
                reg_write(REG_THRESH_ACT, 0x05) -- 312mg (62.5mg/LSB × 5)
            end
        end
        if int_enable & INT_INACTIVITY ~= 0 then
            -- 默认 AC 耦合（INACT_DC=1），可通过 inact_dc = "DC" 切换
            if g_inact_couple == "DC" then
                ctl = ctl & 0xBF                  -- INACT_DC=0, DC coupled
            else
                ctl = ctl | 0x40                  -- INACT_DC=1, AC coupled
            end
            ctl = ctl | 0x03                      -- 使能 X/Y/Z 静止检测
            if (reg_read(REG_THRESH_INACT, 1) or {})[1] == 0 then
                reg_write(REG_THRESH_INACT, 0x03) -- 187mg (62.5mg/LSB × 3)
            end
            if (reg_read(REG_TIME_INACT, 1) or {})[1] == 0 then
                reg_write(REG_TIME_INACT, 4) -- 2 秒
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

I2C 模式参数：scl、sda、i2c_id
通用参数：range、odr、thresh_act、thresh_inact、time_inact
中断参数：

int1
INT1 中断配置表，包含 int_gpio 和事件 boolean：
  int_gpio - INT1 引脚 GPIO 编号
  data_ready - 数据就绪中断（注意：100Hz ODR 下每秒触发 100 次）
  activity - 活动检测中断
  inactivity - 静止检测中断
  free_fall - 自由落体检测中断
  tap - 敲击检测中断
  cb - 中断回调函数(data)，自动传入 {x,y,z}
数据类型：table
是否必选：可选
参数示例：{int_gpio = 10, data_ready = true, cb = adxl34x_cb}

int2
INT2 中断配置表，同 int1 格式

@return boolean
]]
function exs_adxl34x.setup(model, config)
    if type(model) ~= "string" or type(config) ~= "table" then
        log.error("exs_adxl34x.setup 参数错误"); return false
    end

    -- 通信初始化
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

    -- 配置参数
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

    -- 活动/静止阈值（优先应用用户配置，未配置则由 apply_int_config 使用默认值）
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

    -- 耦合模式
    if config.act_couple then
        if config.act_couple == "DC" then
            g_act_couple = "DC"
        else
            g_act_couple = "AC"
        end
    end
    if config.inact_couple then
        if config.inact_couple == "DC" then
            g_inact_couple = "DC"
        else
            g_inact_couple = "AC"
        end
    end

    -- 中断配置
    local int1_cfg, int2_cfg = nil, nil
    if config.int1 and type(config.int1) == "table" then
        int1_cfg = config.int1; g_int1_cb = config.int1.cb
    end
    if config.int2 and type(config.int2) == "table" then
        int2_cfg = config.int2; g_int2_cb = config.int2.cb
    end
    apply_int_config(int1_cfg, int2_cfg)

    -- GPIO 中断注册
    if config.int1 and type(config.int1) == "table" and config.int1.int_gpio then
        gpio.setup(config.int1.int_gpio, function()
            -- 先读取中断源清除芯片中断标志，再读取数据
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
    log.info("exs_adxl34x", string.format("初始化完成 mode=%s range=%s odr=%dHz",
        model, g_range, actual_odr))
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

运行时修改 INT1 或 INT2 的中断触发事件。
注意：
1、与 setup 中 int1/int2 的事件参数格式一致。
2、仅配置芯片内部中断映射和使能，不注册 GPIO 中断回调。
3、如需 GPIO 中断自动回调，请在 setup 中配置 int1/int2 参数。

@api exs_adxl34x.int_config(int, config)
@string int "int1" 或 "int2"
@table  config 事件配置，同 setup 中 int1/int2 的事件 boolean
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

    -- 关中断 → 改 map → 开中断
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

读取后自动清除中断标志。

@api exs_adxl34x.get_int_source()
@return table or nil 事件名称数组，如 {"data_ready"}
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
软件复位

@api exs_adxl34x.soft_reset()
]]
function exs_adxl34x.soft_reset()
    if not g_ready then
        log.error("exs_adxl34x.soft_reset 请先 setup()"); return
    end
    reg_write(REG_POWER_CTL, 0x00); sys.wait(10)
    reg_write(REG_POWER_CTL, PC_MEASURE); sys.wait(10)
    log.info("exs_adxl34x", "软件复位完成")
end

--[[
获取版本号

@api exs_adxl34x.version()
@return string
]]
function exs_adxl34x.version() return "202607141200" end

log.debug("exs_adxl34x", "version -> " .. exs_adxl34x.version())
return exs_adxl34x
