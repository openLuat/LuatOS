-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "usb_cam_rtmp"
VERSION = "1.0.0"
require "net_init"

-- usb摄像头，数据格式选择H264
local frame_type = camera.FORMAT_H264
local sensor_w = 1280
local sensor_h = 720
local usb_app_id
local frame_buff0 = zbuff.create(sensor_w * sensor_h)
local frame_buff1 = zbuff.create(sensor_w * sensor_h)
local function camera_cb(app_id, event, param)
    if event == usb.EV_NEW_RX then
        if param == 0 then
            log.info("数据1")
        elseif param == 1 then
            log.info("数据2")
        end
        return
    end

    if event == usb.EV_CONNECT then
        log.info("usb摄像头已连接，使用app id", app_id, "位于hub端口", param)
        usb_app_id = app_id
        local res, format_num, format_index, frame_num, frame_index, type, fps, w, h
        res, format_num = camera.get_usb_config(usb_app_id, camera.CONF_UVC_FORMAT)
        log.info("总共有", format_num, "种数据流格式")
        for format_index = 1, format_num, 1 do
            res, type, frame_num = camera.get_usb_config(usb_app_id, camera.CONF_UVC_FORMAT, format_index)
            log.info("数据流序号", format_index, "数据流格式", type, "总共有", frame_num, "图像格式")
            for frame_index = 1, frame_num, 1 do
                res, fps, w, h = camera.get_usb_config(usb_app_id, camera.CONF_UVC_RESOLUTION, format_index, frame_index)
                log.info("图像格式序号", frame_index, "图像格式", type, "帧率", fps, "图像宽度", w, "图像高度", h)
            end
        end
        log.info("设置图像格式", frame_type, sensor_w, sensor_h)
        camera.set_usb_config(usb_app_id, camera.CONF_UVC_RESOLUTION, frame_type, sensor_w, sensor_h)
        camera.cache(camera.USB, usb_app_id, frame_buff0, frame_buff1)
        camera.stream(camera.USB, usb_app_id)
        return
    end

    if event == usb.EV_DISCONNECT then
        log.info("usb摄像头已断开")
        usb_app_id = nil
        return
    end

    if event == usb.EV_RX_ERR then
        log.info("usb摄像头接收数据异常")
        return
    end
end

local function camera_init()
    gpio.setup(12, 1, gpio.PULLUP)
    usb.on(0, usb_cb)
    camera.on(camera.USB, "usb_raw", camera_cb)
    pm.power(pm.USB, false)
    usb.mode(0, usb.HOST)
    pm.power(pm.USB, true)
    log.info("camera_app", "初始化完成")
end

local rtmpc = nil
-- 重连控制变量与方法
local rtmp_reconnecting = false -- 是否正在重连
local rtmp_retries = 0 -- 当前重连次数

-- rtmp出现问题时的重连逻辑
local function rtmp_try_reconnect()
    while true do
        local ret, error_id = sys.waitUntil("RECONNECT_RTMP")
        if rtmp_reconnecting or not rtmpc then
            return
        end
        rtmp_reconnecting = true
        while rtmp_reconnecting do
            rtmpc:disconnect() -- 确认断开当前连接
            sys.wait(12 * 1000) -- 每次推流时效需要重连间隔两分钟再进行重连
            rtmp_retries = rtmp_retries + 1
            local isNetReady, adapterIndex = socket.adapter()
            log.info("rtmp", "reconnect attempt", rtmp_retries, "adapter_index: ", adapterIndex)
            -- 检测当前网络是否就绪
            if isNetReady then
                log.info("camera", "reinitializing camera")
                -- 重新连接RTMP
                local ok = rtmpc:connect()
                if ok then
                    -- 等待短时间以便连接完成
                    sys.wait(5000)
                    local st = rtmpc:getState()
                    if st == rtmp.STATE_CONNECTED or st == rtmp.STATE_PUBLISHING then
                        log.info("rtmp", "reconnect success")
                        -- 恢复推流
                        rtmpc:start()
                        rtmp_reconnecting = false
                        rtmp_retries = 0
                    end
                end
            else
                -- 等待任意网卡变为就绪
                log.info("rtmp", "waiting for IP_READY")
                sys.waitUntil("IP_READY", 60 * 1000)
            end
        end
    end
end

local rtmpurl = "rtmp://192.168.1.101:1935/live/test"  -- 替换为你的推流地址
if not rtmpc then
    rtmpc = rtmp.create(rtmpurl, socket.LWIP_USER0)
    -- rtmpc = rtmp.create("rtmp://47.94.236.172/live/1ca786f5") -- 替换为你的推流地址
    -- rtmpc = rtmp.create("rtmp://180.152.6.34:1936/live/guangzhou")
    rtmpc:setCallback(function(state, ...)
        log.info("rtmp状态变化", state, ...)
        if state == rtmp.STATE_CONNECTED then
            log.info("rtmp状态变化", "已连接到推流服务器")
            rtmp_retries = 0
        elseif state == rtmp.STATE_PUBLISHING then
            log.info("rtmp状态变化", "已开始推流")
            rtmp_retries = 0
        elseif state == rtmp.STATE_IDLE then
            log.info("rtmp状态变化", "空闲状态，可能和推流时效有关，需要等待一段时间，再尝试重连")
            sys.publish("RECONNECT_RTMP", ...)
        elseif state == rtmp.STATE_ERROR then
            log.info("rtmp状态变化", "出错:", ...)
            -- 发生错误时尝试重连（若网络可用则立即尝试）
            sys.publish("RECONNECT_RTMP", ...)
        end
    end)
end

sys.taskInit(function()
    log.info("当前脚本版本号：", VERSION, "core版本号：", rtos.version())
    sys.waitUntil("IP_READY")
    camera_init() -- 初始化摄像头

    log.info("开始连接到推流服务器...")
    sys.wait(100)
    rtmpc:connect()
    sys.wait(300)
    -- 开始处理
    log.info("rtmp", "开始推流...")
    rtmpc:start() -- 已自动调用 camera.capture(camera_id, "rtmp", 1)
    while 1 do
        --- 打印一下内存状态
        sys.wait(30 * 1000)
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
        log.info("psram", rtos.meminfo("psram"))
        sys.wait(2000)
    end
end)

sys.taskInit(rtmp_try_reconnect)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
