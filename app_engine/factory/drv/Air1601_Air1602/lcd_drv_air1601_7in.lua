-- nconv: var2-4 fn2-5 tag-short
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

local p, pr = lcd.RGB, 15

function lcd_drv.init()
    local r = lcd.init("custom", {
        port      = p,
        pin_rst   = pr,
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

    log.info("lcd", r)

    if r then
        local w, h = lcd.getSize()
        r = airui.init(w, h)
        if not r then
            log.error("arui", "init failed")
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

        local vr = airui.version()
        log.info("arui", "version -> " .. vr)

        local rot = airui.get_rotation()
        local pw, ph = lcd.getSize()
        if rot == 0 or rot == 180 then
            _G.screen_w, _G.screen_h = pw, ph
        else
            _G.screen_h, _G.screen_w = pw, ph
        end
        _G.is_landscape = (_G.screen_w > _G.screen_h)

        -- 计算像素密度缩放比 (基准: 5寸480×800 ≈ 187 PPI)
        local dp = math.sqrt(_G.screen_w * _G.screen_w + _G.screen_h * _G.screen_h)
        local bp = 186.6                             -- sqrt(480²+800²) / 5.0
        _G.density_scale = (dp / _G.screen_size) / bp
        _G.density_scale = math.max(1.0, _G.density_scale) -- 只放大不缩小
    end
end

function lcd_drv.backlight_on()
    pwm.setup(3, 1000, 100)
    pwm.open(3, 1000, 100)
end

return lcd_drv
