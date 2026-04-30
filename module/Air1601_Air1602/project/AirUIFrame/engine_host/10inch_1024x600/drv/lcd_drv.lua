--[[
@module  lcd_drv
@summary LCD显示驱动模块，基于lcd核心库
@version 1.0
@date    2026.04.28
@author  江访
@usage
本模块为LCD显示驱动功能模块，主要功能包括：
1、初始化 LCD屏幕；
2、配置LCD显示参数和显示缓冲区；
3、初始化AirUI;
4、支持多种屏幕方向和分辨率设置；
5、背光控制；

对外接口：
1、lcd_drv.init()：初始化LCD显示驱动
2、lcd_drv.backlight_on()：开启背光
--]]

local lcd_drv = {}

_G.screen_w, _G.screen_h = 1024, 600
_G.screen_size = 10.0  -- 屏幕物理尺寸(英寸)，用于像素密度计算
_G.density_scale = 1.0 -- 默认值，lcd_drv.init() 中根据实际PPI更新
_G.is_landscape = true

local port, pin_rst, bl = lcd.RGB, 15, 2

function lcd_drv.init()
    local result = lcd.init("custom", {
        port = port,
        hbp = 140,
        hspw = 20,
        hfp = 160,
        vbp = 20,
        vspw = 3,
        vfp = 12,
        bus_speed = 50 * 1000 * 1000,
        pin_pwr = bl,
        pin_rst = pin_rst,
        direction = 0,
        w = 1024,
        h = 600
    })

    log.info("lcd.init", result)

    if result then
        local width, height = lcd.getSize()
        local result = airui.init(width, height)
        if not result then
            log.error("airui", "init failed")
        end

        lcd.setupBuff(nil, true)
        lcd.autoFlush(false)

        airui.font_load({
            type = "hzfont",
            path = nil,
            size = 20,
            cache_size = 1024,
            antialias = 1,
        })

        local version_result = airui.version()
        log.info("airui", "version -> " .. version_result)

        local rotation = airui.get_rotation()
        local phys_w, phys_h = lcd.getSize()
        if rotation == 0 or rotation == 180 then
            _G.screen_w, _G.screen_h = phys_w, phys_h
        else
            _G.screen_h, _G.screen_w = phys_w, phys_h
        end
        _G.is_landscape = (_G.screen_w > _G.screen_h)

        -- 计算像素密度缩放比 (基准: 5寸480×800 ≈ 187 PPI)
        local diagonal_px = math.sqrt(_G.screen_w * _G.screen_w + _G.screen_h * _G.screen_h)
        local base_ppi = 186.6  -- sqrt(480²+800²) / 5.0
        _G.density_scale = (diagonal_px / _G.screen_size) / base_ppi
        _G.density_scale = math.max(1.0, _G.density_scale) -- 只放大不缩小
    end
end

function lcd_drv.backlight_on()
    gpio.setup(5, 1)
end

return lcd_drv
