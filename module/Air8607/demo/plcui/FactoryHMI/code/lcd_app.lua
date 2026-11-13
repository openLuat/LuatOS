--[[
@module  lcd_app
@summary Air8607 LCD 显示初始化应用功能模块（板级上电 + exd_air8607_rgb 扩展库）
@version 1.1
@date    2026.11.10
@author  江访
@usage
本文件为 plcui_water_station 演示项目的显示初始化应用功能模块，核心业务逻辑为：
1、power_on 板级上电时序（防上电花屏）：
- PWM3 占空比 0 压灭背光；
- LCD 供电使能（GPIO17，低有效）、LCD_DISP/复位脚（GPIO15）拉高；
- TF 卡供电（GPIO74）保持上电、功放（GPIO73）关断；
- I2C1 总线初始化，sys.wait(120) 等电源稳定；
2、调用 exd_air8607_rgb.setup 完成显示初始化（复位 + RGB 时序 + 帧缓冲分配）：
- 该扩展库双后端自动适配：固件有 display 核心库走 display，没有则降级 lcd 核心库，
  出厂固件（如 LuatOS_V1021_Air160X）没有 display 库时靠 lcd 后端工作；
- PC 模拟器上扩展库自动跳过硬件初始化；
3、界面首帧准备好后，由 boot_app.lua 调 lcd_app.backlight_on() 点亮背光。

与播放 HZV 的 demo 不同：本项目用 PLCUI 画界面，plcui.init 会自己接管
LVGL 渲染与中文字库（hzfont 由 PLCUI 按 main.xml 的 font 声明自动加载），
所以本模块只负责把屏点亮到"黑屏待命"状态，不初始化任何 UI 框架。

本文件的对外接口有3个：
1、lcd_app.init：板级上电并初始化屏幕，背光保持熄灭，成功返回 true，失败返回 false
2、lcd_app.backlight_on：点亮背光，可重复调用
3、lcd_app.get_size：返回屏幕分辨率 width, height
]]

local lcd_app = {}

-- Air8607 整机 10 寸 RGB 屏分辨率
local LCD_WIDTH  = 1024
local LCD_HEIGHT = 600

-- 板级引脚（与出厂固件 eng_8607_10i_v0.lua 一致）
local PIN_LCD_PWR = 17   -- LCD 供电使能（低有效）
local PIN_LCD_RST = 15   -- LCD_DISP / 复位脚，exd 扩展库内部也用它做复位时序
local PIN_SD_EN   = 74   -- TF 卡供电使能，保持上电
local PIN_PA_EN   = 73   -- 功放使能，本项目不出声，保持关断

-- 背光用 PWM3 调光，PIN55 = GPIO13
local PWM_BACKLIGHT_CH   = 3
local PWM_BACKLIGHT_FREQ = 1000
local PWM_BACKLIGHT_DUTY = 100

-- 触摸 I2C1 总线参数，power_on 里先配好总线，tp_app 再挂 GT911
local TP_I2C_PORT = 1

-- 背光是否已点亮，避免重复设置 PWM
local backlight_is_on = false

--[[
板级上电时序（仅真机）；

@summary 背光压灭 -> LCD 供电/复位/TF/功放 GPIO 配置 -> I2C1 总线 -> 等电源稳定

@return nil
]]
local function power_on()
    -- 背光先给 0，界面搭好再点亮，避免看到初始化花屏
    pwm.setup(PWM_BACKLIGHT_CH, PWM_BACKLIGHT_FREQ, 0)
    pwm.start(PWM_BACKLIGHT_CH)

    gpio.setup(PIN_LCD_PWR, 0)   -- LCD 供电使能（低有效）
    gpio.setup(PIN_LCD_RST, 1)   -- LCD_DISP / 复位脚
    gpio.setup(PIN_SD_EN, 1)     -- TF 卡供电保持上电
    gpio.setup(PIN_PA_EN, 0)     -- 功放关断

    i2c.setup(TP_I2C_PORT, i2c.FAST)
    sys.wait(120)
end

--[[
初始化 LCD 显示驱动；

@api lcd_app.init()

@summary 板级上电时序后，调 exd_air8607_rgb.setup 初始化 1024x600 RGB 屏

@return boolean 初始化成功返回 true，失败返回 false

@usage
if not lcd_app.init() then
    log.error("main", "屏幕初始化失败")
    return
end
]]
function lcd_app.init()
    power_on()
    log.info("lcd_app", "板级上电时序完成", "背光预置为熄灭", "PWM通道" .. PWM_BACKLIGHT_CH)

    -- exd_air8607_rgb 是显示 IC 初始化扩展库（免序列 RGB 屏），
    -- 固件有 display 核心库走 display 后端，没有则降级 lcd 后端；PC 模拟器自动跳过
    local exd = require "exd_air8607_rgb"
    local ok, info = exd.setup({pin_rst = PIN_LCD_RST})
    if not ok then
        log.error("lcd_app", "显示初始化失败", info)
        return false
    end
    log.info("lcd_app", "显示初始化完成", info.backend, info.w .. "x" .. info.h)
    return true
end

--[[
点亮背光；

@api lcd_app.backlight_on()

@summary 把 PWM3 占空比设到 PWM_BACKLIGHT_DUTY，界面首帧画好之后由 boot_app.lua 调用

@return nil

@usage
sys.wait(200)
lcd_app.backlight_on()
]]
function lcd_app.backlight_on()
    if backlight_is_on then
        return
    end

    pwm.setup(PWM_BACKLIGHT_CH, PWM_BACKLIGHT_FREQ, PWM_BACKLIGHT_DUTY)
    pwm.start(PWM_BACKLIGHT_CH)
    backlight_is_on = true
    log.info("lcd_app", "背光点亮", "PWM通道" .. PWM_BACKLIGHT_CH,
        "占空比" .. PWM_BACKLIGHT_DUTY)
end

--[[
查询当前屏幕分辨率；

@api lcd_app.get_size()

@summary 返回屏幕宽高，10 寸 RGB 屏固定 1024x600

@return number 屏幕宽度
@return number 屏幕高度

@usage
local w, h = lcd_app.get_size()
]]
function lcd_app.get_size()
    return LCD_WIDTH, LCD_HEIGHT
end

return lcd_app
