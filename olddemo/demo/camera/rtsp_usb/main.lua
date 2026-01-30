-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "usb_cam_rtsp"
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

    camera.config(0, camera.CONF_UVC_FPS, 15)
    socket.sntp() -- 这个必须有
    sys.wait(200)
    result = camera.init(usb_camera_table)
    log.info("摄像头初始化", result)
    if result ~= 0 then
        log.info("摄像头初始化失败，停止运行")
        return
    end
    camera.start(camera_id)

    -- local rtspc = rtsp.create("rtsp://180.152.6.34:554/stream2live/089dd7d5_04d4_467a_852a_66cbbfc5a9c3_0001")
    local rtspc = rtsp.create("rtsp://192.168.1.10:554/stream2live/089dd7d5_04d4_467a_852a_66cbbfc5a9c3_0001")
    rtspc:setCallback(function(state, ...)
        if state == rtsp.STATE_CONNECTED then
            log.info("rtsp", "已连接到推流服务器")
        elseif state == rtsp.STATE_PUBLISHING then
            log.info("rtsp", "已开始推流")
        elseif state == rtsp.STATE_ERROR then
            log.info("rtsp", "出错:", ...)
        end
    end)
    log.info("开始连接到推流服务器...")
    sys.wait(100)
    rtspc:connect()
    sys.wait(300)

    -- 开始处理
    log.info("rtsp", "开始推流...")
    rtspc:start() -- 已自动调用 camera.capture(camera_id, "rtsp", 1)
    
    while 1 do
        --- 打印一下内存状态
        sys.wait(30*1000)
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
        log.info("psram", rtos.meminfo("psram"))
        sys.wait(2000)
    end
    -- #################################################

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
