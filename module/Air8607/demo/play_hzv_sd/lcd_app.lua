--[[
@module  lcd_app
@summary Air8607 LCD 显示初始化应用功能模块（display 库 + AirUI）
@version 1.0
@date    2026.10.30
@author  江访
@usage
本文件为 Air8607 播放 SD 卡 HZV 素材 demo 的显示初始化应用功能模块，核心业务逻辑为：
1、先用 PWM3 把背光压灭（占空比 0），整个初始化过程背光保持熄灭；
2、调用 display.init("custom", ...) 初始化 10 寸 RGB 屏，分辨率 1024x600；
3、调用 display.fill 把整屏刷黑，清掉上电时显存里的随机内容；
4、调用 airui.init(width, height) 初始化 AirUI，HZV 视频组件必须在它之后创建；
5、调用 airui.font_load 加载固件内置的中文矢量字库，素材列表页的文字才显示得出来；
6、界面或视频首帧准备好后，由 main.lua 调 lcd_app.backlight_on() 点亮背光。

本文件的对外接口有3个：
1、lcd_app.init：初始化屏幕与 AirUI，背光保持熄灭，成功返回 true，失败返回 false
2、lcd_app.backlight_on：点亮背光，可重复调用
3、lcd_app.get_size：返回屏幕分辨率 width, height
]]

local M = {}

-- Air8607 整机 10 寸 RGB 屏分辨率
local LCD_WIDTH  = 1024
local LCD_HEIGHT = 600

-- LCD_DISP = GPIO15，display.init 内部用它做复位/显示使能时序
local PIN_LCD_RST = 15

-- 背光用 PWM3 调光，PIN55 = GPIO13
local PWM_BACKLIGHT_CH   = 3
local PWM_BACKLIGHT_FREQ = 1000
local PWM_BACKLIGHT_DUTY = 100

-- RGB 屏时序参数（1024x600 生态实测组）
local RGB_HBP    = 140
local RGB_HSPW   = 20
local RGB_HFP    = 160
local RGB_VBP    = 20
local RGB_VSPW   = 3
local RGB_VFP    = 12
local RGB_PCLK_HZ = 50 * 1000 * 1000

-- 生效的屏幕分辨率，init 之后以 display.getSize 的返回值为准
local lcd_width  = LCD_WIDTH
local lcd_height = LCD_HEIGHT

-- 背光是否已点亮，避免重复设置 PWM
local backlight_is_on = false

--[[
初始化 LCD 显示驱动和 AirUI；

@api lcd_app.init()

@summary 先压灭背光，再初始化 1024x600 RGB 屏并刷黑整屏，最后初始化 AirUI

@return boolean 初始化成功返回 true，失败返回 false

@usage
if not lcd_app.init() then
    log.error("main", "屏幕初始化失败")
    return
end
]]
function M.init()
    -- 背光先压到最暗，PWM 通道输出有效但占空比为 0
    pwm.setup(PWM_BACKLIGHT_CH, PWM_BACKLIGHT_FREQ, 0)
    pwm.start(PWM_BACKLIGHT_CH)
    log.info("lcd_app", "背光预置为熄灭", "PWM通道" .. PWM_BACKLIGHT_CH, "占空比0")

    if not display or not display.init then
        log.error("lcd_app", "固件不支持 display 库，请烧录带 LUAT_USE_DISPLAY 的固件")
        return false
    end

    -- id 必须显式给 0，AirUI 取的是默认屏
    local ok, err = display.init("custom", {
        id        = 0,
        interface = "rgb",
        w         = LCD_WIDTH,
        h         = LCD_HEIGHT,
        hbp       = RGB_HBP,
        hspw      = RGB_HSPW,
        hfp       = RGB_HFP,
        vbp       = RGB_VBP,
        vspw      = RGB_VSPW,
        vfp       = RGB_VFP,
        pclk_hz   = RGB_PCLK_HZ,
        pin_rst   = PIN_LCD_RST,
    })
    if not ok then
        log.error("lcd_app", "display.init 失败", err)
        return false
    end
    log.info("lcd_app", "display.init 成功", LCD_WIDTH .. "x" .. LCD_HEIGHT)

    -- display 内部可能按屏的实际能力调整分辨率，这里以返回值为准
    if display.getSize then
        local w, h = display.getSize()
        if w and w > 0 and h and h > 0 then
            lcd_width, lcd_height = w, h
        end
    end

    -- 把整屏刷黑，清掉上电时显存里的随机内容
    if display.fill then
        display.fill(0, 0, lcd_width, lcd_height, 0x0000)
        log.info("lcd_app", "屏幕已刷黑", lcd_width .. "x" .. lcd_height)
    end

    if not airui or not airui.init then
        log.error("lcd_app", "固件不支持 AirUI，请烧录带 LUAT_USE_AIRUI 的固件")
        return false
    end
    if not airui.init(lcd_width, lcd_height) then
        log.error("lcd_app", "airui.init 失败")
        return false
    end
    log.info("lcd_app", "airui.init 成功", lcd_width .. "x" .. lcd_height)

    -- 加载固件内置的中文矢量字库，界面文字不加载会全部显示成方块
    if airui.font_load then
        local ok, err = pcall(airui.font_load, {
            type       = "hzfont",
            size       = 20,
            cache_size = 1024,
            antialias  = 1,
        })
        if ok then
            log.info("lcd_app", "中文字库加载成功", "hzfont", "字号20")
        else
            log.error("lcd_app", "中文字库加载失败，界面中文会显示成方块", err)
        end
    else
        log.warn("lcd_app", "固件不支持 airui.font_load，界面中文可能显示成方块")
    end

    return true
end

--[[
点亮背光；

@api lcd_app.backlight_on()

@summary 把 PWM3 占空比设到 PWM_BACKLIGHT_DUTY，视频首帧画好之后由 main.lua 调用

@return nil

@usage
sys.wait(200)
lcd_app.backlight_on()
]]
function M.backlight_on()
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

@summary 返回 init 之后生效的屏幕宽高，用于视频组件居中

@return number 屏幕宽度
@return number 屏幕高度

@usage
local w, h = lcd_app.get_size()
]]
function M.get_size()
    return lcd_width, lcd_height
end

return M
