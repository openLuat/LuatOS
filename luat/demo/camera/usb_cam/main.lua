PROJECT = "camerademo"
VERSION = "1.0.0"
sys = require("sys")

httpplus = require "httpplus"

local SCAN_MODE = 0 -- 写1演示扫码
local scan_pause = true
local getRawStart = false
local RAW_MODE = 0 -- 写1演示获取原始图像


local camera_id = camera.USB

local usb_camera_table = {
    id = camera_id,
    sensor_width = 1280,
    sensor_height = 720,
    usb_port = 1
}

camera.on(camera_id, "scanned", function(id, str)
    if type(str) == 'string' then
        log.info("扫码结果", str)
    elseif str == false then
        log.error("摄像头没有数据")
    else
        log.info("摄像头数据", str)
        sys.publish("capture_done", true)
    end
end)

-- 按键触发拍照
local function press_key()
    log.info("boot press")
    sys.publish("PRESS", true)
end
gpio.setup(14, press_key, gpio.PULLDOWN, gpio.RISING)
gpio.debounce(14, 50)
local rawbuff, err = zbuff.create(200 * 1024, 0, zbuff.HEAP_PSRAM)

sys.taskInit(function()
    if rawbuff == nil then
        while true do
            sys.wait(1000)
        end
        log.info("zbuff创建失败", err)
    end

    wlan.init()
    wlan.connect("uiot", "12345678")

    sys.wait(3000)
    httpsrv.start(80, function() end) -- 联网且抓取成功之后, 可通过设备ip访问图片 http://192.168.1.19/abc.jpg

    log.info("摄像头初始化", camera.init(usb_camera_table))
    log.info(rtos.meminfo("sys"))
    log.info(rtos.meminfo("psram"))
    while 1 do
        local result, data = sys.waitUntil("PRESS", 5000)
        if true then
            -- camera.init(usb_camera_table)
            camera.start(camera_id)
            -- camera.capture(camera_id, rawbuff, 1)
            camera.capture(camera_id, "/abc.jpg", 1)
            result, data = sys.waitUntil("capture_done", 30000)
            -- log.info(rawbuff:used())
            camera.stop(camera_id)
            -- camera.close(camera_id)	--完全关闭摄像头才用这个
            -- rawbuff:resize(60 * 1024)

            -- 上传到upload.air32.cn, 数据访问页面是 https://www.air32.cn/upload/data/
            -- local code, resp = httpplus.request({
            --     url = "http://upload.air32.cn/api/upload/jpg",
            --     method = "POST",
            --     body = rawbuff
            -- })
            -- log.info("http", code)

            -- 打印内存信息, 调试用
            -- log.info("sys", rtos.meminfo())
            -- log.info("sys", rtos.meminfo("sys"))
            -- log.info("psram", rtos.meminfo("psram"))
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
