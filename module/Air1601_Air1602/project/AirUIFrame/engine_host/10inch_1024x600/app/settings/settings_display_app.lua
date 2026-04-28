--[[
@module  settings_display_app
@summary 显示与亮度业务逻辑层
@version 1.0
@date    2026.04.01
@author  LuatOS
]]

-- ==================== 局部变量 ====================
local pwm_initialized = false  -- PWM 初始化标志
local current_brightness = 100 -- 当前亮度值 (10-100)
local PWM_CHANNEL = 0          -- PWM 通道
local PWM_FREQ = 10000         -- PWM 频率 10kHz

-- ==================== 内部函数 ====================

--[[
初始化 PWM
]]
local function init_pwm()
    if not pwm_initialized then
        pwm.setup(PWM_CHANNEL, PWM_FREQ, current_brightness)
        pwm.start(PWM_CHANNEL)
        pwm_initialized = true
        log.info("settings_display_app", "PWM 初始化完成，初始亮度: " .. current_brightness)
    end
end

--[[
设置亮度
@param level 亮度值 (10-100)
]]
local function set_brightness(level)
    if not pwm_initialized then
        init_pwm()
    end

    -- 限制范围
    if level < 10 then
        level = 10
    elseif level > 100 then
        level = 100
    end

    current_brightness = level
    pwm.setDuty(PWM_CHANNEL, level)
    log.info("settings_display_app", "亮度设置为: " .. level .. "%")

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

-- ==================== 开机自动初始化 ====================
sys.taskInit(init_pwm)

log.info("settings_display_app", "模块加载完成")
