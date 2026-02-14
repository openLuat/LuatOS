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


local lcd_drv = {}

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

function lcd_drv.init()
    local result = lcd.init("h050iwv",
        {
            pin_pwr = 8,    -- 背光控制引脚GPIO端口号
            port = lcd.RGB, -- 驱动端口
            direction = 0,  -- lcd屏幕方向 0:0° 1:90° 2:180° 3:270°，屏幕方向和分辨率保存一致
            w = 800,        -- lcd 水平分辨率
            h = 480,        -- lcd 竖直分辨率
            xoffset = 0,    -- x偏移(不同屏幕ic 不同屏幕方向会有差异)
            yoffset = 0,    -- y偏移(不同屏幕ic 不同屏幕方向会有差异)
        })

    log.info("lcd.init", result)

    if result then
        -- 开启缓冲区, 刷屏速度会加快, 但也消耗2倍屏幕分辨率的内存
        lcd.setupBuff(nil, true)
        lcd.autoFlush(false)

        -- 初始化AirUI
        local width, height = lcd.getSize()
        local result = airui.init(width, height)
        if not result then
            log.error("airui", "init failed")
            return result
        end

        -- 加载真实键盘，PC端可以使用键盘输入
        airui.keyboard_enable_system(true)

        -- 加载中文字体
        -- PC端/Air8000/780EHM 从14号固件/114号固件中加载hzfont字库，从而支持12-255号中文显示
        -- airui.font_load({
        --     type = "hzfont", -- 字体类型，可选 "hzfont" 或 "bin"
        --     path = nil,    -- 字体路径，对于 "hzfont"，传 nil 则使用内置字库
        --     size = 20,     -- 字体大小，默认 16
        --     cache_size = 1048, -- 缓存字数大小，默认 2048
        --     antialias = 1, -- 抗锯齿等级，默认 4
        -- })

        -- Air8101使用104号固件将字体文件烧录到文件系统，从文件系统中加载hzfont字库，从而支持12-255号中文显示
        airui.font_load({
            type = "hzfont",             -- 字体类型，可选 "hzfont" 或 "bin"
            path = "/MiSans_gb2312.ttf", -- 字体路径，对于 "hzfont"，传 nil 则使用内置字库
            size = 20,                   -- 字体大小，默认 16
            cache_size = 1048,           -- 缓存字数大小，默认 2048
            antialias = 2,               -- 抗锯齿等级，默认 4
            to_psram = true              -- 将.ttf文件加载到PSRAM中，默认不加载
        })

        -- 开启背光引脚供电
        gpio.setup(8, 1)

        -- 查询当前固件内AirUI核心库版本，V1.0.3新增接口
        log.info("airui", "version -> " .. airui.version())

        return result
    end

    return result
end

return lcd_drv
