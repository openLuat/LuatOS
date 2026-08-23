--[[
@module  exs_vl6180x
@summary VL6180X 飞行时间(ToF)测距传感器扩展库
@version(0.1)
@date    2026.08.20
@author  江访
@usage
本扩展库提供 VL6180X（ST 出品）ToF 测距传感器的 LuatOS 驱动。

核心功能为：
1、初始化（Model ID 校验 -> 芯片寄存器配置加载 -> 就绪确认）
2、测距数据读取（0~255mm，含状态码）
3、测距状态查询
4、睡眠/唤醒/关闭

对外接口 7 个：
- exs_vl6180x.setup(config)：初始化传感器
- exs_vl6180x.get_range()：读取一帧测距数据（阻塞等待就绪）
- exs_vl6180x.get_range_status()：查询测距状态码
- exs_vl6180x.sleep()：停止测距（进入待机）
- exs_vl6180x.wakeup()：恢复测距
- exs_vl6180x.close()：关闭传感器
- exs_vl6180x.version()：获取版本号

-- 版本更新说明
-- 版本号：202608200000
-- 1、更新时间：2026-08-20
-- 2、更新内容：
--   - 移除 ALS 环境光读取功能（get_lux 及相关增益常量/寄存器）
--   - 仅保留测距功能（0~255mm）及测距状态查询、睡眠/唤醒/关闭
--   - 支持软件 I2C 和硬件 I2C 初始化
--   - 支持 I2C 总线卡死自动检测与恢复
]]

local exs_vl6180x = {}

-- ==================== 模块常量 ====================

-- I2C 设备地址
local DEV_ADDR = 0x29

-- 芯片标识寄存器
local REG_IDENTIFICATION_MODEL_ID          = 0x000  -- 应返回 0xB4
local MODEL_ID_VAL                         = 0xB4

-- 系统控制寄存器
local REG_SYSTEM_INTERRUPT_CONFIG          = 0x014  -- 中断配置
local REG_SYSTEM_INTERRUPT_CLEAR           = 0x015  -- 中断清除
local REG_SYSTEM_FRESH_OUT_OF_RESET        = 0x016  -- 冷启动标志
local REG_SYSRANGE_START                   = 0x018  -- 测距触发

-- 结果寄存器
local REG_RESULT_RANGE_STATUS              = 0x04D  -- bit[7:4]=error_code, bit[0]=device_ready
local REG_RESULT_INTERRUPT_STATUS_GPIO     = 0x04F  -- bit[2]=测距完成就绪
local REG_RESULT_RANGE_VAL                 = 0x062  -- 测距结果（mm，8-bit）

-- 中断清除值
local INT_CLEAR_ALL                        = 0x07  -- 清除所有中断

-- ==================== 错误码映射（来自 C++ 源码 VL6180X_ERROR_*）====================

local ERROR_NONE        = 0   -- 测距成功
local ERROR_SYSERR_1    = 1   -- 系统错误
local ERROR_SYSERR_5    = 5   -- 系统错误
local ERROR_ECEFAIL     = 6   -- 早期收敛估计失败
local ERROR_NOCONVERGE  = 7   -- 未检测到目标
local ERROR_RANGEIGNORE = 8   -- 忽略阈值检查失败
local ERROR_SNR         = 11  -- 环境光过强
local ERROR_RAWUFLOW    = 12  -- 原始测距值下溢
local ERROR_RAWOFLOW    = 13  -- 原始测距值上溢
local ERROR_RANGEUFLOW  = 14  -- 测距值下溢
local ERROR_RANGEOFLOW  = 15  -- 测距值上溢

local ERROR_LIST = {
    [ERROR_NONE]        = "测距成功",
    [ERROR_SYSERR_1]    = "系统错误(1)",
    [ERROR_SYSERR_5]    = "系统错误(5)",
    [ERROR_ECEFAIL]     = "早期收敛估计失败",
    [ERROR_NOCONVERGE]  = "未检测到目标",
    [ERROR_RANGEIGNORE] = "忽略阈值检查失败",
    [ERROR_SNR]         = "环境光过强",
    [ERROR_RAWUFLOW]    = "原始测距下溢",
    [ERROR_RAWOFLOW]    = "原始测距上溢",
    [ERROR_RANGEUFLOW]  = "测距值下溢",
    [ERROR_RANGEOFLOW]  = "测距值上溢",
}

-- ==================== 内部状态 ====================

local g_i2c_bus   = nil       -- I2C 总线 id
local g_is_soft   = false     -- 是否软件 I2C
local g_scl_pin   = nil       -- SCL 引脚（总线恢复用）
local g_sda_pin   = nil       -- SDA 引脚（总线恢复用）
local g_i2c_speed = i2c.SLOW  -- 保存原始 speed（总线恢复后恢复）
local g_ready     = false     -- 是否已就绪

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
    log.warn("exs_vl6180x", "检测到I2C总线卡死，尝试恢复")
    i2c_bus_recovery()
    if not g_is_soft then i2c.setup(g_i2c_bus, g_i2c_speed) end  -- 硬件 I2C 恢复后重新 setup 并恢复原始 speed
    return true
end

-- 写单字节寄存器（16-bit 寄存器地址）
local function wr8(reg, val)
    local h = (reg >> 8) & 0xFF; local l = reg & 0xFF
    local ok = i2c.send(g_i2c_bus, DEV_ADDR, {h, l, val})
    if not ok and try_bus_recovery() then
        ok = i2c.send(g_i2c_bus, DEV_ADDR, {h, l, val})
    end
    return ok
end

-- 写多字节（reg 为 16-bit 地址，data 为字节数组）
local function wr_multi(reg, data)
    local h = (reg >> 8) & 0xFF; local l = reg & 0xFF
    local buf = {h, l}
    for i = 1, #data do buf[#buf + 1] = data[i] end
    local ok = i2c.send(g_i2c_bus, DEV_ADDR, buf)
    if not ok and try_bus_recovery() then
        ok = i2c.send(g_i2c_bus, DEV_ADDR, buf)
    end
    return ok
end

-- 读单字节
local function rd8(reg)
    local h = (reg >> 8) & 0xFF; local l = reg & 0xFF
    local ok = i2c.send(g_i2c_bus, DEV_ADDR, {h, l})
    if not ok then
        if try_bus_recovery() then ok = i2c.send(g_i2c_bus, DEV_ADDR, {h, l}) end
        if not ok then return nil end
    end
    local d = i2c.recv(g_i2c_bus, DEV_ADDR, 1)
    if not d or #d < 1 then return nil end
    return d:byte(1)
end

-- ==================== 内部函数 ====================

-- 写入传感器寄存器配置（来自 C++ loadSettings 函数，app note page 24 + 公共寄存器）
-- 按"私有设置区 → 公共推荐区 → 公共可选区"顺序写入
local function load_settings()
    -- 私有设置（来自 app note page 24）
    wr8(0x0207, 0x01); wr8(0x0208, 0x01)
    wr8(0x0096, 0x00); wr8(0x0097, 0xFD)
    wr8(0x00E3, 0x00); wr8(0x00E4, 0x04); wr8(0x00E5, 0x02); wr8(0x00E6, 0x01)
    wr8(0x00E7, 0x03); wr8(0x00F5, 0x02)
    wr8(0x00D9, 0x05); wr8(0x00DB, 0xCE); wr8(0x00DC, 0x03); wr8(0x00DD, 0xF8)
    wr8(0x009F, 0x00); wr8(0x00A3, 0x3C)
    wr8(0x00B7, 0x00); wr8(0x00BB, 0x3C)
    wr8(0x00B2, 0x09); wr8(0x00CA, 0x09)
    wr8(0x0198, 0x01); wr8(0x01B0, 0x17); wr8(0x01AD, 0x00)
    wr8(0x00FF, 0x05); wr8(0x0100, 0x05); wr8(0x0199, 0x05)
    wr8(0x01A6, 0x1B); wr8(0x01AC, 0x3E); wr8(0x01A7, 0x1F)
    wr8(0x0030, 0x00)

    -- 推荐公共寄存器
    wr8(0x0011, 0x10)    -- 使能"新样本就绪"轮询（测量完成后自动置位）
    wr8(0x010A, 0x30)    -- 设置平均采样期（降噪与执行时间的折中）
    wr8(0x0031, 0xFF)    -- 自动校准间隔（每 255 次测距后执行）
    wr8(0x002E, 0x01)    -- 执行一次温度校准

    -- 可选公共寄存器
    wr8(0x001B, 0x09)    -- 测距间隔 100ms
    wr8(0x0014, 0x04)    -- 中断配置：测距新样本就绪触发
end

-- 等待测距就绪（来自 C++ readRange：轮询 RESULT_RANGE_STATUS.bit0）
-- timeout_ms：超时毫秒，默认 500ms
-- 返回 true 就绪，false 超时
local function wait_range_ready(timeout_ms)
    timeout_ms = timeout_ms or 500
    for i = 1, timeout_ms do
        local status = rd8(REG_RESULT_RANGE_STATUS)
        if status and (status & 0x01) == 0x01 then return true end  -- bit0=device_ready
        sys.wait(1)     -- 每 1ms 检测一次
    end
    log.warn("exs_vl6180x", "测距就绪超时")
    return false
end

-- 等待测距完成并获取结果（来自 C++ readRange 的完整流程）
-- 返回 range_mm 或 nil
local function do_range_measurement()
    -- 等待设备就绪
    if not wait_range_ready() then return nil end

    -- 触发测距
    wr8(REG_SYSRANGE_START, 0x01)

    -- 等待测距完成（poll until bit 2 set in INTERRUPT_STATUS_GPIO）
    for i = 1, 500 do
        local int_status = rd8(REG_RESULT_INTERRUPT_STATUS_GPIO)
        if int_status and (int_status & 0x04) ~= 0 then break end  -- bit2=测距完成
        sys.wait(1)     -- 每 1ms 检测一次
    end

    -- 读取测距值
    local range = rd8(REG_RESULT_RANGE_VAL)

    -- 清除中断
    wr8(REG_SYSTEM_INTERRUPT_CLEAR, INT_CLEAR_ALL)

    return range
end

-- ==================== 对外 API ====================

--[[
初始化传感器
@api exs_vl6180x.setup(config)
@param table config
参数含义：配置参数表
数据类型：table
取值范围：
{
    参数含义：I2C 总线 id（可选，与 scl/sda 配合使用参见说明）
    数据类型：number
    取值范围：0 ~ 1，具体取决于硬件支持
    是否必选：否
    注意事项：仅传 i2c_id 时不具总线自动恢复能力
    参数示例：0
    config.i2c_id ,

    参数含义：软件 I2C SCL 引脚
    数据类型：number
    取值范围：根据芯片 GPIO 引脚定义
    是否必选：否
    注意事项：与 sda 需同时传入；传 i2c_id+scl+sda 激活硬件 I2C+总线恢复
    参数示例：31
    config.scl ,

    参数含义：软件 I2C SDA 引脚
    数据类型：number
    取值范围：根据芯片 GPIO 引脚定义
    是否必选：否
    注意事项：与 scl 需同时传入
    参数示例：30
    config.sda ,
}
是否必选：是
参数示例：
    -- 硬件 I2C 模式
    exs_vl6180x.setup({i2c_id = 0})

    -- 软件 I2C 模式
    exs_vl6180x.setup({scl = 31, sda = 30})

    -- 硬件 I2C + 总线自动恢复
    exs_vl6180x.setup({i2c_id = 0, scl = 31, sda = 30})
@return boolean
含义说明：初始化是否成功
数据类型：boolean
取值范围：true（成功），false（失败）
注意事项：失败时请检查接线和I2C通信
]]
function exs_vl6180x.setup(config)
    if type(config) ~= "table" then
        log.error("exs_vl6180x.setup 参数错误")
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
                log.error("exs_vl6180x.setup 硬件 I2C 失败"); return false
            end
            g_i2c_bus = config.i2c_id; g_is_soft = false
        else
            i2c_bus_recovery()
            g_i2c_bus = i2c.createSoft(config.scl, config.sda, 5)
            if not g_i2c_bus then log.error("exs_vl6180x.setup 软件 I2C 失败"); return false end
            g_is_soft = true
        end
    else
        local id = config.i2c_id or 0
        if i2c.setup(id, i2c.SLOW) == 0 then
            log.error("exs_vl6180x.setup I2C 失败"); return false
        end
        g_i2c_bus = id; g_is_soft = false; g_scl_pin = nil; g_sda_pin = nil
    end

    -- 验证芯片标识：Model ID 须为 0xB4
    local model_id = rd8(REG_IDENTIFICATION_MODEL_ID)
    if model_id ~= MODEL_ID_VAL then
        log.error("exs_vl6180x", string.format("芯片识别失败：期望 0x%02X 实际 0x%02X",
            MODEL_ID_VAL, model_id or 0))
        return false
    end
    log.info("exs_vl6180x", string.format("芯片识别成功 Model ID=0x%02X", model_id))

    -- 加载传感器寄存器配置
    load_settings()

    -- 清除冷启动标志
    wr8(REG_SYSTEM_FRESH_OUT_OF_RESET, 0x00)

    g_ready = true
    log.info("exs_vl6180x", "初始化完成")
    return true
end

--[[
读取一帧测距数据（阻塞等待数据就绪）

注意事项：必须在 sys.taskInit() 创建的协程中调用（内部使用 sys.wait() 轮询等待就绪，在 task 外调用会报错）

@api exs_vl6180x.get_range()
@param none
@return table/nil
含义说明：测距数据表，失败返回 nil
数据类型：table 或 nil
取值范围：
    data.range_mm  - 距离值，单位 mm，范围 0~255
    data.status    - 测距状态码，0=成功，详见常量说明
    data.status_str - 状态码中文描述
]]
function exs_vl6180x.get_range()
    if not g_ready then log.error("exs_vl6180x.get_range 请先 setup()"); return nil end

    local range_mm = do_range_measurement()
    if not range_mm then
        log.warn("exs_vl6180x", "测距读取失败")
        return nil
    end

    -- 读取测距状态码（bit[7:4] 为 error_code）
    local status_val = rd8(REG_RESULT_RANGE_STATUS)
    local error_code = ERROR_NONE
    if status_val then
        error_code = (status_val >> 4) & 0x0F
    end

    local status_str = ERROR_LIST[error_code] or ("未知(" .. error_code .. ")")
    return {
        range_mm   = range_mm,
        status     = error_code,
        status_str = status_str,
    }
end

--[[
查询测距状态码（取最近一次测距的 error_code）
@api exs_vl6180x.get_range_status()
@param none
@return number/nil
含义说明：测距状态码
数据类型：number
取值范围：0（成功） / 1~15（错误码，详见常量说明）
]]
function exs_vl6180x.get_range_status()
    if not g_ready then return nil end
    local status = rd8(REG_RESULT_RANGE_STATUS)
    if not status then return nil end
    return (status >> 4) & 0x0F  -- bit[7:4] 为 error_code
end

--[[
进入软件待机（低功耗）

VL6180X 没有专用的睡眠模式寄存器，通过停止后续测量实现低功耗。
调用 wakeup() 可恢复测距，无需重新 setup()。

@api exs_vl6180x.sleep()

@return nil

@usage
exs_vl6180x.sleep()
]]
function exs_vl6180x.sleep()
    if not g_ready then return end
    -- VL6180X 没有专用的睡眠模式寄存器，通过停止后续测量实现低功耗
    log.info("exs_vl6180x", "已进入软件待机（停止后续测量）")
end

--[[
从软件待机唤醒

恢复传感器测距功能，无需重新 setup()。

@api exs_vl6180x.wakeup()

@return boolean
含义说明：唤醒是否成功
数据类型：boolean
取值范围：true（成功），false（未初始化）
]]
function exs_vl6180x.wakeup()
    if not g_ready then log.warn("exs_vl6180x.wakeup 未初始化，请先 setup()"); return false end
    log.info("exs_vl6180x", "已从软件待机唤醒")
    return true
end

--[[
关闭 VL6180X 传感器

重置内部状态，释放 I2C 资源。
close 后需要重新调用 setup() 才能再次使用。

@api exs_vl6180x.close()

@return nil

@usage
exs_vl6180x.close()
]]
function exs_vl6180x.close()
    if not g_ready then return end
    -- 软件 I2C 不需要手动关闭（gc 自动回收），硬件 I2C 需释放
    if not g_is_soft and g_i2c_bus then i2c.close(g_i2c_bus) end
    g_ready = false; g_i2c_bus = nil
    log.info("exs_vl6180x", "传感器已关闭")
end

--[[
获取 exs_vl6180x 库的版本号

@api exs_vl6180x.version()

@return string
含义说明：扩展库版本号
数据类型：string
取值范围：固定格式 "yyyymmddhhmm"
]]
function exs_vl6180x.version()
    return "202608200000"
end

-- ==================== 常量导出 ====================

exs_vl6180x.ERROR_NONE        = ERROR_NONE
exs_vl6180x.ERROR_SYSERR_1    = ERROR_SYSERR_1
exs_vl6180x.ERROR_SYSERR_5    = ERROR_SYSERR_5
exs_vl6180x.ERROR_ECEFAIL     = ERROR_ECEFAIL
exs_vl6180x.ERROR_NOCONVERGE  = ERROR_NOCONVERGE
exs_vl6180x.ERROR_RANGEIGNORE = ERROR_RANGEIGNORE
exs_vl6180x.ERROR_SNR         = ERROR_SNR
exs_vl6180x.ERROR_RAWUFLOW    = ERROR_RAWUFLOW
exs_vl6180x.ERROR_RAWOFLOW    = ERROR_RAWOFLOW
exs_vl6180x.ERROR_RANGEUFLOW  = ERROR_RANGEUFLOW
exs_vl6180x.ERROR_RANGEOFLOW  = ERROR_RANGEOFLOW

return exs_vl6180x
