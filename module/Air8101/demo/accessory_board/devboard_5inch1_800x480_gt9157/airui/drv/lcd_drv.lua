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
]]

local function lcd_drv_init()
    local result = lcd.init("h050iwv",
        {
            pin_rst = 36, -- 复位引脚
            -- pin_pwr = 7,  -- 背光控制引脚GPIO端口号
            port = lcd.RGB, -- 驱动端口
            direction = 0, -- lcd屏幕方向 0:0° 1:90° 2:180° 3:270°，屏幕方向和分辨率保存一致
            w = 800,      -- lcd 水平分辨率
            h = 480,      -- lcd 竖直分辨率
            xoffset = 0,  -- x偏移(不同屏幕ic 不同屏幕方向会有差异)
            yoffset = 0,  -- y偏移(不同屏幕ic 不同屏幕方向会有差异))
        })
log.info("lcd.init", result)

    -- 初始化AirUI
    local width, height = lcd.getSize()
    local result = airui.init(width, height)
    if not result then
        log.error("airui", "init failed")
    end

    lcd.setupBuff(nil, true)     -- 设置帧缓冲区，使用heap内存
    lcd.autoFlush(false)         -- 禁止自动刷新

    -- 加载中文字体
    if rtos.bsp() ~= "Air8101" then
        -- PC端/Air8000/780EHM 从14号固件/114号固件中加载hzfont字库，从而支持12-255~号中文显示
        airui.font_load({
            type = "hzfont",       -- 字体类型，可选 "hzfont" 或 "bin"
            path = nil,            -- 字体路径，对于 "hzfont"，传 nil 则使用内置字库
            size = 20,             -- 字体大小，默认 16
            cache_size = 1024,     -- 缓存字数大小，默认 2048
            antialias = 1,         -- 抗锯齿等级1-3，默认 1
        })
    else
        -- Air8101使用104号固件将字体文件烧录到文件系统，从文件系统中加载hzfont字库，从而支持12-255号中文显示
        airui.font_load({
            type = "hzfont",                 -- 字体类型，可选 "hzfont" 或 "bin"
            path = "/MiSans_gb2312.ttf",     -- 字体路径，对于 "hzfont"，传 nil 则使用内置字库
            size = 20,                       -- 字体大小，默认 16
            cache_size = 1024,               -- 缓存字数大小，默认 2048
            antialias = 1,                   -- 抗锯齿等级1-3，默认 1
            -- load_to_psram= true,
            global = true
        })
    end

    -- airui.set_rotation(270)

    -- 查询当前固件内AirUI核心库版本
    local version_result = airui.version()

    -- 打印查询结果
    log.info("airui", "version -> " .. version_result)
end

lcd_drv_init()