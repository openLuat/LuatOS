PROJECT = "usb_cam_200w"
VERSION = "1.0.0"
sys = require("sys")

httpplus = require "httpplus"


local wifi_ssid = "admin-降功耗，找合宙！"
local wifi_password = "Air123456"

local camera_id = camera.USB

local usb_camera_table = {
    id = camera_id,
    sensor_width = 1920,
    sensor_height = 1080,
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
    gpio.setup(13, 1, gpio.PULLUP)
    gpio.setup(28, 1, gpio.PULLUP)
    if rawbuff == nil then
        while true do
            sys.wait(1000)
        end
        log.info("zbuff创建失败", err)
    end

    wlan.init()
    wlan.connect(wifi_ssid, wifi_password)

    sys.waitUntil("IP_READY")

    log.info("摄像头初始化", camera.init(usb_camera_table))
    log.info(rtos.meminfo("sys"))
    log.info(rtos.meminfo("psram"))
    while 1 do
        local result, data = sys.waitUntil("PRESS", 5000)
        if result then
            camera.start(camera_id)
            camera.capture(camera_id, rawbuff, 1)
            result, data = sys.waitUntil("capture_done", 30000)
            camera.stop(camera_id)
            if result then
                -- 上传到upload.air32.cn, 数据访问页面是 https://www.air32.cn/upload/data/
                local code, resp = httpplus.request({
                    url = "http://upload.air32.cn/api/upload/jpg",
                    method = "POST",
                    body = rawbuff
                })

            end
            -- 打印内存信息, 调试用
            -- log.info("sys", rtos.meminfo())
            -- log.info("sys", rtos.meminfo("sys"))
            -- log.info("psram", rtos.meminfo("psram"))
        end
    end

end)
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
