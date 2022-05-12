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

--[[
-- LCD接法示例, 以Air105开发板的HSPI为例
LCD管脚       Air105管脚
GND          GND
VCC          3.3V
SCL          (PC15/HSPI_SCK)
SDA          (PC13/HSPI_MOSI)
RES          (PC12/HSPI_MISO)
DC           (PE08) --开发板上的U3_RX
CS           (PC14/HSPI_CS)
BL           (PE09) --开发板上的U3_TX


提示:
1. 只使用SPI的时钟线(SCK)和数据输出线(MOSI), 其他均为GPIO脚
2. 数据输入(MISO)和片选(CS), 虽然是SPI, 但已复用为GPIO, 并非固定,是可以自由修改成其他脚
]]

--添加硬狗防止程序卡死
if wdt then
    wdt.init(15000)--初始化watchdog设置为15s
    sys.timerLoopStart(wdt.feed, 10000)--10s喂一次狗
end

-- v0006及以后版本可用pin方式, 请升级到最新固件 https://gitee.com/openLuat/LuatOS/releases
spi_lcd = spi.deviceSetup(5,pin.PC14,0,0,8,96*1000*1000,spi.MSB,1,1)

--[[ 此为合宙售卖的0.96寸TFT LCD LCD 分辨率:160X80 屏幕ic:st7735s 购买地址:https://item.taobao.com/item.htm?spm=a1z10.5-c.w4002-24045920841.19.6c2275a1Pa8F9o&id=560176729178]]
-- lcd.init("st7735s",{port = "device",pin_dc = pin.PE08 ,pin_rst = pin.PC12,pin_pwr = pin.PE09,direction = 2,w = 160,h = 80,xoffset = 1,yoffset = 26},spi_lcd)

--[[ 此为合宙售卖的1.8寸TFT LCD LCD 分辨率:128X160 屏幕ic:st7735 购买地址:https://item.taobao.com/item.htm?spm=a1z10.5-c.w4002-24045920841.19.6c2275a1Pa8F9o&id=560176729178]]
-- lcd.init("st7735",{port = "device",pin_dc = pin.PE08 ,pin_rst = pin.PC12,pin_pwr = pin.PE09,direction = 0,w = 128,h = 160,xoffset = 2,yoffset = 1},spi_lcd)

--[[ 此为合宙售卖的1.54寸TFT LCD LCD 分辨率:240X240 屏幕ic:st7789 购买地址:https://item.taobao.com/item.htm?spm=a1z10.5-c.w4002-24045920841.20.391445d5Ql4uJl&id=659456700222]]
-- lcd.init("st7789",{port = "device",pin_dc = pin.PE08,pin_rst = pin.PC12, pin_pwr = pin.PE09,direction = 0,w = 240,h = 240,xoffset = 0,yoffset = 0},spi_lcd)

--[[ 此为合宙售卖的0.96寸TFT LCD LCD 分辨率:160X80 屏幕ic:st7735s 购买地址:https://item.taobao.com/item.htm?spm=a1z10.5-c.w4002-24045920841.19.6c2275a1Pa8F9o&id=560176729178]]
lcd.init("st7735s",{port = "device",pin_dc = pin.PE08, pin_pwr = pin.PE09, pin_rst = pin.PC12,direction = 2,w = 160,h = 80,xoffset = 0,yoffset = 0},spi_lcd)

--[[ 此为合宙售卖的2.4寸TFT LCD 分辨率:240X320 屏幕ic:GC9306 购买地址:https://item.taobao.com/item.htm?spm=a1z10.5-c.w4002-24045920841.39.6c2275a1Pa8F9o&id=655959696358]]
--lcd.init("gc9306x",{port = "device",pin_dc = pin.PE08 , pin_pwr = pin.PE09, pin_rst = pin.PC12, direction = 0,w = 240,h = 320,xoffset = 0,yoffset = 0},spi_lcd)

-- 不在上述内置驱动的, 需要自定义初始化过程, 看demo/lcd_custom

sys.taskInit(function()
    sys.wait(1000)
    lcd.setupBuff()
    
    local sh = lcd.showImage
    local t = mcu.ticks()
    --local wait = sys.wait
    for i=1,10 do
        sh(0, 0, "/luadb/320240.jpg")
        --wait(5)
    end
    local e = mcu.ticks()

    log.style(0)
    log.info("time", "风格0", e - t)
    log.style(1)
    log.info("time", "风格1", e - t)
    log.style(2)
    log.info("time", "风格2", e - t)
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
