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

-- UI带屏的项目一般不需要低功耗了吧, Air101/Air103设置到最高性能
if mcu and (rtos.bsp() == "AIR101" or rtos.bsp() == "AIR103") then
    mcu.setClk(240)
end

--[[
-- LCD接法示例
LCD管脚       Air780E管脚    Air101/Air103管脚   Air105管脚         
GND          GND            GND                 GND                 
VCC          3.3V           3.3V                3.3V                
SCL          (GPIO11)       (PB02/SPI0_SCK)     (PC15/HSPI_SCK)     
SDA          (GPIO09)       (PB05/SPI0_MOSI)    (PC13/HSPI_MOSI)    
RES          (GPIO01)       (PB03/GPIO19)       (PC12/HSPI_MISO)    
DC           (GPIO10)       (PB01/GPIO17)       (PE08)              
CS           (GPIO08)       (PB04/GPIO20)       (PC14/HSPI_CS)      
BL(可以不接)  (GPIO22)       (PB00/GPIO16)       (PE09)              


提示:
1. 只使用SPI的时钟线(SCK)和数据输出线(MOSI), 其他均为GPIO脚
2. 数据输入(MISO)和片选(CS), 虽然是SPI, 但已复用为GPIO, 并非固定,是可以自由修改成其他脚
3. 若使用多个SPI设备, 那么RES/CS请选用非SPI功能脚
4. BL可以不接的, 若使用Air10x屏幕扩展板,对准排针插上即可
]]

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

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
    else
        log.info("main", "bsp not support")
        return
    end
end

local spi_id,pin_reset,pin_dc,pin_cs,bl = lcd_pin() 

-- v0006及以后版本可用pin方式, 请升级到最新固件 https://gitee.com/openLuat/LuatOS/releases
spi_lcd = spi.deviceSetup(spi_id,pin_cs,0,0,8,20*1000*1000,spi.MSB,1,0)

--[[ 此为合宙售卖的2.4寸TFT LCD 分辨率:240X320 屏幕ic:GC9306 购买地址:https://item.taobao.com/item.htm?spm=a1z10.5-c.w4002-24045920841.39.6c2275a1Pa8F9o&id=655959696358]]
-- lcd.init("gc9a01",{port = "device",pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 0,w = 240,h = 320,xoffset = 0,yoffset = 0},spi_lcd)

--[[ 此为合宙售卖的1.8寸TFT LCD LCD 分辨率:128X160 屏幕ic:st7735 购买地址:https://item.taobao.com/item.htm?spm=a1z10.5-c.w4002-24045920841.19.6c2275a1Pa8F9o&id=560176729178]]
lcd.init("st7735",{port = "device",pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 0,w = 128,h = 160,xoffset = 0,yoffset = 0},spi_lcd)

--[[ 此为合宙售卖的1.54寸TFT LCD LCD 分辨率:240X240 屏幕ic:st7789 购买地址:https://item.taobao.com/item.htm?spm=a1z10.5-c.w4002-24045920841.20.391445d5Ql4uJl&id=659456700222]]
-- lcd.init("st7789",{port = "device",pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 0,w = 240,h = 240,xoffset = 0,yoffset = 0},spi_lcd)

--[[ 此为合宙售卖的0.96寸TFT LCD LCD 分辨率:160X80 屏幕ic:st7735s 购买地址:https://item.taobao.com/item.htm?id=661054472686]]
--lcd.init("st7735v",{port = "device",pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 1,w = 160,h = 80,xoffset = 0,yoffset = 24},spi_lcd)
--如果显示颜色相反，请解开下面一行的注释，关闭反色
--lcd.invoff()
--如果显示依旧不正常，可以尝试老版本的板子的驱动
--lcd.init("st7735s",{port = "device",pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 2,w = 160,h = 80,xoffset = 0,yoffset = 0},spi_lcd)

--[[ 此为合宙售卖的2.4寸TFT LCD 分辨率:240X320 屏幕ic:GC9306 购买地址:https://item.taobao.com/item.htm?spm=a1z10.5-c.w4002-24045920841.39.6c2275a1Pa8F9o&id=655959696358]]
-- lcd.init("gc9306",{port = "device",pin_dc = pin_dc , pin_pwr = bl,pin_rst = pin_reset,direction = 0,w = 240,h = 320,xoffset = 0,yoffset = 0},spi_lcd)

-- 不在上述内置驱动的, 看demo/lcd_custom

sys.taskInit(function()
    while 1 do 
        lcd.clear()
        log.info("wiki", "https://wiki.luatos.com/api/lcd.html")
        -- API 文档 https://wiki.luatos.com/api/lcd.html
        if lcd.showImage then
            -- 注意, jpg需要是常规格式, 不能是渐进式JPG
            -- 如果无法解码, 可以用画图工具另存为,新文件就能解码了
            lcd.showImage(40,0,"/luadb/logo.jpg")
            sys.wait(100)
        end
        log.info("lcd.drawLine", lcd.drawLine(20,20,150,20,0x001F))
        log.info("lcd.drawRectangle", lcd.drawRectangle(20,40,120,70,0xF800))
        log.info("lcd.drawCircle", lcd.drawCircle(50,50,20,0x0CE0))
        sys.wait(1000)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
