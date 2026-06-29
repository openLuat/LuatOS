--[[
@module  gsensor
@summary DA267三轴加速度传感器驱动（Air8201G 适配版，仅运动检测）
@version 2.1
@date    2026-05-27
@author  孟伟（重构自花生宠物 da267.lua 2.0，移除计步功能）
@usage
本模块基于花生宠物项目 da267.lua 2.0 重构，专用于 Air8201G 内置 DA267 加速度传感器。
适配本机硬件特性：
  - DA267 电源使能：GPIO24（高电平使能）
  - I2C 总线上拉使能：GPIO28（高电平使能）
  - DA267 INT 中断输入：GPIO20（推挽+高有效，上升沿触发）
  - I2C 总线：I2C1，地址 0x26（7-bit）

功能模块（仅震动检测，无计步）：
  - 震动触发 → 立即标记为运动中
  - 持续无震动超过 motion_timeout 秒 → 自动恢复为静止
  - 对外提供 is_moving() 接口供智能上报间隔调度使用
]]

local gsensor = {}

-- ========== I2C 配置 ==========
local I2C_ID         = 1
local DA267_ADDR     = 0x26

-- ========== 引脚配置 ==========
local INT_PIN        = 20    -- DA267 INT 输入
local POWER_EN_PIN   = 24    -- DA267 电源使能
local I2C_PU_EN_PIN  = 28    -- I2C 总线上拉使能

-- ========== 寄存器地址（仅保留震动检测相关） ==========
local REG = {
    WHO_AM_I  = 0x01,
    RANGE     = 0x0F,
    BW_ODR    = 0x10,
    MODE      = 0x11,
    INT_EN    = 0x16,
    INT_CFG   = 0x19,
    THS_X     = 0x39,
    THS_Y     = 0x3A,
    THS_Z     = 0x3B,
}

-- ========== 模块状态 ==========
local state = {
    initialized = false,
    -- 震动阈值：写入 DA267 的 THS_X/Y/Z 寄存器（0x39/0x3A/0x3B）
    -- 越小越敏感，越大越钝感。范围 1-255
    -- 历史版本：0x07（=7）过于敏感，轻微触碰即误触发
    -- 当前调为 0x20（=32），约 4.5 倍阈值，仅明显震动才触发
    -- 如仍嫌灵敏，可继续调大（如 0x40=64 / 0x80=128）
    sensitivity = 0x20,
    vibration_callback = nil,
    last_vibration_time = 0,
    -- 震动回调最小触发间隔(毫秒)：节流，避免短时间连续中断打爆业务
    -- 历史：2000ms；当前调为 3000ms 配合更钝感的阈值
    vibration_interval = 3000,

    is_moving = false,            -- 当前运动状态（true=运动中, false=静止）
    last_motion_time = 0,         -- 最后一次检测到震动的时间戳（秒）
    motion_timeout = 10,          -- 运动超时时间（秒）
}

-- ========== I2C 寄存器读写 ==========
local function write_reg(reg_addr, value)
    return i2c.send(I2C_ID, DA267_ADDR, {reg_addr, value}, 1)
end

local function read_reg(reg_addr, len)
    i2c.send(I2C_ID, DA267_ADDR, reg_addr, 1)
    return i2c.recv(I2C_ID, DA267_ADDR, len)
end

-- ========== DA267 寄存器初始化序列（仅震动检测） ==========
local function init_registers()
    write_reg(REG.RANGE, 0x01)         -- 量程 4g
    write_reg(REG.BW_ODR, 0x07)        -- 采样率
    write_reg(REG.INT_EN, 0x87)        -- 使能 XYZ 三轴活动中断
    write_reg(REG.THS_X, state.sensitivity)
    write_reg(REG.THS_Y, state.sensitivity)
    write_reg(REG.THS_Z, state.sensitivity)
    write_reg(REG.INT_CFG, 0x04)       -- 活动中断映射到 INT1
    write_reg(REG.MODE, 0x30)          -- 正常工作模式
end

-- ========== 中断处理函数 ==========
local function interrupt_handler()
    if not state.initialized then return end

    local now = os.time()

    -- 震动节流：最小触发间隔内不重复处理
    local last_time = state.last_vibration_time
    local interval = state.vibration_interval
    if now - last_time >= (interval / 1000) then
        state.last_vibration_time = now

        -- 运动状态切换
        if not state.is_moving then
            state.is_moving = true
            log.info("GSENSOR", "状态切换: 静止 → 运动中")
        end
        state.last_motion_time = now

        -- 外部震动回调
        if state.vibration_callback then
            state.vibration_callback()
        end
    end
end

-- ========== 本机硬件预初始化（电源 + I2C 上拉） ==========
-- Air8201G 本机硬件特殊要求：
--   ① 必须先 GPIO24 拉高给 DA267 上电
--   ② 必须 GPIO28 拉高使能 I2C 总线上拉
local function hw_power_on()
    gpio.setup(POWER_EN_PIN, 1, gpio.PULLUP)
    log.info("GSENSOR", "DA267 power on (GPIO" .. POWER_EN_PIN .. " HIGH)")
    sys.wait(50)    -- DA267 上电后等待芯片内部 POR 稳定（合宙官方建议 100ms 给传感器稳定）

    gpio.setup(I2C_PU_EN_PIN, 1, gpio.PULLUP)
    log.info("GSENSOR", "I2C bus pull-up enable (GPIO" .. I2C_PU_EN_PIN .. " HIGH)")
    sys.wait(150)   -- I2C 上拉电阻使能 + 总线稳定 + DA267 接口 ready（关键延时）
end

local function hw_power_off()
    gpio.setup(POWER_EN_PIN, 0)
    gpio.setup(I2C_PU_EN_PIN, 0)
    log.info("GSENSOR", "DA267 power off + I2C pull-up disable")
end

--[[
初始化 DA267 传感器
@return boolean 是否初始化成功
]]
function gsensor.init()
    if state.initialized then
        return true
    end

    log.info("GSENSOR", "Initializing DA267 (motion-only) ...")

    -- 1. 本机硬件预初始化（电源 + I2C 上拉）
    hw_power_on()

    -- 2. I2C 总线初始化
    i2c.close(I2C_ID)
    i2c.setup(I2C_ID, i2c.SLOW)

    -- 3. 设备 ID 验证（带重试：i2c -6 多由时序导致，重试通常可恢复）
    local data, chip_id
    local MAX_RETRY = 5
    for attempt = 1, MAX_RETRY do
        data = read_reg(REG.WHO_AM_I, 1)
        if data and #data > 0 then
            chip_id = string.byte(data, 1)
            if chip_id == 0x13 then
                log.info("GSENSOR", "DA267 验证成功 (第 " .. attempt .. " 次尝试, chipid=0x"
                                    .. string.format("%02X", chip_id) .. ")")
                break
            end
        end
        log.warn("GSENSOR", "DA267 验证失败 (第 " .. attempt .. "/" .. MAX_RETRY
                            .. " 次), chipid=" .. tostring(chip_id) .. ", 100ms 后重试")
        sys.wait(100)
    end
    if not data or string.byte(data, 1) ~= 0x13 then
        log.error("GSENSOR", "DA267 设备验证彻底失败（" .. MAX_RETRY .. " 次重试均失败），放弃初始化")
        hw_power_off()  -- 释放电源，避免空跑功耗
        return false
    end

    -- 4. 写入工作寄存器
    init_registers()

    -- 5. 配置中断引脚（标准 4 参签名：pin, callback, pull_mode, trigger_edge）
    --    PULLDOWN：悬空时拉低，避免误触发
    --    RISING：DA267 INT1 推挽+高有效，上升沿触发
    gpio.debounce(INT_PIN, 100)
    gpio.setup(INT_PIN, interrupt_handler, gpio.PULLDOWN, gpio.RISING)

    state.initialized = true
    state.last_vibration_time = os.time()
    log.info("GSENSOR", "DA267 初始化成功 chipid=0x13, INT=GPIO" .. INT_PIN)
    return true
end

--[[
关闭传感器
]]
function gsensor.close()
    if not state.initialized then return end

    gpio.close(INT_PIN)
    i2c.close(I2C_ID)
    hw_power_off()

    state.initialized = false
    log.info("GSENSOR", "DA267 已关闭")
end

--[[
设置震动回调函数
@param callback 回调函数，震动时触发
@param interval 触发间隔(毫秒)，默认 3000ms（钝感版）
]]
function gsensor.on_vibration(callback, interval)
    state.vibration_callback = callback
    if interval then
        state.vibration_interval = interval
    end
end

--[[
设置震动敏感度
@param level 敏感度等级 (1-255)，越小越敏感，默认 0x20=32（钝感版）
              推荐范围：
                0x10(=16)  灵敏（容易误触发，仅适合极静环境）
                0x20(=32)  当前默认（钝感平衡）
                0x40(=64)  更钝感（仅明显敲击/拍打才触发）
                0x80(=128) 极钝感（仅强烈震动才触发）
]]
function gsensor.set_sensitivity(level)
    if level then
        level = math.max(1, math.min(255, level))
    else
        level = state.sensitivity
    end

    state.sensitivity = level

    if state.initialized then
        write_reg(REG.THS_X, level)
        write_reg(REG.THS_Y, level)
        write_reg(REG.THS_Z, level)
    end

    log.info("GSENSOR", "敏感度设置为:", level)
    return level
end

--[[
获取当前是否处于运动状态
基于三轴加速度震动中断判断
- 震动触发 → 立即返回 true（运动中）
- 持续无震动超过 motion_timeout 秒 → 自动返回 false（静止恢复）
@return boolean true=运动中, false=静止
]]
function gsensor.is_moving()
    if not state.initialized then return false end

    if state.is_moving then
        local now = os.time()
        if now - state.last_motion_time >= state.motion_timeout then
            -- 超时无震动，自动恢复为静止
            state.is_moving = false
            log.info("GSENSOR", "状态切换: 运动中 → 静止（超时", state.motion_timeout, "秒无震动）")
        end
    end

    return state.is_moving
end

--[[
设置运动判定超时时间
@param timeout 超时时间（秒），默认 10 秒
]]
function gsensor.set_motion_timeout(timeout)
    if timeout and timeout > 0 then
        state.motion_timeout = timeout
        log.info("GSENSOR", "运动超时时间设置为:", timeout, "秒")
    end
end

--[[
强制设置运动状态（供测试或外部覆盖使用）
@param moving boolean 是否运动中
]]
function gsensor.set_motion_state(moving)
    state.is_moving = moving
    if moving then
        state.last_motion_time = os.time()
    end
    log.info("GSENSOR", "运动状态强制设置为:", moving and "运动中" or "静止")
end

--[[
获取最后一次震动时间戳（秒）
@return number 时间戳
]]
function gsensor.get_last_motion_time()
    return state.last_motion_time
end

--[[
获取传感器状态
@return table 状态信息
]]
function gsensor.get_status()
    return {
        initialized = state.initialized,
        sensitivity = state.sensitivity,
        is_moving = state.is_moving,
        last_motion_time = state.last_motion_time,
        motion_timeout = state.motion_timeout,
    }
end

return gsensor
