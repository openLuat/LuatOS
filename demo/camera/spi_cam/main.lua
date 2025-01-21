PROJECT = "camera_30W_480_320_demo"
VERSION = "4.0.0"
-- 实际使用时选1个就行
-- require "bf30a2"
require "gc032a"
-- require "gc0310"
sys = require("sys")
log.style(1)

--设置GPIO电压为3V
 pm.ioVol(pm.IOVOL_ALL_GPIO, 3000)

gpio.setup(2,1)--GPIO2打开给camera_3.3V供电
gpio.setup(28,1)--GPIO28打开给lcd3.3V供电

--GPIO 14 15设置为输入
gpio.setup(14, nil)
gpio.setup(15, nil)

local SCAN_MODE = 0 -- 写1演示扫码
local scan_pause = true
local getRawStart = false
local RAW_MODE = 0 -- 写1演示获取原始图像
-- SCAN_MODE和RAW_MODE都没有写1就是拍照

-- 根据不同的BSP返回不同的值
-- spi_id,pin_reset,pin_dc,pin_cs,bl
local function lcd_pin()
    local rtos_bsp = rtos.bsp()
    if string.find(rtos_bsp,"780EPM") then
        return lcd.HWID_0, 36, 0xff, 0xff, 0xff -- 注意:EC718P有硬件lcd驱动接口, 无需使用spi,当然spi驱动也支持
    else
        log.info("main", "没找到合适的cat.1芯片",rtos_bsp)
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

--lcd用的ST7796
lcd.init("custom", {
    port = port,
    pin_dc = pin_dc,
    pin_pwr = bl,
    pin_rst = pin_reset,
    direction = 0,
    direction0 = 0x00,
    w = 480,
    h = 320,
    xoffset = 50,
    yoffset = 50,
    sleepcmd = 0x10,
    wakecmd = 0x11,
    initcmd = {0x0200F0, 0x0300C3, 0x0200F0, 0x030096, 0x020036, 0x030068, 0x02003A, 0x030005, 0x0200B0, 0x030080,
               0x0200B6, 0x030000, 0x030002, 0x0200B5, 0x030002, 0x030003, 0x030000, 0x030004, 0x0200B1, 0x030080,
               0x030010, 0x0200B4, 0x030000, 0x0200B7, 0x0300C6, 0x0200C5, 0x030024, 0x0200E4, 0x030031, 0x0200E8,
               0x030040, 0x03008A, 0x030000, 0x030000, 0x030029, 0x030019, 0x0300A5, 0x030033, 0x0200C2, 0x0200A7,
               0x0200E0, 0x0300F0, 0x030009, 0x030013, 0x030012, 0x030012, 0x03002B, 0x03003C, 0x030044, 0x03004B,
               0x03001B, 0x030018, 0x030017, 0x03001D, 0x030021, 0x0200E1, 0x0300F0, 0x030009, 0x030013, 0x03000C,
               0x03000D, 0x030027, 0x03003B, 0x030044, 0x03004D, 0x03000B, 0x030017, 0x030017, 0x03001D, 0x030021,

               0x020036, 0x0300EC, 0x0200F0, 0x0300C3, 0x0200F0, 0x030069, 0x020013, 0x020011, 0x020029}
}, spi_lcd)

local uartid = uart.VUART_0 -- 根据实际设备选取不同的uartid
-- 初始化
local result = uart.setup(uartid, -- 串口id
115200, -- 波特率
8, -- 数据位
1 -- 停止位
)

camera.on(0, "scanned", function(id, str)
    if type(str) == 'string' then
        log.info("扫码结果", str)
    elseif str == false then
        log.error("摄像头没有数据")
    else
        log.info("摄像头数据", str)
        sys.publish("capture done", true)
    end
end)

local function press_key()
    log.info("boot press")
    sys.publish("PRESS", true)
end
gpio.setup(0, press_key, gpio.PULLDOWN, gpio.RISING)
gpio.debounce(0, 100, 1)
local rawbuff, err
if RAW_MODE ~= 1 then
    rawbuff, err = zbuff.create(60 * 1024, 0, zbuff.HEAP_AUTO)
else
    rawbuff, err = zbuff.create(640 * 480 * 2, 0, zbuff.HEAP_AUTO) -- gc032a
    -- local rawbuff = zbuff.create(240 * 320 * 2, zbuff.HEAP_AUTO)  --bf302a
end
if rawbuff == nil then
    log.info(err)
end

sys.taskInit(function()
    log.info("摄像头启动")
    local cspiId, i2cId = 1, 1
    local camera_id
    i2c.setup(i2cId, i2c.FAST)
    gpio.setup(5, 0) -- PD拉低
    -- camera_id = bf30a2Init(cspiId,i2cId,25500000,SCAN_MODE,SCAN_MODE)
    -- camera_id = gc0310Init(cspiId, i2cId, 25500000, SCAN_MODE, SCAN_MODE)
    camera_id = gc032aInit(cspiId,i2cId,24000000,SCAN_MODE,SCAN_MODE)
    camera.stop(camera_id)
    camera.preview(camera_id, true)
    log.info("按下boot开始测试")
    log.info(rtos.meminfo("sys"))
    log.info(rtos.meminfo("psram"))
    while 1 do
        result, data = sys.waitUntil("PRESS", 30000)
        if result == true and data == true then
            if SCAN_MODE == 1 then
                if scan_pause then
                    log.info("启动扫码")
                    -- camera_id = gc0310Init(cspiId,i2cId,25500000,SCAN_MODE,SCAN_MODE)
                    camera.start(camera_id)
                    scan_pause = false
                    sys.wait(200)
                    log.info(rtos.meminfo("sys"))
                    log.info(rtos.meminfo("psram"))
                else
                    log.info("停止扫码")
                    -- camera.close(camera_id)	--完全关闭摄像头才用这个
                    camera.stop(camera_id)
                    scan_pause = true
                    sys.wait(200)
                    log.info(rtos.meminfo("sys"))
                    log.info(rtos.meminfo("psram"))
                end
            elseif RAW_MODE == 1 then
                if getRawStart == false then
                    getRawStart = true
                    log.debug("摄像头首次捕获原始图像")
                    camera.startRaw(camera_id, 640, 480, rawbuff) -- gc032a
                    -- camera.startRaw(camera_id,240,320,rawbuff) --bf302a
                else
                    log.debug("摄像头继续捕获原始图像")
                    camera.getRaw(camera_id)
                end
                result, data = sys.waitUntil("capture done", 30000)
                log.info("摄像头捕获原始图像完成")
                log.info(rtos.meminfo("sys"))
                log.info(rtos.meminfo("psram"))
                -- uart.tx(uartid, rawbuff) --找个能保存数据的串口工具保存成文件就能在电脑上看了, 格式为JPG                
            else
                log.debug("摄像头拍照")
                -- camera_id = gc0310Init(cspiId,i2cId,25500000,SCAN_MODE,SCAN_MODE)
                camera.capture(camera_id, rawbuff, 1) -- 2和3需要非常多非常多的psram,尽量不要用
                result, data = sys.waitUntil("capture done", 30000)
                log.info(rawbuff:used())
                -- camera.close(camera_id)	--完全关闭摄像头才用这个
                camera.stop(camera_id)
                uart.tx(uartid, rawbuff) -- 找个能保存数据的串口工具保存成文件就能在电脑上看了, 格式为JPG
                rawbuff:resize(60 * 1024)
                log.info(rtos.meminfo("sys"))
                log.info(rtos.meminfo("psram"))
            end

        end
    end

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
