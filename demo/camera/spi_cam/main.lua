

PROJECT = "camerademo"
VERSION = "1.0.0"
require "bf302a"
require "gc032a"
sys = require("sys")

local SCAN_MODE = 1
local scan_pause = true

-- 根据不同的BSP返回不同的值
-- spi_id,pin_reset,pin_dc,pin_cs,bl
local function lcd_pin()
    local rtos_bsp = rtos.bsp()
    if rtos_bsp == "EC718P" then
        return lcd.HWID_0,36,0xff,0xff,0xff -- 注意:EC718P有硬件lcd驱动接口, 无需使用spi,当然spi驱动也支持
    else
        log.info("main", "bsp not support")
        return
    end
end
local spi_id,pin_reset,pin_dc,pin_cs,bl = lcd_pin() 
if spi_id ~= lcd.HWID_0 then
    spi_lcd = spi.deviceSetup(spi_id,pin_cs,0,0,8,20*1000*1000,spi.MSB,1,0)
    port = "device"
else
    port = spi_id
end

--[[ 此为合宙售卖的1.8寸TFT LCD LCD 分辨率:128X160 屏幕ic:st7735 购买地址:https://item.taobao.com/item.htm?spm=a1z10.5-c.w4002-24045920841.19.6c2275a1Pa8F9o&id=560176729178]]
-- lcd.init("st7735",{port = port,pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 0,w = 128,h = 160,xoffset = 0,yoffset = 0},spi_lcd)

--[[ 此为合宙售卖的1.54寸TFT LCD LCD 分辨率:240X240 屏幕ic:st7789 购买地址:https://item.taobao.com/item.htm?spm=a1z10.5-c.w4002-24045920841.20.391445d5Ql4uJl&id=659456700222]]
--lcd.init("st7789",{port = port,pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 0,w = 240,h = 320,xoffset = 0,yoffset = 0},spi_lcd,true)

--[[ 此为合宙售卖的0.96寸TFT LCD LCD 分辨率:160X80 屏幕ic:st7735s 购买地址:https://item.taobao.com/item.htm?id=661054472686]]
--lcd.init("st7735v",{port = port,pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 1,w = 160,h = 80,xoffset = 0,yoffset = 24},spi_lcd)
--如果显示颜色相反，请解开下面一行的注释，关闭反色
--lcd.invoff()
--如果显示依旧不正常，可以尝试老版本的板子的驱动
-- lcd.init("st7735s",{port = port,pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 2,w = 160,h = 80,xoffset = 0,yoffset = 0},spi_lcd)
lcd.init("gc9306x",{port = port,pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 0,w = 240,h = 320,xoffset = 0,yoffset = 0},spi_lcd,true)

local uartid = uart.VUART_0 -- 根据实际设备选取不同的uartid
--初始化
local result = uart.setup(
    uartid,--串口id
    115200,--波特率
    8,--数据位
    1--停止位
)

camera.on(0, "scanned", function(id, str)
    if type(str) == 'string' then
        log.info("扫码结果", str)
    elseif str == false then
        log.error("摄像头没有数据")
    else
        log.info("摄像头数据",str)
        sys.publish("capture done", true)
    end
end)



local function press_key()
    log.info("boot press")
    sys.publish("PRESS", true)
end
gpio.setup(0, press_key, gpio.PULLDOWN,gpio.RISING)
gpio.debounce(0 ,100, 1)
local rawbuff = zbuff.create(60 * 1024, zbuff.HEAP_AUTO)
sys.taskInit(function()
    log.info("摄像头启动")
    local cspiId,i2cId=1,1
    i2c.setup(i2cId,i2c.FAST)
    gpio.setup(5,0) --PD拉低
    --local camera_id = bf302aInit(cspiId,i2cId,25500000,SCAN_MODE,SCAN_MODE)
    local camera_id = gc032aInit(cspiId,i2cId,24000000,SCAN_MODE,SCAN_MODE)
    camera.stop(camera_id)
    camera.preview(camera_id,true)
    log.info("按下boot开始测试")
    while 1 do
        result, data = sys.waitUntil("PRESS", 30000)
        if result==true and data==true then
            if SCAN_MODE == 1 then
                if scan_pause then
                    log.info("启动扫码")
                    camera.start(camera_id)
                    scan_pause = false
                    sys.wait(200)
                    log.info(rtos.meminfo("sys"))
                    log.info(rtos.meminfo("psram"))
                else
                    log.info("停止扫码")
                    camera.stop(camera_id)
                    scan_pause = true
                    sys.wait(200)
                    log.info(rtos.meminfo("sys"))
                    log.info(rtos.meminfo("psram"))
                end
            else
                log.debug("摄像头捕获图像")
                camera.capture(camera_id,rawbuff,1)
                result, data = sys.waitUntil("capture done", 30000)
                log.info(rawbuff:used())
                log.info(rtos.meminfo("sys"))
                log.info(rtos.meminfo("psram"))
                uart.tx(uartid, rawbuff) --找个能保存数据的串口工具保存成文件就能在电脑上看了, 格式为JPG
            end


        end
    end

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
