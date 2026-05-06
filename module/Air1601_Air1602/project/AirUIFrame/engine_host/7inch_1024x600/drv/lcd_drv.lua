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
		-- pin_dc    = 0xff,    -- RGB接口不需要DC引脚
		pin_clk   = 23, -- SPI 时钟引脚 (用于初始化)
		pin_sda   = 22, -- SPI 数据引脚
		pin_cs    = 2,  -- SPI 片选引脚
		-- pin_pwr   = bl,
		pin_rst   = pin_rst,
		direction = 0,
		w         = 1024,
		h         = 600,
		xoffset   = 0,
		yoffset   = 0,
		-- 时序参数采用最新 lcddemo.lua 中的配置 (7寸 1024x600)
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
		-- 初始化AirUI
		local width, height = lcd.getSize()
		local result = airui.init(width, height)
		if not result then
			log.error("airui", "init failed")
		end

		lcd.setupBuff(nil, true) -- 设置帧缓冲区，使用heap内存
		lcd.autoFlush(false)     -- 禁止自动刷新

		local rst_pin = gpio.setup(pin_rst, 1)
		rst_pin(1)
		sys.wait(20);
		rst_pin(0)
		sys.wait(20);
		rst_pin(1)
		sys.wait(120);

		-- ============================================================
		-- 注意：原720x1280驱动中的NV3052C初始化命令段已全部删除，
		-- 因为1024x600屏幕（HX8282+HX8696或TK101BOG-50）不需要这些命令。
		-- 如需自定义初始化，可在此处添加 lcd.cmd(...)
		-- ============================================================

		-- 加载中文字体
		if rtos.bsp() ~= "Air8101" then
			-- PC端/Air8000/780EHM 从14号固件/114号固件中加载hzfont字库，从而支持12-255~号中文显示
			airui.font_load({
				type = "hzfont",   -- 字体类型，可选 "hzfont" 或 "bin"
				path = nil,        -- 字体路径，对于 "hzfont"，传 nil 则使用内置字库
				size = 20,         -- 字体大小，默认 16
				cache_size = 1024, -- 缓存字数大小，默认 2048
				antialias = 1,     -- 抗锯齿等级1-3，默认 1
			})
		else
			-- Air8101使用104号固件将字体文件烧录到文件系统，从文件系统中加载hzfont字库，从而支持12-255号中文显示
			airui.font_load({
				type = "hzfont",             -- 字体类型，可选 "hzfont" 或 "bin"
				path = "/MiSans_gb2312.ttf", -- 字体路径，对于 "hzfont"，传 nil 则使用内置字库
				size = 20,                   -- 字体大小，默认 16
				cache_size = 1024,           -- 缓存字数大小，默认 2048
				antialias = 1,               -- 抗锯齿等级1-3，默认 1
				-- load_to_psram= true,
				global = true
			})
		end

		-- 查询当前固件内AirUI核心库版本
		local version_result = airui.version()

		-- 打印查询结果
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
    pwm.setup(3, 1000, 100)
    pwm.open(3, 1000, 100)
end

return lcd_drv