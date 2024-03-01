--- 模块功能：lcddemo
-- @module lcd
-- @author Dozingfiretruck
-- @release 2021.01.25

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "lcddemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

--添加硬狗防止程序卡死
wdt.init(9000)--初始化watchdog设置为9s
sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗

local rtos_bsp = rtos.bsp()

-- 根据不同的BSP返回不同的值
-- spi_id,pin_reset,pin_dc,pin_cs,bl
function lcd_pin()
    if rtos_bsp == "AIR101" then
        return 0,pin.PB03,pin.PB01,pin.PB04,pin.PB00
    elseif rtos_bsp == "AIR103" then
        return 0,pin.PB03,pin.PB01,pin.PB04,pin.PB00
    elseif rtos_bsp == "AIR105" then
        return 5,pin.PC12,pin.PE08,pin.PC14,pin.PE09
    elseif rtos_bsp == "ESP32C3" then
        return 2,10,6,7,11
    elseif rtos_bsp == "ESP32S3" then
        return 2,16,15,14,13
    elseif rtos_bsp == "EC618" then
        return 0,1,10,8,22
    elseif rtos_bsp == "EC718P" then
        return lcd.HWID_0,36,0xff,0xff,0xff -- 注意:EC718P有硬件lcd驱动接口, 无需使用spi,当然spi驱动也支持
    else
        log.info("main", "bsp not support")
        return
    end
end

local spi_id,pin_reset,pin_dc,pin_cs,bl = lcd_pin() 

spi_gtfont = spi.deviceSetup(1,7,0,0,8,20*1000*1000,spi.MSB,1,0) --此处根据自己实际接线修改

if spi_id ~= lcd.HWID_0 then
    spi_lcd = spi.deviceSetup(spi_id,pin_cs,0,0,8,20*1000*1000,spi.MSB,1,0)
    port = "device"
else
    port = spi_id
end


lcd.init("st7789",{port = port,pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 0,w = 240,h = 320,xoffset = 0,yoffset = 0},spi_lcd)

gtfont.init(spi_gtfont)
lcd.drawGtfontUtf8("啊啊啊",32,0,0)
lcd.drawGtfontUtf8Gray("啊啊啊",32,4,0,40)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!