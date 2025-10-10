-- exlcd.lua
--[[
@module  exlcd
@summary LCD显示拓展库
@version 1.0
@date    2025.09.17
@author  江访
@usage
核心业务逻辑为：
1、初始化LCD显示屏，支持多种显示芯片
2、管理屏幕背光亮度及开关状态
3、管理屏幕休眠和唤醒状态
4、提供屏幕状态管理功能

本文件的对外接口有4个：
1、exlcd.init(args)   -- LCD初始化函数
2、exlcd.bkl(level)   -- 设置背光亮度接口,level 亮度级别(0-100)
3、exlcd.sleep()      -- 屏幕休眠
4、exlcd.wakeup()     -- 屏幕唤醒
]]

local exlcd = {}

-- 屏幕状态管理表
local screen_state = {
    is_sleeping = false,   -- 是否休眠中标识
    last_brightness = 100,  -- 默认亮度100%
    backlight_on = true,   -- 背光默认开启
    lcd_config = nil       -- 存储LCD配置
}

-- LCD初始化函数
-- @param args LCD参数配置表
-- @return 初始化成功状态
function exlcd.init(args)

    if type(args) ~= "table" then
        log.error("exlcd", "参数必须为表")
        return false
    end

    -- 检查必要参数
    if not args.LCD_MODEL then
        log.error("exlcd", "缺少必要参数: LCD_MODEL")
        return false
    end

    -- LCD型号映射表
    local lcd_models = {
        AirLCD_1000 = "st7796",
        AirLCD_1001 = "st7796",
        Air780EHM_LCD_1 = "st7796",
        Air780EHM_LCD_2 = "st7796",
        Air780EHM_LCD_3 = "st7796",
        Air780EHM_LCD_4 = "st7796",
        AirLCD_1020 = "nv3052c"
    }

    -- 确定LCD型号
    local lcd_model = lcd_models[args.LCD_MODEL] or args.LCD_MODEL

    -- 存储LCD配置供其他函数使用
    screen_state.lcd_config = {
        pin_pwr = args.pin_pwr,
        pin_pwm = args.pin_pwm,
        model = lcd_model
    }

    -- 设置电源引脚 (可选)
    if args.pin_vcc then
        gpio.setup(args.pin_vcc, 1, gpio.PULLUP)
        gpio.set(args.pin_vcc, 1)
    end

    -- 设置背光电源引脚 (可选)
    if args.pin_pwr then
        gpio.setup(args.pin_pwr, 1, gpio.PULLUP)
        gpio.set(args.pin_pwr, 1)  -- 默认开启背光
    end

    -- 设置PWM背光引脚 (可选)
    if args.pin_pwm then
        pwm.setup(args.pin_pwm, 1000, screen_state.last_brightness)
        pwm.open(args.pin_pwm, 1000, screen_state.last_brightness)
    end

    -- 屏幕初始化 (spi_dev和init_in_service为可选参数)
    local lcd_init = lcd.init(
        lcd_model,
        args,
        args.spi_dev and args.spi_dev or nil,
        args.init_in_service and args.init_in_service or nil
    )
    log.info("exlcd", "LCD初始化", lcd_init)
    return lcd_init
end

-- 设置背光亮度接口
-- 使用背光PWM模式控制亮度
-- @param level 亮度级别(0-100)

function exlcd.bkl(level)
    -- 检查屏幕状态和PWM配置
    if screen_state.is_sleeping then
        log.warn("exlcd", "屏幕处于休眠状态，无法调节背光")
        return false
    end
    if not screen_state.lcd_config.pin_pwm then
        log.error("exlcd", "PWM配置不存在，无法调节背光")
        return false
    end

    -- 确保GPIO已关闭 
    gpio.close(screen_state.lcd_config.pin_pwr)

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



-- function exlcd.bkl(level)
--     -- 检查屏幕状态
--     if screen_state.is_sleeping then
--         log.warn("exlcd", "屏幕处于休眠状态，无法调节背光")
--         return
--     end

--     -- 确保亮度在有效范围内
--     -- level = level or screen_state.last_brightness
--     -- level = math.max(0, math.min(100, level or 0))

--     if screen_state.lcd_config.pin_pwr then
--          gpio.close(screen_state.lcd_config.pin_pwr)
--     end

--     -- 设置PWM背光 (如果配置了PWM引脚)
--     if screen_state.lcd_config and screen_state.lcd_config.pin_pwm then
--         --pwm.setup(screen_state.lcd_config.pin_pwm, 1000, level)
--         pwm.open(screen_state.lcd_config.pin_pwm, 1000, level)
--     -- 如果没有PWM但配置了电源引脚，则通过开关控制
--     elseif screen_state.lcd_config and screen_state.lcd_config.pin_pwr then
--         gpio.set(screen_state.lcd_config.pin_pwr, level > 0 and 1 or 0)
--     end

--     screen_state.last_brightness = level
--     screen_state.backlight_on = (level > 0)
--     log.info("exlcd", "背光设置为", level, "%")
-- end

-- 屏幕休眠
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

-- 屏幕唤醒
function exlcd.wakeup()
    if screen_state.is_sleeping then
        -- 开启背光电源 (如果配置了)
        if screen_state.lcd_config and screen_state.lcd_config.pin_pwr then
            gpio.set(screen_state.lcd_config.pin_pwr, 1)
        end

        -- 唤醒LCD
        lcd.wakeup()
        sys.wait(100)  -- 等待100ms稳定

        -- 恢复背光设置 (如果配置了PWM引脚)
        if screen_state.lcd_config and screen_state.lcd_config.pin_pwm then
            pwm.setup(screen_state.lcd_config.pin_pwm, 1000, screen_state.last_brightness)
            pwm.open(screen_state.lcd_config.pin_pwm, 1000, screen_state.last_brightness)
        end

        screen_state.is_sleeping = false
        log.info("exlcd", "LCD唤醒")
    end
end


function exlcd.get_brightness()
    return screen_state.last_brightness
end

-- 获取当前休眠状态
function exlcd.is_sleeping()
    return screen_state.is_sleeping
end

return exlcd