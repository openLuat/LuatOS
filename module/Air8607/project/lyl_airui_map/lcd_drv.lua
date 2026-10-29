--[[
@module  lcd_drv
@summary Air8607(Air1603) RGB 10寸 1024x600，使用 display 库初始化 + AirUI
@version 1.0
@date    2026.10.28
@usage
与 projects/airui_button 相同。参数来自
resources/software/factory_new/config/eng_8607_10i_v0.lua 的 hw.lcd。
lcd_drv.init() 完成：
1、display.init("custom", {interface = "rgb", ...}) 配置 RGB 时序 + LCD_DISP 复位脚
2、display.getSize(0) 取实际分辨率
3、airui.init(w, h) -> font_load(hzfont) -> set_rotation(0)
display.init 末尾已经开显示，这里不再调用 display.on。
背光由 lcd_drv.backlight_on() 单独点亮，调用时机放在首帧之后。
成功后设置全局 _G.screen_w / _G.screen_h / _G.density_scale

背光是 PWM3（PIN55 = GPIO13），不把 pin_bl 交给 display.init：
display.init 末尾会无条件拉高 pin_bl，会和 PWM 调光抢这只脚。
]]

local lcd_drv = {}

--[[
按 display 库方式初始化屏幕
@return number|nil w, number|nil h 成功返回分辨率
]]
local function init_display()
    if rtos.bsp() == "PC" then
        log.info("lcd_drv", "PC 仿真跳过 display.init")
        return 1024, 600
    end

    -- RGB 10寸 1024x600（免序列四合一，无 SPI 初始化引脚）
    -- 时序与工厂 eng_8607_10i_v0 一致：hbp=140 hspw=20 hfp=160 vbp=20 vspw=3 vfp=12 @50MHz
    local ok, err = display.init("custom", {
        id        = 0,
        interface = "rgb",
        w         = 1024,
        h         = 600,
        hbp       = 140,
        hspw      = 20,
        hfp       = 160,
        vbp       = 20,
        vspw      = 3,
        vfp       = 12,
        pclk_hz   = 50 * 1000 * 1000,
        pin_rst   = 15, -- LCD_DISP = GPIO15
    })
    log.info("lcd_drv", "display.init", ok, err)
    if not ok then
        log.error("lcd_drv", "display 初始化失败", err)
        return nil
    end

    local w, h = display.getSize(0)
    if not w or w <= 0 or not h or h <= 0 then
        log.warn("lcd_drv", "display.getSize 异常，按 1024x600 处理", w, h)
        w, h = 1024, 600
    end
    log.info("lcd_drv", "display 就绪", w, h)
    return w, h
end

-- 背光 PWM3，1kHz，占空比 100。与工厂 backlight = { pwm_ch = 3, pwm_freq = 1000 } 一致
function lcd_drv.backlight_on()
    if rtos.bsp() == "PC" then
        return
    end
    pwm.setup(3, 1000, 100)
    pwm.start(3)
    log.info("lcd_drv", "背光 PWM3 已点亮")
end

--[[
初始化屏幕与 AirUI
@return boolean 成功返回 true
]]
function lcd_drv.init()
    local w, h = init_display()
    if not w then
        return false
    end

    local r = airui.init(w, h)
    if not r then
        log.error("lcd_drv", "airui.init 失败", w, h)
        return false
    end

    -- 加载中文字体（固件内置，无需 path）。工厂高分屏用 20 号字
    airui.font_load({
        type       = "hzfont",
        size       = 20,
        cache_size = 1024,
        antialias  = 1,
    })
    airui.set_rotation(0)
    log.info("lcd_drv", "airui version -> " .. tostring(airui.version()))

    -- 记录实际可用分辨率与缩放系数（以 1024x600 为设计基准）
    local rot = airui.get_rotation()
    if rot == 0 or rot == 180 then
        _G.screen_w, _G.screen_h = w, h
    else
        _G.screen_w, _G.screen_h = h, w
    end
    _G.density_scale = math.min(_G.screen_w / 1024, _G.screen_h / 600)

    log.info("lcd_drv", "屏幕就绪", _G.screen_w, _G.screen_h, _G.density_scale)
    return true
end

return lcd_drv
