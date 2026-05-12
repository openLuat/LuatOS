-- Naming: local vars 2-4 chars, local funcs 2-5 chars, public API unchanged
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
_G.screen_w, _G.screen_h = 1024, 600
_G.screen_size = 7.0  -- 屏幕物理尺寸(英寸)，用于像素密度计算
_G.density_scale = 1.0 -- 默认值，lcd_drv.init() 中根据实际PPI更新
_G.is_landscape = false
local lcd_drv = {}

function lcd_drv.init()
    local res = lcd.init("hx8282",
    {
        pin_rst = 36,   -- 复位引脚
        pin_pwr = 7,    -- 背光控制引脚GPIO端口号
        port = lcd.RGB, -- 驱动端口
        direction = 0,  -- lcd屏幕方向 0:0° 1:90° 2:180° 3:270°，屏幕方向和分辨率保存一致
        w = 1024,       -- lcd 水平分辨率
        h = 600,        -- lcd 竖直分辨率
        xoffset = 0,    -- x偏移(不同屏幕ic 不同屏幕方向会有差异)
        yoffset = 0,    -- y偏移(不同屏幕ic 不同屏幕方向会有差异)
    })
    log.info("ld", res)

    if res then
        -- 初始化AirUI
        local w, h = lcd.getSize()
        local res = airui.init(w, h)
        if not res then
            log.error("au", "init failed")
        end

        lcd.setupBuff(nil, true) -- 设置帧缓冲区，使用heap内存
        lcd.autoFlush(false)     -- 禁止自动刷新

        

		-- 加载中文字体
		if not _G.model_str:find("Air8101") then
			-- PC端/Air8000/780EHM 从14号固件/114号固件中加载hzfont字库，从而支持12-255~号中文显示
			airui.font_load({
				type = "hzfont",   -- 字体类型，可选 "hzfont" 或 "bin"
				path = nil,        -- 字体路径，对于 type = "hzfont"，传path = nil, 则使用内置字库
				size = 20,         -- 字体大小，默认 16
				cache_size = 1024, -- 缓存字数大小，默认 2048
				antialias = 1,     -- 抗锯齿等级1-3，默认 1
			})
		else
			-- Air8101使用104号固件将字体文件烧录到文件系统，从文件系统中加载hzfont字库，从而支持12-255号中文显示
			airui.font_load({
				type = "hzfont",             -- 字体类型，可选 "hzfont" 或 "bin"
				path = "/MiSans_gb2312.ttf", -- 字体路径，对于 type = "hzfont"，传path = ".ttf文件路径", 则使用对应的.ttf字体
				size = 20,                   -- 字体大小，默认 16
				cache_size = 1024,           -- 缓存字数大小，默认 2048
				antialias = 1,               -- 抗锯齿等级1-3，默认 1
				global = true
			})
		end

        -- airui.set_rotation(180)
        local ver = airui.version()
        log.info("au", "version -> " .. ver)

        local rot = airui.get_rotation()
        local pw, ph = lcd.getSize()
        if rot == 0 or rot == 180 then
            _G.screen_w, _G.screen_h = pw, ph
        else
            _G.screen_h, _G.screen_w = pw, ph
        end
        _G.is_landscape = (_G.screen_w > _G.screen_h)

        -- 计算像素密度缩放比 (基准: 5寸480×800 ≈ 187 PPI)
        local dg = math.sqrt(_G.screen_w * _G.screen_w + _G.screen_h * _G.screen_h)
        local bp = 186.6  -- sqrt(480²+800²) / 5.0
        _G.density_scale = (dg / _G.screen_size) / bp
        _G.density_scale = math.max(1.0, _G.density_scale) -- 只放大不缩小
    end
end

function lcd_drv.backlight_on()
    gpio.setup(7, 1)
end

return lcd_drv
