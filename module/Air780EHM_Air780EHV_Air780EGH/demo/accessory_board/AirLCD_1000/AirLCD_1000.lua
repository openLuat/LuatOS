--[[
@module  AirLCD_1000
@summary AirLCD_1000显示驱动模块
@version 1.0
@date    2025.09.4
@author  江访
@usage

核心业务逻辑为：
1、初始化AirLCD_1000显示屏
2、管理屏幕背光亮度及开关状态
3、管理屏幕休眠和唤醒状态
4、提供屏幕状态管理功能

本文件的对外接口有5个：
1、AirLCD_1000.lcd_init()           --LCD初始化函数,
2、AirLCD_1000.set_backlight(level) -- 设置背光亮度接口,level 亮度级别(0-100)
3、AirLCD_1000.lcd_on()             -- 开启LCD背光
4、AirLCD_1000.lcd_off()            -- 关闭LCD背光
5、AirLCD_1000.set_sleep(sleep)     -- 设置休眠状态接口，sleep:true进入休眠, false唤醒
]]

-- AirLCD_1000.lua - LCD显示驱动模块
-- 此文件负责初始化LCD显示屏，管理背光及休眠状态
local AirLCD_1000 = {}

-- 屏幕状态管理表
local screen_state = {
    lcd_pin_pwr = 1,        -- 屏幕背光引脚GPIO号
    lcd_pwm_id = 0,         -- 屏幕背光引脚PWM端口号
    is_sleeping = false,    -- 是否休眠中标识
    last_brightness = 50,   -- 默认亮度50%
    backlight_on = true     -- 背光默认开启
}

-- LCD初始化函数
-- @param LCD_MODEL   显示屏型号型号
-- @param lcd_vcc     屏幕供电引脚GPIO号
-- @param lcd_pin_rst 复位引脚GPIO号
-- @param lcd_pin_pwr 背光引脚GPIO号
-- @param lcd_pwm_id  背光引脚PWM端口号

function AirLCD_1000.lcd_init(LCD_MODEL, lcd_vcc, lcd_pin_rst, lcd_pin_pwr,lcd_pwm_id)
    -- 根据接线设置AirLCD_1000初始化参数
    local LCD_MODEL, lcd_vcc, lcd_pin_rst, lcd_pin_pwr,lcd_pwm_id = "AirLCD_1000" or LCD_MODEL, lcd_vcc or 29, lcd_pin_rst or 36, lcd_pin_pwr or 1, lcd_pwm_id or 0

    -- 设置屏幕尺寸
    local width, height = 320, 480

    -- LCD参数配置表
    local lcd_param = {
        port = lcd.HWID_0,       -- 使用SPI设备模式
        pin_dc = 0xff,           -- DC引脚，无需设置
        pin_rst = lcd_pin_rst,   -- 复位引脚，对应GPIO号
        pin_pwr = lcd_pin_pwr,   -- 背光引脚（可选）
        direction = 0,           -- 屏幕默认0°方向
                                 -- 0:0°, 1:90°, 2:180°, 3:270°
        w = width,               -- 屏幕宽度(像素)
        h = height,              -- 屏幕高度(像素)
        xoffset = 0,             -- X方向偏移量
        yoffset = 0,             -- Y方向偏移量
        sleepcmd = 0x10,         -- 睡眠命令
        wakecmd = 0x11           -- 唤醒命令
    }

    -- 初始化SPI设备
    spi.deviceSetup(
        lcd.HWID_0,  -- LCD端口号
        nil,         -- CS片选脚，可选
        0,           -- CPHA=0
        0,           -- CPOL=0
        8,           -- 8位数据宽度
        20000000,    -- 20MHz波特率
        spi.MSB,     -- 高位先传
        1,           -- 主机模式
        1            -- 全双工模式
    )

    -- 设置VCC/RST/背光引脚为输出模式，并启用上拉电阻
    gpio.setup(lcd_vcc, 1, gpio.PULLUP)
    gpio.setup(lcd_pin_rst, 0, gpio.PULLUP)
    gpio.setup(lcd_pin_pwr, 1, gpio.PULLUP)
    
    -- 开启屏幕VCC供电
    gpio.set(lcd_vcc, 1)

    -- 拉低屏幕复位引脚
    gpio.set(lcd_pin_rst, 0)  -- 拉低复位引脚
    sys.wait(20)                    -- 等待20ms(ST7796复位拉低大于10ms生效)
    gpio.set(lcd_pin_rst, 1)  -- 拉高复位引脚
    sys.wait(150)                   -- 等待150ms(ST7796复位拉高大于120ms重置)
    gpio.set(lcd_pin_pwr, 1)

    -- 初始化ST7796显示芯片
    lcd.init("st7796", lcd_param)

    -- 通用显示设置
    lcd.setupBuff(nil,false)     -- 设置帧缓冲区
    lcd.autoFlush(false)         -- 禁止自动刷新

    screen_state.lcd_pin_pwr = lcd_pin_pwr
    screen_state.lcd_pwm_id = lcd_pwm_id

    log.info("AirLCD_1000", "LCD初始化成功，尺寸:", width, "x", height)
    -- return true
end

-- 设置背光亮度接口
-- 使用背光PWM模式控制亮度，休眠和关闭背光使用背光引脚GPIO模式
-- @param level 亮度级别(0-100)
-- @return 设置成功状态
function AirLCD_1000.set_backlight(level)

    -- 检查屏幕状态和PWM配置
    if screen_state.is_sleeping then
        log.warn("AirLCD_1000", "屏幕处于休眠状态，无法调节背光")
        return false
    end
    if not screen_state.lcd_pin_pwr then
        log.error("AirLCD_1000", "PWM配置不存在，无法调节背光")
        return false
    end

    -- 确保GPIO已关闭 
    gpio.close(screen_state.lcd_pin_pwr)

    -- 设置并开启PWM
    pwm.stop(screen_state.lcd_pwm_id)
    pwm.close(screen_state.lcd_pwm_id)
    pwm.setup(screen_state.lcd_pwm_id, 1000, 100)
    pwm.open(screen_state.lcd_pwm_id, 1000, level)

    -- 修改默认背光亮度为当前设置
    screen_state.last_brightness = level
    screen_state.backlight_on = (level > 0)
    log.info("AirLCD_1000", "背光设置为", level, "%")
    return true
end

-- 开启LCD显示屏背光
-- @return 操作成功状态
function AirLCD_1000.lcd_on()
    if screen_state.is_sleeping then
        log.warn("AirLCD_1000", "屏幕处于休眠状态，无法开启背光")
        return false
    end

    pwm.stop(screen_state.lcd_pwm_id)
    pwm.close(screen_state.lcd_pwm_id)

    -- 设置GPIO控制电源（如果存在）
    if screen_state.lcd_pin_pwr then
        gpio.setup(screen_state.lcd_pin_pwr, 1, gpio.PULLUP)
    end

    lcd.on()
    log.info("AirLCD_1000", "LCD背光已开启")
end

-- 关闭LCD显示屏背光
-- @return 操作成功状态
function AirLCD_1000.lcd_off()
    if screen_state.is_sleeping then
        log.warn("AirLCD_1000", "屏幕处于休眠状态，无法关闭背光")
        return false
    end
    pwm.stop(screen_state.lcd_pwm_id)
    pwm.close(screen_state.lcd_pwm_id)
        -- 设置GPIO控制电源（如果存在）
    if screen_state.lcd_pin_pwr then
        gpio.setup(screen_state.lcd_pin_pwr, 1, gpio.PULLUP)
    end
    lcd.off()
    log.info("AirLCD_1000", "LCD背光已关闭")
end

-- 设置休眠状态接口
-- @param sleep true进入休眠, false唤醒
-- @return 操作成功状态
function AirLCD_1000.set_sleep(sleep)
    if sleep then
        -- 进入休眠模式
        if not screen_state.is_sleeping then
            -- 关闭PWM（如果存在）
            if screen_state.lcd_pwm_id then
                pwm.stop(screen_state.lcd_pwm_id)
                pwm.close(screen_state.lcd_pwm_id)
            end

            -- 设置GPIO控制电源（如果存在）
            if screen_state.lcd_pin_pwr then
                gpio.setup(screen_state.lcd_pin_pwr, 1, gpio.PULLUP)
                gpio.set(screen_state.lcd_pin_pwr, 0)
            end

            -- 执行LCD睡眠
            lcd.sleep()
            screen_state.is_sleeping = true
            log.info("AirLCD_1000", "LCD进入休眠状态")
        end
    else
        -- 退出休眠模式
        if screen_state.is_sleeping then
            -- 唤醒LCD
            lcd.wakeup()

            -- 关闭GPIO控制（如果存在）
            if screen_state.lcd_pin_pwr then
                gpio.close(screen_state.lcd_pin_pwr)
            end

            -- 恢复之前的背光设置（如果PWM存在）
            if screen_state.lcd_pin_pwr then
                if screen_state.backlight_on then
                    AirLCD_1000.set_backlight(screen_state.last_brightness)
                else
                    -- 如果背光原本是关闭状态，保持关闭
                    pwm.stop(screen_state.lcd_pwm_id)
                    pwm.close(screen_state.lcd_pwm_id)
                end
            end

            screen_state.is_sleeping = false
            log.info("AirLCD_1000", "LCD唤醒")
        end
    end
    return true
end

return AirLCD_1000