--[[
pwm_step_pulse —— PWM 多步脉冲(step pulse)演示

演示内容:
  1. pwm.open(ch, freq, duty, pnum) 单段定数脉冲, 输出指定个数后自动停止, 回调 EV_PULSE_DONE
  2. pwm.step_add + pwm.step_start 多步脉冲(加速-匀速-减速), 整组输出完回调 EV_STEP_DONE
  3. 同一组步骤重复 step_start(step_start 不清步骤)
  4. step_stop 中途停止

平台要求:
  - pwm.step_* 依赖 BSP 实现 luat_pwm_step_pulse_add/clear/start/stop 与 luat_pwm_set_isr_callback,
    目前仅 Air160X 系列(Air1601/Air1602 等)支持; 其它平台 step_add 直接返回 false,
    本 demo 会自动降级为 pnum 定数脉冲演示, 不会卡死
  - Air1601 可用通道: PWM1 / PWM3;  Air1602 可用通道: PWM1 / PWM2 / PWM3
  - PC 模拟器不支持(weak 实现直接返回 -1)

关键单位差异(容易踩坑):
  - pwm.open / pwm.setup / pwm.setDuty 的占空比基于 precision(默认 100), 50 表示 50%
  - pwm.step_add 的 duty 是千分比, 500 表示 50%
  - pwm.step_add 的 num 是脉冲个数, 不允许为 0

硬件连接: 示波器/逻辑分析仪接 PWM 通道对应的 GPIO, 详见同目录 readme.md
]]

PROJECT = "pwm_step_pulse"
VERSION = "1.0.0"

local TAG = "pwm_step"

-- LuaTools需要PROJECT和VERSION这两个信息
log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

-- ==================== 硬件配置 ====================
-- 默认用 PWM3: Air1601/Air1602 都可用, 且引脚复用明确(43脚/GPIO13)
-- 实测时按实际接线改这里
local PWM_CH = 3

do
    local bsp = rtos.bsp()
    local name = string.lower(tostring(bsp))
    if name:find("160") then
        PWM_CH = 3      -- Air160X 系列
    elseif name == "ec618" then
        PWM_CH = 4      -- 同 demo/pwm, GPIO27 / NetLed
    elseif name == "ec718" then
        PWM_CH = 2      -- 同 demo/pwm, GPIO25
    end
    log.info(TAG, "bsp", bsp, "pwm channel", PWM_CH)
end

-- ==================== 事件回调 ====================
local EVT_DONE = "PWM_PULSE_DONE"

local function on_pwm_event(channel, event, param)
    if event == pwm.EV_STEP_DONE then
        log.info(TAG, "事件 EV_STEP_DONE", channel)
    elseif event == pwm.EV_PULSE_DONE then
        log.info(TAG, "事件 EV_PULSE_DONE", channel)
    else
        log.warn(TAG, "事件 未知", channel, event)
    end
    sys.publish(EVT_DONE, channel, event)
end

if pwm.on then
    pwm.on(on_pwm_event)
else
    log.warn(TAG, "当前固件无 pwm.on, 事件完成通知不可用")
end

-- ==================== 工具函数 ====================
-- 指定频率下 num 个脉冲的理论耗时, 单位 ms
local function ms_of(freq, num)
    return math.ceil(num * 1000 / freq)
end

local function wait_done(tag, timeout)
    local ok, ch, ev = sys.waitUntil(EVT_DONE, timeout)
    if ok then
        log.info(TAG, tag, "完成", "ch" .. ch, "ev" .. ev, "上限" .. timeout .. "ms")
    else
        log.warn(TAG, tag, "等待完成事件超时", timeout .. "ms")
    end
    return ok
end

-- ==================== 1) 单段定数脉冲 ====================
local function demo_single_pulse()
    local freq, duty, num = 1000, 50, 20
    log.info(TAG, "===== 1) 单段定数脉冲", freq .. "Hz", "duty" .. duty .. "%", num .. "个")
    local ok = pwm.open(PWM_CH, freq, duty, num)
    log.info(TAG, "pwm.open ->", ok)
    if not ok then
        return false
    end
    wait_done("单段", ms_of(freq, num) + 500)
    pwm.close(PWM_CH)
    return true
end

-- ==================== 2/3) 多步脉冲 ====================
-- 模拟步进电机加减速: 低频起步 -> 匀速 -> 低频收尾
-- freq 单位 Hz, duty 单位千分之1, num 单位个
local STEP_TABLE = {
    { freq = 500,  duty = 500, num = 20 },  -- 起步
    { freq = 1000, duty = 500, num = 20 },
    { freq = 2000, duty = 500, num = 20 },
    { freq = 4000, duty = 500, num = 100 }, -- 匀速
    { freq = 2000, duty = 500, num = 20 },
    { freq = 1000, duty = 500, num = 20 },
    { freq = 500,  duty = 500, num = 20 },  -- 收尾
}

local function step_total()
    local ms, num = 0, 0
    for _, s in ipairs(STEP_TABLE) do
        ms = ms + ms_of(s.freq, s.num)
        num = num + s.num
    end
    return ms, num
end

-- 装载步骤: step_clear 后逐条 step_add
local function step_load()
    pwm.step_clear(PWM_CH)
    for i, s in ipairs(STEP_TABLE) do
        local ok = pwm.step_add(PWM_CH, s.freq, s.duty, s.num)
        log.info(TAG, string.format("  step_add #%d %dHz duty %d/1000 x %d -> %s",
            i, s.freq, s.duty, s.num, tostring(ok)))
        if not ok then
            return false
        end
    end
    return true
end

local function demo_step_pulse(title)
    local total_ms, total_num = step_total()
    log.info(TAG, "===== " .. title, "共" .. total_num .. "个脉冲, 理论" .. total_ms .. "ms")
    local ok = pwm.step_start(PWM_CH)
    log.info(TAG, "pwm.step_start ->", ok)
    if not ok then
        return false
    end
    return wait_done(title, total_ms + 500)
end

-- ==================== 4) 中途停止 ====================
local function demo_step_stop()
    log.info(TAG, "===== 4) step_stop 中途停止")
    pwm.step_clear(PWM_CH)
    pwm.step_add(PWM_CH, 1000, 500, 1000)   -- 1kHz x 1000 个 = 1s
    local ok = pwm.step_start(PWM_CH)
    log.info(TAG, "pwm.step_start ->", ok)
    sys.wait(200)
    local ret = pwm.step_stop(PWM_CH)
    log.info(TAG, "200ms 后 pwm.step_stop ->", ret)
    pwm.close(PWM_CH)
end

-- ==================== 主流程 ====================
sys.taskInit(function()
    sys.wait(1000)

    -- 能力探测: step_add 返回 false 说明当前 BSP 没实现 step pulse
    local probe = pwm.step_add(PWM_CH, 1000, 500, 10)
    pwm.step_clear(PWM_CH)
    log.info(TAG, "step pulse 能力探测(step_add) ->", probe)

    if not probe then
        log.warn(TAG, "当前 BSP 未实现 luat_pwm_step_pulse_*, 降级为单段定数脉冲演示")
        while 1 do
            demo_single_pulse()
            sys.wait(2000)
        end
    end

    while 1 do
        demo_single_pulse()
        sys.wait(500)

        -- 每轮重新装载步骤, 保证与上一轮 step_stop 清空的步骤不冲突
        if step_load() then
            -- 2) 首轮执行整组步骤
            demo_step_pulse("2) 多步脉冲(加速-匀速-减速)")
            sys.wait(500)
            -- 3) 不重新装载, 直接再启动, 验证步骤可重复使用
            demo_step_pulse("3) 同一组步骤重复启动")
            sys.wait(500)
        end

        demo_step_stop()
        sys.wait(3000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
