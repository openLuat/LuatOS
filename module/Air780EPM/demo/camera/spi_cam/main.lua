PROJECT = "camera_30W_480_320_demo"
VERSION = "4.0.0"
-- 实际使用时选1个就行
-- require "bf30a2"
require "gc032a"
-- require "gc0310"
sys = require("sys")
log.style(1)


pm.ioVol(pm.IOVOL_ALL_GPIO, 3000)

--  mcu.altfun(mcu.I2C, 0, 66, 2, nil)
--  mcu.altfun(mcu.I2C, 0, 67, 2, nil)

gpio.setup(2,1)--GPIO2打开给camera_3.3V供电

-- 注意：V1.2的开发板需要打开GPIO28，V1.3的开发板需要打开GPIO29
-- gpio.setup(28, 1) -- GPIO28打开给lcd电源供电 
gpio.setup(29, 1) -- GPIO29打开给lcd电源供电 

gpio.setup(14, nil)
gpio.setup(15, nil)

local SCAN_MODE = 0 -- 写1演示扫码（使用摄像头对二维码、条形码或其他类型的图案进行扫描和识别）
local scan_pause = true -- 扫码启动与停止标志位
local getRawStart = false
local RAW_MODE = 0 -- 写1演示获取原始图像
-- SCAN_MODE和RAW_MODE都没有写1就是拍照

------------------------------------
------------ 初始化 LCD ------------
------------------------------------
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

------------------------------------
------------ 初始化串口 -------------
------------------------------------
local uartid = uart.VUART_0 -- 根据实际设备选取不同的uartid
-- 初始化
local result = uart.setup(uartid, -- 串口id
600000, -- 波特率
8, -- 数据位
1 -- 停止位
)

------------------------------------
----------- 初始化摄像头 -----------
------------------------------------
camera.on(0, "scanned", function(id, str)
    if type(str) == 'string' then -- 如果是扫码模式（使用摄像头对二维码、条形码或其他类型的图案进行扫描和识别）
        log.info("扫码结果", str)
    elseif str == false then -- 如果摄像头没有正常工作
        log.error("摄像头没有数据")
    else -- 如果摄像头正常工作，并且不是扫码模式
        log.info("摄像头数据", str)
        sys.publish("capture done", true)
    end
end) -- 注册 camera 0 的 "scanned" 事件

------------------------------------
-------- 注册 boot 按键中断 ---------
------------------------------------
local function press_key()
    log.info("boot press")
    sys.publish("PRESS", true)
end
gpio.setup(0, press_key, gpio.PULLDOWN, gpio.RISING)
gpio.debounce(0, 100, 1)
local rawbuff, err
if RAW_MODE ~= 1 then
    -- 如果 RAW_MODE 不等于 1，创建一个大小为 60KB 的缓冲区
    rawbuff, err = zbuff.create(60 * 1024, 0, zbuff.HEAP_AUTO)
else
    -- 如果 RAW_MODE 等于 1
    rawbuff, err = zbuff.create(640 * 480 * 2, 0, zbuff.HEAP_AUTO) -- 创建一个大小为 640x480 像素，每个像素占用 2 字节的缓冲区，适用于 gc032a 摄像头
    -- local rawbuff = zbuff.create(240 * 320 * 2, zbuff.HEAP_AUTO)  -- 创建一个大小为 240x320 像素，每个像素占用 2 字节的缓冲区，适用于 bf302a 摄像头
end
if rawbuff == nil then
    log.info(err)
end

--------------------------------------------------
---- 将文件系统中存储的jpg文件通过串口发送给电脑 ----
--------------------------------------------------
local function sendFile()
    sys.taskInit(function()
        local fileHandle = io.open("/testCamera.jpg","rb")
        -- log.info("文件大小",fileHandle)
        if not fileHandle then
            log.error("打开文件失败")
            return            
        else
            log.info("文件打开成功,文件大小为",io.fileSize("/testCamera.jpg"))
        end

        while true do
            local data = fileHandle:read(1460)
            -- log.info("data我看看",data)
            if not data then break end
            log.info("虚拟uart发送数据",uart.write(uartid, data))
            sys.wait(10)
            -- sys.waitUntil("UART_SENT2MCU_OK")
        end
        fileHandle:close()

        os.remove("/testCamera.jpg") -- 删除文件
    end)
end

sys.taskInit(function()
    log.info("摄像头启动")

    -- 初始化摄像头
    local cspiId, i2cId = 1, 1 -- spi的id和摄像头的id
    local camera_id
    i2c.setup(i2cId, i2c.FAST) -- I2C1设置为快速模式，不开启上拉
    gpio.setup(5, 0) -- 将 GPIO5 下拉，用于 SPI 片选信号
    -- camera_id = bf30a2Init(cspiId,i2cId,25500000,SCAN_MODE,SCAN_MODE)
    -- camera_id = gc0310Init(cspiId, i2cId, 25500000, SCAN_MODE, SCAN_MODE)
    camera_id = gc032aInit(cspiId,i2cId,24000000,SCAN_MODE,SCAN_MODE) -- 通过 I2C1 配置摄像头，SPI1 时钟频率为 24 MHz
    camera.stop(camera_id) -- 暂停摄像头捕获数据。仅停止了图像捕获，未影响预览功能。
    camera.preview(camera_id, true) -- 打开LCD预览功能（直接将摄像头数据输出到LCD）

    log.info("按下boot开始测试")
    -- 总内存大小,单位字节;当前已使用的内存大小,单位字节;历史最高已使用的内存大小,单位字节
    log.info(rtos.meminfo("sys")) -- 打印系统内存信息
    log.info(rtos.meminfo("psram")) -- 打印PSRAM内存信息
    while 1 do
        result, data = sys.waitUntil("PRESS", 30 * 1000) -- 等待 "PRESS" 事件 30 秒（等待boot按键被按下）
        if result == true and data == true then -- 如果 30 秒内检测到 "PRESS" 事件往下执行
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
            elseif RAW_MODE == 1 then -- 摄像头捕获原始数据
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
                camera.stop(camera_id) -- 暂停摄像头捕获数据。仅停止了图像捕获，未影响预览功能。
                log.info(rtos.meminfo("sys"))
                log.info(rtos.meminfo("psram"))
                -- uart.tx(uartid, rawbuff) --找个能保存数据的串口工具保存成文件就能在电脑上看了, 格式为JPG
            else -- 拍照模式
                log.debug("摄像头拍照")
                -- camera_id = gc0310Init(cspiId,i2cId,25500000,SCAN_MODE,SCAN_MODE)
                -- 将摄像头拍照的数据存入 "/testCamera.jpg" 文件中
                -- jpeg压缩质量1最差，占用空间小，3最高，占用空间大，2和3需要非常多非常多的psram,尽量不要用
                camera.capture(camera_id, "/testCamera.jpg", 1) -- 2和3需要非常多非常多的psram,尽量不要用
                result, data = sys.waitUntil("capture done", 30000)
                -- log.info(rawbuff:used())
                -- camera.close(camera_id)	--完全关闭摄像头才用这个
                camera.stop(camera_id) -- 暂停摄像头捕获数据。仅停止了图像捕获，未影响预览功能。
                sendFile() -- 创建一个任务将摄像头数据通过串口发送到电脑
                -- rawbuff:resize(60 * 1024)
                -- log.info(rtos.meminfo("sys"))
                -- log.info(rtos.meminfo("psram"))
            end

        end
    end

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
