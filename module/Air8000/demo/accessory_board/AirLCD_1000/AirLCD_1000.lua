--[[
@module  AirLCD_1000
@summary LCD显示驱动模块
@version 1.0
@date    2025.09.4
@author  江访
@usage
核心业务逻辑为：
1、初始化LCD显示屏，支持多种显示芯片
2、管理屏幕背光亮度及开关状态
3、管理屏幕休眠和唤醒状态
4、提供屏幕状态管理功能

本文件的对外接口有4个：
1、lcd_init(LCD_MODEL, lcd_pin_dc, lcd_pin_rst, lcd_pin_pwr)   --LCD初始化函数,
    LCD_MODEL-LCD型号, lcd_pin_dc-数据/命令引脚, lcd_pin_rst-复位引脚, lcd_pin_pwr-背光引脚
2、setBacklight(level) - 设置背光亮度接口,level 亮度级别(0-100)
3、lcd_on() - 开启LCD背光
4、lcd_off() - 关闭LCD背光
5、setSleep(sleep) - 设置休眠状态接口，sleep:true进入休眠, false唤醒
]]

-- AirLCD_1000.lua - LCD显示驱动模块
-- 此文件负责初始化LCD显示屏，管理背光及休眠状态
local AirLCD_1000 = {}
local screen_data = require "screen_data_table"  -- 引入屏幕配置数据

-- 屏幕状态管理表
local screen_state = {
    is_sleeping = false,   -- 是否休眠中标识
    last_brightness = 50,  -- 默认亮度50%
    backlight_on = true    -- 背光默认开启
}

-- CO5300显示芯片的初始化函数
-- @param lcd_param LCD参数配置表
local function co5300_init(lcd_param)
    -- 发送初始化命令序列
    lcd.qspi(0x02, 0x32, 0x12)      -- CO5300驱动ic所需的qspi配置，需要在lcd.init前配置好
    lcd.init("custom", lcd_param)   -- 初始显示屏

    -- 复位操作
    gpio.set(lcd_param.pin_rst, 0)  -- 拉低复位引脚
    sys.wait(300)                   -- 等待300ms
    gpio.set(lcd_param.pin_rst, 1)  -- 拉高复位引脚
    sys.wait(200)                   -- 等待200ms

    -- 发送配置命令
    lcd.cmd(0xfe, 0x00)
    lcd.cmd(0xc4, 0x80)
    lcd.cmd(0x3a, 0x55)
    lcd.cmd(0x35, 0x00)
    lcd.cmd(0x53, 0x20)
    lcd.cmd(0x51, 0x7a)
    lcd.cmd(0x63, 0xaa)
    lcd.cmd(0x36, 0x00) -- 设置显示方向

    -- 唤醒显示屏
    lcd.wakeup()
    sys.wait(200)

    -- 开启显示
    lcd.cmd(0x29)
end

-- LCD初始化函数
-- @param LCD_MODEL LCD型号
-- @param lcd_pin_dc 数据/命令引脚
-- @param lcd_pin_rst 复位引脚
-- @param lcd_pin_pwr 背光引脚
-- @return 初始化成功状态，屏幕宽度，屏幕高度
function AirLCD_1000.lcd_init()
    local LCD_MODEL, lcd_pin_dc, lcd_pin_rst, lcd_pin_pwr =
        screen_data.lcd.model,
        screen_data.lcd.pin_dc,
        screen_data.lcd.pin_rst,
        screen_data.lcd.pin_pwr

    -- 从配置表中获取LCD参数
    local lcd_model_data = screen_data.lcd_models[LCD_MODEL]

    if not lcd_model_data then
        log.error("AirLCD_1000", "不支持的LCD型号:", LCD_MODEL)
        return false, 0, 0  -- 返回初始化失败和默认尺寸
    end

    local width = lcd_model_data.width
    local height = lcd_model_data.height
    local lcd_ic = lcd_model_data.lcd_ic

    -- LCD参数配置表
    local lcd_param = {
        port = lcd.HWID_0,       -- 使用SPI设备模式
        pin_dc = lcd_pin_dc,     -- DC引脚，对应GPIO号
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

    -- ST7796显示芯片初始化
    if lcd_ic == "st7796" or "st7789" then
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

        -- 设置DC和RST引脚为输出模式，并启用上拉电阻
        gpio.setup(lcd_param.pin_dc, 1, gpio.PULLUP)
        gpio.setup(lcd_param.pin_rst, 1, gpio.PULLUP)
        gpio.setup(lcd_param.pin_pwr, 1, gpio.PULLUP)
        -- 设置DC引脚为高电平(数据模式)
        gpio.set(lcd_param.pin_dc, 1)

        -- 执行复位序列
        gpio.set(lcd_param.pin_rst, 0)  -- 拉低复位引脚
        sys.wait(20)                    -- 等待20ms(ST7796复位拉低大于10ms生效)
        gpio.set(lcd_param.pin_rst, 1)  -- 拉高复位引脚
        sys.wait(150)                   -- 等待150ms(ST7796复位拉高大于120ms重置)
        gpio.set(lcd_param.pin_pwr, 1)
        -- 初始化ST7796显示芯片
        lcd.init(lcd_ic, lcd_param)

    -- CO5300显示芯片初始化
    elseif lcd_ic == "co5300" then
        -- 设置QSPI模式和参数
        lcd_param.interface_mode = lcd.QSPI_MODE  -- QSPI模式
        lcd_param.bus_speed = 60000000            -- 60MHz总线速度
        lcd_param.rb_swap = true                  -- 红蓝交换

        -- 设置DC引脚为输出模式并启用上拉电阻
        gpio.setup(lcd_param.pin_dc, 1, gpio.PULLUP)
        sys.wait(100)  -- 等待100ms

        -- 设置DC引脚为高电平
        gpio.set(lcd_param.pin_dc, 1)
        sys.wait(1000)  -- 等待1秒

        -- 调用CO5300专用初始化函数
        co5300_init(lcd_param)
    end

    -- 通用显示设置
    lcd.setupBuff(nil,false)     -- 设置帧缓冲区
    lcd.autoFlush(false)         -- 禁止自动刷新
    lcd.user_done()              -- 标记用户初始化完成

    screen_data.default.width = width
    screen_data.default.height = height

    log.info("AirLCD_1000", "LCD初始化成功，尺寸:", width, "x", height)
    return true, width, height  -- 返回初始化成功和屏幕尺寸
end

-- 设置背光亮度接口
-- 使用背光PWM模式控制亮度，休眠和关闭背光使用背光引脚GPIO模式
-- @param level 亮度级别(0-100)
-- @return 设置成功状态
function AirLCD_1000.setBacklight(level)
    -- 检查屏幕状态和PWM配置
    if screen_state.is_sleeping then
        log.warn("AirLCD_1000", "屏幕处于休眠状态，无法调节背光")
        return false
    end
    if not screen_data.lcd.pwm_id then
        log.error("AirLCD_1000", "PWM配置不存在，无法调节背光")
        return false
    end

    -- 确保GPIO已关闭 
    gpio.close(screen_data.lcd.pin_pwr)

    -- 设置并开启PWM
    pwm.stop(screen_data.lcd.pwm_id)
    pwm.close(screen_data.lcd.pwm_id)
    pwm.setup(screen_data.lcd.pwm_id, 1000, 100)
    pwm.open(screen_data.lcd.pwm_id, 1000, level)

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

    pwm.stop(screen_data.lcd.pwm_id)
    pwm.close(screen_data.lcd.pwm_id)
    
    -- 设置GPIO控制电源（如果存在）
    if screen_data.lcd and screen_data.lcd.pin_pwr then
        gpio.setup(screen_data.lcd.pin_pwr, 1, gpio.PULLUP)
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
    pwm.stop(screen_data.lcd.pwm_id)
    pwm.close(screen_data.lcd.pwm_id)
        -- 设置GPIO控制电源（如果存在）
    if screen_data.lcd and screen_data.lcd.pin_pwr then
        gpio.setup(screen_data.lcd.pin_pwr, 1, gpio.PULLUP)
    end
    lcd.off()
    log.info("AirLCD_1000", "LCD背光已关闭")
end

-- 设置休眠状态接口
-- @param sleep true进入休眠, false唤醒
-- @return 操作成功状态
function AirLCD_1000.setSleep(sleep)
    if sleep then
        -- 进入休眠模式
        if not screen_state.is_sleeping then
            -- 关闭PWM（如果存在）
            if screen_data.lcd and screen_data.lcd.pwm_id then
                pwm.stop(screen_data.lcd.pwm_id)
                pwm.close(screen_data.lcd.pwm_id)
            end

            -- 设置GPIO控制电源（如果存在）
            if screen_data.lcd and screen_data.lcd.pin_pwr then
                gpio.setup(screen_data.lcd.pin_pwr, 1, gpio.PULLUP)
                gpio.set(screen_data.lcd.pin_pwr, 1)
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
            if screen_data.lcd and screen_data.lcd.pin_pwr then
                gpio.close(screen_data.lcd.pin_pwr)
            end

            -- 恢复之前的背光设置（如果PWM存在）
            if screen_data.lcd and screen_data.lcd.pwm_id then
                if screen_state.backlight_on then
                    AirLCD_1000.setBacklight(screen_state.last_brightness)
                else
                    -- 如果背光原本是关闭状态，保持关闭
                    pwm.stop(screen_data.lcd.pwm_id)
                    pwm.close(screen_data.lcd.pwm_id)
                end
            end

            screen_state.is_sleeping = false
            log.info("AirLCD_1000", "LCD唤醒")
        end
    end
    return true
end

return AirLCD_1000