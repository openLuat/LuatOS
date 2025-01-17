PROJECT = "camerademo"
VERSION = "1.0.0"
sys = require("sys")
log.style(1)

local SCAN_MODE = 0 -- 写1演示扫码
local scan_pause = true
local getRawStart = false
local RAW_MODE = 0 -- 写1演示获取原始图像

local uartid = 1 -- 根据实际设备选取不同的uartid
local uartBaudRate = 115200 -- 串口波特率
local uartDatabits = 8 -- 串口数据位
local uartStopBits = 1 -- 串口停止位

-- 初始化串口
uart.setup(uartid, uartBaudRate, uartDatabits, uartStopBits)

local camera_id = camera.USB

local usb_camera_table = {
    id = camera_id,
    sensor_width = 800,
    sensor_height = 480
}

camera.on(camera_id, "scanned", function(id, str)
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
gpio.setup(14, press_key, gpio.PULLDOWN, gpio.RISING)
gpio.debounce(14, 50)
local rawbuff, err = zbuff.create(60 * 1024, 0, zbuff.HEAP_AUTO)

sys.taskInit(function()
    if rawbuff == nil then
        while true do
            sys.wait(1000)
        end
        log.info("zbuff创建失败", err)
    end

    log.info("摄像头初始化", camera.init(usb_camera_table))
    log.info(rtos.meminfo("sys"))
    log.info(rtos.meminfo("psram"))
    while 1 do
        local result, data = sys.waitUntil("PRESS", 30000)
        if result == true and data == true then
            -- camera.init(usb_camera_table)
            camera.start(camera_id)
            camera.capture(camera_id, rawbuff, 1)
            result, data = sys.waitUntil("capture done", 30000)
            log.info(rawbuff:used())
            camera.stop(camera_id)
            -- camera.close(camera_id)	--完全关闭摄像头才用这个
            rawbuff:resize(60 * 1024)
            log.info(rtos.meminfo("sys"))
            log.info(rtos.meminfo("psram"))
        end
    end

end)

-- sys.taskInit(
--    function ()
--         while 1 do
--             sys.wait(1000)
--             log.info("aaaaa")
--         end
--    end
-- )

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
