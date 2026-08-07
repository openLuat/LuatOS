--[[
@module  exs_opt3001
@summary OPT3001 数字环境光传感器驱动扩展库
@version 1.0
@date    2026.08.06
@author  沈园园
@usage
本扩展库提供 TI OPT3001 数字环境光传感器的 LuatOS 驱动，功能包括：
1、初始化（I2C 通信配置、厂商 ID/设备 ID 校验、默认配置加载）
2、数据读取（单次/连续测量模式、照度 lux 值计算）
3、阈值中断（上限/下限阈值设置与报警）
4、配置管理（测量模式、转换时间、满量程、中断极性等）
5、软件复位（恢复默认配置）

对外接口 9 个：
- exs_opt3001.setup(config)：初始化
- exs_opt3001.get_data()：读取数据
- exs_opt3001.close()：释放资源
- exs_opt3001.version()：获取版本号
- exs_opt3001.set_threshold(low, high)：设置阈值
- exs_opt3001.get_threshold()：读取阈值
- exs_opt3001.set_config(cfg)：配置参数
- exs_opt3001.get_config()：读取配置
- exs_opt3001.soft_reset()：软件复位

=== 版本更新说明 ===
-- 版本号：202608061000
-- 1、更新时间：2026-08-06
-- 2、更新内容：
--   - 正式发布版本
--   - 支持硬件 I2C 和软件 I2C
--   - 支持单次/连续测量模式
--   - 支持自动/手动满量程选择
--   - 支持阈值中断功能
--   - 支持 I2C 总线恢复（9 时钟脉冲 + SDA 释放检测）
--   - 支持 9 个对外接口（setup/get_data/close/version/set_threshold/get_threshold/set_config/get_config/soft_reset）
]]

-- ========== 模块表 ==========
local exs_opt3001 = {}

-- ========== 寄存器地址 ==========
local REG_RESULT       = 0x00   -- 结果寄存器（只读）
local REG_CONFIG       = 0x01   -- 配置寄存器（读写）
local REG_LOWLIMIT     = 0x02   -- 低限阈值寄存器（读写）
local REG_HIGHLIMIT    = 0x03   -- 高限阈值寄存器（读写）
local REG_MANUFACTURE  = 0x7E   -- 厂商 ID 寄存器（只读）
local REG_DEVICE       = 0x7F   -- 设备 ID 寄存器（只读）

-- ========== 常量定义 ==========
local DEV_ADDR_0       = 0x44   -- ADDR 接地时的 I2C 地址
local DEV_ADDR_1       = 0x45   -- ADDR 接 VDD 时的 I2C 地址
local MANUFACTURER_ID  = 0x5449 -- 厂商 ID 期望值
local DEVICE_ID        = 0x3001 -- 设备 ID 期望值
local DEFAULT_CONFIG   = 0xCC10 -- 默认配置（自动量程+800ms+连续+锁存）

-- ========== 内部状态 ==========
local g_i2c_id    = nil        -- I2C 总线 id
local g_is_soft   = false      -- 是否软件 I2C
local g_i2c_speed = i2c.FAST   -- 原始 I2C 速率
local g_dev_addr  = nil        -- 从设备地址
local g_scl_pin   = nil        -- SCL 引脚
local g_sda_pin   = nil        -- SDA 引脚
local g_int_gpio  = nil        -- 中断 GPIO ID
local g_ready     = false      -- 设备就绪标志
local g_mode      = "continuous" -- 当前测量模式
local g_ct        = 800        -- 当前转换时间
local g_range     = "auto"     -- 当前量程配置

-- ========== I2C 总线恢复 ==========

-- I2C 总线硬件恢复：9 个 SCL 脉冲 + 每脉冲检测 SDA 释放 + STOP 信号
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
-- 锁死判据：SDA=0, SCL=1（从机锁死 SDA）
-- 恢复后恢复硬件 I2C 原始 speed（g_i2c_speed）
local function try_bus_recovery()
    if not g_scl_pin or not g_sda_pin then return false end
    gpio.setup(g_sda_pin, gpio.INPUT, gpio.PULLUP)
    gpio.setup(g_scl_pin, gpio.INPUT, gpio.PULLUP); sys.wait(1)
    local is_stall = (gpio.get(g_sda_pin) == 0 and gpio.get(g_scl_pin) == 1)
    gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    gpio.setup(g_scl_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    if not is_stall then return false end  -- 总线未卡死，无需恢复
    log.warn("exs_opt3001", "检测到 I2C 总线卡死，尝试恢复")
    i2c_bus_recovery()
    if not g_is_soft then i2c.setup(g_i2c_id, g_i2c_speed) end  -- 恢复原始 speed
    return true
end

-- ========== I2C 底层操作 ==========

-- 写 16 位寄存器
-- reg: 寄存器地址，val: 16 位值，返回: boolean
local function wr16(reg, val)
    if not g_i2c_id or not g_dev_addr then
        log.error("exs_opt3001", "设备未初始化")
        return false
    end
    local h = (val >> 8) & 0xFF
    local l = val & 0xFF
    local ok = i2c.send(g_i2c_id, g_dev_addr, {reg, h, l})
    if not ok and try_bus_recovery() then
        ok = i2c.send(g_i2c_id, g_dev_addr, {reg, h, l})
    end
    if not ok then
        log.error("exs_opt3001", string.format("I2C 写入失败: reg=0x%02X", reg))
        return false
    end
    return true
end

-- 读 16 位寄存器
-- reg: 寄存器地址，返回: number 或 nil
local function rd16(reg)
    if not g_i2c_id or not g_dev_addr then
        log.error("exs_opt3001", "设备未初始化")
        return nil
    end
    if not i2c.send(g_i2c_id, g_dev_addr, {reg}) then
        if try_bus_recovery() then i2c.send(g_i2c_id, g_dev_addr, {reg}) end
        log.error("exs_opt3001", string.format("I2C 发送寄存器地址失败: reg=0x%02X", reg))
        return nil
    end
    local d = i2c.recv(g_i2c_id, g_dev_addr, 2)
    if not d or #d < 2 then
        log.error("exs_opt3001", "I2C 接收数据失败")
        return nil
    end
    return (d:byte(1) << 8) | d:byte(2)
end

-- ========== 配置寄存器解析与构建 ==========

-- 解析配置寄存器值为结构化数据
local function parse_config(config_val)
    local rn     = (config_val >> 12) & 0x0F
    local ct     = (config_val >> 11) & 0x01
    local mode   = (config_val >> 9) & 0x03
    local ovf    = (config_val >> 8) & 0x01
    local crf    = (config_val >> 7) & 0x01
    local fh     = (config_val >> 6) & 0x01
    local fl     = (config_val >> 5) & 0x01
    local latch  = (config_val >> 4) & 0x01
    local pol    = (config_val >> 3) & 0x01
    local mask   = (config_val >> 2) & 0x01
    local fc     = config_val & 0x03

    -- 量程名称
    local range
    if rn == 0xC then
        range = "auto"
    else
        local lut = {[0]=0.40,[1]=0.80,[2]=1.60,[3]=3.20,[4]=6.40,
                     [5]=12.80,[6]=25.60,[7]=51.20,[8]=102,[9]=204,
                     [0xA]=408,[0xB]=819}
        range = lut[rn] or "unknown"
    end

    -- 模式名称
    local mode_names = {[0]="shutdown",[1]="single",[2]="continuous",[3]="continuous"}
    -- 转换时间
    local ct_val = ct == 1 and 800 or 100
    -- 故障计数
    local fc_map = {[0]=1,[1]=2,[2]=4,[3]=8}

    return {
        mode        = mode_names[mode] or "unknown",
        ct          = ct_val,
        range       = range,
        overflow    = (ovf == 1),
        conv_ready  = (crf == 1),
        flag_high   = (fh == 1),
        flag_low    = (fl == 1),
        latch       = (latch == 1),
        polarity    = pol,
        mask_enable = (mask == 1),
        fault_count = fc_map[fc] or 1,
        raw         = config_val,
    }
end

-- 构建配置寄存器值
local function build_config(params)
    local val = 0

    -- 量程（0xC = 自动）
    local rn_bits = 0xC
    if params.range == "auto" or params.range == nil then
        rn_bits = 0xC
    elseif type(params.range) == "number" then
        local lut_rev = {[0.40]=0,[0.80]=1,[1.60]=2,[3.20]=3,[6.40]=4,
                         [12.80]=5,[25.60]=6,[51.20]=7,[102]=8,[204]=9,
                         [408]=0xA,[819]=0xB}
        local found = false
        for k, v in pairs(lut_rev) do
            if k == params.range then
                rn_bits = v
                found = true
                break
            end
        end
        if not found then
            log.warn("exs_opt3001", "无效的量程值，使用自动量程")
            rn_bits = 0xC
        end
    end
    val = val | (rn_bits << 12)

    -- 转换时间（1 = 800ms，0 = 100ms）
    local ct_bits = (params.ct == 100) and 0 or 1
    val = val | (ct_bits << 11)

    -- 工作模式（00=关断，01=单次，10=连续）
    local mode_bits
    if params.mode == "shutdown" then
        mode_bits = 0
    elseif params.mode == "single" then
        mode_bits = 1
    else
        mode_bits = 2
    end
    val = val | (mode_bits << 9)

    -- 锁存模式
    local latch_bits = (params.latch == false) and 0 or 1
    val = val | (latch_bits << 4)

    -- 中断极性
    local pol_bit = (params.polarity == 1) and 1 or 0
    val = val | (pol_bit << 3)

    -- 故障计数
    local fc_bits = 0
    local fc_val = params.fault_count or 1
    if fc_val == 2 then fc_bits = 1
    elseif fc_val == 4 then fc_bits = 2
    elseif fc_val == 8 then fc_bits = 3
    end
    val = val | fc_bits

    return val
end

-- ========== 照度计算 ==========

-- 将结果寄存器原始值转换为照度（lux）
-- 公式: lux = 0.01 × 2^E × R（来源：OPT3001 Datasheet Page 8）
local function calc_lux(raw)
    local exponent = (raw >> 12) & 0x0F
    local mantissa = raw & 0x0FFF
    return 0.01 * (2 ^ exponent) * mantissa
end

-- 将照度值转换为结果寄存器格式
-- 用 0.01 × 2^E × 4095 作为量程判据（实际物理最大值）
local function calc_raw(lux)
    if lux <= 0 then
        return 0
    end
    for e = 0, 11 do
        local max_lux = 0.01 * (2 ^ e) * 4095
        if lux <= max_lux then
            local mantissa = math.floor(lux / (0.01 * (2 ^ e)) + 0.5)
            if mantissa > 4095 then mantissa = 4095 end
            if mantissa < 1 then mantissa = 1 end
            return (e << 12) | mantissa
        end
    end
    -- 超出最大量程钳位
    local e = 11
    local mantissa = math.floor(lux / (0.01 * (2 ^ e)) + 0.5)
    if mantissa > 4095 then mantissa = 4095 end
    return (e << 12) | mantissa
end

-- ========== 中断处理 ==========

-- INT 引脚中断回调
-- OPT3001 INT 为开漏输出，默认低有效，使用下降沿触发
local function int_callback()
    if g_ready then
        sys.publish("exs_opt3001_INT")
    end
end

-- 配置中断 GPIO
-- OPT3001 INT 为开漏输出，默认低有效，使用下降沿触发
-- LuatOS GPIO 中断配置：gpio.setup(pin, callback, pull, irq_type)
local function setup_int_gpio(gpio_id)
    g_int_gpio = gpio_id
    gpio.setup(gpio_id, int_callback, gpio.PULLUP, gpio.FALLING)
    log.info("exs_opt3001", string.format("中断 GPIO 已配置: %d", gpio_id))
end

-- ========== 内部函数 ==========

-- 等待单次测量转换完成
-- timeout_ms：超时毫秒，默认 g_ct
-- 返回 true 就绪，false 超时
local function wait_conversion(timeout_ms)
    timeout_ms = timeout_ms or g_ct
    local elapsed = 0
    while elapsed < timeout_ms do
        sys.wait(1)     -- 每 1ms 轮询一次
        elapsed = elapsed + 1
        local cfg = rd16(REG_CONFIG)
        if cfg and (cfg & 0x80) ~= 0 then  -- CRF 位 7
            return true
        end
    end
    log.warn("exs_opt3001", string.format("转换超时 (%dms)", timeout_ms))
    return false
end

-- 触发单次测量
local function trigger_single_shot()
    local cfg_val = build_config({
        mode  = "single",
        ct    = g_ct,
        range = g_range,
    })
    if wr16(REG_CONFIG, cfg_val) then
        g_mode = "single"
        return true
    end
    return false
end

-- ========== 固定对外接口 ==========

--[[
初始化 OPT3001
@api exs_opt3001.setup(config)
@param table config
参数含义：初始化配置表
数据类型：table
字段说明：
  - i2c_id：I2C 总线 ID（number，硬件 I2C 必选）
  - scl：SCL 引脚号（number，软件 I2C 可选）
  - sda：SDA 引脚号（number，软件 I2C 可选）
  - addr：I2C 地址（number，默认 0x44）
  - int_gpio：中断 GPIO ID（number，可选）
  - mode：初始模式（string，可选，默认 "continuous"）
  - ct：转换时间（number，可选，100 或 800，默认 800）
  - range：量程（string/number，可选，默认 "auto"）
  - latch：锁存模式（boolean，可选，默认 true）
  - polarity：极性（number，可选，0/1，默认 0）
  - fault_count：故障计数（number，可选，1/2/4/8，默认 1）
是否必选：是
参数示例：{i2c_id = 1, int_gpio = 2}
@return boolean
含义说明：初始化是否成功
数据类型：boolean
]]
function exs_opt3001.setup(config)
    if type(config) ~= "table" then
        log.error("exs_opt3001", "config 参数必须为 table")
        return false
    end

    -- I2C 初始化
    if config.scl and config.sda then
        g_scl_pin = config.scl
        g_sda_pin = config.sda
        if config.i2c_id then
            i2c_bus_recovery()
            i2c.setup(config.i2c_id, i2c.FAST)
            g_i2c_id = config.i2c_id
            g_is_soft = false
            g_i2c_speed = i2c.FAST
        else
            i2c_bus_recovery()
            g_i2c_id = i2c.createSoft(config.scl, config.sda, 5)
            g_is_soft = true
        end
    else
        g_i2c_id = config.i2c_id or 0
        g_is_soft = false
        i2c.setup(g_i2c_id, i2c.FAST)
        g_i2c_speed = i2c.FAST
    end

    -- 设置从设备地址
    g_dev_addr = config.addr or DEV_ADDR_0

    -- 校验厂商 ID
    local mid = rd16(REG_MANUFACTURE)
    if mid ~= MANUFACTURER_ID then
        log.error("exs_opt3001", string.format("厂商 ID 校验失败: 期望 0x%04X 实际 0x%04X",
            MANUFACTURER_ID, mid or 0))
        return false
    end

    -- 校验设备 ID
    local did = rd16(REG_DEVICE)
    if did ~= DEVICE_ID then
        log.error("exs_opt3001", string.format("设备 ID 校验失败: 期望 0x%04X 实际 0x%04X",
            DEVICE_ID, did or 0))
        return false
    end

    -- 加载配置参数
    g_mode = config.mode or "continuous"
    g_ct = config.ct or 800
    g_range = config.range or "auto"

    -- 参数裁剪：无效值回退默认
    if g_ct ~= 100 and g_ct ~= 800 then
        log.warn("exs_opt3001", "转换时间无效，使用默认 800ms")
        g_ct = 800
    end
    if g_mode ~= "shutdown" and g_mode ~= "single" and g_mode ~= "continuous" then
        log.warn("exs_opt3001", "工作模式无效，使用默认 continuous")
        g_mode = "continuous"
    end

    -- 写入默认配置
    local cfg_table = {
        mode        = g_mode,
        ct          = g_ct,
        range       = g_range,
        latch       = config.latch,
        polarity    = config.polarity,
        fault_count = config.fault_count,
    }
    if not wr16(REG_CONFIG, build_config(cfg_table)) then
        log.error("exs_opt3001", "配置写入失败")
        return false
    end

    -- 配置中断 GPIO
    if config.int_gpio then
        setup_int_gpio(config.int_gpio)
    end

    g_ready = true
    log.info("exs_opt3001", string.format("初始化完成: i2c=%d addr=0x%02X", g_i2c_id, g_dev_addr))
    return true
end

--[[
读取环境光照度
@api exs_opt3001.get_data()
@return table/nil
含义说明：照度数据表
数据类型：table 或 nil
返回字段：lux(number) - 照度值(lux), raw(number) - 原始寄存器值, overflow(boolean) - 是否溢出
]]
function exs_opt3001.get_data()
    if not g_ready then
        log.error("exs_opt3001", "设备未初始化")
        return nil
    end

    -- 单次测量模式：触发转换并等待
    if g_mode == "single" then
        if not trigger_single_shot() then
            return nil
        end
        if not wait_conversion(g_ct + 50) then
            return nil
        end
    end

    -- 读取结果寄存器
    local raw = rd16(REG_RESULT)
    if raw == nil then
        return nil
    end

    local lux = calc_lux(raw)
    local exponent = (raw >> 12) & 0x0F
    local overflow = (exponent == 0x0F)

    return {
        lux      = lux,
        raw      = raw,
        overflow = overflow,
    }
end

--[[
释放资源
@api exs_opt3001.close()
]]
function exs_opt3001.close()
    if not g_ready then return end

    wr16(REG_CONFIG, 0x0000)  -- 关断模式

    if not g_is_soft and g_i2c_id then
        i2c.close(g_i2c_id)
    end

    if g_int_gpio then
        gpio.close(g_int_gpio)
        g_int_gpio = nil
    end

    g_i2c_id = nil
    g_is_soft = false
    g_dev_addr = nil
    g_scl_pin = nil
    g_sda_pin = nil
    g_ready = false
    g_mode = "continuous"
    g_ct = 800
    g_range = "auto"

    log.info("exs_opt3001", "资源已释放")
end

-- ========== 可选对外接口 ==========

--[[
设置照度阈值
@api exs_opt3001.set_threshold(low, high)
@param number low
参数含义：低限阈值（lux）
数据类型：number
取值范围：0.01 ~ 83865
是否必选：是
参数示例：10
@param number high
参数含义：高限阈值（lux）
数据类型：number
取值范围：0.01 ~ 83865
是否必选：是
参数示例：1000
@return boolean
]]
function exs_opt3001.set_threshold(low, high)
    if not g_ready then
        log.error("exs_opt3001", "设备未初始化")
        return false
    end
    if type(low) ~= "number" or type(high) ~= "number" then
        log.error("exs_opt3001", "阈值参数必须为 number")
        return false
    end
    if low >= high then
        log.error("exs_opt3001", "低限必须小于高限")
        return false
    end

    local low_raw = calc_raw(low)
    local high_raw = calc_raw(high)

    local ok1 = wr16(REG_LOWLIMIT, low_raw)
    local ok2 = wr16(REG_HIGHLIMIT, high_raw)

    if ok1 and ok2 then
        log.info("exs_opt3001", string.format("阈值已设置: low=%.2f high=%.2f", low, high))
        return true
    end
    return false
end

--[[
读取当前阈值
@api exs_opt3001.get_threshold()
@return table/nil
含义说明：当前阈值配置
数据类型：table 或 nil
返回字段：low(number) - 低限阈值(lux), high(number) - 高限阈值(lux)
]]
function exs_opt3001.get_threshold()
    if not g_ready then
        log.error("exs_opt3001", "设备未初始化")
        return nil
    end

    local low_raw = rd16(REG_LOWLIMIT)
    local high_raw = rd16(REG_HIGHLIMIT)
    if low_raw == nil or high_raw == nil then
        return nil
    end

    return {
        low  = calc_lux(low_raw),
        high = calc_lux(high_raw),
    }
end

--[[
配置测量参数
@api exs_opt3001.set_config(cfg)
@param table cfg
参数含义：配置参数表
数据类型：table
字段说明：mode/ct/range/latch/polarity/fault_count
@return boolean
]]
function exs_opt3001.set_config(cfg)
    if not g_ready then
        log.error("exs_opt3001", "设备未初始化")
        return false
    end
    if type(cfg) ~= "table" then
        log.error("exs_opt3001", "cfg 参数必须为 table")
        return false
    end

    local merged = {
        mode        = cfg.mode or g_mode,
        ct          = cfg.ct or g_ct,
        range       = cfg.range or g_range,
        latch       = cfg.latch,
        polarity    = cfg.polarity,
        fault_count = cfg.fault_count,
    }

    -- 参数裁剪：无效值回退默认
    if merged.ct ~= 100 and merged.ct ~= 800 then
        log.warn("exs_opt3001", "转换时间无效，使用默认 800ms")
        merged.ct = 800
    end
    if merged.mode ~= "shutdown" and merged.mode ~= "single" and merged.mode ~= "continuous" then
        log.warn("exs_opt3001", "工作模式无效，使用默认 continuous")
        merged.mode = "continuous"
    end

    local cfg_val = build_config(merged)
    if not wr16(REG_CONFIG, cfg_val) then
        return false
    end

    g_mode = merged.mode
    g_ct = merged.ct
    g_range = merged.range

    log.info("exs_opt3001", string.format("配置已更新: mode=%s ct=%dms", g_mode, g_ct))
    return true
end

--[[
读取当前配置
@api exs_opt3001.get_config()
@return table/nil
含义说明：当前配置与状态
数据类型：table 或 nil
返回字段：mode/ct/range/conv_ready/flag_high/flag_low/overflow/latch/polarity/fault_count/raw
]]
function exs_opt3001.get_config()
    if not g_ready then
        log.error("exs_opt3001", "设备未初始化")
        return nil
    end

    local val = rd16(REG_CONFIG)
    if val == nil then
        return nil
    end

    local parsed = parse_config(val)
    g_mode = parsed.mode
    g_ct = parsed.ct
    g_range = parsed.range

    return parsed
end

--[[
软件复位（关断后重配）
说明：OPT3001 无硬件复位寄存器，此函数通过关断后重配实现复位
@api exs_opt3001.soft_reset()
@return boolean
]]
function exs_opt3001.soft_reset()
    if not g_ready then
        log.error("exs_opt3001", "设备未初始化")
        return false
    end

    log.info("exs_opt3001", "执行软件复位...")

    wr16(REG_CONFIG, 0x0000)       -- 关断
    sys.wait(10)                   -- 等待关断生效

    local default_cfg = build_config({
        mode  = "continuous",
        ct    = 800,
        range = "auto",
    })
    if not wr16(REG_CONFIG, default_cfg) then
        return false
    end

    -- 清除阈值
    wr16(REG_LOWLIMIT, 0x0000)
    wr16(REG_HIGHLIMIT, 0xFFFF)

    g_mode = "continuous"
    g_ct = 800
    g_range = "auto"

    log.info("exs_opt3001", "软件复位完成")
    return true
end

-- ========== 版本信息 ==========

--[[
获取版本号
@api exs_opt3001.version()
@return string
含义说明：扩展库版本号
数据类型：string
]]
function exs_opt3001.version()
    return "202608061000"
end

return exs_opt3001