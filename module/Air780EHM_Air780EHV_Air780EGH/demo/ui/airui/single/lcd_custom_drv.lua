--[[
@module  lcd_custom_drv
@summary LCD自定义显示驱动模块，基于lcd核心库
@version 1.0
@date    2026.01.29
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
    local result = lcd.init("custom",
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
            pin_rst = 36,      -- lcd复位引脚
            direction = 0,     -- lcd屏幕方向 0:0° 1:90° 2:180° 3:270°，屏幕方向和分辨率保存一致
            w = 320,           -- lcd 水平分辨率
            h = 480,           -- lcd 竖直分辨率
            xoffset = 0,       -- x偏移(不同屏幕ic 不同屏幕方向会有差异)
            yoffset = 0,       -- y偏移(不同屏幕ic 不同屏幕方向会有差异)
            bus_speed = 80000000,
            sleepcmd = 0x10,             -- 睡眠命令：SLPIN命令，进入睡眠模式
            wakecmd = 0x11,              -- 唤醒命令：SLPOUT命令，退出睡眠模式
            interface_mode = lcd.WIRE_4_BIT_8_INTERFACE_I,  -- 接口模式：4线SPI 8bit模式I
        })

    log.info("lcd.init", result)


    -------------------------------------自定义初始化配置（开始）-------------------------------------------

    -- 0. 内存访问控制 (MADCTL: 0x36)
    -- 控制屏幕扫描方向、显示方向：0x40 = 正常竖屏、修复左右镜像/显示翻转
    lcd.cmd(0x36, 0x40)

    -- 1. 像素格式设置 (COLMOD: 0x3A)
    -- 设置LCD像素接口格式：0x05 = 16位 RGB565（通用色彩格式，速度快、占用资源小）
    lcd.cmd(0x3A, 0x05)

    -- 创建20字节固定数据缓冲区，用于发送多参数指令，缓冲区不可扩容
    local buff1 = zbuff.create(20)

    -- 2. 帧率控制2 (FRCTRL2: 0xB2)
    -- 配置空闲模式下的帧率、消隐周期、时钟分频等显示时序参数
    buff1:write(0x0C, 0x0C, 0x00, 0x33, 0x33)
    lcd.cmd(0xB2, buff1, 5)

    -- 3. 门控设置 (GCTRL: 0xB7)
    -- 配置栅极扫描控制参数，调节行扫描时序与开关特性
    lcd.cmd(0xB7, 0x35)

    -- 4. VCOM 电压设置 (VCOMS: 0xBB)
    -- 设置公共电极电压VCOM，直接影响屏幕对比度与显示清晰度
    lcd.cmd(0xBB, 0x32)

    -- 5. 电源控制3 (PVCTRL3: 0xC2)
    -- 配置升压电路工作模式，确保LCD驱动电压稳定
    lcd.cmd(0xC2, 0x01)

    -- 6. 电源控制4 (PVCTRL4: 0xC3)
    -- 设置VCOMH高电平电压，控制屏幕最大亮度
    lcd.cmd(0xC3, 0x15)

    -- 7. 电源控制5 (PVCTRL5: 0xC4)
    -- 设置VCOML低电平电压，控制屏幕最小亮度
    lcd.cmd(0xC4, 0x20)

    -- 8. VCOM 偏移控制 (VMFCTRL: 0xC6)
    -- 微调VCOM电压偏移量，优化显示对比度、消除闪烁
    lcd.cmd(0xC6, 0x0F)

    -- 9. 电源控制1 (PVCTRL1: 0xD0)
    -- 核心电源启动配置，设置LCD驱动芯片的供电启动参数
    buff1:write(0xA4, 0xA1)
    lcd.cmd(0xD0, buff1, 2)

    -- 10. 正伽马校正 (GMCTRP1: 0xE0)
    -- 14组参数：调整亮部色彩灰度曲线，优化高亮区域显示效果、色彩鲜艳度
    buff1:write(0xD0, 0x08, 0x0E, 0x09, 0x09, 0x05, 0x31, 0x33, 0x48, 0x17, 0x14, 0x15, 0x31, 0x34)
    lcd.cmd(0xE0, buff1, 14)

    -- 11. 负伽马校正 (GMCTRN1: 0xE1)
    -- 14组参数：调整暗部色彩灰度曲线，优化暗场细节、黑色纯净度
    buff1:write(0xD0, 0x08, 0x0E, 0x09, 0x09, 0x15, 0x31, 0x33, 0x48, 0x17, 0x14, 0x15, 0x31, 0x34)
    lcd.cmd(0xE1, buff1, 14)

    -- 结束自定义初始化流程，通知驱动初始化完成
    lcd.user_done()

    -- 清屏：清除初始化过程中的屏幕残留杂色
    lcd.clear()

    -- 释放缓冲区内存，避免资源占用
    buff1:free()

    -------------------------------------自定义初始化配置（结束）-------------------------------------------

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