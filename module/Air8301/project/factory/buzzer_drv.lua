--[[
@module  buzzer_drv
@summary 蜂鸣器 PWM 驱动模块，PWM2/PIN98 唯一占用者（Air8301 出厂固件）
@version 1.0
@date    2026.10.08
@author  江访
@usage
本模块是蜂鸣器 PWM 通道 PWM2(PIN98) 的唯一占用者，其他模块一律不得再直接调用
pwm 接口（原 board_init 与 buzzer_app 各自 pwm.setup/close 抢占同一通道、
且频率不一致的问题在本次修改中收敛到本模块）。

对外接口：
1、buzzer_drv.init()                   ：引脚复用 + PWM 配置并启动，0% 占空比静音待命（require 即自动执行）
2、buzzer_drv.tone_on()                ：开声（占空比 50%）
3、buzzer_drv.tone_off()               ：静音（占空比 0%）
4、buzzer_drv.beep(ms, tag, wait_ms)   ：协程内发声 ms 毫秒，含扬声器占用互斥
5、buzzer_drv.beep_bg(ms)              ：非协程上下文（订阅回调/定时器）可用的定时关断提示音
6、buzzer_drv.lock(tag, wait_ms)       ：申请扬声器占用权
7、buzzer_drv.unlock(tag)              ：释放扬声器占用权
8、buzzer_drv.is_busy()                ：查询扬声器是否被占用

硬件说明（重要）：
本机蜂鸣器为【有源蜂鸣器】，自带振荡电路，只能"响/不响"，无法通过改变频率变调，
故 PWM 频率固定 2700Hz（沿用出厂产测频率），仅通过占空比 50%/0% 控制通断。
若后续硬件改为【无源蜂鸣器】，只需在本模块内改用 pwm.setFreq() 逐音符调频，
music 模块的曲谱与节拍逻辑无需任何改动即可演奏真实旋律。
]]

local buzzer_drv = {}

-- ==================== 硬件参数（PWM2/PIN98，硬件固定） ====================
local BUZZER_PIN       = 98
local BUZZER_PIN_FUNC  = "PWM2"
local BUZZER_PWM       = 2

-- 有源蜂鸣器只能通断，频率固定 2700Hz（与出厂产测一致）
local BUZZER_FREQ      = 2700
local BUZZER_PRECISION = 100   -- 分频精度 100，duty 数值即占空比百分比
local DUTY_ON          = 50    -- 50% 占空比，音量最大
local DUTY_OFF         = 0     -- 0% 占空比，静音

-- ==================== 内部状态 ====================
local inited   = false   -- PWM 通道是否已配置并启动
local owner    = nil     -- 扬声器占用者标记（nil=空闲；"key"/"test"/"music" 等为占用方标识）
local bg_timer = nil     -- 非阻塞提示音的关断定时器

--[[
初始化 PWM 通道（引脚复用 + 参数配置 + 启动），0% 占空比静音待命。
全程无阻塞调用，可安全在模块加载期执行；重复调用直接返回。

@local
@function do_init
]]
local function do_init()
    if inited then return end
    pins.setup(BUZZER_PIN, BUZZER_PIN_FUNC)
    pwm.setup(BUZZER_PWM, BUZZER_FREQ, DUTY_OFF, 0, BUZZER_PRECISION)
    pwm.start(BUZZER_PWM)
    inited = true
    log.info("buzzer_drv", "init done", BUZZER_PIN_FUNC, BUZZER_FREQ .. "Hz silent")
end

--[[
初始化蜂鸣器 PWM 通道（对外接口，require 时已自动调用）

@api buzzer_drv.init
]]
function buzzer_drv.init()
    do_init()
end

--[[
停止非阻塞提示音的关断定时器（若存在）

@local
@function stop_bg_timer
]]
local function stop_bg_timer()
    if bg_timer then
        sys.timerStop(bg_timer)
        bg_timer = nil
    end
end

--[[
非阻塞提示音的关断回调：静音并清除定时器句柄

@local
@function bg_stop
]]
local function bg_stop()
    bg_timer = nil
    pwm.setDuty(BUZZER_PWM, DUTY_OFF)
end

--[[
开声：占空比置 50%（会先取消未完成的非阻塞提示音，避免相互覆盖）

@api buzzer_drv.tone_on
]]
function buzzer_drv.tone_on()
    do_init()
    stop_bg_timer()
    pwm.setDuty(BUZZER_PWM, DUTY_ON)
end

--[[
静音：占空比置 0%

@api buzzer_drv.tone_off
]]
function buzzer_drv.tone_off()
    if not inited then return end
    stop_bg_timer()
    pwm.setDuty(BUZZER_PWM, DUTY_OFF)
end

--[[
申请扬声器占用权（协程内调用，忙时按 wait_ms 等待）

@api buzzer_drv.lock
@param string tag       占用者标识，用于同标记去重
@param number wait_ms   最大等待时长(ms)，默认 0（不等待，忙则立即失败）
@return boolean true=申请成功
]]
function buzzer_drv.lock(tag, wait_ms)
    do_init()
    wait_ms = wait_ms or 0
    local waited = 0
    while owner ~= nil do
        -- 同一占用者的重复请求直接丢弃（例如连点按键音）
        if owner == tag then return false end
        if waited >= wait_ms then return false end
        sys.wait(10)
        waited = waited + 10
    end
    owner = tag
    return true
end

--[[
释放扬声器占用权（仅释放自己的标记，避免误放他人）

@api buzzer_drv.unlock
@param string tag 占用者标识
]]
function buzzer_drv.unlock(tag)
    if owner == tag then owner = nil end
end

--[[
查询扬声器是否被占用

@api buzzer_drv.is_busy
@return boolean true=有模块正在发声
]]
function buzzer_drv.is_busy()
    return owner ~= nil
end

--[[
协程内发声：申请占用权 → 开声 → 等待 ms → 静音 → 释放占用权。
必须在协程中调用（内部含 sys.wait）。

@api buzzer_drv.beep
@param number ms        发声时长(ms)，默认 100
@param string tag       占用者标识，默认 "beep"
@param number wait_ms   忙时最大等待时长(ms)，默认 0（忙则丢弃本次发声）
@return boolean true=已发声；false=扬声器忙，本次丢弃
]]
function buzzer_drv.beep(ms, tag, wait_ms)
    ms  = ms or 100
    tag = tag or "beep"
    if not buzzer_drv.lock(tag, wait_ms) then
        log.warn("buzzer_drv", "busy, drop beep", tag, ms .. "ms")
        return false
    end
    buzzer_drv.tone_on()
    sys.wait(ms)
    buzzer_drv.tone_off()
    buzzer_drv.unlock(tag)
    return true
end

--[[
非阻塞提示音：开声后用定时器在 ms 毫秒后自动静音。
可在非协程上下文（sys.subscribe 回调、sys.timerStart 回调）中调用。
注意：本接口不参与占用互斥，仅用于恢复出厂设置等"简单提示"场景。

@api buzzer_drv.beep_bg
@param number ms 发声时长(ms)，默认 100
]]
function buzzer_drv.beep_bg(ms)
    ms = ms or 100
    do_init()
    stop_bg_timer()
    pwm.setDuty(BUZZER_PWM, DUTY_ON)
    bg_timer = sys.timerStart(bg_stop, ms)
end

-- require 即完成引脚复用与 PWM 配置（0% 占空比静音待命），后续发声只需切换占空比
do_init()

return buzzer_drv
