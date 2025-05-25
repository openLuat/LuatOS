
--使用docs网站上的1002版本的固件（对外正式发布的固件）可以测试HC-B202+wifi联网+http上传照片的应用

local httpplus = require "httpplus"
--加载AirCAMERA_1020驱动文件
local air_camera = require "AirCAMERA_1020"


local function http_upload_photo_task_func() 

    local result = air_camera.open()
    if not result then
        log.error("http_upload_photo_task_func error", "air_camera.open fail")
        return
    end

    while true do

        result = air_camera.capture()
        if not result then
            log.error("http_upload_photo_task_func error", "air_camera.capture fail")
            air_camera.close()
            return
        end

        log.info("http_upload_photo_task_func", "wlan.ready()", wlan.ready())
        if not wlan.ready() then
            if not sys.waitUntil("IP_READY", 30000) then
                log.error("http_upload_photo_task_func error", "ip network timeout")
                air_camera.close()
                return
            end
        end

        -- 通过WIFI网络上传到服务器查看
        -- 上传到upload.air32.cn, 数据访问页面是 https://www.air32.cn/upload/data/
        local code, resp = httpplus.request({
            url = "http://upload.air32.cn/api/upload/jpg",
            method = "POST",
            body = result
        })
        log.info("http_upload_photo_task_func", "httpplus.request", code)

        -- 打印内存信息, 调试用
        log.info("sys", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
        log.info("psram", rtos.meminfo("psram"))

        sys.wait(10000)
    end

    air_camera.close()
end

sys.taskInit(http_upload_photo_task_func)
