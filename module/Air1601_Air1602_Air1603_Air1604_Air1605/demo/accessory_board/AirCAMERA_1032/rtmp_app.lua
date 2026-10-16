--[[
@module  rtmp_app
@summary Air1601 + AirCAMERA_1032 USB摄像头 RTMP 推流功能模块（参照 olddemo/rtmp_usb_mcu）
@version 3.0
@date    2026.09.09
@usage
本文件严格参照 LuatOS olddemo/demo/camera/rtmp_usb_mcu/main.lua 的结构改写，
适配 Air1601/Air1602 + AirCAMERA_1032（H.264 UVC）USB 摄像头：

1. camera 原始 API：USB 主机上电 → 枚举 H.264 → set_usb_config + cache + stream 采集
2. 从合宙音视频平台获取 RTMP 地址（video.luatos.com）
3. rtmp.create(url) → connect → wait 300ms → start（组件内部 capture("rtmp") 取帧推流）
4. 断线自动重连（rtmp_try_reconnect）

注意：
- 必须在 main.lua 打开 require "netdrv_device"；与 face_demo/photo_to_aircloud/audio_record 互斥。
- 摄像头供电：Air1601_V1.1 用 GPIO12，Air160X_V1.2 用 GPIO58（见下方 CAMERA_PWR_PIN 定义，按实际开发板切换）。
- 推流依赖固件实现 camera.capture("rtmp")（若固件未实现，则帧数为 0、无画面，需改固件或换平台）。
]]

-- ==================== 用户配置区 ====================
local DEVICE_USER = "admin"      -- 平台录像机设置的设备用户（非登录用户名；若后台不是 admin 请改）
local DEVICE_PSD  = "Air123456"  -- 平台录像机设置的设备密码（非登录密码）
local DEVICE_ID   = "C8C2C693F4C2"   -- 接入ID（后台录像机的接入ID）

-- AirCAMERA_1032摄像头供电控制引脚，高电平有效（客户按实际开发板切换）
-- Air1601_V1.1开发板：GPIO12 = USB主机模式/摄像头总供电
-- gpio.setup(12, 1, gpio.PULLUP)
-- Air160X_V1.2开发板：GPIO58 = USB主机模式/摄像头总供电
local CAMERA_PWR_PIN = 58    -- 如改用 Air1601_V1.1 开发板，请改为 12

-- 目标分辨率（H.264）
local SENSOR_W = 1280
local SENSOR_H = 720

-- ==================== 全局变量 ====================
local usb_app_id = nil
local frame_buff0 = nil
local frame_buff1 = nil
local buff_size = math.ceil(SENSOR_W * SENSOR_H * 1.5)
local frame_count = 0        -- 已接收帧计数（降频打印用）
local rtmpc = nil            -- RTMP 客户端对象
local rtmp_reconnecting = false
local rtmp_retries = 0
local RTMP_TASK_NAME = "rtmp_app_task"

-- ==================== 从合宙音视频平台获取 RTMP 地址 ====================
local function rtmp_http_request()
    local get_device_id = DEVICE_ID or netdrv.mac(socket.dft())
    log.info("rtmp_app", "设备ID", get_device_id)
    local url = "https://video.luatos.com/api-system/deviceVideo/get/" .. get_device_id
    log.info("rtmp_app", "请求URL", url)
    local header = {
        ["Accept-Encoding"] = "identity",
        ["Host"] = "video.luatos.com",
        ["Content-Type"] = "application/json"
    }
    local post_body = {
        deviceAccess = "8",     -- 8 = RTMP 接入方式
        deviceUser = DEVICE_USER,
        devicePsd = DEVICE_PSD
    }
    local code, _, body = http.request("POST", url, header, json.encode(post_body)).wait()
    log.info("rtmp_app", "请求code", code)
    if code ~= 200 then
        log.error("rtmp_app", "HTTP请求失败", code)
        return false, nil
    end
    local json_body = json.decode(body)
    if not json_body or json_body.code ~= 200 then
        log.error("rtmp_app", "获取RTMP地址失败", json_body and json_body.msg or "未知错误")
        return false, nil
    end
    local rtmp_url = json_body.data and json_body.data.urlList and json_body.data.urlList[1]
    if not rtmp_url then
        log.error("rtmp_app", "未获取到RTMP地址")
        return false, nil
    end
    log.info("rtmp_app", "获取到RTMP地址", rtmp_url)
    return true, rtmp_url
end

-- ==================== USB 设备回调 ====================
local function usb_cb(usb_id, class, app_id, event, param1, param2, param3)
    if event == usb.EV_CONNECT and class == usb.CAMERA then
        log.info("rtmp_app", "USB摄像头连接事件 app id", app_id)
    elseif event == usb.EV_DISCONNECT and class == usb.CAMERA then
        log.info("rtmp_app", "USB摄像头断开事件 app id", app_id)
    end
end

-- ==================== 摄像头回调：枚举 H.264 + 开启采集 ====================
local function camera_cb(app_id, event, param)
    if event == usb.EV_NEW_RX then
        frame_count = frame_count + 1
        if frame_count % 300 == 1 then
            log.info("rtmp_app", "已接收帧 累计", frame_count)
        end
        return
    end

    if event == usb.EV_CONNECT then
        log.info("rtmp_app", "USB摄像头已连接, app id", app_id)
        usb_app_id = app_id
        local res, format_num = camera.get_usb_config(app_id, camera.CONF_UVC_FORMAT)
        if not res then
            log.error("rtmp_app", "枚举摄像头格式失败")
            return
        end
        log.info("rtmp_app", "UVC格式数量:", format_num)
        local has_h264 = false
        for fmt_idx = 1, format_num do
            local _, type, frame_num = camera.get_usb_config(app_id, camera.CONF_UVC_FORMAT, fmt_idx)
            log.info("rtmp_app", "格式索引", fmt_idx, "类型", type, "图像数", frame_num)
            if type == camera.FORMAT_H264 then
                has_h264 = true
            end
        end
        if not has_h264 then
            log.error("rtmp_app", "当前摄像头不支持 H.264，无法 RTMP 推流")
            return
        end
        log.info("rtmp_app", "设置H.264", SENSOR_W, "x", SENSOR_H)
        camera.set_usb_config(app_id, camera.CONF_UVC_RESOLUTION, camera.FORMAT_H264, SENSOR_W, SENSOR_H)
        frame_buff0 = zbuff.create(buff_size)
        frame_buff1 = zbuff.create(buff_size)
        camera.cache(camera.USB, app_id, frame_buff0, frame_buff1)
        camera.stream(camera.USB, app_id)
        log.info("rtmp_app", "摄像头采集已启动")
        return
    end

    if event == usb.EV_DISCONNECT then
        log.info("rtmp_app", "USB摄像头已断开")
        usb_app_id = nil
        return
    end

    if event == usb.EV_RX_ERR then
        log.warn("rtmp_app", "USB摄像头接收数据异常")
        return
    end
end

-- ==================== 摄像头初始化 ====================
local function camera_init()
    -- 摄像头供电控制引脚上电（Air1601_V1.1=GPIO12 / Air160X_V1.2=GPIO58，由 CAMERA_PWR_PIN 决定）
    gpio.setup(CAMERA_PWR_PIN, 1, gpio.PULLUP)
    usb.on(0, usb_cb)
    camera.on(camera.USB, "usb_raw", camera_cb)
    pm.power(pm.USB, false)
    local mode_result = usb.mode(0, usb.HOST)
    log.info("rtmp_app", "USB模式设置结果", mode_result)
    pm.power(pm.USB, true)
    log.info("rtmp_app", "USB上电完成")
end

local g_s_rtmp_state

-- ==================== RTMP 状态回调 ====================
local function rtmp_state_callback(state)
    log.info("rtmp_app", "rtmp状态变化", state)
    if state == rtmp.STATE_IDLE then
        log.info("rtmp_app", "空闲状态（可能推流时效）")
        if g_s_rtmp_state == rtmp.STATE_DISCONNECTING then
            sys.sendMsg(RTMP_TASK_NAME, "RTMP_EVENT", "DISCONNECTED")
        end
        sys.publish("RECONNECT_RTMP")
    elseif state == rtmp.STATE_CONNECTING then
        log.info("rtmp_app", "正在连接")
    elseif state == rtmp.STATE_HANDSHAKING then
        log.info("rtmp_app", "握手中")
    elseif state == rtmp.STATE_CONNECTED then
        log.info("rtmp_app", "已连接")
        sys.sendMsg(RTMP_TASK_NAME, "RTMP_EVENT", "CONNECTED")
    elseif state == rtmp.STATE_PUBLISHING then
        log.info("rtmp_app", "推流中")
    elseif state == rtmp.STATE_DISCONNECTING then
        log.info("rtmp_app", "正在断开")
    elseif state == rtmp.STATE_ERROR then
        log.info("rtmp_app", "错误")
        sys.sendMsg(RTMP_TASK_NAME, "RTMP_EVENT", "DISCONNECTED")
    end
    g_s_rtmp_state = state
end

-- ==================== RTMP 断线重连任务 ====================
local function rtmp_try_reconnect()
    while true do
        local ret, err = sys.waitUntil("RECONNECT_RTMP")
        if rtmp_reconnecting or not rtmpc then
            return
        end
        rtmp_reconnecting = true
        while rtmp_reconnecting do
            rtmpc:disconnect()
            sys.wait(12 * 1000)
            rtmp_retries = rtmp_retries + 1
            local isNetReady, adapterIndex = socket.adapter()
            log.info("rtmp_app", "reconnect attempt", rtmp_retries, "adapter_index:", adapterIndex)
            if isNetReady then
                log.info("rtmp_app", "重新连接RTMP...")
                if rtmpc:connect() then
                    sys.wait(5000)
                    local st = rtmpc:getState()
                    if st == rtmp.STATE_CONNECTED or st == rtmp.STATE_PUBLISHING then
                        log.info("rtmp_app", "重连成功")
                        rtmpc:start()
                        rtmp_reconnecting = false
                        rtmp_retries = 0
                    end
                end
            else
                log.info("rtmp_app", "等待网络就绪...")
                sys.waitUntil("IP_READY", 60 * 1000)
            end
        end
    end
end

-- ==================== 主推流任务 ====================
sys.taskInit(function()
    log.info("rtmp_app", "等待网络就绪...")
    sys.waitUntil("IP_READY", 60000)

    camera_init()

    local ok_url, rtmp_url = rtmp_http_request()
    if not ok_url or not rtmp_url then
        log.error("rtmp_app", "获取RTMP地址失败")
        return
    end

    rtmpc = rtmp.create(rtmp_url, socket.dft())
    if not rtmpc then
        log.error("rtmp_app", "rtmp.create 失败")
        return
    end
    rtmpc:setCallback(rtmp_state_callback)

    log.info("rtmp_app", "开始连接推流服务器:", rtmp_url)
    rtmpc:connect()
    sys.wait(300)
    log.info("rtmp_app", "开始推流...")
    rtmpc:start() -- 组件内部自动调用 camera.capture("rtmp") 取帧推流

    while true do
        sys.wait(30 * 1000)
        log.info("rtmp_app", "lua ram", rtos.meminfo("lua"))
        log.info("rtmp_app", "sys ram", rtos.meminfo("sys"))
        sys.wait(2000)
    end
end)

-- 断线重连任务
sys.taskInit(rtmp_try_reconnect)
