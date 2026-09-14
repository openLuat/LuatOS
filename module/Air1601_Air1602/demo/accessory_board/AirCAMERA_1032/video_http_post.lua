--[[
@module  video_http_post
@summary Air1601 + AirCAMERA_1032 USB摄像头 视频(H.264裸流)录制 + HTTP上传 功能模块
@version 1.0
@date    2026.09.07
@usage
本文件适配 Air1601/Air1602 开发板 + AirCAMERA_1032（H.264 UVC 编码）USB 摄像头，
实现「录制 H.264 裸流 → 保存文件 → 通过 httpplus 上传到服务器」的近似“视频上传”功能：

1. USB 主机模式上电，枚举摄像头并选择 H.264 + 1280x720
2. 双缓冲 camera.cache + camera.stream 采集 H.264 裸流
3. 连续录制 RECORD_SECONDS 秒，落盘为 .h264 文件
4. 通过 httpplus.request(POST, bodyfile) 上传到服务器

与 AirCAMERA_1031/video_http_post.lua 的区别：
- 1031 走 excamera + MP4 封装；本模块因 Air1601 无 MP4 mux / 无 excamera USB 支持，
  改为采集 H.264 裸流直接上传（保存为 .h264）。
- 网络使用 Air1601 默认网卡（netdrv_device 里配置，如 4G/WIFI/以太网）。

注意：
- Air1601 不支持 camera.capture()，故本模块使用 camera 原始 API（get_usb_config/set_usb_config/cache/stream）。
- rtmp_app.lua 的 RTMP 推流在 Air1601 上暂未实现（取帧接入缺口），本文件不含 RTMP。
- 本模块与 face_demo / photo_to_aircloud / audio_record 互斥：一次只能打开一个。
]]

-- 引入 httpplus 扩展库（http 上传）
local httpplus = require("httpplus")
-- 引入 excloud 扩展库（合宙云上传，默认方式）
local excloud = require("excloud")

-- AirCAMERA_1032摄像头供电控制引脚，高电平有效（客户按实际开发板切换）
-- Air1601_V1.1开发板：GPIO12 = USB主机模式/摄像头总供电
-- gpio.setup(12, 1, gpio.PULLUP)
-- Air160X_V1.2开发板：GPIO58 = USB主机模式/摄像头总供电
local CAMERA_PWR_PIN = 58    -- 如改用 Air1601_V1.1 开发板，请改为 12
gpio.setup(CAMERA_PWR_PIN, 1, gpio.PULLUP)

-- Air160X_V1.2开发板：拉高 GPIO56（SD_EN）；Air1601_V1.1开发板无 SD_EN 引脚
gpio.setup(56, 1)

-- 目标分辨率（期望值；摄像头不支持时按 1032 的默认逻辑处理）
local SENSOR_W = 1280
local SENSOR_H = 720

-- 录制时长（秒）
local RECORD_SECONDS = 5
-- 每次录制/上传完成后的间隔（秒）
local LOOP_INTERVAL = 2

-- 保存路径（默认 /ram，如需落 SD 卡可自行挂载并改为 /sd/video.h264）
local SAVE_PATH = "/ram/video.h264"

-- 上传服务器地址（POST，bodyfile 上传）
-- 可替换为你自己的接收接口；默认继承 1031 的上传地址
local UPLOAD_URL = "http://uploadtest.luatos.com/api/upload/mp4"
-- 上传超时（秒）
local UPLOAD_TIMEOUT = 150

-- 上传方式：true=走 excloud(合宙云，默认)，false=走 httpplus(UPLOAD_URL)
local UPLOAD_VIA_EXCLOUD = true
-- excloud 项目密钥（UPLOAD_VIA_EXCLOUD=true 时使用，需在 iot.luatos.com 立项并填自己的 key）
local PROJECT_AUTH_KEY = "hegiSG73FHMzvFToaugk4CZXIla92Dnj"

-- 是否启用 SD 卡挂载（挂载成功则保存到 /sd/video.h264）
local USE_SD = true

-- ==================== 全局变量 ====================
local usb_app_id = nil          -- USB 摄像头应用 ID
local frame_buff0 = nil         -- 双缓冲帧缓冲区
local frame_buff1 = nil
local recording = false         -- 是否正在录制
local file_handle = nil         -- 当前写入的文件句柄
local record_start_time = 0     -- 录制开始时间戳
local file_bytes = 0            -- 本次录制写入的字节数
local frame_count = 0           -- 收到帧计数（调试）
local buff_size = math.ceil(SENSOR_W * SENSOR_H * 1.5)  -- H.264 缓冲区大小（按分辨率自适应）

-- ==================== TF/SD 卡挂载（可选，参考 Air1601 平台 sd 挂载示例） ====================
local function mount_sd_card()
    -- 使用 SPI1，片选 GPIO8（Air1601 平台）
    local spi_id = 1
    local pin_cs = 8
    spi.setup(spi_id, nil, 0, 0, 8, 400000)   -- 低速初始化
    gpio.setup(pin_cs, 1)                     -- 片选拉高
    local ok, err = fatfs.mount(fatfs.SPI, "/sd", spi_id, pin_cs, 24000000, nil, 1, false)
    if ok then
        log.info("video_http_post", "SD卡挂载成功")
        SAVE_PATH = "/sd/video.h264"
        sys.publish("SD_READY")
    else
        log.warn("video_http_post", "SD卡挂载失败，回退 /ram:", err)
        SAVE_PATH = "/ram/video.h264"
    end
end

-- ==================== USB 事件回调 ====================
local function usb_cb(usb_id, class, app_id, event, param1, param2, param3)
    if event == usb.EV_CONNECT then
        if class == usb.CAMERA then
            log.info("video_http_post", "USB摄像头已连接, app id", app_id)
        end
    elseif event == usb.EV_DISCONNECT then
        if class == usb.CAMERA then
            log.info("video_http_post", "USB摄像头已断开")
            usb_app_id = nil
            recording = false
            if file_handle then file_handle:close(); file_handle = nil end
        end
    end
end

-- ==================== 摄像头回调：枚举 H.264 + 设置缓存 ====================
local function camera_cb(app_id, event, param)
    -- 摄像头连接成功，枚举并设置 H.264 + 720P
    if event == usb.EV_CONNECT then
        usb_app_id = app_id
        -- 枚举 USB 摄像头支持的数据流格式
        local res, format_num = camera.get_usb_config(app_id, camera.CONF_UVC_FORMAT)
        if not res then
            log.error("video_http_post", "枚举摄像头格式失败")
            return
        end
        log.info("video_http_post", "UVC格式数量:", format_num)

        local found = false
        for fmt_idx = 1, format_num do
            local _, type, frame_num = camera.get_usb_config(app_id, camera.CONF_UVC_FORMAT, fmt_idx)
            if type == camera.FORMAT_H264 then
                -- 找到 H.264 格式，遍历该格式下的可用分辨率，优先匹配 SENSOR_W x SENSOR_H
                for frm_idx = 1, frame_num do
                    local _, fps, w, h = camera.get_usb_config(app_id, camera.CONF_UVC_RESOLUTION, fmt_idx, frm_idx)
                    if not w then break end
                    log.info("video_http_post", "H.264 分辨率", w, "x", h)
                    if w == SENSOR_W and h == SENSOR_H then
                        camera.set_usb_config(app_id, camera.CONF_UVC_RESOLUTION, fmt_idx, frm_idx)
                        found = true
                        break
                    end
                end
                if found then break end
            end
        end

        if not found then
            -- 退而求其次：直接按目标分辨率设置（摄像头缺省）
            log.warn("video_http_post", "未匹配到 H.264 目标分辨率，使用默认设置")
            camera.set_usb_config(app_id, camera.CONF_UVC_RESOLUTION, camera.FORMAT_H264, SENSOR_W, SENSOR_H)
        end

        -- 创建双缓冲并开启缓存
        frame_buff0 = zbuff.create(buff_size)
        frame_buff1 = zbuff.create(buff_size)
        camera.cache(camera.USB, app_id, frame_buff0, frame_buff1)

        log.info("video_http_post", "摄像头已就绪，准备录制")
        sys.publish("CAMERA_READY")
    elseif event == usb.EV_NEW_RX then
        -- 收到一帧 H.264 裸流
        local current_buff = (param == 0) and frame_buff0 or frame_buff1
        local data_len = current_buff:used()
        if data_len <= 0 then return end
        -- 调试：每 300 帧打印一次
        frame_count = frame_count + 1
        if frame_count % 300 == 1 then
            log.info("video_http_post", "收到帧 #", frame_count, "len", data_len)
        end
        -- 正在录制则写入文件（懒打开，LuatOS io.open 用 "a" 追加）
        if recording then
            if not file_handle then
                file_handle = io.open(SAVE_PATH, "a")
                if not file_handle then
                    log.error("video_http_post", "打开文件失败:", SAVE_PATH)
                end
            end
            if file_handle then
                file_handle:write(current_buff:toStr(0, data_len))
                file_bytes = file_bytes + data_len
            end
        end
    elseif event == usb.EV_ERR_STOP then
        log.error("video_http_post", "摄像头采集异常停止")
        recording = false
        if file_handle then file_handle:close(); file_handle = nil end
    end
end

-- ==================== excloud（合宙云，默认）上传 ====================
local excloud_initialized = false
local excloud_init_lock = false

local function excloud_event_cb(event, data)
    log.info("video_http_post", "excloud事件", event)
    if event == "connect_result" then
        if data and data.success then
            sys.publish("aircloud_connected")
        else
            log.error("video_http_post", "excloud连接失败:", data and data.error or "unknown")
        end
    elseif event == "disconnect" then
        log.warn("video_http_post", "excloud断开连接")
    end
end
excloud.on(excloud_event_cb)

local function init_excloud()
    if excloud_initialized then return true end
    if excloud_init_lock then
        sys.waitUntil("aircloud_connected", 30000)
        return excloud_initialized
    end
    excloud_init_lock = true

    while not socket.adapter(socket.dft()) do
        log.warn("video_http_post", "等待网络连接...")
        sys.waitUntil("IP_READY", 1000)
    end

    local ok, err = excloud.setup({
        use_getip = true,
        auth_key = PROJECT_AUTH_KEY,
        transport = "tcp",
        auto_reconnect = true,
        reconnect_interval = 10,
        max_reconnect = 5
    })
    if not ok then
        log.error("video_http_post", "excloud配置失败:", err)
        excloud_init_lock = false
        return false
    end
    ok, err = excloud.open()
    if not ok then
        log.error("video_http_post", "excloud开启失败:", err)
        excloud_init_lock = false
        return false
    end
    excloud.start_heartbeat()

    local ret = sys.waitUntil("aircloud_connected", 30000)
    if ret and excloud.status().is_connected then
        excloud_initialized = true
        excloud_init_lock = false
        return true
    else
        log.error("video_http_post", "AirCloud连接超时")
        excloud_init_lock = false
        return false
    end
end

local function upload_via_excloud(filepath)
    if not excloud_initialized then
        if not init_excloud() then
            log.error("video_http_post", "excloud初始化失败，跳过上传")
            return false
        end
    end
    if not excloud.status().is_connected then
        sys.waitUntil("aircloud_connected", 30000)
    end
    -- 函数名含 image，但支持任意二进制文件（官方 h264 上传即是如此）
    local ok, err = excloud.upload_image(filepath, "video.h264")
    if ok then
        log.info("video_http_post", "AirCloud上传成功")
        return true
    else
        log.error("video_http_post", "AirCloud上传失败:", err)
        return false
    end
end

-- ==================== 上传分派 ====================
local function upload_file(filepath)
    if UPLOAD_VIA_EXCLOUD then
        return upload_via_excloud(filepath)
    end
    -- 备用：httpplus POST 到自定义接口
    while not socket.adapter(socket.dft()) do
        log.warn("video_http_post", "wait IP_READY", socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end
    local opts = {
        url = UPLOAD_URL,
        method = "POST",
        bodyfile = filepath,
        timeout = UPLOAD_TIMEOUT
    }
    local code = httpplus.request(opts)
    if code == 200 then
        log.info("video_http_post", "上传成功, code:", code)
    else
        log.error("video_http_post", "上传失败, code:", code)
    end
    return code
end

-- ==================== 主循环：录制 -> 上传 ====================
local function video_capture_loop()
    while true do
        -- 等摄像头就绪
        sys.waitUntil("CAMERA_READY", 60000)
        if not usb_app_id then
            log.warn("video_http_post", "摄像头未就绪，重试")
            sys.wait(2000)
        end

        -- 开始录制：先创建空文件（io.open "w"），实际写入由 camera_cb 懒打开 "a" 追加
        recording = true
        file_bytes = 0
        os.remove(SAVE_PATH)   -- 清旧文件
        local f = io.open(SAVE_PATH, "w")
        if f then f:close() end
        record_start_time = os.time()
        log.info("video_http_post", "开始录制:", SAVE_PATH, RECORD_SECONDS, "秒")
        camera.stream(camera.USB, usb_app_id)

        -- 录制 RECORD_SECONDS 秒
        while (os.time() - record_start_time) < RECORD_SECONDS do
            sys.wait(100)
        end

        -- 停止录制
        recording = false
        camera.stop(camera.USB)
        if file_handle then file_handle:close(); file_handle = nil end
        log.info("video_http_post", "录制结束文件:", SAVE_PATH, "字节数:", file_bytes)

        -- 检查文件大小（用写入字节计数判断）
        if file_bytes <= 0 then
            log.warn("video_http_post", "文件为空，跳过上传")
        else
            -- 上传
            upload_file(SAVE_PATH)
        end

        -- 等待下一次触发
        sys.wait(LOOP_INTERVAL * 1000)
    end
end

-- ==================== 摄像头供电 ====================
-- AirCAMERA_1032摄像头供电控制引脚上电（Air1601_V1.1=GPIO12 / Air160X_V1.2=GPIO58，由上方 CAMERA_PWR_PIN 决定）
gpio.setup(CAMERA_PWR_PIN, 1, gpio.PULLUP)

-- ==================== USB / 相机初始化 ====================
local function camera_app_init()
    -- 注册回调
    usb.on(0, usb_cb)
    camera.on(camera.USB, "usb_raw", camera_cb)
    -- 确保 USB 外设掉电，再设为主机模式上电
    pm.power(pm.USB, false)
    local mode_result = usb.mode(0, usb.HOST)
    log.info("video_http_post", "USB模式设置结果", mode_result)
    pm.power(pm.USB, true)
    log.info("video_http_post", "USB上电完成")
end

-- 延迟 2 秒初始化，给系统留出准备时间
sys.taskInit(function()
    sys.wait(2000)
    camera_app_init()
end)

-- 可选：挂载 SD 卡（挂载成功后 SAVE_PATH 会切到 /sd）
if USE_SD then
    sys.taskInit(function()
        mount_sd_card()
    end)
end

-- 录制主循环
sys.taskInit(video_capture_loop)

-- 内存监控（无 LCD，重点关注内存）
sys.taskInit(function()
    while true do
        sys.wait(10000)
        log.info("video_http_post", "sys ram", rtos.meminfo("sys"))
        log.info("video_http_post", "lua ram", rtos.meminfo("lua"))
        collectgarbage()
    end
end)
