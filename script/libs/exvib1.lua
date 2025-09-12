--[[
@summary exvib1扩展库
@version 1.0
@date    2025.09.07
@author  孟伟
@usage
-- 应用场景
此库适用于滚珠震动传感器BL_2529,主要目的是对振动中断进行过滤，识别有效震动
对于一些震动传感器的中断管脚算法处理，也可以用做参考。

实现的功能：
1. GPIO 中断检测：通过 GPIO 引脚检测震动传感器产生的脉冲信号
2. 双重消抖机制：
  - io中断消抖  gpio.debounce()
3. 时间窗口检测：在指定时间窗口(time_window)内统计脉冲数量
4. 阈值触发：当脉冲数超过设定阈值(pulse_threshold)时触发回调
5. 脉冲超时机制：在检测状态下，如果超过pulse_timeout时间没有新的脉冲，则提前结束当前检测周期并判断是否触发回调

状态机工作流程：
- IDLE状态：等待第一个有效脉冲
- DETECTING状态：进入检测窗口，统计脉冲数量
- 触发条件：
时间窗口结束
脉冲空闲时间超过设定超时
- 结果判断：脉冲数≥阈值则调用用户回调

-- 用法实例
本扩展库对外提供了以下2个接口：
1）启动震动检测功能 exvib1.open(opts)
2）停止震动检测功能 exvib1.close()

--加载exvib1扩展库
local exvib1= require "exvib1"

-- 震动事件回调
local function vibration_cb(pulse_cnt)
    log.info("VIB", "detected! pulses =", pulse_cnt)
end
--演示最简单的使用方法，都使用默认配置
exvib1.open({
    gpio_pin = 24,
    on_event = vibration_cb,
})


以下为exvib1扩展库两个函数的详细说明及代码实现：
]]

local exvib1 = {}

-- 默认配置
local cfg = {
    gpio_pin        = nil, -- 传感器中断所接 GPIO
    pull            = gpio.PULLUP,
    trigger         = gpio.RISING,
    debounce_irq    = 100,  -- gpio消抖时间，gpio.debounce 时间(ms)
    time_window     = 1000, -- 检测窗口(ms)
    pulse_threshold = 3,    -- 触发阈值
    pulse_timeout   = 200,  -- 脉冲超时(ms)
    poll_interval   = 10,   -- 状态机轮询(ms)
    on_event        = nil,  -- 用户回调
}

-- 内部状态
local st = {
    pulse_cnt  = 0,
    last_valid = 0,
    detect_t0  = 0,
    state      = "IDLE",
}

-- 重置内部状态，将状态机置为空闲状态并清零脉冲计数
local function reset()
    st.state = "IDLE"
    st.pulse_cnt = 0
end

-- GPIO 中断处理函数，用于处理传感器的脉冲信号
local function isr()
    local now = mcu.ticks()
    st.pulse_cnt = st.pulse_cnt + 1
    st.last_valid = now
    -- 如果当前状态为空闲状态
    if st.state == "IDLE" then
        -- 切换到检测状态
        st.state = "DETECTING"
        -- 记录检测开始时间
        st.detect_t0 = now
    end
end

-- 状态机处理函数，用于检测是否满足震动触发条件
local function fsm()
    -- 如果当前状态不是检测状态，则直接返回
    if st.state ~= "DETECTING" then return end
    local now = mcu.ticks()
    -- 处理时间戳溢出情况
    if now < st.detect_t0 or now < st.last_valid then
        st.detect_t0 = 0
        st.last_valid = 0
        return -- 等待下次调用重新判断
    end

    -- 计算从检测开始到现在经过的时间
    local elapsed = now - st.detect_t0
    -- 判断是否脉冲空闲时间过长
    local idle_too_long = (now - st.last_valid) >= cfg.pulse_timeout
    -- 当检测窗口结束或者脉冲空闲时间过长时
    if elapsed >= cfg.time_window or idle_too_long then
        -- 检查脉冲计数是否达到触发阈值，并且用户回调函数存在
        if st.pulse_cnt >= cfg.pulse_threshold and st.on_event then
            -- 调用用户回调函数并传入脉冲计数值
            st.on_event(st.pulse_cnt)
        end
        -- 重置内部状态
        reset()
    end
end
--[[
启动震动检测功能
@api exvib1.open(opts)
@table opts 配置参数表，用于自定义震动检测功能的各项属性。
@return nil 无返回值
@usage
-- 配置参数介绍
--local otps = {
--    gpio_pin        --"传感器中断所接 GPIO 引脚号，默认值为 nil",
--    pull            --"上拉/下拉模式，可选 gpio.PULLUP 或 gpio.PULLDOWN，默认值为 gpio.PULLUP",
--    trigger         --"触发方式，可选 gpio.RISING 或 gpio.FALLING，默认值为 gpio.RISING",
--    debounce_irq    --"GPIO 消抖时间，单位为毫秒，默认值为 100",
--    time_window     --"检测窗口时间，单位为毫秒，默认值为 1000",
--    pulse_threshold --"触发阈值，即连续脉冲次数，默认值为 3",
--    pulse_timeout   --"脉冲超时时间，单位为毫秒，默认值为 200",
--    poll_interval   --"状态机轮询时间，单位为毫秒，默认值为 10",
--    on_event        --"用户回调函数，用于处理检测到的震动事件，默认值为 nil",
--}
-- 震动事件回调
local function vibration_cb(pulse_cnt)
    log.info("VIB", "detected! pulses =", pulse_cnt)
end
exvib1.open({
    gpio_pin = 24,
    on_event = vibration_cb,
})
--不同场景下的参数配置可参考下面的示例
--高灵敏度，响应快，误触可能高
exvib1.open({
    gpio_pin = 24,
    on_event = vibration_cb,
    time_window     = 300, -- 检测窗口(ms)
    pulse_threshold = 1,    -- 触发阈值
    pulse_timeout   = 100,  -- 脉冲超时(ms)
})
--默认配置，较高灵敏度
exvib1.open({
    gpio_pin = 24,
    on_event = vibration_cb,
    time_window     = 1000, -- 检测窗口(ms)
    pulse_threshold = 3,    -- 触发阈值
    pulse_timeout   = 200,  -- 脉冲超时(ms)
})

--中等灵敏度，
exvib1.open({
    gpio_pin = 24,
    on_event = vibration_cb,
    time_window     = 2000, -- 检测窗口(ms)
    pulse_threshold = 3,    -- 触发阈值
    pulse_timeout   = 300,  -- 脉冲超时(ms)
})
--低灵敏度，减少误报
exvib1.open({
    gpio_pin = 24,
    on_event = vibration_cb,
    time_window     = 3000, -- 检测窗口(ms)
    pulse_threshold = 10,    -- 触发阈值
    pulse_timeout   = 500,  -- 脉冲超时(ms)
})
]]
-- 启动震动检测功能
function exvib1.open(opts)
    -- 如果没有传入配置参数，则使用空表
    opts = opts or {}
    -- 用传入的配置参数更新默认配置
    for k, v in pairs(opts) do cfg[k] = v end
    -- 更新用户回调函数，如果传入了新的回调则使用新的，否则保持原有回调
    st.on_event = opts.on_event or st.on_event
    -- 配置 GPIO 消抖时间，设置中断处理函数、上拉模式和触发方式
    gpio.debounce(cfg.gpio_pin, cfg.debounce_irq)
    gpio.setup(cfg.gpio_pin, isr, cfg.pull, cfg.trigger)
    -- 启动定时器循环调用状态机处理函数
    sys.timerLoopStart(fsm, cfg.poll_interval)
    log.info("Vibration", "start on gpio", cfg.gpio_pin)
end

--[[
关闭震动检测功能
@api exvib1.close()
@return nil 无返回值
@usage
exvib1.close()  --关闭震动检测功能
--]]
function exvib1.close()
    -- 关闭 GPIO 引脚
    gpio.close(cfg.gpio_pin)
    -- 停止定时器
    sys.timerStop(fsm)
    reset()
end

return exvib1
