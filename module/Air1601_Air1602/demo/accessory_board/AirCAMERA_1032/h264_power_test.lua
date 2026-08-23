--[[
@module  h264_power_test
@summary H.264 功耗分阶段测试（可选模式）
@version 2.1
@date    2026-07-09
@usage

使用说明：
1. 在文件开头修改 TEST_MODE 选择测试阶段：
  1 = 仅 H.264 编码（不保存、不上传）
  2 = 编码 + 本地保存（保存到 SD 卡，文件保留）
  3 = 编码 + 保存 + 串口上传（文件保留）
  4 = 编码 + 保存 + AirCloud 上传（使用 excloud 上传到合宙云平台，自动初始化）
2. 确保 SD 卡已插入（若使用），且格式为 FAT32
3. 模式4需要网络连接，确保4G/WiFi已配置，并填写正确的 PROJECT_AUTH_KEY
4. 烧录到设备，等待摄像头连接
5. 用功耗分析仪Air9000P测量稳定运行时的平均电流
6. 测试完成后断电或复位即可
7. 录制文件会以 video_时间戳.h264 保存在 SD 卡（或 /ram）中，需定期手动清理。

AirCloud 上传说明：
- 模式4使用 excloud.upload_image 上传 H.264 文件，服务器会按二进制文件存储。
- 若需查看上传的文件，可在合宙云平台（https://iot.luatos.com/）的对应项目下查看。

]]

-- ==================== 引入必要的库 ====================
local httpplus = require("httpplus")   
local excloud = require("excloud")    

-- ==================== 用户配置区 ====================
local TEST_MODE = 4        -- 1/2/3/4，选择测试阶段
local RECORD_SECONDS = 5   -- 录制时长（秒），仅用于模式 2/3/4
local LOOP_INTERVAL = 2    -- 每个循环结束后的等待间隔（秒），仅模式 2/3/4
local UART_BAUD = 2000000  -- 串口波特率（仅模式 3）

-- AirCloud 项目密钥（模式4使用）
local PROJECT_AUTH_KEY = "hegiSG73FHMzvFToaugk4CZXIla92Dnj"  -- 请替换为自己的 key

-- 首选保存路径（SD 卡），若挂载失败会自动回退到 /ram
local SAVE_PATH_PREFERRED = "/sd/video.h264"
local SAVE_PATH_FALLBACK = "/ram/video.h264"
local SAVE_PATH = SAVE_PATH_PREFERRED   -- 初始值，稍后可能被覆盖

-- 摄像头分辨率（720P）
local SENSOR_W = 1280
local SENSOR_H = 720

-- ==================== 全局变量 ====================
local excloud_initialized = false   -- 标记 excloud 是否已初始化
local excloud_init_lock = false     -- 防止并发初始化

-- ==================== 硬件初始化 ====================
-- 拉高摄像头供电（GPIO12）
gpio.setup(12, 1, gpio.PULLUP)
-- 关闭 LCD 背光（背光控制 GPIO2，如不需要可注释）
-- gpio.setup(2, 0)  -- 拉低关闭背光
-- 关闭 4G 模块（避免射频干扰功耗测量）
-- pm.power(pm.MODEM, false)

-- ==================== SD 卡挂载（Air1601 专用，参考 tfcard_app.lua） ====================
-- 使用 SPI1，片选 GPIO8
local function mount_sd_card()
    local spi_id = 1
    local pin_cs = 8
    -- 配置 SPI
    spi.setup(spi_id, nil, 0, 0, 8, 400000)   -- 低速初始化
    gpio.setup(pin_cs, 1)                     -- 片选拉高

    -- 挂载 TF 卡（如果格式化，可去掉第5个参数或设为 false）
    local ok, err = fatfs.mount(fatfs.SPI, "/sd", spi_id, pin_cs, 24000000, nil, 1, false)
    if ok then
        log.info("SD卡", "挂载成功")
        -- 获取可用空间（可选）
        local data, err = fatfs.getfree("/sd")
        if data then
            log.info("SD卡", "可用空间", json.encode(data))
        end
        sys.publish("SD_READY")   -- 可选，用于其他任务
    else
        log.error("SD卡", "挂载失败", err)
        sys.publish("SD_FAILED")
    end
end

-- 启动挂载任务（独立于主任务，提前执行）
sys.taskInit(function()
    mount_sd_card()
    -- 挂载完成后任务结束，但保留事件通知
end)

-- ==================== 串口初始化（仅模式3） ====================
local uartid = 3
if TEST_MODE == 3 then
    uart.setup(uartid, UART_BAUD, 8, 0, 1)  
    log.info("h264_test", "UART 初始化完成，波特率", UART_BAUD)
end

-- ==================== 摄像头缓冲区 ====================
local buff_size = math.ceil(SENSOR_W * SENSOR_H * 1.5)
local frame_buff0 = zbuff.create(buff_size)
local frame_buff1 = zbuff.create(buff_size)
local usb_app_id = nil
local recording = false
local file_handle = nil
local record_start_time = 0

-- ==================== USB / 摄像头回调 ====================
local function usb_cb(usb_id, class, app_id, event, param1, param2, param3)
    if event == usb.EV_CONNECT and class == usb.CAMERA then
        log.info("h264_test", "USB 摄像头已连接，app id", app_id)
    elseif event == usb.EV_DISCONNECT and class == usb.CAMERA then
        log.info("h264_test", "USB 摄像头已断开")
        usb_app_id = nil
        recording = false
        if file_handle then file_handle:close(); file_handle = nil end
    end
end

local function camera_cb(app_id, event, param)
    if event == usb.EV_NEW_RX then
        local current_buff = (param == 0) and frame_buff0 or frame_buff1
        local data_len = current_buff:used()
        if data_len == 0 then return end

        if TEST_MODE == 1 then
            -- 模式1：仅编码，不保存不上传（仅记录日志，每100帧打印一次）
            static_frame_count = (static_frame_count or 0) + 1
            if static_frame_count % 100 == 0 then
                log.info("h264_test", "编码帧数", static_frame_count, "长度", data_len)
            end
        elseif TEST_MODE >= 2 and recording then
            -- 模式2/3/4：写入文件
            if not file_handle then
                file_handle = io.open(SAVE_PATH, "a")
                if not file_handle then
                    log.error("h264_test", "无法打开文件写入")
                    recording = false
                    return
                end
            end
            local block_data = current_buff:toStr(0, data_len)
            file_handle:write(block_data)
        end
        return
    end

    if event == usb.EV_CONNECT then
        usb_app_id = app_id
        -- 枚举并设置 H.264 + 720P
        local res, format_num = camera.get_usb_config(app_id, camera.CONF_UVC_FORMAT)
        local found = false
        for fmt_idx = 1, format_num do
            local _, type, frame_num = camera.get_usb_config(app_id, camera.CONF_UVC_FORMAT, fmt_idx)
            if type == camera.FORMAT_H264 then
                for frm_idx = 1, frame_num do
                    local _, fps, w, h = camera.get_usb_config(app_id, camera.CONF_UVC_RESOLUTION, fmt_idx, frm_idx)
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
            log.warn("h264_test", "未找到 H.264 720P，使用默认")
            camera.set_usb_config(app_id, camera.CONF_UVC_RESOLUTION, camera.FORMAT_H264, SENSOR_W, SENSOR_H)
        end
        camera.cache(camera.USB, app_id, frame_buff0, frame_buff1)
        sys.publish("CAMERA_READY")
        return
    end

    if event == usb.EV_DISCONNECT then
        usb_app_id = nil
        recording = false
        if file_handle then file_handle:close(); file_handle = nil end
        return
    end

    if event == usb.EV_RX_ERR or event == usb.EV_ERR_STOP then
        log.warn("h264_test", "摄像头异常", event)
        if event == usb.EV_ERR_STOP then
            usb.reset_device(0, app_id)
            usb_app_id = nil
        end
        recording = false
        if file_handle then file_handle:close(); file_handle = nil end
    end
end

-- ==================== 串口发送函数（模式3） ====================
local function send_file_via_uart(file_path)
    local file_size = io.fileSize(file_path)
    if not file_size or file_size == 0 then
        log.error("h264_test", "文件为空，跳过发送")
        return false
    end
    log.info("h264_test", "开始发送文件，大小", file_size, "字节")
    local file = io.open(file_path, "r")
    if not file then return false end
    local block_size = 4096
    local total_sent = 0
    while true do
        local data = file:read(block_size)
        if not data then break end
        uart.tx(uartid, data)
        total_sent = total_sent + #data
        sys.wait(1)  -- 避免串口溢出
    end
    file:close()
    log.info("h264_test", "文件发送完成，共发送", total_sent, "字节")
    return true
end

-- ==================== excloud 初始化函数（模式4专用） ====================
local function init_excloud()
    if excloud_initialized then
        return true
    end
    if excloud_init_lock then
        -- 若已在初始化中，则等待结果
        sys.waitUntil("EXCLOUD_INIT_DONE", 30000)
        return excloud_initialized
    end
    excloud_init_lock = true

    log.info("h264_test", "初始化 excloud...")

    -- 等待网络就绪
    while not socket.adapter(socket.dft()) do
        log.warn("h264_test", "等待网络连接...")
        sys.waitUntil("IP_READY", 1000)
    end

    -- 配置 excloud（不指定 device_type，自动检测）
    local ok, err = excloud.setup({
        use_getip = true,
        auth_key = PROJECT_AUTH_KEY,
        transport = "tcp",
        auto_reconnect = true,
        reconnect_interval = 10,
        max_reconnect = 5,
        mtn_log_enabled = true,
        mtn_log_blocks = 1,
        mtn_log_write_way = excloud.MTN_LOG_CACHE_WRITE
    })
    if not ok then
        log.error("h264_test", "excloud 配置失败:", err)
        excloud_init_lock = false
        sys.publish("EXCLOUD_INIT_DONE")
        return false
    end

    ok, err = excloud.open()
    if not ok then
        log.error("h264_test", "excloud 开启失败:", err)
        excloud_init_lock = false
        sys.publish("EXCLOUD_INIT_DONE")
        return false
    end

    -- 启动心跳
    excloud.start_heartbeat()

    -- 等待连接成功事件（回调中会发布 aircloud_connected）
    log.info("h264_test", "等待 AirCloud 连接...")
    local ret = sys.waitUntil("aircloud_connected", 30000)
    if ret and excloud.status().is_connected then
        log.info("h264_test", "AirCloud 已连接")
        excloud_initialized = true
        excloud_init_lock = false
        sys.publish("EXCLOUD_INIT_DONE")
        return true
    else
        log.error("h264_test", "AirCloud 连接超时")
        excloud_init_lock = false
        sys.publish("EXCLOUD_INIT_DONE")
        return false
    end
end

-- ==================== AirCloud 上传函数（模式4） ====================
local function aircloud_upload_file(file_path)
    local file_size = io.fileSize(file_path)
    if not file_size or file_size == 0 then
        log.error("h264_test", "文件为空，跳过上传")
        return false
    end
    log.info("h264_test", "开始 AirCloud 上传，大小", file_size, "字节")

    -- 如果未初始化，尝试初始化
    if not excloud_initialized then
        log.info("h264_test", "excloud 未初始化，尝试初始化...")
        local init_ok = init_excloud()
        if not init_ok then
            log.error("h264_test", "excloud 初始化失败，跳过上传")
            return false
        end
    end

    -- 再次检查连接状态
    local status = excloud.status()
    if not status.is_connected then
        log.warn("h264_test", "excloud 未连接，等待连接...")
        sys.waitUntil("aircloud_connected", 30000)
        status = excloud.status()
        if not status.is_connected then
            log.error("h264_test", "excloud 连接超时，跳过上传")
            return false
        end
    end

    -- 使用 excloud.upload_image 上传（虽然函数名含 image，但支持任意文件）
    local ok, err = excloud.upload_image(file_path, "video.h264")
    if ok then
        log.info("h264_test", "AirCloud 上传成功")
        return true
    else
        log.error("h264_test", "AirCloud 上传失败:", err)
        return false
    end
end

-- ==================== excloud 事件回调（用于处理连接状态） ====================
local function excloud_event_cb(event, data)
    log.info("h264_test", "excloud 事件:", event)
    if event == "connect_result" then
        if data and data.success then
            log.info("h264_test", "excloud 连接成功")
            sys.publish("aircloud_connected")
        else
            log.error("h264_test", "excloud 连接失败:", data and data.error or "unknown")
        end
    elseif event == "disconnect" then
        log.warn("h264_test", "excloud 断开连接")
    end
end

-- 注册 excloud 回调
excloud.on(excloud_event_cb)

-- ==================== 主任务 ====================
sys.taskInit(function()
    sys.wait(100)
    log.info("h264_test", "启动，测试模式", TEST_MODE)

    -- 如果模式 2/3/4 需要存储，检查 SD 卡挂载状态（方案一：直接检查目录）
    if TEST_MODE >= 2 then
        log.info("h264_test", "检查 SD 卡状态...")
        sys.wait(200)  -- 给挂载任务一点处理时间
        if io.dexist("/sd") then
            log.info("h264_test", "SD 卡已就绪，使用路径:", SAVE_PATH_PREFERRED)
            SAVE_PATH = SAVE_PATH_PREFERRED
        else
            log.warn("h264_test", "SD 卡未就绪，回退到 /ram 路径")
            SAVE_PATH = SAVE_PATH_FALLBACK
        end
        log.info("h264_test", "最终保存路径:", SAVE_PATH)
    end

    -- 注册 USB 和摄像头回调
    usb.on(0, usb_cb)
    camera.on(camera.USB, "usb_raw", camera_cb)

    -- USB 主机模式上电
    pm.power(pm.USB, false)
    usb.mode(0, usb.HOST)
    pm.power(pm.USB, true)

    -- 等待摄像头就绪
    sys.waitUntil("CAMERA_READY")
    log.info("h264_test", "摄像头已就绪")

    if TEST_MODE == 1 then
        -- ====== 模式1：仅编码，持续运行 ======
        log.info("h264_test", "模式1：仅编码（不保存不上传），持续运行...")
        camera.stream(camera.USB, usb_app_id)
        while true do
            sys.wait(60000)
            log.info("h264_test", "模式1 运行中... 帧数", static_frame_count or 0)
        end
    else
        -- ====== 模式2/3/4：循环录制 ======
        local loop_count = 0
        while true do
            loop_count = loop_count + 1
            log.info("h264_test", string.format("===== 循环 %d 开始 =====", loop_count))

            -- 1. 准备录制
            recording = true
            record_start_time = os.time()
            if io.exists(SAVE_PATH) then
                os.remove(SAVE_PATH)
            end
            file_handle = io.open(SAVE_PATH, "w")
            if not file_handle then
                log.error("h264_test", "无法创建文件")
                recording = false
                sys.wait(1000)
                goto continue_loop
            end
            file_handle:close()
            file_handle = nil

            -- 2. 启动流
            camera.stream(camera.USB, usb_app_id)

            -- 3. 录制指定时长
            while os.time() - record_start_time < RECORD_SECONDS do
                sys.wait(100)
            end

            -- 4. 停止录制
            recording = false
            camera.stop(camera.USB)
            if file_handle then
                file_handle:close()
                file_handle = nil
            end

            local file_size = io.fileSize(SAVE_PATH) or 0
            log.info("h264_test", "录制完成，文件大小", file_size, "字节")

            -- 5. 根据不同模式执行上传
            if TEST_MODE == 3 then
                -- 串口上传
                send_file_via_uart(SAVE_PATH)
            elseif TEST_MODE == 4 then
                -- AirCloud 上传（内部会自动初始化）
                aircloud_upload_file(SAVE_PATH)
            end

            -- 6. 保留文件（重命名加上时间戳），不删除
            if file_size > 0 then
                local ts = os.time()
                local dir = SAVE_PATH:match("(.*)/") or "/sd"
                local name = SAVE_PATH:match(".*/(.*)") or "video.h264"
                local base = name:match("^(.*)%..*$") or name
                local ext = name:match("^.*%.(.*)$") or "h264"
                local new_path = string.format("%s/%s_%d.%s", dir, base, ts, ext)
                local ok = os.rename(SAVE_PATH, new_path)
                if ok then
                    log.info("h264_test", "文件已保留为", new_path)
                else
                    log.error("h264_test", "保留文件失败，尝试删除", SAVE_PATH)
                    os.remove(SAVE_PATH)
                end
            else
                -- 文件大小为0，无意义，删除
                os.remove(SAVE_PATH)
                log.info("h264_test", "文件为空，已删除")
            end

            -- 7. 等待间隔
            sys.wait(LOOP_INTERVAL * 1000)

            ::continue_loop::
        end
    end
end)

