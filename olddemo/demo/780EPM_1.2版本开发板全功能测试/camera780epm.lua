-- 实际使用时选1个就行
-- require "bf30a2"
require "gc032a"
-- require "gc0310"
httpplus = require "httpplus"

gpio.setup(2, 1) -- GPIO2打开给camera电源供电
gpio.setup(28, 1) -- 1.2版本 GPIO28打开给lcd电源供电

gpio.setup(14, nil) -- 关闭GPIO14,防止camera复用关系出问题
gpio.setup(15, nil) -- 关闭GPIO15,防止camera复用关系出问题

local SCAN_MODE = 0 -- 写1演示扫码
local scan_pause = true
local getRawStart = false
local RAW_MODE = 0 -- 写1演示获取原始图像
-- SCAN_MODE和RAW_MODE都没有写1就是拍照

-- 根据不同的BSP返回不同的值
-- spi_id,pin_reset,pin_dc,pin_cs,bl
local function lcd_pin()
    local rtos_bsp = rtos.bsp()
    if string.find(rtos_bsp, "780EPM") then
        return lcd.HWID_0, 36, 0xff, 0xff, 25 -- 注意:EC718P有硬件lcd驱动接口, 无需使用spi,当然spi驱动也支持
    else
        log.info("main", "你用的不是780EPM,请更换demo测试", rtos_bsp)
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
    wakecmd = 0x11
})

local uartid = uart.VUART_0 -- 根据实际设备选取不同的uartid
-- 初始化
local result = uart.setup(uartid, -- 串口id
600000, -- 波特率
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
--按下boot(下载)按键，进行拍照
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
--拍照完成后向USB虚拟串口发送拍的照片，用户可以使用串口调试工具保存原始文件，然后改文件后缀名为jpg
local function sendFile()
    sys.taskInit(function()
        local fileHandle = io.open("/testCamera.jpg", "rb")
        if not fileHandle then
            log.error("打开文件失败")
            return
        else
            log.info("文件打开成功,文件大小为", io.fileSize("/testCamera.jpg"))
        end

        while true do
            local data = fileHandle:read(1460)
            -- log.info("我看看原始data", data)
            if not data then
                break
            end
            log.info("虚拟uart发送数据", uart.write(uartid, data))
            sys.wait(10)
        end
        fileHandle:close() --发送完文件后关闭文件
    end)
end

sys.taskInit(function()
    log.info("摄像头启动")
    -- spi的id和摄像头的id
    local cspiId, i2cId = 1, 1

    local camera_id
    -- 配置iic
    i2c.setup(i2cId, i2c.FAST)
    gpio.setup(5, 0) -- PD拉低

    --不同的摄像头型号就打开不同的注释
    -- camera_id = bf30a2Init(cspiId,i2cId,25500000,SCAN_MODE,SCAN_MODE)
    camera_id = gc0310Init(cspiId, i2cId, 25500000, SCAN_MODE, SCAN_MODE)
    -- camera_id = gc032aInit(cspiId, i2cId, 24000000, SCAN_MODE, SCAN_MODE)
    camera.stop(camera_id)

    camera.preview(camera_id, true) -- 打开LCD预览功能
    log.info("按下boot开始测试拍照")

    log.info(rtos.meminfo("sys"))
    log.info(rtos.meminfo("psram"))

    while 1 do
        result, data = sys.waitUntil("PRESS", 30000)
        if result == true and data == true then
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
                    -- camera.close(camera_id)	--完全关闭摄像头才用这个
                    camera.stop(camera_id)  --一般循环打开摄像头拍照的话就只用暂停即可
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
              
            else
                log.debug("摄像头拍照")
                -- camera_id = gc0310Init(cspiId,i2cId,25500000,SCAN_MODE,SCAN_MODE)
                camera.capture(camera_id, "/testCamera.jpg", 1) -- 2和3需要非常多非常多的psram,尽量不要用
                -- camera.capture(camera_id, rawbuff, 1) -- 2和3需要非常多非常多的psram,尽量不要用

                result, data = sys.waitUntil("capture done", 30000)
                -- log.info(rawbuff:used())
                -- camera.close(camera_id)	--完全关闭摄像头才用这个
                camera.stop(camera_id)
                log.info("rawbuff长度", rawbuff:len())
                sendFile() --也可以上传文件到HTTP服务器，可以结合示例"780EPM_拍照发给HTTP服务器后进入psm+模式"使用
                rawbuff:resize(60 * 1024)
                log.info("sys ram", rtos.meminfo("sys"))
                log.info("lua ram", rtos.meminfo("psram"))
            end

        end
    end

end)
