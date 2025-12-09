-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "usb_cam_rtmp"
VERSION = "1.0.0"

local camera_id = camera.USB

local usb_camera_table = {
    id = camera_id,
    sensor_width = 640,
    sensor_height = 480,
    usb_port = 1
}

sys.taskInit(function()
    wlan.init()
    wlan.connect("luatos1234", "12341234", 1)

    sys.waitUntil("IP_READY")

    -- local rtmpc = rtmp.create("rtmp://192.168.1.10:1935/live/abc")
    -- local rtmpc = rtmp.create("rtmp://180.152.6.34:1935/stream1live/1ca786f5_23e5_4d89_8b1d_2eec6932775a_0001")
    local rtmpc = rtmp.create("rtmp://47.94.236.172/live/1ca786f5")
    rtmpc:setCallback(function(state, ...)
        if state == rtmp.STATE_CONNECTED then
            log.info("rtmp", "已连接到推流服务器")
        elseif state == rtmp.STATE_PUBLISHING then
            log.info("rtmp", "已开始推流")
        elseif state == rtmp.STATE_ERROR then
            log.info("rtmp", "出错:", ...)
        end
    end)
    log.info("开始连接到推流服务器...")
    -- sys.wait(100)
    rtmpc:connect()

    sys.wait(500)

    -- 开始处理
    log.info("rtmp", "开始推流...")
    rtmpc:start()

    camera.config(0, camera.CONF_UVC_FPS, 15)

    socket.sntp()
    sys.wait(200)

    -- 初始化摄像头
    while 1 do
        -- if true then rtos.reboot() end
        result = camera.init(usb_camera_table)
        log.info("摄像头初始化", result)
        -- log.info("lua", rtos.meminfo())
        -- log.info("sys", rtos.meminfo("sys"))
        -- log.info("psram", rtos.meminfo("psram"))
        if (result == 0) then
            camera.start(camera_id)
            -- 开始mp4录制
            camera.capture(camera_id, "rtmp", 1)
            sys.wait(3000000)

            -- 结束MP4录制
            camera.stop(camera_id)

            log.info("保存成功")
        end
        camera.close(camera_id)
        --- 打印一下内存状态
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
        log.info("psram", rtos.meminfo("psram"))
        sys.wait(2000)
        -- rtos.reboot()
    end
    -- #################################################

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
