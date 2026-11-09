--[[
@module  servo_pulse
@summary 伺服「脉冲 + 方向」控制（PWM1 固定参数单次输出，GPIO9 给方向）
@version  4.0
@date    2026.11.05

本模块只负责三件事，全部由界面按钮调用：
  1. 方向脚输出高/低电平（gpio.set）
  2. PWM 启动：pwm.setup + pwm.start，脉冲个数由 pnum 交给硬件，发满自停
  3. PWM 停止：以 0% 占空比重配压停输出

PWM 参数固定（不提供频率/占空比设置）：
  频率 1 kHz，占空比 50%，脉冲个数由界面手动输入（0 = 连续输出）
  · 脉冲个数通过 pwm.setup 第 4 个参数（pnum）下发给硬件，实测有效：
    个数 > 0 时由 PWM 外设发满自停，没有任何软件定时器
  · 软件状态只由两个动作改变：点"启动"置运行态，点"停止"清运行态；
    硬件发满自停后软件仍视为运行中，必须先点"停止"才能再次启动

接口只使用：pwm.setup / pwm.start，每次调用前打印函数名和参数。
刻意不使用 pwm.stop：它会释放引脚（悬空后被 50MHz RGB 总线串成持续假脉冲，
且 V1028 上释放后 pwm.start 抢不回复用），"停止"改为以 0% 占空比重配实现（见 M.stop）。
]]
local M = {}

local conf = require "conf"
local P = conf.pulse
local D = conf.dir

-- 固定参数
local FREQ_HZ = 10000    -- 固定频率 10kHz
local DUTY    = 50      -- 固定占空比 50%

-- 当前状态（界面通过 snapshot() 读取）
local S = {
    dir_level  = 0,     -- 方向脚当前电平 0/1
    count      = conf.ui.count_default,  -- 目标脉冲个数（0 = 连续输出）
    running    = false,
    start_ms   = 0,
    elapsed_ms = 0,     -- 上一次运行的实际时长（停止后保留）
}

-- ==================== 内部工具 ====================

local function now_ms()
    if mcu and mcu.hz and mcu.ticks then
        local hz = mcu.hz()
        if hz and hz > 1 then
            return mcu.ticks() * 1000 // hz
        end
        return mcu.ticks()
    end
    return 0
end

-- ==================== 初始化 / 方向 ====================

--[[初始化：配置管脚复用与方向脚
上电驻留：脉冲脚以 0% 占空比挂到 PWM 上压成常量低电平，
避免上电到第一次启动之间引脚悬空被 50MHz RGB 总线串成假脉冲。]]
function M.init()
    if P.pin and pins and pins.setup then
        pcall(pins.setup, P.pin, P.pin_func)
    end
    -- PIN50 默认是 SPI1_CLK；AIR1603 V1028 没有 air1603 管脚表，
    -- pins.setup 会报"pin50不支持修改"，所以 conf.dir.pin 默认 nil，直接走 gpio 库
    if D.pin and pins and pins.setup then
        pcall(pins.setup, D.pin, D.pin_func)
    end

    gpio.setup(D.gpio, 1)
    gpio.set(D.gpio, 0)
    S.dir_level = 0

    -- 上电驻留（setup + start，0% = 常量低电平）
    log.info("pulse", string.format("call pwm.setup(%d, %d, %d) -- 驻留: 通道, 频率Hz, 占空比%%",
        P.pwm_ch, P.park_freq, 0))
    pwm.setup(P.pwm_ch, P.park_freq, 0)
    log.info("pulse", string.format("call pwm.start(%d) -- 驻留通道", P.pwm_ch))
    pwm.start(P.pwm_ch)

    log.info("pulse", string.format("就绪：脉冲 PWM%d(GPIO%d) 固定 %dHz/%d%%，目标个数 %d，方向 GPIO%d",
        P.pwm_ch, P.gpio, FREQ_HZ, DUTY, S.count, D.gpio))
    return true
end

--[[方向脚输出电平
@param level number 1=高电平 0=低电平
]]
function M.set_direction_level(level)
    level = (level and level ~= 0) and 1 or 0
    gpio.set(D.gpio, level)
    S.dir_level = level
    log.info("pulse", "方向 GPIO" .. D.gpio .. " -> " .. (level == 1 and "高电平" or "低电平"))
end

function M.direction_level()
    return S.dir_level
end

-- ==================== 参数设置 ====================

--[[脉冲个数，0 = 连续输出
个数恒为正数，不带方向含义（方向只由 GPIO9 决定）；小于 0 按 0 处理。
运行中修改不生效，下次启动按新值输出]]
function M.set_count(n)
    n = math.floor(n + 0.5)
    if n < 0 then n = 0 end
    if n > conf.ui.count_max then n = conf.ui.count_max end
    S.count = n
    log.info("pulse", "目标脉冲个数 -> " .. n)
    return n
end

function M.count()
    return S.count
end

-- ==================== 启停 ====================

--[[PWM 启动：setup（含 pnum）+ start，发满由硬件自停
@return boolean, string
]]
function M.start()
    -- 消抖：运行态下重复触发一律忽略，必须先点"PWM停止"
    if S.running then
        log.warn("pulse", "启动被忽略：输出进行中，请先点 PWM停止")
        return false, "输出进行中"
    end

    S.start_ms = now_ms()
    S.elapsed_ms = 0

    log.info("pulse", string.format("call pwm.setup(%d, %d, %d, %d) -- 通道, 频率Hz, 占空比%%, 脉冲个数",
        P.pwm_ch, FREQ_HZ, DUTY, S.count))
    if not pwm.setup(P.pwm_ch, FREQ_HZ, DUTY, S.count) then
        log.error("pulse", "pwm.setup 失败")
        return false, "pwm.setup 失败"
    end
    log.info("pulse", string.format("call pwm.start(%d) -- 通道", P.pwm_ch))
    if not pwm.start(P.pwm_ch) then
        log.error("pulse", "pwm.start 失败")
        return false, "pwm.start 失败"
    end
    S.running = true

    log.info("pulse", string.format("启动：%dHz 占空比%d%% 个数%s%s",
        FREQ_HZ, DUTY, S.count == 0 and "连续" or tostring(S.count),
        S.count > 0 and "（pnum 发满硬件自停）" or "（只能手动停止）"))
    return true
end

--[[PWM 停止：以 0% 占空比重配压停输出
注意：这里刻意不调 pwm.stop！
pwm.stop 会把引脚释放脱离 PWM 外设（V1028 上 pwm.start 无法把复用抢回，
实测），引脚就此悬空，被 50MHz RGB 总线持续串出假脉冲——表现为
"调了 stop，示波器反而一直在出脉冲"。
正确做法：通道自始至终由 PWM 持有，"停止"= 以 0% 占空比重配：
0% = 常量低电平，没有任何边沿，引脚也不悬空（v2.0 实测可靠路径）。]]
function M.stop(reason)
    log.info("pulse", string.format("call pwm.setup(%d, %d, %d) -- 停止=压0%%: 通道, 频率Hz, 占空比%%",
        P.pwm_ch, FREQ_HZ, 0))
    pwm.setup(P.pwm_ch, FREQ_HZ, 0)
    log.info("pulse", string.format("call pwm.start(%d) -- 应用 0%% 重配", P.pwm_ch))
    pwm.start(P.pwm_ch)
    if S.running then
        S.elapsed_ms = now_ms() - S.start_ms
        S.running = false
        log.info("pulse", string.format("停止(%s)：运行 %dms",
            tostring(reason or "手动"), S.elapsed_ms))
    else
        log.info("pulse", string.format("停止(%s)：已处于停止态", tostring(reason or "手动")))
    end
end

function M.is_running()
    return S.running
end

-- ==================== 界面读取 ====================

--[[取当前状态快照（界面刷新用）
@return table {dir_level, duty, period_us, freq, rpm, count, running, elapsed_ms}
]]
function M.snapshot()
    local now = now_ms()
    local elapsed = S.running and (now - S.start_ms) or S.elapsed_ms
    return {
        dir_level  = S.dir_level,
        duty       = DUTY,
        period_us  = 1000000 // FREQ_HZ,
        freq       = FREQ_HZ,
        rpm        = FREQ_HZ / conf.servo.pulses_per_rev * 60,
        count      = S.count,
        running    = S.running,
        elapsed_ms = elapsed,
    }
end

return M
