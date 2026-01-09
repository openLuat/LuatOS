-- exlcd.lua
--[[
@module  exlcd
@summary LCD显示拓展库
@version 1.0.6
@date    2026.01.08
@author  江访
@usage
本文件为LCD显示拓展库，核心业务逻辑为：
1、初始化LCD显示屏，支持多种显示芯片
2、管理屏幕背光亮度及开关状态
3、提供屏幕状态管理功能
4、支持根据lcd_model自动配置参数

本文件的对外接口有6个：
1、exlcd.init(param)：LCD初始化函数
2、exlcd.set_bl(level)：设置背光亮度接口，level为亮度级别(0-100)
3、exlcd.get_bl()：当前设置背光亮度级别查询
4、exlcd.sleep()：屏幕休眠
5、exlcd.wakeup()：屏幕唤醒
6、exlcd.get_sleep()：休眠状态查询
]]

local exlcd = {}

-- 屏幕状态管理表
local screen_state = {
    last_brightness = 100, -- 默认亮度100%
    backlight_on = true,   -- 背光默认开启
    lcd_config = nil       -- 存储LCD配置
}

-- 预定义屏幕配置表
local predefined_configs = {
    Air780EHM_LCD_4 = {
        lcd_model = "Air780EHM_LCD_4",
        pin_vcc = 24,
        pin_rst = 36,
        pin_pwr = 25,
        pin_pwm = 2,
        port = lcd.HWID_0,
        direction = 3,
        w = 480,
        h = 320,
        xoffset = 0,
        yoffset = 0,
        sleepcmd = 0X10,
        wakecmd = 0X11,
    },

    AirLCD_1000 = {
        lcd_model = "AirLCD_1000",
        pin_vcc = 29,
        pin_rst = 36,
        pin_pwr = 30,
        pin_pwm = 1,
        port = lcd.HWID_0,
        direction = 0,
        w = 320,
        h = 480,
        xoffset = 0,
        yoffset = 0,
        sleepcmd = 0X10,
        wakecmd = 0X11,
    },

    AirLCD_1010 = {
        lcd_model = "AirLCD_1010",
        pin_vcc = 141,
        pin_rst = 36,
        pin_pwr = 1,
        pin_pwm = 0,
        port = lcd.HWID_0,
        direction = 0,
        w = 320,
        h = 480,
        xoffset = 0,
        yoffset = 0,
        sleepcmd = 0X10,
        wakecmd = 0X11,
    },

    AirLCD_1020 = {
        lcd_model = "AirLCD_1020",
        pin_pwr = 8,
        pin_pwm = 0,
        port = lcd.RGB,
        direction = 0,
        w = 800,
        h = 480,
        xoffset = 0,
        yoffset = 0,
    }
}

--[[
初始化LCD显示屏
@api exlcd.init(param)
@table param LCD配置参数，参考库的说明及demo用法
@return bool 初始化成功返回true，失败返回false
@usage
-- 使用预定义配置初始化
exlcd.init({lcd_model = "Air780EHM_LCD_4"})

-- 自定义参数初始化
exlcd.init({
    lcd_model = "st7796",
    port = lcd.HWID_0,
    pin_rst = 36,
    pin_pwr = 25,
    pin_pwm = 2,
    w = 480,
    h = 320,
    direction = 0
})
]]
function exlcd.init(param)
    if type(param) ~= "table" then
        log.error("exlcd", "参数必须为表")
        return false
    end

    -- 检查必要参数
    if not param.lcd_model then
        log.error("exlcd", "缺少必要参数: lcd_model")
        return false
    end

    local config = {}

    -- 根据lcd_model选择配置策略
    if param.lcd_model == "Air780EHM_LCD_4" then
        -- Air780EHM_LCD_4: 只使用lcd_model，其他参数固定
        config = predefined_configs.Air780EHM_LCD_4
        log.info("exlcd", "使用Air780EHM_LCD_4固定配置")
    elseif predefined_configs[param.lcd_model] then
        -- 其他预定义型号: 使用预定义配置作为基础，传入参数覆盖预定义配置
        config = {}

        -- 复制预定义配置
        for k, v in pairs(predefined_configs[param.lcd_model]) do
            config[k] = v
        end

        -- 用传入参数覆盖预定义配置
        for k, v in pairs(param) do
            if k ~= "lcd_model" or v ~= param.lcd_model then -- 避免重复设置lcd_model
                config[k] = v
            end
        end

        log.info("exlcd", "使用" .. param.lcd_model .. "基础配置，传入参数已覆盖")
    else
        -- 未知型号: 直接使用传入参数
        config = param
        log.info("exlcd", "使用传入参数配置")
    end

    -- LCD型号映射表
    local lcd_models = {
        AirLCD_1000 = "st7796",
        Air780EHM_LCD_4 = "st7796",
        AirLCD_1010 = "st7796",
        AirLCD_1020 = "h050iwv"
    }

    -- 确定LCD型号
    local lcd_model = lcd_models[config.lcd_model] or config.lcd_model

    -- 存储LCD配置供其他函数使用
    screen_state.lcd_config = {
        pin_pwr = config.pin_pwr,
        pin_pwm = config.pin_pwm,
        model = lcd_model,
        lcd_model = config.lcd_model
    }

    -- 设置电源引脚 (可选)
    if config.pin_vcc then
        gpio.setup(config.pin_vcc, 1, gpio.PULLUP)
        gpio.set(config.pin_vcc, 1)
    end

    -- 设置背光电源引脚 (可选)
    if config.pin_pwr then
        gpio.setup(config.pin_pwr, 1, gpio.PULLUP)
        gpio.set(config.pin_pwr, 1) -- 默认开启背光
    end

    -- 设置PWM背光引脚 (可选)
    if config.pin_pwm then
        pwm.setup(config.pin_pwm, 1000, screen_state.last_brightness)
        pwm.open(config.pin_pwm, 1000, screen_state.last_brightness)
    end

    -- 屏幕初始化 (spi_dev和init_in_service为可选参数)
    local lcd_init = lcd.init(
        lcd_model,
        config,
        config.spi_dev and config.spi_dev or nil,
        config.init_in_service and config.init_in_service or nil
    )
    log.info("exlcd", "LCD初始化", lcd_init)

    -- 自定义初始化完成确认
    if lcd_model == "custom" then
        lcd.user_done()
    end
    return lcd_init
end

--[[
设置背光亮度
@api exlcd.set_bl(level)
@number level 亮度级别，0-100，0表示关闭背光
@return bool 设置成功返回true，失败返回false
@usage
-- 设置50%亮度
exlcd.set_bl(50)

-- 关闭背光
exlcd.set_bl(0)
]]

function exlcd.set_bl(level)
    -- 检查PWM配置
    if not screen_state.lcd_config.pin_pwm then
        log.error("exlcd", "PWM配置不存在，无法调节背光")
        return false
    end

    -- 确保GPIO已关闭
    if screen_state.lcd_config.pin_pwr then
        gpio.close(screen_state.lcd_config.pin_pwr)
    end

    -- 设置并开启PWM
    pwm.stop(screen_state.lcd_config.pin_pwm)
    pwm.close(screen_state.lcd_config.pin_pwm)
    pwm.setup(screen_state.lcd_config.pin_pwm, 1000, 100)
    pwm.open(screen_state.lcd_config.pin_pwm, 1000, level)
    screen_state.last_brightness = level
    screen_state.backlight_on = (level > 0)
    log.info("exlcd", "背光设置为", level, "%")
    return true
end

--[[
获取当前背光亮度
@api exlcd.get_bl()
@return number 当前背光亮度级别(0-100)
@usage
local brightness = exlcd.get_bl()
log.info("当前背光亮度", brightness)
]]
function exlcd.get_bl()
    return screen_state.last_brightness
end

--[[
屏幕进入休眠状态
@api exlcd.sleep()
@usage
exlcd.sleep()
]]
function exlcd.sleep()
    if not screen_state.is_sleeping then
        -- 关闭PWM背光 (如果配置了)
        if screen_state.lcd_config and screen_state.lcd_config.pin_pwm then
            pwm.close(screen_state.lcd_config.pin_pwm)
        end

        -- 关闭背光电源 (如果配置了)
        if screen_state.lcd_config and screen_state.lcd_config.pin_pwr then
            gpio.setup(screen_state.lcd_config.pin_pwr, 1, gpio.PULLUP)
            gpio.set(screen_state.lcd_config.pin_pwr, 0)
        end

        -- 执行LCD睡眠
        lcd.sleep()
        screen_state.is_sleeping = true
        log.info("exlcd", "LCD进入休眠状态")
    end
end

--[[
屏幕从休眠状态唤醒
@api exlcd.wakeup()
@usage
exlcd.wakeup()
]]
function exlcd.wakeup()
    if screen_state.is_sleeping then
        -- 开启背光电源 (如果配置了)
        if screen_state.lcd_config and screen_state.lcd_config.pin_pwr then
            gpio.set(screen_state.lcd_config.pin_pwr, 1)
        end

        -- 唤醒LCD
        lcd.wakeup()

        -- 恢复背光设置 (如果配置了PWM引脚)
        if screen_state.lcd_config and screen_state.lcd_config.pin_pwm then
            pwm.setup(screen_state.lcd_config.pin_pwm, 1000, screen_state.last_brightness)
            pwm.open(screen_state.lcd_config.pin_pwm, 1000, screen_state.last_brightness)
        end

        screen_state.is_sleeping = false
        log.info("exlcd", "LCD唤醒")
    end
end

--[[
获取屏幕休眠状态
@api exlcd.get_sleep()
@return bool true表示屏幕处于休眠状态，false表示屏幕处于工作状态
@usage
if exlcd.get_sleep() then
    log.info("屏幕处于休眠状态")
end
]]
function exlcd.get_sleep()
    return screen_state.is_sleeping
end

return exlcd