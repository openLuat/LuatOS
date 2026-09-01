--[[
@module  photo_aircloud_nolcd
@summary Air8101 + AirCAMERA_1034 USB摄像头循环拍照上传合宙云平台
@version 1.0
@date    2026.08.25
@author  王城钧
@usage
本demo主要使用Air8101 + AirCAMERA_1034 USB摄像头完成以下功能：
1、使用Air8101原生excamera库初始化USB摄像头（标准UVC接口），无需usb.mode手动切主机模式；
2、初始化excloud库并连接合宙iot.openluat.com云平台；
3、使用1280x720分辨率，每10秒触发一次拍照（open→photo→close）；
4、将照片保存到/ram/photo.jpg；
5、通过excloud.upload_image将照片上传到合宙云平台。

注意：
1、本文件为Air1601版本适配Air8101的改写版。Air1601使用 usb.mode(0,usb.HOST)+"usb_raw"事件+camera.cache/stream 的UVC裸流程，
   该流程在Air8101上不可用（usb.mode返回false），Air8101原生驱动为 excamera/camera.init 方案。
2、Air8101上 GPIO13 控制 3.3V LDO 输出，为摄像头供电（拉高使能）。
3、使用前需要：main.lua 中 require "netdrv_wifi"（提供WiFi网络）。
]]

-- 引入excamera扩展库（Air8101原生USB摄像头驱动封装）
local excamera = require "excamera"
-- 引入excloud扩展库
local excloud = require("excloud")


-- 拍照间隔（毫秒），每隔多久触发一次拍照
local capture_interval_ms = 10000

-- AirCAMERA_1034摄像头供电控制引脚（Air8101上GPIO13控制3.3V LDO输出），需要拉高使能
gpio.setup(13, 1, gpio.PULLUP)

-- 全局变量
local save_path = "/ram/photo.jpg"           -- 照片保存路径
local excloud_connected = false              -- excloud连接状态

-- USB摄像头配置表（Air8101原生excamera参数）
-- 注意（实测结论）：
-- 必须配置 fps，否则摄像头不出流。
local usb_camera_param = {
    id = camera.USB,                          -- 摄像头类型：USB接口
    sensor_width = 320,                       -- 像素宽度
    sensor_height = 240,                      -- 像素高度
    usb_port = 1,                             -- USB端口号（无HUB时填1；有HUB时1~4）
    fps = 15,                                 -- 帧率
    save_path = save_path                     -- 照片保存路径
}

-- 打开摄像头并拍照
-- 返回：(是否拍成照片)
local function open_and_photo()
    local open_ok = excamera.open(usb_camera_param)
    if not open_ok then
        excamera.close()
        log.warn("photo_aircloud_nolcd", "摄像头初始化失败（请检查USB连接/供电）")
        return false
    end
    local photo_ok, path = excamera.photo()
    excamera.close()
    if not photo_ok then
        log.warn("photo_aircloud_nolcd", "拍照失败或超时")
        return false
    end
    log.info("photo_aircloud_nolcd", "照片已保存到", path or save_path)
    return true
end

-- excloud事件回调函数
-- 作用：处理excloud的连接、认证、断开、重连、发送结果等事件
local function on_excloud_event(event, data)
    log.info("photo_aircloud_nolcd", "excloud回调", event)
    if data then
        log.info("photo_aircloud_nolcd", "excloud回调数据", json.encode(data))
    end

    if event == "connect_result" then
        if data.success then
            log.info("photo_aircloud_nolcd", "excloud连接成功")
            excloud_connected = true
            sys.publish("EXCLOUD_CONNECTED")
        else
            log.info("photo_aircloud_nolcd", "excloud连接失败:", data.error or "未知错误")
            excloud_connected = false
        end
    elseif event == "auth_result" then
        if data.success then
            log.info("photo_aircloud_nolcd", "excloud认证成功")
        else
            log.info("photo_aircloud_nolcd", "excloud认证失败:", data.message)
        end
    elseif event == "disconnect" then
        log.warn("photo_aircloud_nolcd", "与excloud服务器断开连接")
        excloud_connected = false
    elseif event == "reconnect_failed" then
        log.info("photo_aircloud_nolcd", "excloud重连失败，已尝试", data.count, "次")
    elseif event == "send_result" then
        if data.success then
            log.info("photo_aircloud_nolcd", "excloud发送成功，流水号:", data.sequence_num)
        else
            log.info("photo_aircloud_nolcd", "excloud发送失败:", data.error_msg)
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
        log.info("photo_aircloud_nolcd", "sys ram", rtos.meminfo("sys"))
        log.info("photo_aircloud_nolcd", "lua ram", rtos.meminfo("lua"))
        collectgarbage()
    end
end

-- 启动内存监控任务
sys.taskInit(memory_check)

-- 拍照+上传任务
-- 作用：循环执行 打开摄像头→拍照→关闭摄像头→上传
local function capture_upload_task()
    while true do
        -- 1、打开摄像头并拍照（固定分辨率320x240，失败重试）
        local photo_ok = open_and_photo()
        if not photo_ok then
            log.warn("photo_aircloud_nolcd", "本轮拍照失败，", capture_interval_ms, "ms后重试")
            sys.wait(capture_interval_ms)
        else
            collectgarbage()
            collectgarbage()
            log.info("photo_aircloud_nolcd", "上传前内存状态", rtos.meminfo("lua"))

            -- 2、上传到云平台（必须已连接excloud才会真正上传）
            if excloud_connected then
                local status = excloud.status()
                if status.is_connected then
                    log.info("photo_aircloud_nolcd", "开始使用excloud上传图片")
                    local ok, err = excloud.upload_image(save_path, "photo.jpg")
                    if ok then
                        log.info("photo_aircloud_nolcd", "照片上传成功")
                    else
                        log.error("photo_aircloud_nolcd", "照片上传失败:", err)
                    end
                else
                    log.warn("photo_aircloud_nolcd", "excloud未连接，跳过本轮上传")
                end
            else
                log.warn("photo_aircloud_nolcd", "excloud尚未连接，跳过本轮上传")
            end
            sys.wait(capture_interval_ms)
        end
    end
end

-- excloud初始化任务
-- 作用：等待网络连接成功后，初始化excloud并开启服务
local function excloud_init_task()
    -- 等待默认网卡的IP_READY消息，确认联网成功
    while not socket.adapter(socket.dft()) do
        log.warn("photo_aircloud_nolcd", "等待IP_READY")
        sys.waitUntil("IP_READY", 1000)
    end
    log.info("photo_aircloud_nolcd", "网络已连接，开始初始化excloud")

    -- 配置excloud参数
    local ok, err_msg = excloud.setup({
        transport = "tcp",                    -- 使用TCP传输
        auto_reconnect = true,                -- 自动重连
        reconnect_interval = 10,              -- 重连间隔(秒)
        max_reconnect = 5,                    -- 最大重连次数
        mtn_log_enabled = true,               -- 启用运维日志
        mtn_log_blocks = 1,                   -- 日志文件块数
        mtn_log_write_way = excloud.MTN_LOG_CACHE_WRITE -- 缓存写入方式
    })

    if not ok then
        log.info("photo_aircloud_nolcd", "excloud初始化失败:", err_msg)
        return
    end
    log.info("photo_aircloud_nolcd", "excloud初始化成功")

    -- 开启excloud服务
    local ok, err_msg = excloud.open()
    if not ok then
        log.info("photo_aircloud_nolcd", "excloud服务开启失败:", err_msg)
        return
    end
    log.info("photo_aircloud_nolcd", "excloud服务已开启")

    -- 启动自动心跳（默认5分钟一次）
    excloud.start_heartbeat()
    log.info("photo_aircloud_nolcd", "自动心跳已启动")
end

-- 创建excloud初始化任务
sys.taskInit(excloud_init_task)
-- 创建拍照上传任务
sys.taskInit(capture_upload_task)
