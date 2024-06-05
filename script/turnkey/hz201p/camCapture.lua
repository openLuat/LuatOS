require "bf30a2"
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

local rawbuff, err = zbuff.create(60 * 1024, 0, zbuff.HEAP_AUTO)

if rawbuff == nil then
    log.info(err)
end

sys.taskInit(function()
    log.info("摄像头启动")
    local cspiId, i2cId = 1, 0
    local camera_id
    i2c.setup(i2cId, i2c.FAST)
    gpio.setup(5, 0) -- PD拉低
    log.info("按下boot开始测试")
    log.info(rtos.meminfo("sys"))
    log.info(rtos.meminfo("psram"))
    while 1 do
        local result, data = sys.waitUntil("PRESS", 30000)
        if result == true and data == true then
            log.debug("摄像头拍照")
            camera_id = bf30a2Init(cspiId, i2cId, 25500000)
            camera.capture(camera_id, rawbuff, 1) -- 2和3需要非常多非常多的psram,尽量不要用
            result, data = sys.waitUntil("capture done", 30000)
            if result then
                log.info(rawbuff:used())
            end
            camera.close(camera_id) -- 完全关闭摄像头才用这个
            rawbuff:resize(60 * 1024)
            log.info(rtos.meminfo("sys"))
            log.info(rtos.meminfo("psram"))
        end
    end
end)
