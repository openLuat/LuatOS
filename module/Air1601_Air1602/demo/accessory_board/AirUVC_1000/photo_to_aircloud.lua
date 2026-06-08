--[[
@module  photo_to_aircloud
@summary AirUVC_1000 USB摄像头循环拍照+LCD显示+合宙云平台上传应用模块
@version 2.0
@date    2026.06.08
@author  江访
@usage
本demo主要使用Air1601 + AirUVC_1000 USB摄像头完成以下功能：
1、初始化USB主机模式，连接USB摄像头；
2、初始化excloud库并连接合宙iot.openluat.com云平台；
3、遍历USB摄像头支持的格式和分辨率，只选择MJPEG格式 + 1024x576；
4、每10秒触发一次拍照：启动stream → 接收一帧 → 停止stream；
5、将照片保存到/ram/photo.jpg；
6、调用lcd.showImage将照片显示到LCD屏幕；
7、通过excloud.upload_image将照片上传到合宙云平台。

使用前需要：
1、确保 main.lua 中 require "netdrv_device" 已打开（在 netdrv_device 内部选择实际使用的网卡）；
2、将下方 project_auth_key 替换为自己的合宙iot.openluat.com项目key。

本文件没有对外接口，直接在main.lua中require "photo_to_aircloud"就可以加载运行。
]]

-- 引入excloud扩展库
local excloud = require("excloud")

-- 合宙云平台项目key（请替换为自己项目的key）
local project_auth_key = "hegiSG73FHMzvFToaugk4CZXIla92Dnj"

-- 拍照间隔（毫秒），每隔多久触发一次拍照
local capture_interval_ms = 10000

-- 根据当前默认网卡自动判断 excloud 的 device_type
-- excloud 内部按 device_type 决定从哪个硬件源生成设备ID与鉴权信息：
--   1 = 4G   → 使用 mobile.imei() + mobile.muid()
--   2 = WIFI → 使用 wlan.getMac()
--   4 = 以太网 → 使用 netdrv.mac(socket.LWIP_ETH)
-- 因此必须与 netdrv_device 中启用的网卡匹配，本函数会自动适配
-- 如果识别失败（未启用任何已知网卡），返回 nil，由调用方终止 excloud 初始化
local function get_device_type_by_adapter()
    local adapter = socket.dft()
    if adapter == socket.LWIP_GP_GW then     -- 4G(AirLink)
        return 1
    elseif adapter == socket.LWIP_STA then   -- WIFI
        return 2
    elseif adapter == socket.LWIP_ETH then   -- 以太网
        return 4
    else
        return nil
    end
end

-- 12号GPIO配置（AirUVC_1000摄像头供电控制引脚），需要拉高使能
gpio.setup(12, 1, gpio.PULLUP)

-- 全局变量
local usb_app_id = nil                       -- USB摄像头应用ID
local frame_type = camera.FORMAT_MJPG        -- 使用MJPEG格式
local sensor_w = 1024                        -- 目标分辨率宽度
local sensor_h = 576                         -- 目标分辨率高度
local frame_buff = nil                       -- 帧数据缓冲区
local captured = false                       -- 本轮是否已拍照标志位
local save_path = "/ram/photo.jpg"           -- 照片保存路径
local excloud_connected = false              -- excloud连接状态

-- excloud事件回调函数
-- 作用：处理excloud的连接、认证、断开、重连、发送结果等事件
function on_excloud_event(event, data)
    log.info("photo_to_aircloud", "excloud回调", event)
    if data then
        log.info("photo_to_aircloud", "excloud回调数据", json.encode(data))
    end

    if event == "connect_result" then
        if data.success then
            log.info("photo_to_aircloud", "excloud连接成功")
            excloud_connected = true
            sys.publish("EXCLOUD_CONNECTED")
        else
            log.info("photo_to_aircloud", "excloud连接失败:", data.error or "未知错误")
            excloud_connected = false
        end
    elseif event == "auth_result" then
        if data.success then
            log.info("photo_to_aircloud", "excloud认证成功")
        else
            log.info("photo_to_aircloud", "excloud认证失败:", data.message)
        end
    elseif event == "disconnect" then
        log.warn("photo_to_aircloud", "与excloud服务器断开连接")
        excloud_connected = false
    elseif event == "reconnect_failed" then
        log.info("photo_to_aircloud", "excloud重连失败，已尝试", data.count, "次")
    elseif event == "send_result" then
        if data.success then
            log.info("photo_to_aircloud", "excloud发送成功，流水号:", data.sequence_num)
        else
            log.info("photo_to_aircloud", "excloud发送失败:", data.error_msg)
        end
    end
end

-- 注册excloud回调
excloud.on(on_excloud_event)

-- 内存检查函数
-- 作用：定期监控系统内存使用情况
local function memory_check()
    while true do
        sys.wait(10000)
        log.info("photo_to_aircloud", "sys ram", rtos.meminfo("sys"))
        log.info("photo_to_aircloud", "lua ram", rtos.meminfo("lua"))
        collectgarbage()
    end
end

-- 启动内存监控任务
sys.taskInit(memory_check)

-- USB事件回调函数
-- 作用：监听USB摄像头的连接和断开事件
local function usb_cb(usb_id, class, app_id, event, param1, param2, param3)
    if event == usb.EV_CONNECT then
        if class == usb.CAMERA then
            log.info("photo_to_aircloud", "usb摄像头已连接，app id", app_id,
                "hub地址", param1, "端口", param2, "地址", param3)
        end
    end
    if event == usb.EV_DISCONNECT then
        if class == usb.CAMERA then
            log.info("photo_to_aircloud", "usb摄像头已断开，app id", app_id,
                "hub地址", param1, "端口", param2, "地址", param3)
        end
    end
end

-- 摄像头事件回调函数
-- 作用：处理USB摄像头连接、断开、收到新帧、接收异常等事件
local function camera_cb(app_id, event, param)
    -- 接收到一帧图像数据（本轮只处理一帧，处理完立即停止stream）
    if event == usb.EV_NEW_RX then
        if not captured then
            local data_len = frame_buff:used()
            log.info("photo_to_aircloud", "接收到图像数据，长度", data_len)
            captured = true

            -- 立即停止摄像头流，避免后续帧继续涌入
            if usb_app_id then
                log.info("photo_to_aircloud", "本轮拍照完成，停止摄像头流")
                camera.stop(camera.USB)
            end

            -- 发布拍照完成事件，由capture_handler_task处理保存/显示/上传等耗时操作
            sys.publish("PHOTO_CAPTURED", data_len)
        end
        return
    end

    -- USB摄像头连接事件：枚举摄像头支持的格式和分辨率，但不主动启动stream
    if event == usb.EV_CONNECT then
        log.info("photo_to_aircloud", "usb摄像头已连接，app id", app_id)
        usb_app_id = app_id

        -- 创建帧数据缓冲区，按分辨率自适应大小
        -- 公式：宽 × 高（足够容纳任意质量的MJPEG压缩帧，留有充足余量）
        log.info("photo_to_aircloud", "创建frame_buff，当前内存状态", rtos.meminfo("lua"))
        collectgarbage()
        collectgarbage()
        if not frame_buff then
            local buff_size = math.ceil(sensor_w * sensor_h)
            log.info("photo_to_aircloud", "按分辨率自适应缓冲区大小", buff_size, "字节")
            frame_buff = zbuff.create(buff_size)
        end
        log.info("photo_to_aircloud", "frame_buff就绪，当前内存状态", rtos.meminfo("lua"))

        -- 遍历USB摄像头支持的所有格式和分辨率（只选择MJPEG格式）
        local res, format_num = camera.get_usb_config(usb_app_id, camera.CONF_UVC_FORMAT)
        log.info("photo_to_aircloud", "总共有", format_num, "种数据流格式")

        local found = false
        for format_index = 1, format_num, 1 do
            local res, type, frame_num = camera.get_usb_config(usb_app_id, camera.CONF_UVC_FORMAT, format_index)
            log.info("photo_to_aircloud", "格式索引", format_index, "类型", type, "帧数", frame_num)

            -- 只处理MJPEG格式
            if type == camera.FORMAT_MJPG then
                for frame_index = 1, frame_num, 1 do
                    local res, fps, w, h = camera.get_usb_config(usb_app_id, camera.CONF_UVC_RESOLUTION,
                        format_index, frame_index)
                    log.info("photo_to_aircloud", "  分辨率", w, "x", h, "fps", fps)

                    if w == sensor_w and h == sensor_h then
                        log.info("photo_to_aircloud", "找到匹配分辨率", w, "x", h, "(MJPEG)")
                        camera.set_usb_config(usb_app_id, camera.CONF_UVC_RESOLUTION, format_index, frame_index)
                        found = true
                        break
                    end
                end
                if found then break end
            else
                log.info("photo_to_aircloud", "跳过非MJPEG格式")
            end
        end

        -- 配置缓冲（stream将由拍照任务按需启动，此处不启动）
        camera.cache(camera.USB, usb_app_id, frame_buff, frame_buff)

        -- 通知拍照任务，摄像头已就绪，可以开始循环拍照
        sys.publish("CAMERA_READY")
        return
    end

    -- USB摄像头断开事件
    if event == usb.EV_DISCONNECT then
        log.info("photo_to_aircloud", "usb摄像头 app id", app_id, "已断开")
        usb_app_id = nil
        captured = false
        return
    end

    -- USB摄像头接收数据异常
    if event == usb.EV_RX_ERR then
        log.info("photo_to_aircloud", "usb摄像头接收数据异常")
        return
    end
end

-- 拍照处理任务
-- 作用：循环监听 PHOTO_CAPTURED 事件，将收到的帧数据保存到文件、LCD显示、上传云平台
local function capture_handler_task()
    while true do
        local _, data_len = sys.waitUntil("PHOTO_CAPTURED")
        log.info("photo_to_aircloud", "开始处理本轮拍照数据，长度", data_len)

        -- 提前声明goto后面要用到的所有local变量，避免goto跨越local声明导致编译错误
        local lcd_result = nil
        local status = nil
        local ok = nil
        local err = nil

        -- 保存照片到文件（分块写入，避免一次性占用大内存）
        local save_ok, save_err = pcall(function()
            local file = io.open(save_path, "w")
            if file then
                local block_size = 4096
                local offset = 0
                while offset < data_len do
                    local block_end = offset + block_size
                    if block_end > data_len then
                        block_end = data_len
                    end
                    local block_data = frame_buff:toStr(offset, block_end - offset)
                    file:write(block_data)
                    offset = block_end
                end
                file:close()
                log.info("photo_to_aircloud", "照片已保存到", save_path, "大小", data_len)
            else
                error("无法打开文件")
            end
        end)

        if not save_ok then
            log.error("photo_to_aircloud", "保存照片失败", save_err)
            sys.publish("PHOTO_DONE")
            goto continue_loop
        end

        -- 在LCD上显示照片
        log.info("photo_to_aircloud", "开始显示照片到LCD")
        lcd.clear(0x0000)
        lcd_result = lcd.showImage(0, 0, save_path)
        log.info("photo_to_aircloud", "lcd.showImage返回值", lcd_result)
        lcd.flush()
        log.info("photo_to_aircloud", "照片显示完成")

        -- 释放垃圾内存，准备上传
        collectgarbage()
        collectgarbage()
        log.info("photo_to_aircloud", "上传前内存状态", rtos.meminfo("lua"))

        -- 上传到云平台（必须已连接excloud才会真正上传）
        if excloud_connected then
            status = excloud.status()
            if status.is_connected then
                log.info("photo_to_aircloud", "开始使用excloud上传图片")
                ok, err = excloud.upload_image(save_path, "photo.jpg")
                if ok then
                    log.info("photo_to_aircloud", "照片上传成功")
                else
                    log.error("photo_to_aircloud", "照片上传失败:", err)
                end
            else
                log.warn("photo_to_aircloud", "excloud未连接，跳过本轮上传")
            end
        else
            log.warn("photo_to_aircloud", "excloud尚未连接，跳过本轮上传")
        end

        ::continue_loop::
        -- 通知触发任务，本轮拍照已完全处理结束
        sys.publish("PHOTO_DONE")
    end
end

-- 拍照循环触发任务
-- 作用：摄像头就绪后立即触发第一张拍照，然后每隔 capture_interval_ms 触发一次
local function capture_trigger_task()
    -- 等待摄像头连接并初始化完成
    sys.waitUntil("CAMERA_READY")
    log.info("photo_to_aircloud", "摄像头已就绪，开始循环拍照，间隔", capture_interval_ms, "ms")

    while true do
        if usb_app_id then
            -- 重置标志位，准备本轮拍照
            captured = false
            log.info("photo_to_aircloud", "触发新一轮拍照")
            -- 启动摄像头流，等待回调收到一帧后会自动停止
            camera.stream(camera.USB, usb_app_id)
            -- 等待本轮拍照处理完成（最多等30秒，防止上传慢卡死）
            sys.waitUntil("PHOTO_DONE", 30000)
        else
            log.warn("photo_to_aircloud", "摄像头未连接，跳过本轮拍照")
        end
        -- 等待下一轮拍照间隔
        sys.wait(capture_interval_ms)
    end
end

-- excloud初始化任务
-- 作用：等待网络连接成功后，初始化excloud并开启服务
local function excloud_init_task()
    -- 等待默认网卡的IP_READY消息，确认联网成功
    while not socket.adapter(socket.dft()) do
        log.warn("photo_to_aircloud", "等待IP_READY")
        sys.waitUntil("IP_READY", 1000)
    end
    log.info("photo_to_aircloud", "网络已连接，开始初始化excloud")

    -- 配置excloud参数（device_type 由 get_device_type_by_adapter 根据当前网卡自动确定）
    local device_type = get_device_type_by_adapter()
    if not device_type then
        log.error("photo_to_aircloud", "未识别的网卡，无法上传到云平台",
            "请检查 netdrv_device.lua 中是否已启用 WIFI / 以太网 / 4G 网卡")
        return
    end
    log.info("photo_to_aircloud", "根据当前网卡自动选择 device_type", device_type)
    local ok, err_msg = excloud.setup({
        use_getip = true,
        device_type = device_type,            -- 自动适配 netdrv_device 中启用的网卡
        auth_key = project_auth_key,
        transport = "tcp",                    -- 使用TCP传输
        auto_reconnect = true,                -- 自动重连
        reconnect_interval = 10,              -- 重连间隔(秒)
        max_reconnect = 5,                    -- 最大重连次数
        mtn_log_enabled = true,               -- 启用运维日志
        mtn_log_blocks = 1,                   -- 日志文件块数
        mtn_log_write_way = excloud.MTN_LOG_CACHE_WRITE -- 缓存写入方式
    })

    if not ok then
        log.info("photo_to_aircloud", "excloud初始化失败:", err_msg)
        return
    end
    log.info("photo_to_aircloud", "excloud初始化成功")

    -- 开启excloud服务
    local ok, err_msg = excloud.open()
    if not ok then
        log.info("photo_to_aircloud", "excloud服务开启失败:", err_msg)
        return
    end
    log.info("photo_to_aircloud", "excloud服务已开启")

    -- 启动自动心跳（默认5分钟一次）
    excloud.start_heartbeat()
    log.info("photo_to_aircloud", "自动心跳已启动")
end

-- 摄像头初始化函数
-- 作用：注册回调，切换USB为主机模式并上电
local function camera_app_init()
    -- 注册USB回调函数
    usb.on(0, usb_cb)
    -- 注册摄像头回调函数
    camera.on(camera.USB, "usb_raw", camera_cb)
    -- 确保USB外设是掉电状态
    pm.power(pm.USB, false)
    -- USB设置成主机模式
    local mode_result = usb.mode(0, usb.HOST)
    log.info("photo_to_aircloud", "USB模式设置结果", mode_result)
    -- USB上电初始化开始工作
    pm.power(pm.USB, true)
    log.info("photo_to_aircloud", "USB上电完成")

    log.info("photo_to_aircloud", "初始化完成，摄像头连接后将每", capture_interval_ms, "ms循环拍照并上传")
end

-- 在协程中延迟2秒后初始化，给系统留出准备时间
local function init_camera_in_coroutine()
    sys.wait(2000)
    camera_app_init()
end

-- 创建摄像头初始化任务
sys.taskInit(init_camera_in_coroutine)
-- 创建excloud初始化任务
sys.taskInit(excloud_init_task)
-- 创建拍照数据处理任务
sys.taskInit(capture_handler_task)
-- 创建拍照循环触发任务
sys.taskInit(capture_trigger_task)
