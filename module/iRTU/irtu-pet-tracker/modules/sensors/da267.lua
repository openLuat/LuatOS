--[[
@module da267
@summary DA267三轴加速度传感器驱动
@version 2.0
@date    2026-04-22
@author  孟伟
@usage
DA267传感器驱动，支持计步功能和震动检测
I2C地址: 0x26, I2C总线: 1

功能模块：
1. 震动检测（运动状态判断）：三轴加速度超过阈值触发中断，自动管理运动/静止状态切换
   - 震动触发 → 立即标记为运动中
   - 持续无震动超过 motion_timeout 秒 → 自动恢复为静止
   - 对外提供 is_moving() 接口供智能模式调度使用

2. 计步功能：硬件计步器，通过中断读取步数，带异常过滤
   - 步数仅用于统计上报服务器，不参与运动状态判断
]]

local da267 = {}

-- I2C配置
local I2C_ID = 1
local DA267_ADDR = 0x26

-- 引脚配置
local INT_PIN = 20
local POWER_PIN = 24     -- V_BCKP: DA267供电使能
local I2C1_PULLUP = 28   -- I2C1总线上拉（与NS2520共享，仅置高不置低）

-- 寄存器地址（严格对照数据手册）
local REG = {
    WHO_AM_I     = 0x01,
    STEPS_MSB    = 0x0D,
    STEPS_LSB    = 0x0E,
    RANGE        = 0x0F,
    BW_ODR       = 0x10,
    MODE         = 0x11,
    INT_EN       = 0x16,
    INT_CFG      = 0x19,
    STEP_FILTER  = 0x33,
    THS_X        = 0x39,
    THS_Y        = 0x3A,
    THS_Z        = 0x3B,
    RESET_STEP   = 0x2E,
}

-- 状态
local state = {
    initialized = false,
    hw_step = 0,
    valid_step = 0,
    last_valid_step = 0,
    max_step_per_read = 50,
    sensitivity = 0x07,
    step_callback = nil,
    vibration_callback = nil,
    last_vibration_time = 0,
    vibration_interval = 2000,

    is_moving = false,          -- 当前运动状态（true=运动中, false=静止）
    last_motion_time = 0,       -- 最后一次检测到震动的时间戳（秒）
    motion_timeout = 10,        -- 运动超时时间（秒），持续无震动超过此时间则判定为静止
    step_pending = false,       -- 是否有待读取的步数中断（不在ISR中读I2C）
}

-- 写寄存器
local function write_reg(reg_addr, value)
    return i2c.send(I2C_ID, DA267_ADDR, {reg_addr, value}, 1)
end

-- 读寄存器
local function read_reg(reg_addr, len)
    i2c.send(I2C_ID, DA267_ADDR, reg_addr, 1)
    return i2c.recv(I2C_ID, DA267_ADDR, len)
end

-- 初始化寄存器
local function init_registers()
    write_reg(REG.RANGE, 0x01)
    write_reg(REG.BW_ODR, 0x07)
    write_reg(REG.INT_EN, 0x87)
    write_reg(REG.THS_X, state.sensitivity)
    write_reg(REG.THS_Y, state.sensitivity)
    write_reg(REG.THS_Z, state.sensitivity)
    write_reg(REG.INT_CFG, 0x04)
    write_reg(REG.MODE, 0x30)
    write_reg(REG.STEP_FILTER, 0x80)
end

-- 中断处理函数（仅做轻量操作，禁止I2C阻塞读写）
local function interrupt_handler()
    if not state.initialized then return end

    local now = os.time()

    -- 震动检测 → 更新运动状态
    if state.vibration_callback then
        local last_time = state.last_vibration_time
        local interval = state.vibration_interval
        if now - last_time >= (interval / 1000) then
            state.last_vibration_time = now

            -- 运动状态管理：任何震动触发都标记为运动中
            if not state.is_moving then
                state.is_moving = true
                log.info("da267", "状态切换: 静止 → 运动中")
            end
            state.last_motion_time = now

            state.vibration_callback()
        end
    end

    -- 仅标记待读取，I2C读取挪到调用者任务上下文执行
    if gpio.get(INT_PIN) == 1 then
        state.step_pending = true
    end
end

-- 读取步数寄存器（在调用者任务上下文中执行，不在中断中调用）
local function read_steps_if_pending()
    if not state.step_pending then return end
    state.step_pending = false

    local data = read_reg(REG.STEPS_MSB, 2)
    if data and #data == 2 then
        local byte0 = string.byte(data, 1)
        local byte1 = string.byte(data, 2)

        local hw = (byte0 << 8) | byte1
        log.debug("da267", "reg0x0D:", byte0, "reg0x0E:", byte1, "步数:", hw)

        if hw < state.hw_step then
            log.warn("da267", "硬件计步器复位", hw, state.hw_step)
            state.hw_step = hw
            state.valid_step = hw
        else
            state.hw_step = hw
        end

        local step_diff = state.hw_step - state.valid_step
        if step_diff <= 0 then return end

        if step_diff <= state.max_step_per_read then
            state.valid_step = state.hw_step
            if state.step_callback then
                state.step_callback(state.valid_step)
            end
        else
            log.debug("da267", "过滤异常步数:", step_diff, "阈值:", state.max_step_per_read)
        end
    else
        log.error("da267", "读取计步数据失败")
    end
end

--[[
初始化DA267传感器
@return boolean 是否初始化成功
]]
function da267.init()
    if state.initialized then
        return true
    end

    -- 传感器供电使能：V_BCKP置高+I2C1上拉，等待电源稳定
    gpio.setup(POWER_PIN, 1)
    gpio.setup(I2C1_PULLUP, 1)
    sys.wait(50)

    i2c.close(I2C_ID)
    i2c.setup(I2C_ID, i2c.SLOW)
    
    local data = read_reg(REG.WHO_AM_I, 1)
    if not data or string.byte(data, 1) ~= 0x13 then
        log.error("da267", "设备验证失败")
        return false
    end

    -- 初始化前先彻底复位硬件计步器
    write_reg(REG.RESET_STEP, 0x01)
    sys.wait(10)
    write_reg(REG.STEP_FILTER, 0x25)
    sys.wait(10)

    init_registers()

    gpio.debounce(INT_PIN, 100)
    gpio.setup(INT_PIN, interrupt_handler)

    state.initialized = true
    state.last_vibration_time = os.time()
    log.info("da267", "初始化成功")
    return true
end

-- 休眠唤醒后恢复中断（内部接口，供 drv_lowpower 调用）
-- pm.power 期间 gpio.setup(WAKEUP3, ...) 会替换掉 da267 的原始中断 handler
function da267._restore_interrupt()
    if not state.initialized then return end
    -- 重新初始化 I2C（休眠期间 I2C 外设被关闭）
    i2c.close(I2C_ID)
    i2c.setup(I2C_ID, i2c.SLOW)
    -- 恢复 DA267 中断 handler
    gpio.debounce(INT_PIN, 100)
    gpio.setup(INT_PIN, interrupt_handler)
    -- 休眠期间可能有震动/计步，标记待读取
    state.step_pending = true
    log.info("da267", "中断已恢复")
end

--[[
关闭传感器
]]
function da267.close()
    if not state.initialized then return end

    gpio.setup(INT_PIN, 0)
    i2c.close(I2C_ID)

    -- 关闭DA267供电（I2C1上拉不关，NS2520可能还在用）
    gpio.setup(POWER_PIN, 0)

    state.initialized = false
    log.info("da267", "已关闭")
end

--[[
读取当前有效步数
@return number 当前总步数
]]
function da267.get_step_count()
    read_steps_if_pending()
    return state.valid_step
end

--[[
获取新增步数（自上次调用后）
@return number 新增步数
]]
function da267.get_new_steps()
    read_steps_if_pending()
    local new_steps = state.valid_step - state.last_valid_step
    state.last_valid_step = state.valid_step
    return new_steps
end

--[[
重置步数计数（彻底复位）
]]
function da267.reset_step_count()
    if state.initialized then
        write_reg(REG.RESET_STEP, 0x01)
        sys.wait(10)
        write_reg(REG.STEP_FILTER, 0x25)
        sys.wait(10)
        write_reg(REG.STEP_FILTER, 0x80)
        sys.wait(10)
    end
    state.hw_step = 0
    state.valid_step = 0
    state.last_valid_step = 0
    state.last_vibration_time = os.time()
    state.is_moving = false
    state.last_motion_time = 0
    log.info("da267", "步数和运动状态已重置")
end

--[[
设置步数回调函数
@param callback 回调函数，参数为当前总步数
]]
function da267.on_step(callback)
    state.step_callback = callback
end

--[[
设置震动回调函数
@param callback 回调函数，震动时触发
@param interval 触发间隔(毫秒)，默认2000ms
]]
function da267.on_vibration(callback, interval)
    state.vibration_callback = callback
    if interval then
        state.vibration_interval = interval
    end
end

--[[
设置震动敏感度
@param level 敏感度等级 (1-255)，越小越敏感，默认0x07
]]
function da267.set_sensitivity(level)
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

    log.info("da267", "敏感度设置为:", level)
    return level
end

--[[
设置单次读取最大允许步数增量
@param max 单次最大增量，默认10
]]
function da267.set_max_step_per_read(max)
    state.max_step_per_read = max or 10
    log.info("da267", "单次最大步数增量设置为:", state.max_step_per_read)
end

--[[
获取当前是否处于运动状态
基于三轴加速度震动中断判断，非步数判断
- 震动触发 → 立即返回 true（运动中）
- 持续无震动超过 motion_timeout 秒 → 自动返回 false（静止恢复）

@return boolean true=运动中, false=静止
]]
function da267.is_moving()
    if not state.initialized then return false end

    if state.is_moving then
        local now = os.time()
        if now - state.last_motion_time >= state.motion_timeout then
            -- 超时无震动，自动恢复为静止
            state.is_moving = false
            log.info("da267", "状态切换: 运动中 → 静止（超时", state.motion_timeout, "秒无震动）")
        end
    end

    return state.is_moving
end

--[[
设置运动判定超时时间
持续无震动超过此时间则认为从运动恢复为静止
@param timeout 超时时间（秒），默认10秒
]]
function da267.set_motion_timeout(timeout)
    if timeout and timeout > 0 then
        state.motion_timeout = timeout
        log.info("da267", "运动超时时间设置为:", timeout, "秒")
    end
end

--[[
强制设置运动状态（供测试或外部覆盖使用）
@param moving boolean 是否运动中
]]
function da267.set_motion_state(moving)
    state.is_moving = moving
    if moving then
        state.last_motion_time = os.time()
    end
    log.info("da267", "运动状态强制设置为:", moving and "运动中" or "静止")
end

--[[
获取传感器状态
@return table 状态信息
]]
function da267.get_status()
    return {
        initialized = state.initialized,
        step_count = state.valid_step,
        hw_step_count = state.hw_step,
        sensitivity = state.sensitivity,
        max_step_per_read = state.max_step_per_read,
        is_moving = state.is_moving,
        last_motion_time = state.last_motion_time,
        motion_timeout = state.motion_timeout,
    }
end

return da267
