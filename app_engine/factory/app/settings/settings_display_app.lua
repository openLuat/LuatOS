--[[
@module  settings_display_app
@summary 显示与亮度业务逻辑层
@version 1.0
@date    2026.04.01
@author  江访
@usage
本模块为显示与亮度业务逻辑层，管理PWM背光亮度调节。提供亮度增减、设置、查询接口。
]]
-- ==================== 局部变量 ====================
local pwm_initialized = false  -- PWM 初始化标志
local current_brightness = 100    -- 当前亮度值 (10-100)

-- 从配置文件读取背光 PWM 参数（hw.lcd.backlight）
local pwm_channel, pwm_freq = 0, 1000
local cfg = _G.project_config
if cfg and cfg.hw and cfg.hw.lcd and cfg.hw.lcd.backlight then
    local bl = cfg.hw.lcd.backlight
    pwm_channel = bl.pwm_ch or 0
    pwm_freq = bl.pwm_freq or 1000
end

-- ==================== 内部函数 ====================
--[[
@function init_pwm
@summary 初始化背光 PWM
]]
local function init_pwm()
    if not pwm_initialized then
        local ok, err = pcall(pwm.setup, pwm_channel, pwm_freq, current_brightness)
        if not ok then
            log.error("settings_display", "PWM setup 失败:", err)
            return
        end
        ok, err = pcall(pwm.start, pwm_channel)
        if not ok then
            log.error("settings_display", "PWM start 失败:", err)
            return
        end
        pwm_initialized = true
        log.info("settings_display", "PWM 初始化完成，初始亮度: " .. current_brightness)
    end
end

--[[
@function set_brightness
@summary 设置背光亮度并上报变更事件
@param level 亮度值 (10-100)
]]
local function set_brightness(level)
    if not pwm_initialized then
        init_pwm()
    end
    if level < 10 then
        level = 10
    elseif level > 100 then
        level = 100
    end
    current_brightness = level
    local ok, err = pcall(pwm.setDuty, pwm_channel, level)
    if not ok then
        log.error("settings_display", "PWM setDuty 失败:", err)
    end
    log.info("settings_display", "亮度设置为: " .. level .. "%")
    -- 上报亮度变化事件
    sys.publish("DISPLAY_BRIGHTNESS_CHANGED", current_brightness)
end

-- ==================== 事件订阅 ====================
-- 订阅亮度增加事件
sys.subscribe("DISPLAY_BRIGHTNESS_INCREASE", function()
    local new_level = current_brightness + 10
    if new_level > 100 then
        new_level = 100
    end
    set_brightness(new_level)
end)

-- 订阅亮度减少事件
sys.subscribe("DISPLAY_BRIGHTNESS_DECREASE", function()
    local new_level = current_brightness - 10
    if new_level < 10 then
        new_level = 10
    end
    set_brightness(new_level)
end)

-- 订阅亮度设置事件（直接设置指定值）
sys.subscribe("DISPLAY_BRIGHTNESS_SET", function(level)
    if type(level) == "number" then
        set_brightness(level)
    end
end)

-- 订阅亮度查询事件（业务层上报当前值）
sys.subscribe("DISPLAY_BRIGHTNESS_GET", function()
    sys.publish("DISPLAY_BRIGHTNESS_VALUE", current_brightness)
end)
