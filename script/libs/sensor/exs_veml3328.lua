--[[
@module  exs_veml3328
@summary VEML3328 RGBW颜色传感器驱动扩展库
@version 1.0
@date    2026.08.07
@author  沈园园
@usage
本扩展库提供 VEML3328 RGBW颜色传感器的 LuatOS 驱动，功能包括：
1、初始化（I2C地址校验/传感器配置加载/就绪确认）
2、数据读取（Red/Green/Blue/Clear/IR 五通道16位数据）
3、增益配置（Gain/DG双增益控制）
4、集成时间配置（50/100/200/400ms）
5、灵敏度配置（高/低）
6、电源管理（使能/禁用）

对外接口 8 个：
- exs_veml3328.setup(config)：初始化
- exs_veml3328.get_data()：读取RGBW+IR数据
- exs_veml3328.set_gain(gain)：设置增益
- exs_veml3328.set_dg(dg)：设置DG增益
- exs_veml3328.set_it(it)：设置集成时间
- exs_veml3328.set_sensitivity(sens)：设置灵敏度
- exs_veml3328.enable()/disable()：使能/禁用传感器
- exs_veml3328.get_config()：读取配置寄存器
- exs_veml3328.close()：释放资源
- exs_veml3328.version()：获取版本号

=== 版本更新说明 ===
-- 版本号：202608071000
-- 1、更新时间：2026-08-07
-- 2、更新内容：
--   - 正式发布版本
]]

-- ==================== 模块表 ====================
local exs_veml3328 = {}

-- ==================== 模块常量 ====================

-- I2C 地址
local DEV_ADDR = 0x10          -- VEML3328 固定 I2C 地址

-- 寄存器地址
local REG_CONF   = 0x00         -- 配置寄存器（16位）
local REG_CLEAR  = 0x04         -- Clear 数据（16位）
local REG_RED    = 0x05         -- Red 数据（16位）
local REG_GREEN  = 0x06         -- Green 数据（16位）
local REG_BLUE   = 0x07         -- Blue 数据（16位）
local REG_IR     = 0x08         -- IR 数据（16位）

-- 配置寄存器位域掩码
local BIT_SD1        = 0x8000  -- bit15: 第二级关机模式（1=禁用）
local BIT_DG_MASK    = 0x3000  -- bit12:11: DG 增益
local BIT_GAIN_MASK  = 0x0C00  -- bit10:8: Gain 增益
local BIT_SENSITIVITY= 0x0040  -- bit6: 灵敏度
local BIT_IT_MASK    = 0x0030  -- bit5:4: 集成时间
local BIT_TRIG       = 0x0004  -- bit2: 触发使能
local BIT_AF         = 0x0008  -- bit3: 自动/强制模式
local BIT_SD0        = 0x0001  -- bit0: 第一级关机模式

-- Gain 增益常量
local GAIN_05  = 0xC00         -- 0.5x (bit10=1, bit9=1, bit8=0)
local GAIN_1   = 0x000         -- 1x
local GAIN_2   = 0x400         -- 2x
local GAIN_4   = 0x800         -- 4x
local GAIN_12  = 0xC00         -- 12x (同0.5x)

-- DG 增益常量
local DG_1 = 0x000             -- 1x
local DG_2 = 0x1000            -- 2x
local DG_4 = 0x2000            -- 4x

-- 集成时间常量
local IT_50   = 0x00           -- 50ms
local IT_100  = 0x10           -- 100ms
local IT_200  = 0x20           -- 200ms
local IT_400  = 0x30           -- 400ms

-- ==================== 内部变量 ====================
local g_i2c_id    = nil        -- I2C 总线 id
local g_is_soft   = false      -- 是否软件 I2C
local g_scl_pin   = nil        -- SCL 引脚（总线恢复用）
local g_sda_pin   = nil        -- SDA 引脚（总线恢复用）
local g_i2c_speed = i2c.FAST   -- 保存原始 speed（总线恢复后恢复）
local g_dev_addr  = DEV_ADDR   -- 设备地址
local g_ready     = false      -- 是否已就绪
local g_config    = 0x0000     -- 当前配置寄存器缓存

-- ==================== I2C 操作 ====================

-- I2C 总线硬件恢复：9 个 SCL 脉冲 + STOP 信号
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

-- 检测总线是否卡死
-- 锁死判据：SDA=0, SCL=1（从机锁死 SDA）
-- 硬件 I2C 恢复后重新 setup；软件 I2C 恢复后重新 createSoft
local function try_bus_recovery()
    if not g_scl_pin or not g_sda_pin then return false end
    gpio.setup(g_sda_pin, gpio.INPUT, gpio.PULLUP)
    gpio.setup(g_scl_pin, gpio.INPUT, gpio.PULLUP); sys.wait(1)
    local is_stall = (gpio.get(g_sda_pin) == 0 and gpio.get(g_scl_pin) == 1)
    gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    gpio.setup(g_scl_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    if not is_stall then return false end  -- 总线未卡死，无需恢复
    log.warn("exs_veml3328", "检测到 I2C 总线卡死，尝试恢复")
    i2c_bus_recovery()
    if g_is_soft then
        -- 软件I2C：重新创建对象
        g_i2c_id = i2c.createSoft(g_scl_pin, g_sda_pin, 5)
    else
        -- 硬件I2C：恢复原始 speed
        i2c.setup(g_i2c_id, g_i2c_speed)
    end
    return true
end

-- 写16位寄存器：3字节格式 reg + low + high
-- VEML3328 接受3字节写入（第4字节0x00会导致NACK）
local function wr16(reg, val)
    local low  = val & 0xFF
    local high = (val >> 8) & 0xFF
    local ok = i2c.send(g_i2c_id, g_dev_addr, {reg, low, high})
    if not ok and try_bus_recovery() then
        ok = i2c.send(g_i2c_id, g_dev_addr, {reg, low, high})
    end
    return ok
end

-- 读16位寄存器：send(stop=0) + recv 实现Repeated Start
-- 软件 I2C 支持 stop=0 参数，硬件 I2C 会忽略此参数
-- 返回 16位数值，失败返回 nil
local function rd16(reg)
    -- 发送寄存器地址，stop=0 不发STOP（软件I2C生效）
    local ok = i2c.send(g_i2c_id, g_dev_addr, {reg}, 0)
    if not ok then
        if try_bus_recovery() then ok = i2c.send(g_i2c_id, g_dev_addr, {reg}, 0) end
        if not ok then return nil end
    end
    -- 接收2字节数据
    local d = i2c.recv(g_i2c_id, g_dev_addr, 2)
    if not d or #d < 2 then
        return nil
    end
    return d:byte(1) | (d:byte(2) << 8)
end

-- ==================== 内部函数 ====================

-- 更新配置寄存器
-- new_bits: 需要设置的位（OR 操作）
-- clear_bits: 需要清除的位（AND 操作的反）
local function update_config(new_bits, clear_bits)
    local conf = g_config
    if clear_bits then
        conf = conf & (~clear_bits)
    end
    if new_bits then
        conf = conf | new_bits
    end
    if not wr16(REG_CONF, conf) then
        log.error("exs_veml3328", "写配置寄存器失败")
        return false
    end
    g_config = conf
    return true
end

-- ==================== 对外 API ====================

--[[
初始化 VEML3328 传感器
@api exs_veml3328.setup(config)
@param table config
参数含义：配置参数表
数据类型：table
取值范围：
    {
        参数含义：I2C 总线 id
        数据类型：number
        取值范围：0 ~ 1，具体取决于硬件支持
        是否必选：否
        注意事项：仅传 i2c_id 时不具总线自动恢复能力
        参数示例：1
        config.i2c_id ,

        参数含义：软件 I2C SCL 引脚（传 scl+sda 时自动使用软件 I2C）
        数据类型：number
        取值范围：根据芯片 GPIO 引脚定义
        是否必选：否
        注意事项：与 sda 需同时传入
        参数示例：31
        config.scl ,

        参数含义：软件 I2C SDA 引脚
        数据类型：number
        取值范围：根据芯片 GPIO 引脚定义
        是否必选：否
        注意事项：与 scl 需同时传入
        参数示例：30
        config.sda ,

        参数含义：初始增益（Gain）
        数据类型：number
        取值范围：0.5（最低灵敏度）/ 1（默认，适合大多数场景）/ 2 / 4 / 12（最高灵敏度，适合低光场景）
        是否必选：否
        注意事项：增益越高测量范围越大但噪声也越大；建议默认使用 1x
        参数示例：1
        config.gain ,

        参数含义：初始 DG 增益
        数据类型：number
        取值范围：1（默认）/ 2 / 4
        是否必选：否
        注意事项：与 gain 叠加作用，总增益 = gain × dg；DG 4x 配合 Gain 12x 可达最高灵敏度
        参数示例：1
        config.dg ,

        参数含义：初始集成时间
        数据类型：number
        取值范围：50（最快，低精度）/ 100 / 200 / 400（最慢，高精度）
        是否必选：否
        注意事项：集成时间越长精度越高但响应越慢；默认 100ms 适合大多数场景
        参数示例：100
        config.it ,

        参数含义：初始灵敏度模式
        数据类型：string
        取值范围："high"（高灵敏度模式，适合低光）/ "low"（低灵敏度模式，适合强光）
        是否必选：否
        注意事项：默认 "high"
        参数示例："high"
        config.sensitivity ,
    }
是否必选：是
参数示例：
    -- 硬件 I2C 模式
    exs_veml3328.setup({i2c_id = 1})

    -- 软件 I2C 模式
    exs_veml3328.setup({scl = 31, sda = 30})
@return boolean
含义说明：初始化是否成功
数据类型：boolean
取值范围：true（成功），false（失败）
注意事项：失败时请检查接线和通信参数
返回示例：true
]]
function exs_veml3328.setup(config)
    if g_ready then
        log.warn("exs_veml3328", "已初始化，请勿重复调用")
        return true
    end

    -- 参数校验
    if type(config) ~= "table" then
        log.error("exs_veml3328", "参数错误：需要 table 类型")
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
        i2c.setup(g_i2c_id, i2c.FAST)
        g_is_soft = false
        g_i2c_speed = i2c.FAST
    end

    -- 设备探测
    local test = rd16(REG_CONF)
    if test == nil then
        log.error("exs_veml3328", "设备探测失败，请检查 I2C 接线")
        if not g_is_soft then i2c.close(g_i2c_id) end
        return false
    end

    log.info("exs_veml3328", string.format("设备探测成功，配置寄存器初始值: 0x%04X", test))

    -- 构建初始配置
    local conf = 0x0000

    -- 使能传感器（清除 SD0 和 SD1）
    conf = conf & ~BIT_SD0  -- SD0 = 0（使能）
    conf = conf & ~BIT_SD1  -- SD1 = 0（使能）

    -- 设置增益
    local gain = config.gain or 1
    if gain == 1 then
        conf = conf & ~BIT_GAIN_MASK  -- 清除增益位
        conf = conf | GAIN_1
    elseif gain == 2 then
        conf = conf & ~BIT_GAIN_MASK
        conf = conf | GAIN_2
    elseif gain == 4 then
        conf = conf & ~BIT_GAIN_MASK
        conf = conf | GAIN_4
    elseif gain == 12 then
        conf = conf & ~BIT_GAIN_MASK
        conf = conf | GAIN_12
    elseif gain == 0.5 then
        conf = conf & ~BIT_GAIN_MASK
        conf = conf | GAIN_05
    else
        log.warn("exs_veml3328", "未知增益 " .. tostring(gain) .. "，使用默认 1x")
        conf = conf & ~BIT_GAIN_MASK
        conf = conf | GAIN_1
    end

    -- 设置 DG 增益
    local dg = config.dg or 1
    if dg == 1 then
        conf = conf & ~BIT_DG_MASK
        conf = conf | DG_1
    elseif dg == 2 then
        conf = conf & ~BIT_DG_MASK
        conf = conf | DG_2
    elseif dg == 4 then
        conf = conf & ~BIT_DG_MASK
        conf = conf | DG_4
    else
        log.warn("exs_veml3328", "未知 DG 增益 " .. tostring(dg) .. "，使用默认 1x")
        conf = conf & ~BIT_DG_MASK
        conf = conf | DG_1
    end

    -- 设置集成时间
    local it = config.it or 100
    if it == 50 then
        conf = conf & ~BIT_IT_MASK
        conf = conf | IT_50
    elseif it == 100 then
        conf = conf & ~BIT_IT_MASK
        conf = conf | IT_100
    elseif it == 200 then
        conf = conf & ~BIT_IT_MASK
        conf = conf | IT_200
    elseif it == 400 then
        conf = conf & ~BIT_IT_MASK
        conf = conf | IT_400
    else
        log.warn("exs_veml3328", "未知集成时间 " .. tostring(it) .. "，使用默认 100ms")
        conf = conf & ~BIT_IT_MASK
        conf = conf | IT_100
    end

    -- 设置灵敏度
    local sens = config.sensitivity or "high"
    if sens == "low" then
        conf = conf | BIT_SENSITIVITY
    else
        conf = conf & ~BIT_SENSITIVITY
    end

    -- 写入配置
    if not wr16(REG_CONF, conf) then
        log.error("exs_veml3328", "配置写入失败")
        if not g_is_soft then i2c.close(g_i2c_id) end
        return false
    end

    g_config = conf

    -- 等待传感器稳定（最长 400ms 集成时间 + 余量）
    sys.wait(500)  -- 等待传感器上电稳定并完成首次测量

    g_ready = true
    log.info("exs_veml3328", "初始化完成")
    return true
end

--[[
读取 RGBW+IR 五通道数据
@api exs_veml3328.get_data()
@return table
含义说明：传感器测量数据
数据类型：table 或 nil
取值范围：
    data.red    - 红色通道原始值，范围 0~65535（16位）
    data.green  - 绿色通道原始值，范围 0~65535（16位）
    data.blue   - 蓝色通道原始值，范围 0~65535（16位）
    data.clear  - 清光通道原始值，范围 0~65535（16位）
    data.ir     - 红外通道原始值，范围 0~65535（16位）
注意事项：返回 nil 表示读取失败
返回示例：{red = 1234, green = 2345, blue = 3456, clear = 4567, ir = 567}
]]
function exs_veml3328.get_data()
    if not g_ready then
        log.error("exs_veml3328", "传感器未初始化")
        return nil
    end

    -- 依次读取五个通道
    local red   = rd16(REG_RED)
    local green = rd16(REG_GREEN)
    local blue  = rd16(REG_BLUE)
    local clear = rd16(REG_CLEAR)
    local ir    = rd16(REG_IR)

    -- 检查读取结果
    if red == nil or green == nil or blue == nil or clear == nil or ir == nil then
        log.error("exs_veml3328", "读取数据失败")
        return nil
    end

    return {
        red   = red,
        green = green,
        blue  = blue,
        clear = clear,
        ir    = ir
    }
end

--[[
设置增益（Gain）
@api exs_veml3328.set_gain(gain)
@param number gain
参数含义：增益倍数
数据类型：number
取值范围：0.5（最低灵敏度）/ 1（默认）/ 2 / 4 / 12（最高灵敏度）
是否必选：是
注意事项：增益越高灵敏度越高但噪声也越大；增益改变后需要等待新的集成周期
参数示例：2
@return boolean
含义说明：设置是否成功
数据类型：boolean
取值范围：true（成功），false（失败）
返回示例：true
]]
function exs_veml3328.set_gain(gain)
    if not g_ready then
        log.error("exs_veml3328", "传感器未初始化")
        return false
    end

    local new_gain
    if gain == 1 then
        new_gain = GAIN_1
    elseif gain == 2 then
        new_gain = GAIN_2
    elseif gain == 4 then
        new_gain = GAIN_4
    elseif gain == 12 then
        new_gain = GAIN_12
    elseif gain == 0.5 then
        new_gain = GAIN_05
    else
        log.warn("exs_veml3328", "未知增益 " .. tostring(gain) .. "，支持 0.5/1/2/4/12")
        return false
    end

    return update_config(new_gain, BIT_GAIN_MASK)
end

--[[
设置 DG 增益
@api exs_veml3328.set_dg(dg)
@param number dg
参数含义：DG 增益倍数
数据类型：number
取值范围：1（默认）/ 2 / 4
是否必选：是
注意事项：与 Gain 叠加作用，总增益 = gain × dg
参数示例：2
@return boolean
含义说明：设置是否成功
数据类型：boolean
取值范围：true（成功），false（失败）
返回示例：true
]]
function exs_veml3328.set_dg(dg)
    if not g_ready then
        log.error("exs_veml3328", "传感器未初始化")
        return false
    end

    local new_dg
    if dg == 1 then
        new_dg = DG_1
    elseif dg == 2 then
        new_dg = DG_2
    elseif dg == 4 then
        new_dg = DG_4
    else
        log.warn("exs_veml3328", "未知 DG 增益 " .. tostring(dg) .. "，支持 1/2/4")
        return false
    end

    return update_config(new_dg, BIT_DG_MASK)
end

--[[
设置集成时间
@api exs_veml3328.set_it(it)
@param number it
参数含义：集成时间，单位 ms
数据类型：number
取值范围：50（最快，低精度）/ 100 / 200 / 400（最慢，高精度）
是否必选：是
注意事项：集成时间越长精度越高但响应越慢
参数示例：200
@return boolean
含义说明：设置是否成功
数据类型：boolean
取值范围：true（成功），false（失败）
返回示例：true
]]
function exs_veml3328.set_it(it)
    if not g_ready then
        log.error("exs_veml3328", "传感器未初始化")
        return false
    end

    local new_it
    if it == 50 then
        new_it = IT_50
    elseif it == 100 then
        new_it = IT_100
    elseif it == 200 then
        new_it = IT_200
    elseif it == 400 then
        new_it = IT_400
    else
        log.warn("exs_veml3328", "未知集成时间 " .. tostring(it) .. "，支持 50/100/200/400")
        return false
    end

    return update_config(new_it, BIT_IT_MASK)
end

--[[
设置灵敏度模式
@api exs_veml3328.set_sensitivity(sens)
@param string sens
参数含义：灵敏度模式
数据类型：string
取值范围："high"（高灵敏度，适合低光）/ "low"（低灵敏度，适合强光）
是否必选：是
注意事项：高灵敏度模式下测量范围更大但噪声也更大
参数示例："low"
@return boolean
含义说明：设置是否成功
数据类型：boolean
取值范围：true（成功），false（失败）
返回示例：true
]]
function exs_veml3328.set_sensitivity(sens)
    if not g_ready then
        log.error("exs_veml3328", "传感器未初始化")
        return false
    end

    if sens == "low" then
        return update_config(BIT_SENSITIVITY, 0)
    elseif sens == "high" then
        return update_config(0, BIT_SENSITIVITY)
    else
        log.warn("exs_veml3328", "未知灵敏度模式 " .. tostring(sens) .. "，支持 high/low")
        return false
    end
end

--[[
使能传感器（退出关机模式）
@api exs_veml3328.enable()
@return boolean
含义说明：使能是否成功
数据类型：boolean
取值范围：true（成功），false（失败）
返回示例：true
]]
function exs_veml3328.enable()
    if not g_ready then
        log.error("exs_veml3328", "传感器未初始化")
        return false
    end

    -- 清除 SD0 和 SD1
    return update_config(0, BIT_SD0 | BIT_SD1)
end

--[[
禁用传感器（进入关机模式）
@api exs_veml3328.disable()
@return boolean
含义说明：禁用是否成功
数据类型：boolean
取值范围：true（成功），false（失败）
返回示例：true
]]
function exs_veml3328.disable()
    if not g_ready then
        log.error("exs_veml3328", "传感器未初始化")
        return false
    end

    -- 设置 SD0 和 SD1
    return update_config(BIT_SD0 | BIT_SD1, 0)
end

--[[
读取当前配置寄存器值
@api exs_veml3328.get_config()
@return number
含义说明：配置寄存器值（16位）
数据类型：number
取值范围：0x0000 ~ 0xFFFF
注意事项：返回 nil 表示读取失败
返回示例：0x1000
]]
function exs_veml3328.get_config()
    if not g_ready then
        log.error("exs_veml3328", "传感器未初始化")
        return nil
    end

    local val = rd16(REG_CONF)
    if val then g_config = val end
    return val
end

--[[
释放资源
@api exs_veml3328.close()
@return nil
含义说明：无返回值
注意事项：软件 I2C 无需手动关闭（gc 自动回收），硬件 I2C 会关闭总线
]]
function exs_veml3328.close()
    if g_ready then
        -- 禁用传感器（可选，降低功耗）
        -- update_config(BIT_SD0 | BIT_SD1, 0)
        g_ready = false
        g_config = 0x0000
        log.info("exs_veml3328", "资源已释放")
    end

    if not g_is_soft and g_i2c_id then
        i2c.close(g_i2c_id)
    end

    g_i2c_id = nil
    g_is_soft = false
    g_scl_pin = nil
    g_sda_pin = nil
end

--[[
获取扩展库版本号
@api exs_veml3328.version()
@return string
含义说明：版本号字符串
数据类型：string
取值范围："yyyymmddhhmm" 格式
返回示例："202608062000"
]]
function exs_veml3328.version()
    return "202608071000"
end

return exs_veml3328
