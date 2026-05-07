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
_G.screen_w, _G.screen_h = 480, 800
_G.screen_size = 5.0  -- 屏幕物理尺寸(英寸)，用于像素密度计算
_G.density_scale = 1.0 -- 默认值，lcd_drv.init() 中根据实际PPI更新
_G.is_landscape = false
local lcd_drv = {}

function lcd_drv.init()
    gpio.setup(3, 0)

    local lcd_param = {
        port = lcd.RGB,
        pin_rst = 9,
        pin_clk = 2,
        pin_sda = 4,
        pin_cs = 3,
        direction = 0,
        pclk = lcd.PCLK_RISING,
        w = 480,
        h = 854,
        xoffset = 0,
        yoffset = 0,
        hbp = 30,
        hspw = 6,
        hfp = 12,
        vbp = 30,
        vspw = 1,
        vfp = 12,
        bus_speed = 26 * 1000 * 1000,
    }
    local result = lcd.init("custom", lcd_param)
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


        local rst_pin = gpio.setup(9, 1)
        rst_pin(1)
        sys.wait(20);
        rst_pin(0)
        sys.wait(20);
        rst_pin(1)
        sys.wait(120);

        -- st7701s
        lcd.cmd(0xFF)
        lcd.data(0x77)
        lcd.data(0x01)
        lcd.data(0x00)
        lcd.data(0x00)
        lcd.data(0x13)
        lcd.cmd(0xEF)
        lcd.data(0x08)
        -- /*-------------------------------Bank0 Setting--------------------------------*/
        -- /*--------------------------Display Control setting---------------------------*/
        lcd.cmd(0xFF)
        lcd.data(0x77)
        lcd.data(0x01)
        lcd.data(0x00)
        lcd.data(0x00)
        lcd.data(0x10)
        lcd.cmd(0xC0)
        lcd.data(0xE9)
        lcd.data(0x03)
        lcd.cmd(0xC1)
        lcd.data(0x11)
        lcd.data(0x02)
        lcd.cmd(0xC2)
        lcd.data(0x01)
        lcd.data(0x08)
        lcd.cmd(0xCC)
        lcd.data(0x18)
        -- /*---------------------------Gamma Cluster Setting----------------------------*/
        lcd.cmd(0xB0)
        lcd.data(0x00)
        lcd.data(0x0D)
        lcd.data(0x14)
        lcd.data(0x0D)
        lcd.data(0x10)
        lcd.data(0x05)
        lcd.data(0x02)
        lcd.data(0x08)
        lcd.data(0x08)
        lcd.data(0x1E)
        lcd.data(0x05)
        lcd.data(0x13)
        lcd.data(0x11)
        lcd.data(0xA3)
        lcd.data(0x29)
        lcd.data(0x18)
        lcd.cmd(0xB1)
        lcd.data(0x00)
        lcd.data(0x0C)
        lcd.data(0x14)
        lcd.data(0x0C)
        lcd.data(0x10)
        lcd.data(0x05)
        lcd.data(0x03)
        lcd.data(0x08)
        lcd.data(0x07)
        lcd.data(0x20)
        lcd.data(0x05)
        lcd.data(0x13)
        lcd.data(0x11)
        lcd.data(0xA4)
        lcd.data(0x29)
        lcd.data(0x18)
        -- /*-----------------------------End Gamma Setting------------------------------*/
        -- /*------------------------End Display Control setting-------------------------*/
        -- /*-----------------------------Bank0 Setting  End-----------------------------*/
        -- /*-------------------------------Bank1 Setting--------------------------------*/
        -- /*--------------------- Power Control Registers Initial ----------------------*/
        lcd.cmd(0xFF)
        lcd.data(0x77)
        lcd.data(0x01)
        lcd.data(0x00)
        lcd.data(0x00)
        lcd.data(0x11)
        lcd.cmd(0xB0)
        lcd.data(0x6C)
        -- /*--------------------------------Vcom Setting--------------------------------*/
        lcd.cmd(0xB1)
        lcd.data(0x43)
        -- /*------------------------------End Vcom Setting------------------------------*/
        lcd.cmd(0xB2)
        lcd.data(0x87)
        lcd.cmd(0xB3)
        lcd.data(0x80)
        lcd.cmd(0xB5)
        lcd.data(0x47)
        lcd.cmd(0xB7)
        lcd.data(0x85)
        lcd.cmd(0xB8)
        lcd.data(0x20)
        lcd.cmd(0xB9)
        lcd.data(0x10)
        lcd.cmd(0xC1)
        lcd.data(0x78)
        lcd.cmd(0xC2)
        lcd.data(0x78)
        lcd.cmd(0xD0)
        lcd.data(0x88)
        -- /*--------------------End Power Control Registers Initial --------------------*/
        sys.wait(100)
        -- /*--------------------------------GIP Setting---------------------------------*/
        lcd.cmd(0xE0)
        lcd.data(0x00)
        lcd.data(0x00)
        lcd.data(0x02)
        lcd.cmd(0xE1)
        lcd.data(0x08)
        lcd.data(0x00)
        lcd.data(0x0A)
        lcd.data(0x00)
        lcd.data(0x07)
        lcd.data(0x00)
        lcd.data(0x09)
        lcd.data(0x00)
        lcd.data(0x00)
        lcd.data(0x33)
        lcd.data(0x33)
        lcd.cmd(0xE2)
        lcd.data(0x00)
        lcd.data(0x00)
        lcd.data(0x00)
        lcd.data(0x00)
        lcd.data(0x00)
        lcd.data(0x00)
        lcd.data(0x00)
        lcd.data(0x00)
        lcd.data(0x00)
        lcd.data(0x00)
        lcd.data(0x00)
        lcd.data(0x00)
        lcd.data(0x00)
        lcd.cmd(0xE3)
        lcd.data(0x00)
        lcd.data(0x00)
        lcd.data(0x33)
        lcd.data(0x33)
        lcd.cmd(0xE4)
        lcd.data(0x44)
        lcd.data(0x44)
        lcd.cmd(0xE5)
        lcd.data(0x0E)
        lcd.data(0x60)
        lcd.data(0xA0)
        lcd.data(0xA0)
        lcd.data(0x10)
        lcd.data(0x60)
        lcd.data(0xA0)
        lcd.data(0xA0)
        lcd.data(0x0A)
        lcd.data(0x60)
        lcd.data(0xA0)
        lcd.data(0xA0)
        lcd.data(0x0C)
        lcd.data(0x60)
        lcd.data(0xA0)
        lcd.data(0xA0)
        lcd.cmd(0xE6)
        lcd.data(0x00)
        lcd.data(0x00)
        lcd.data(0x33)
        lcd.data(0x33)
        lcd.cmd(0xE7)
        lcd.data(0x44)
        lcd.data(0x44)
        lcd.cmd(0xE8)
        lcd.data(0x0D)
        lcd.data(0x60)
        lcd.data(0xA0)
        lcd.data(0xA0)
        lcd.data(0x0F)
        lcd.data(0x60)
        lcd.data(0xA0)
        lcd.data(0xA0)
        lcd.data(0x09)
        lcd.data(0x60)
        lcd.data(0xA0)
        lcd.data(0xA0)
        lcd.data(0x0B)
        lcd.data(0x60)
        lcd.data(0xA0)
        lcd.data(0xA0)
        lcd.cmd(0xEB)
        lcd.data(0x02)
        lcd.data(0x01)
        lcd.data(0xE4)
        lcd.data(0xE4)
        lcd.data(0x44)
        lcd.data(0x00)
        lcd.data(0x40)
        lcd.cmd(0xEC)
        lcd.data(0x02)
        lcd.data(0x01)
        lcd.cmd(0xED)
        lcd.data(0xAB)
        lcd.data(0x89)
        lcd.data(0x76)
        lcd.data(0x54)
        lcd.data(0x01)
        lcd.data(0xFF)
        lcd.data(0xFF)
        lcd.data(0xFF)
        lcd.data(0xFF)
        lcd.data(0xFF)
        lcd.data(0xFF)
        lcd.data(0x10)
        lcd.data(0x45)
        lcd.data(0x67)
        lcd.data(0x98)
        lcd.data(0xBA)
        lcd.cmd(0xEF)
        lcd.data(0x08)
        lcd.data(0x08)
        lcd.data(0x08)
        lcd.data(0x45)
        lcd.data(0x3F)
        lcd.data(0x54)
        lcd.cmd(0xFF)
        lcd.data(0x77)
        lcd.data(0x01)
        lcd.data(0x00)
        lcd.data(0x00)
        lcd.data(0x13)
        lcd.cmd(0xE8)
        lcd.data(0x00)
        lcd.data(0x0E)
        -- /*------------------------------End GIP Setting-------------------------------*/
        -- /*-------------------- Power Control Registers Initial End--------------------*/
        -- /*-------------------------------Bank1 Setting--------------------------------*/
        lcd.cmd(0xFF)
        lcd.data(0x77)
        lcd.data(0x01)
        lcd.data(0x00)
        lcd.data(0x00)
        lcd.data(0x00)
        lcd.cmd(0x11)
        sys.wait(120)
        lcd.cmd(0xFF)
        lcd.data(0x77)
        lcd.data(0x01)
        lcd.data(0x00)
        lcd.data(0x00)
        lcd.data(0x13)
        lcd.cmd(0xE8)
        lcd.data(0x00)
        lcd.data(0x0C)
        sys.wait(10)
        lcd.cmd(0xE8)
        lcd.data(0x00)
        lcd.data(0x00)
        lcd.cmd(0xFF)
        lcd.data(0x77)
        lcd.data(0x01)
        lcd.data(0x00)
        lcd.data(0x00)
        lcd.data(0x00)
        lcd.cmd(0x29)
        lcd.cmd(0x3a)
        lcd.data(0x77)
        lcd.cmd(0x36)
        lcd.data(0x08)
        sys.wait(20)

        -- 加载中文字体
        if not _G.model_str:find("Air8101") then
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
                load_to_psram= true,
                global = true
            })
        end

        airui.set_rotation(180)
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
    pwm.setup(1, 10000, 100) -- 通道1，10kHz频率，100%占空比
    pwm.open(1, 10000, 100)
end

return lcd_drv