-- DA221 运动检测模块（替代原 da267 计步+运动检测，DA221 仅支持运动检测）
-- 对外接口：
--   gsensor.init()              - 初始化（经 exvib 库配置 DA221，WAKEUP2 中断）
--   gsensor.on_vibration(cb,i)  - 注册震动回调（主循环用于发布 MOTION_EVENT）
--   gsensor.is_moving()         - 查询是否运动中（震动后 10s 内返回 true，超时恢复静止）
--   gsensor.set_motion_state(b) - 强制设置运动状态（低功耗震动唤醒时用）
local gsensor = {}

-- DA221 中断脚：WAKEUP2（需与硬件一致）
local INT_PIN = gpio.WAKEUP2

-- 模块状态
local state = {
    initialized = false,       -- 是否初始化完成
    vibration_callback = nil,  -- 震动回调（由主循环注册）
    last_vibration_time = 0,   -- 上次震动时间戳（用于 2000ms 限流）
    vibration_interval = 2000, -- 震动回调限流间隔(ms)：2秒内连续震动只算一次

    is_moving = false,         -- 当前是否运动中
    last_motion_time = 0,      -- 上次运动时间戳（用于超时恢复）
    motion_timeout = 10,       -- 运动超时(秒)：超过此时间无震动自动恢复静止
    pending_gps = false,       -- 震动唤醒待处理标志：置位后下一次上报强制走 GPS
}

local function interrupt_handler()
    if not state.initialized then return end

    local now = os.time()

    if state.vibration_callback then
        local last_time = state.last_vibration_time
        local interval = state.vibration_interval
        if now - last_time >= (interval / 1000) then
            state.last_vibration_time = now

            if not state.is_moving then
                state.is_moving = true
                log.info("gsensor", "状态切换: 静止 → 运动中")
            end
            state.last_motion_time = now

            -- 关键：震动唤醒后（可能刚从低功耗恢复）网络恢复需要时间，
            -- 必须延长运动有效期到60秒，否则 is_moving 会在等网络期间超时变 false，
            -- 导致智能模式震动上报走基站而非 GPS
            state.motion_timeout = 60
            -- 震动触发：标记待处理 GPS，确保本次上报走 GPS（不依赖 is_moving 时序）
            state.pending_gps = true

            state.vibration_callback()
        end
    end
end

function gsensor.init()
    if state.initialized then
        return true
    end

    -- 加载 DA221 驱动库（exvib），open(3)=高动态检测（8g量程，跌倒/剧烈震动检测）
    local ok, exvib = pcall(require, "exvib")
    if not ok or not exvib then
        log.error("gsensor", "加载 exvib 库失败")
        return false
    end

    -- open 内部为异步初始化（供电+I2C+寄存器），等待其完成后再配中断
    exvib.open(3)
    sys.wait(300)

    -- 配置 WAKEUP2 中断：震动时 DA221 INT 脚产生中断，进入 interrupt_handler
    gpio.debounce(INT_PIN, 100)
    gpio.setup(INT_PIN, interrupt_handler)

    state.initialized = true
    state.last_vibration_time = os.time()
    log.info("gsensor", "DA221 运动检测初始化成功")
    return true
end

-- 低功耗唤醒后恢复中断（drv_lowpower 调用），确保震动仍能触发
function gsensor._restore_interrupt()
    if not state.initialized then return end
    gpio.debounce(INT_PIN, 100)
    gpio.setup(INT_PIN, interrupt_handler)
    log.info("gsensor", "中断已恢复")
end

function gsensor.close()
    if not state.initialized then return end

    gpio.setup(INT_PIN, 0)
    local ok, exvib = pcall(require, "exvib")
    if ok and exvib and exvib.close then
        exvib.close()
    end

    state.initialized = false
    log.info("gsensor", "已关闭")
end

-- 注册震动回调：震动（过限流）时触发 cb，主循环用它发布 MOTION_EVENT
function gsensor.on_vibration(callback, interval)
    state.vibration_callback = callback
    if interval then
        state.vibration_interval = interval
    end
end

function gsensor.is_moving()
    if not state.initialized then return false end

    if state.is_moving then
        local now = os.time()
        if now - state.last_motion_time >= state.motion_timeout then
            state.is_moving = false
            log.info("gsensor", "状态切换: 运动中 → 静止（超时", state.motion_timeout, "秒无震动）")
        end
    end

    return state.is_moving
end

function gsensor.set_motion_timeout(timeout)
    if timeout and timeout > 0 then
        state.motion_timeout = timeout
        log.info("gsensor", "运动超时时间设置为:", timeout, "秒")
    end
end

function gsensor.set_motion_state(moving, timeout)
    state.is_moving = moving
    if moving then
        state.last_motion_time = os.time()
        if timeout and timeout > 0 then
            -- 临时延长运动有效期（如震动唤醒后网络恢复需要时间，默认10秒不够）
            state.motion_timeout = timeout
        end
        -- 震动唤醒：标记待处理 GPS（低功耗唤醒路径也强制本次上报走 GPS）
        state.pending_gps = true
    end
    log.info("gsensor", "运动状态强制设置为:", moving and "运动中" or "静止")
end

-- 消费待处理 GPS 标志：返回 true 表示本次上报应强制走 GPS（读取后清除）
function gsensor.consume_pending_gps()
    local pending = state.pending_gps
    state.pending_gps = false
    return pending
end

function gsensor.get_status()
    return {
        initialized = state.initialized,
        is_moving = state.is_moving,
        last_motion_time = state.last_motion_time,
        motion_timeout = state.motion_timeout,
    }
end

return gsensor
