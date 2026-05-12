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
local DEFAULT_ENABLED = true
local DEFAULT_DURATION = 50
local DEFAULT_VOLUME = 50

-- PWM 参数
local PWM_CHANNEL = 4
local PWM_FREQ = 2700

-- ==================== 局部变量 ====================
local buzz_enabled  = DEFAULT_ENABLED
local buzz_duration  = DEFAULT_DURATION
local buzz_volume  = DEFAULT_VOLUME

-- ==================== 工具函数 ====================

-- 音量值(10-100) 映射到占空比(20-50)
local function volume_to_duty(volume)
    volume = volume or buzz_volume
    if volume < 10 then volume = 10 end
    if volume > 100 then volume = 100 end
    return 20 + (volume - 10) * (50 - 20) / (100 - 10)
end

-- ==================== PWM 控制 ====================

local function buzz_on(duty)
    pwm.open(PWM_CHANNEL, PWM_FREQ, math.floor(duty))
end

local function buzz_off()
    pwm.open(PWM_CHANNEL, PWM_FREQ, 0)
end

-- ==================== 触摸反馈处理 ====================

local touch_timer = nil

local function on_touch(state, x, y, track_id, timestamp)
    if not buzz_enabled then
        return
    end
    if state == airui.TP_DOWN then
        local duty = volume_to_duty(buzz_volume)
        buzz_on(duty)
        if touch_timer then
            sys.timerStop(touch_timer)
        end
        touch_timer = sys.timerStart(function()
            buzz_off()
            touch_timer = nil
        end, buzz_duration)
    end
end

-- ==================== 外部接口 ====================

local function get_enabled()
    return buzz_enabled
end

local function set_enabled(value)
    if buzz_enabled == value then return end
    buzz_enabled = value
    fskv.set(CONFIG_KEYS.ENABLED, value)
    sys.publish("BUZZER_ENABLED_CHANGED", value)
end

local function get_duration()
    return buzz_duration
end

local function set_duration(value)
    value = tonumber(value) or DEFAULT_DURATION
    if value < 20 then value = 20 end
    if value > 500 then value = 500 end
    buzz_duration = value
    fskv.set(CONFIG_KEYS.DURATION, value)
    sys.publish("BUZZER_DURATION_CHANGED", value)
end

local function get_volume()
    return buzz_volume
end

local function set_volume(value)
    value = tonumber(value) or DEFAULT_VOLUME
    if value < 10 then value = 10 end
    if value > 100 then value = 100 end
    buzz_volume = value
    fskv.set(CONFIG_KEYS.VOLUME, value)
    sys.publish("BUZZER_VOLUME_CHANGED", value)
end

-- ==================== 初始化 ====================

local function init()
    pwm.setup(PWM_CHANNEL, PWM_FREQ, 0)

    buzz_enabled  = fskv.get(CONFIG_KEYS.ENABLED)
    if buzz_enabled == nil then buzz_enabled = DEFAULT_ENABLED end

    buzz_duration = fskv.get(CONFIG_KEYS.DURATION)
    if buzz_duration == nil then buzz_duration = DEFAULT_DURATION end

    buzz_volume = fskv.get(CONFIG_KEYS.VOLUME)
    if buzz_volume == nil then buzz_volume = DEFAULT_VOLUME end

    -- 延迟注册触摸回调，等待tp_drv初始化完成
    sys.taskInit(function()
        sys.wait(500)
        airui.touch_subscribe(on_touch)
        log.info("settings_buzz", "触摸回调注册完成")
    end)

    log.info("settings_buzz", "初始化完成",
        "enabled:", buzz_enabled,
        "duration:", buzz_duration,
        "volume:", buzz_volume)
end

sys.subscribe("SETTINGS_APP_INIT", init)

-- ==================== 事件订阅 ====================

sys.subscribe("BUZZER_GET_ENABLED", function()
    sys.publish("BUZZER_ENABLED_VALUE", buzz_enabled)
end)

sys.subscribe("BUZZER_SET_ENABLED", function(value)
    set_enabled(value == true)
end)

sys.subscribe("BUZZER_GET_DURATION", function()
    sys.publish("BUZZER_DURATION_VALUE", buzz_duration)
end)

sys.subscribe("BUZZER_SET_DURATION", function(value)
    set_duration(value)
end)

sys.subscribe("BUZZER_GET_VOLUME", function()
    sys.publish("BUZZER_VOLUME_VALUE", buzz_volume)
end)

sys.subscribe("BUZZER_SET_VOLUME", function(value)
    set_volume(value)
end)

-- 播放一次测试音
sys.subscribe("BUZZER_PLAY_TEST", function()
    if not buzz_enabled then return end
    local duty = volume_to_duty(buzz_volume)
    buzz_on(duty)
    sys.timerStart(function()
        buzz_off()
    end, buzz_duration)
end)

sys.subscribe("BUZZER_DURATION_DECREASE", function()
    set_duration(buzz_duration - 10)
end)

sys.subscribe("BUZZER_DURATION_INCREASE", function()
    set_duration(buzz_duration + 10)
end)

sys.subscribe("BUZZER_VOLUME_DECREASE", function()
    set_volume(buzz_volume - 10)
end)

sys.subscribe("BUZZER_VOLUME_INCREASE", function()
    set_volume(buzz_volume + 10)
end)
