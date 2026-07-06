--[[
@module  lcd_custom_drv
@summary ST6201 4.3 寸 480x272 LCD 驱动（HWID_0 硬件 SPI 接口）
@version 1.0
@date    2026.07.06
@author  蒋骞
@usage
本模块为LCD显示驱动功能模块，主要功能包括：
1、初始化 LCD屏幕；
2、配置LCD显示参数和显示缓冲区；
3、初始化AirUI;
4、支持多种屏幕方向和分辨率设置；

对外接口：无
]]

-- 背光控制引脚
local PIN_BL = 1

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
            
            port = lcd.HWID_0,                             -- 驱动端口
            w = 480,                                       -- lcd 水平分辨率
            h = 272,                                       -- lcd 竖直分辨率
            pin_pwr = 1,
            direction = 0,                                 -- lcd屏幕方向 0:0° 1:90° 2:180° 3:270°，屏幕方向和分辨率保存一致
            xoffset = 0,                                   -- x偏移(不同屏幕ic 不同屏幕方向会有差异)
            yoffset = 0,                                   -- y偏移(不同屏幕ic 不同屏幕方向会有差异)
            bus_speed = 80*1000*1000,
            sleepcmd = 0x10,                               -- 睡眠命令：SLPIN命令，进入睡眠模式
            wakecmd = 0x11,                                -- 唤醒命令：SLPOUT命令，退出睡眠模式
            interface_mode = lcd.WIRE_4_BIT_8_INTERFACE_I, -- 接口模式：4线SPI 8bit模式I
            rb_swap          = true,           -- 红/蓝通道交换
        })

    log.info("lcd.init", result)


    -------------------------------------初始化序列（开始）-------------------------------------------

    --退出睡眠模式
    lcd.cmd(0x11); 
    --手册要求等待120ms稳定
    sys.wait(120)
    --设置颜色格式为RGB565(0x01)
    lcd.cmd(0x3A, string.char(0x01)); 
    sys.wait(10)
    --设置扫描方向为BGR顺序（配合 rb_swap）
    lcd.cmd(0x36, string.char(0x00)); 
    sys.wait(1)  -- BGR 顺序（配合 rb_swap）
    --
    lcd.cmd(0x40, string.char(0x00))
    --设置为4线SPI模式
    lcd.cmd(0x41, string.char(0x00))   -- 4线SPI模式
        --进入显示反转模式
    lcd.cmd(0x21); 
    sys.wait(120)

    -- 设置全屏地址窗口（列 0~479，行 0~271）
    lcd.cmd(0x2A, string.char(0x00, 0x00, 0x01, 0xDF))
    lcd.cmd(0x2B, string.char(0x00, 0x00, 0x01, 0x0F))

    --开启显示
    lcd.cmd(0x29); 
    --必须等待20ms保持稳定
    sys.wait(20)

    -- 结束自定义初始化流程，通知驱动初始化完成
    lcd.user_done()

    -- 清屏：清除初始化过程中的屏幕残留杂色
    lcd.clear()

    -- 开启背光
    gpio.setup(PIN_BL, 1)

    -------------------------------------自定义初始化配置（结束）-------------------------------------------

    if result then
        if airui then
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
                    -- path = "/luadb/NotoSansSC_subset.ttf", -- 展示NotoSansSC_subset自定义字体
                    size = 20,         -- 字体大小，默认 16
                    cache_size = 1048, -- 缓存字数大小，默认 2048
                    antialias = 1,     -- 抗锯齿等级1-3，默认 1
                })
            elseif rtos.bsp() == "PC" then
                -- PC模拟器使用外部TTF字体文件（与lua脚本同目录），完整展示字体特性
                airui.font_load({
                    type = "hzfont",
                    path = nil,        -- 字体路径，对于 "hzfont"，传 nil 则使用内置字库
                    -- path = "/luadb/NotoSansSC_subset.ttf", -- 展示NotoSansSC_subset自定义字体
                    size = 20,
                    cache_size = 2048,
                    antialias = 3, -- 高抗锯齿等级，展示字体边缘平滑特性
                    global = true
                })
            end

            -- 查询当前固件内AirUI核心库版本
            local version_result = airui.version()

            -- 打印查询结果
            log.info("airui", "version -> " .. version_result)
        else
            log.warn("lcd_st6201_cust_drv", "AirUI not available, skip AirUI init")
        end
    end

    -- 通知 lcd_app 任务：LCD 与 AirUI 初始化已完成
    sys.publish("ST6201_LCD_AIRUI_READY")
end

sys.taskInit(lcd_drv_init)
