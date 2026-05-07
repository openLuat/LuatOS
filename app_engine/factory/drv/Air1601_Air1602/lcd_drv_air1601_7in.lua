--[[
@module  lcd_drv
@summary LCD显示驱动模块，基于lcd核心库
@version 1.0
@date    2025.12.1
@author  江访
@usage
本模块为LCD显示驱动功能模块，主要功能包括：
1、初始化 LCD屏幕；
2、配置LCD显示参数和显示缓冲区；
3、初始化AirUI;
4、支持多种屏幕方向和分辨率设置；

对外接口：
1、lcd_drv.init()：初始化LCD显示驱动
]]


--[[
初始化LCD显示驱动；

@api lcd_drv.init()
@summary 配置并初始化LCD屏幕
@return boolean 初始化成功返回true，失败返回false

@usage
-- 初始化LCD显示
local result = lcd_drv.init()
if result then
    log.info("LCD初始化成功")
else
    log.error("LCD初始化失败")
end
]]
local lcd_drv = {}
_G.screen_w, _G.screen_h = 1024, 600      -- 修改为1024x600
_G.screen_size = 7.0  -- 屏幕物理尺寸(英寸)，用于像素密度计算
_G.density_scale = 1.0 -- 默认值，lcd_drv.init() 中根据实际PPI更新
_G.is_landscape = false

local port, pin_rst, bl = lcd.RGB, 15, 2

function lcd_drv.init()
    local result = lcd.init("custom", {
        port      = port,
        pin_rst   = pin_rst,
        direction = 0,
        w         = 1024,
        h         = 600,
        xoffset   = 0,
        yoffset   = 0,
        -- 时序参数采用 lcddemo.lua 中的 custom 配置
		hbp       = 120,
		hspw      = 40,
		hfp       = 150,
		vbp       = 23,
		vspw      = 10,
		vfp       = 12,
		bus_speed = 51 * 1000 * 1000,   -- 51 MHz
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
        local base_ppi = 186.6                             -- sqrt(480²+800²) / 5.0
        _G.density_scale = (diagonal_px / _G.screen_size) / base_ppi
        _G.density_scale = math.max(1.0, _G.density_scale) -- 只放大不缩小
    end
end

function lcd_drv.backlight_on()
    pwm.setup(3, 1000, 100)
    pwm.open(3, 1000, 100)
end

return lcd_drv