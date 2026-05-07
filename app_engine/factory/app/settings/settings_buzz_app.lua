--[[
@module  settings_buzz_app
@summary 蜂鸣器(触摸反馈)业务逻辑层
@version 1.0
@date    2026.04.24
@author  江访
@usage
本模块为蜂鸣器(触摸反馈)业务逻辑层，管理PWM蜂鸣器的开关、发声时长、音量，订阅触摸事件驱动反馈。
]]

-- ==================== 配置常量 ====================
local CONFIG_KEYS = {
    ENABLED    = "buzzer_enabled",
    DURATION   = "buzzer_duration",
    VOLUME     = "buzzer_volume"
}

-- 默认值
local DEFAULT_ENABLED  = true
local DEFAULT_DURATION = 50
local DEFAULT_VOLUME   = 50

-- PWM 参数
local PWM_CHANNEL = 4
local PWM_FREQ    = 2700

-- ==================== 局部变量 ====================
local buzzer_enabled  = DEFAULT_ENABLED
local buzzer_duration = DEFAULT_DURATION  -- 20~500ms
local buzzer_volume   = DEFAULT_VOLUME    -- 10~100, 映射到占空比20%~50%

-- ==================== 工具函数 ====================

-- 音量值(10-100) 映射到占空比(20-50)
local function volume_to_duty(vol)
    vol = vol or buzzer_volume
    if vol < 10 then vol = 10 end
    if vol > 100 then vol = 100 end
    return 20 + (vol - 10) * (50 - 20) / (100 - 10)
end

-- ==================== PWM 控制 ====================

local function buzzer_on(duty)
    pwm.open(PWM_CHANNEL, PWM_FREQ, math.floor(duty))
end

local function buzzer_off()
    pwm.open(PWM_CHANNEL, PWM_FREQ, 0)
end

-- ==================== 触摸反馈处理 ====================

local touch_timer_id = nil

local function on_touch(state, x, y, track_id, timestamp)
    if not buzzer_enabled then
        return
    end
    if state == airui.TP_DOWN then
        local duty = volume_to_duty(buzzer_volume)
        buzzer_on(duty)
        if touch_timer_id then
            sys.timerStop(touch_timer_id)
        end
        touch_timer_id = sys.timerStart(function()
            buzzer_off()
            touch_timer_id = nil
        end, buzzer_duration)
    end
end

-- ==================== 外部接口 ====================

local function get_enabled()
    return buzzer_enabled
end

local function set_enabled(val)
    if buzzer_enabled == val then return end
    buzzer_enabled = val
    fskv.set(CONFIG_KEYS.ENABLED, val)
    sys.publish("BUZZER_ENABLED_CHANGED", val)
end

local function get_duration()
    return buzzer_duration
end

local function set_duration(val)
    val = tonumber(val) or DEFAULT_DURATION
    if val < 20 then val = 20 end
    if val > 500 then val = 500 end
    buzzer_duration = val
    fskv.set(CONFIG_KEYS.DURATION, val)
    sys.publish("BUZZER_DURATION_CHANGED", val)
end

local function get_volume()
    return buzzer_volume
end

local function set_volume(val)
    val = tonumber(val) or DEFAULT_VOLUME
    if val < 10 then val = 10 end
    if val > 100 then val = 100 end
    buzzer_volume = val
    fskv.set(CONFIG_KEYS.VOLUME, val)
    sys.publish("BUZZER_VOLUME_CHANGED", val)
end

-- ==================== 初始化 ====================

local function init()
    pwm.setup(PWM_CHANNEL, PWM_FREQ, 0)

    buzzer_enabled  = fskv.get(CONFIG_KEYS.ENABLED)
    if buzzer_enabled == nil then buzzer_enabled = DEFAULT_ENABLED end

    buzzer_duration = fskv.get(CONFIG_KEYS.DURATION)
    if buzzer_duration == nil then buzzer_duration = DEFAULT_DURATION end

    buzzer_volume   = fskv.get(CONFIG_KEYS.VOLUME)
    if buzzer_volume == nil then buzzer_volume = DEFAULT_VOLUME end

    -- 延迟注册触摸回调，等待tp_drv初始化完成
    sys.taskInit(function()
        sys.wait(500)
        airui.touch_subscribe(on_touch)
        log.info("settings_buzzer_app", "触摸回调注册完成")
    end)

    log.info("settings_buzzer_app", "初始化完成",
        "enabled:", buzzer_enabled,
        "duration:", buzzer_duration,
        "volume:", buzzer_volume)
end

sys.subscribe("SETTINGS_APP_INIT", init)

-- ==================== 事件订阅 ====================

sys.subscribe("BUZZER_GET_ENABLED", function()
    sys.publish("BUZZER_ENABLED_VALUE", buzzer_enabled)
end)

sys.subscribe("BUZZER_SET_ENABLED", function(val)
    set_enabled(val == true)
end)

sys.subscribe("BUZZER_GET_DURATION", function()
    sys.publish("BUZZER_DURATION_VALUE", buzzer_duration)
end)

sys.subscribe("BUZZER_SET_DURATION", function(val)
    set_duration(val)
end)

sys.subscribe("BUZZER_GET_VOLUME", function()
    sys.publish("BUZZER_VOLUME_VALUE", buzzer_volume)
end)

sys.subscribe("BUZZER_SET_VOLUME", function(val)
    set_volume(val)
end)

-- 播放一次测试音
sys.subscribe("BUZZER_PLAY_TEST", function()
    if not buzzer_enabled then return end
    local duty = volume_to_duty(buzzer_volume)
    buzzer_on(duty)
    sys.timerStart(function()
        buzzer_off()
    end, buzzer_duration)
end)

sys.subscribe("BUZZER_DURATION_DECREASE", function()
    set_duration(buzzer_duration - 10)
end)

sys.subscribe("BUZZER_DURATION_INCREASE", function()
    set_duration(buzzer_duration + 10)
end)

sys.subscribe("BUZZER_VOLUME_DECREASE", function()
    set_volume(buzzer_volume - 10)
end)

sys.subscribe("BUZZER_VOLUME_INCREASE", function()
    set_volume(buzzer_volume + 10)
end)

log.info("settings_buzzer_app", "模块加载完成")
