
--使用5月13日编译的固件可以正常测试KC6089和HC-B202两款usb摄像头

local httpplus = require "httpplus"

local camera_id = camera.USB


local function camera_scan_cbfunc(id, str)
    log.info("camera_scan_cbfunc", id, str)
    if type(str) == 'string' then
        log.info("扫码结果", str)
    elseif str == false then
        log.error("摄像头没有数据")
    else
        log.info("摄像头数据", str)
        sys.publish("CAPTURE_IND", true)
    end
end


local function capture_upload_task_func()

    -- 创建zbuff
    local capture_photo_buff, err = zbuff.create(200 * 1024, 0, zbuff.HEAP_PSRAM)

    if capture_photo_buff == nil then
        log.error("zbuff创建失败，退出任务！", err)
        return
    end

    if not camera.init({id = camera_id, sensor_width = 1280, sensor_height = 720 , usb_port = 1}) then
        log.error("摄像头初始化失败，退出任务！")
        capture_photo_buff:free()
        return
    end

    while true do
        if not camera.start(camera_id) then
            log.error("摄像头打开失败，退出任务！")
            camera.close(camera_id)
            capture_photo_buff:free()
            return
        end

        if not camera.capture(camera_id, capture_photo_buff, 1) then
            log.error("摄像头拍照失败，退出任务！")
            camera.stop(camera_id)
            camera.close(camera_id)
            capture_photo_buff:free()
            return
        end

        result = sys.waitUntil("CAPTURE_IND", 30000)
        camera.stop(camera_id)

        log.info("photo size", capture_photo_buff:used())
        log.info("wlan.ready", wlan.ready())

        if not wlan.ready() then
            log.info("capture_upload_task_func wait IP_READY")
            if not sys.waitUntil("IP_READY", 30000) then
                log.error("网络连接超时失败，退出任务！")
                camera.close(camera_id)
                capture_photo_buff:free()
                return
            else
                log.info("capture_upload_task_func receive IP_READY")
            end
        end

        -- sys.wait(3000)

        -- 通过WIFI网络上传到服务器查看
        -- 上传到upload.air32.cn, 数据访问页面是 https://www.air32.cn/upload/data/
        local code, resp = httpplus.request({
            url = "http://upload.air32.cn/api/upload/jpg",
            method = "POST",
            body = capture_photo_buff
        })
        log.info("http", code)

        -- 打印内存信息, 调试用
        log.info("sys", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
        log.info("psram", rtos.meminfo("psram"))

        sys.wait(200000)        
    end
end



camera.on(camera_id, "scanned", camera_scan_cbfunc)
-- 初始化摄像头并处理拍照和上传图片的操作
sys.taskInit(capture_upload_task_func)
