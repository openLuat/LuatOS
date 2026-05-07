--[[
@module  lcd_inner_drv
@summary LCD内置显示驱动模块，基于lcd核心库
@version 1.0
@date    2026.02.05
@author  江访
@usage
本模块为LCD显示驱动功能模块，主要功能包括：
1、初始化 LCD屏幕；
2、配置LCD显示参数和显示缓冲区；
3、初始化AirUI;
4、支持多种屏幕方向和分辨率设置；

对外接口：无
]]




--[[
初始化LCD显示驱动；

@api lcd_drv_init()
@summary 配置并初始化LCD屏幕
@return boolean 初始化成功返回true，失败返回false

@usage
-- 初始化LCD显示
local result = lcd_drv_init()
if result then
    log.info("LCD初始化成功")
else
    log.error("LCD初始化失败")
end
]]


local function lcd_drv_init()
    -- Air8000开发板上，使能lcd供电的ldo电源开关
    -- 如果你使用的不是Air8000开发板，而是自己设计的硬件，需要根据实际情况来配置电源使能
    gpio.setup(141, 1)

    local result = lcd.init("st7796",
        {
            -- 背光控制引脚GPIO端口号
            -- 此处如果配置了背光控制引脚，在lcd初始化之后，就会立即点亮背光，会先白屏一小段时间，然后才会显示画面，这是正常现象
            --
            -- 如果你无法接受这种现象，可以在此处将pin_pwr配置为nil，在代码逻辑显示开机第一个画面之后，再手动通过gpio.setup接口去控制背光引脚
            -- 如果采用手动控制背光的方式，需要注意的是，在低功耗场景：
            -- 使用lcd.sleep接口休眠lcd前，需要手动通过gpio接口关闭背光；
            -- 使用lcd.wakeup接口唤醒lcd后，需要手动控通过gpio接口打开背光；
            pin_pwr = 1,

            port = lcd.HWID_0, -- 驱动端口
            pin_rst = 2,       -- lcd复位引脚
            direction = 0,     -- lcd屏幕方向 0:0° 1:90° 2:180° 3:270°，屏幕方向和分辨率保存一致
            w = 320,           -- lcd 水平分辨率
            h = 480,           -- lcd 竖直分辨率
            xoffset = 0,       -- x偏移(不同屏幕ic 不同屏幕方向会有差异)
            yoffset = 0,       -- y偏移(不同屏幕ic 不同屏幕方向会有差异)
            bus_speed = 80000000
        })

    log.info("lcd.init", result)

    if result then
        -- 开启缓冲区, 刷屏速度会加快（效果不明显，如果有需要，在自己的项目上打开实际体验一下）, 但也消耗2倍屏幕分辨率的内存
        -- lcd.setupBuff(nil, true)
        -- lcd.autoFlush(false)

        -- 初始化AirUI
        local width, height = lcd.getSize()
        local result = airui.init(width, height)
        if not result then
            log.error("airui", "init failed")
            return result
        end

        -- 加载中文字体
        if rtos.bsp() ~= "Air8101" then
            -- PC端/Air8000/780EHM 从14号固件/114号固件中加载hzfont字库，从而支持12-255~号中文显示
            airui.font_load({
                type = "hzfont",   -- 字体类型，可选 "hzfont" 或 "bin"
                path = nil,        -- 字体路径，对于 "hzfont"，传 nil 则使用内置字库
                size = 20,         -- 字体大小，默认 16
                cache_size = 1048, -- 缓存字数大小，默认 2048
                antialias = 1,     -- 抗锯齿等级1-3，默认 1
            })
        else
            -- Air8101使用104号固件将字体文件烧录到文件系统，从文件系统中加载hzfont字库，从而支持12-255号中文显示
            airui.font_load({
                type = "hzfont",             -- 字体类型，可选 "hzfont" 或 "bin"
                path = "/MiSans_gb2312.ttf", -- 字体路径，对于 "hzfont"，传 nil 则使用内置字库
                size = 20,                   -- 字体大小，默认 16
                cache_size = 1048,           -- 缓存字数大小，默认 2048
                antialias = 1,               -- 抗锯齿等级1-3，默认 1
                -- load_to_psram= true,
                global = true
            })
        end

        -- 查询当前固件内AirUI核心库版本
        local version_result = airui.version()

        -- 打印查询结果
        log.info("airui", "version -> " .. version_result)

    end

end

lcd_drv_init()