PROJECT = "lcddemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
sys = require("sys")


-- 添加硬狗防止程序卡死
if wdt then
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end

pm.ioVol(pm.IOVOL_ALL_GPIO, 3000)--所有IO电平开到3V，电平匹配

-- 注意：V1.2的开发板需要打开GPIO28，V1.3的开发板需要打开GPIO29
-- gpio.setup(28, 1) -- GPIO28打开给lcd电源供电 
gpio.setup(29, 1) -- GPIO29打开给lcd电源供电 

local rtos_bsp = rtos.bsp()
-- local chip_type = hmeta.chip()
-- 根据不同的BSP返回不同的值
-- 根据不同的BSP返回不同的值
-- spi_id,pin_reset,pin_dc,pin_cs,bl
local function lcd_pin()
    local rtos_bsp = rtos.bsp()
    if string.find(rtos_bsp, "780EPM") then
        return lcd.HWID_0, 36, 0xff, 0xff, 25 -- 注意:EC718P有硬件lcd驱动接口, 无需使用spi,当然spi驱动也支持
    else
        log.info("main", "没找到合适的cat.1芯片", rtos_bsp)
        return
    end
end

local spi_id, pin_reset, pin_dc, pin_cs, bl = lcd_pin()
if spi_id ~= lcd.HWID_0 then
    spi_lcd = spi.deviceSetup(spi_id, pin_cs, 0, 0, 8, 20 * 1000 * 1000, spi.MSB, 1, 0)
    port = "device"
else
    port = spi_id
end

lcd.init("st7796", {
    port = port,
    pin_dc = pin_dc,
    pin_pwr = bl,
    pin_rst = pin_reset,
    direction = 0,
    -- direction0 = 0x00,
    w = 320,
    h = 480,
    xoffset = 0,
    yoffset = 0,
    sleepcmd = 0x10,
    wakecmd = 0x11,
})

-- 不在内置驱动的, 看demo/lcd_custom

sys.taskInit(function()
    -- 开启缓冲区, 刷屏速度回加快, 但也消耗2倍屏幕分辨率的内存
    -- lcd.setupBuff()          -- 使用lua内存
    lcd.setupBuff(nil, true) -- 使用sys内存, 只需要选一种
    lcd.autoFlush(false)

    while 1 do
        lcd.clear()
        log.info("合宙 780EPM LCD演示")
        -- API 文档 https://wiki.luatos.com/api/lcd.html
        if lcd.showImage then
            -- 注意, jpg需要是常规格式, 不能是渐进式JPG
            -- 如果无法解码, 可以用画图工具另存为,新文件就能解码了
            lcd.showImage(0, 0, "/luadb/picture.jpg")
            sys.wait(100)
        end
        -- log.info("lcd.drawLine", lcd.drawLine(100, 240, 240, 240, 0x001F)) -- 画线
        -- log.info("lcd.drawRectangle", lcd.drawRectangle(100, 240, 240, 70, 0xF800)) -- 画框
        -- log.info("lcd.drawCircle", lcd.drawCircle(150, 240, 100, 0x0CE0)) -- 画圆

        -- lcd.setFont(lcd.font_opposansm32)
        -- lcd.drawStr(60,240,"hello hezhou") --显示字符
        lcd.flush()
        sys.wait(1000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
