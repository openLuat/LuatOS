--[[
@module  camera_preview
@summary AirCAMERA_1032 USB摄像头LCD实时预览应用模块
@version 1.0
@date    2026.06.08
@author  江访
@usage
本demo主要使用Air1601 + AirCAMERA_1032 USB摄像头完成实时画面预览到LCD屏幕的功能。
核心业务逻辑为：
1、初始化USB主机模式并打开摄像头预览功能；
2、监听USB摄像头连接事件；
3、遍历USB摄像头支持的格式和分辨率，只选择MJPEG格式；
4、优先匹配1024x576分辨率，找不到时退回到800x600；
5、通过camera.stream持续接收帧数据，画面由底层preview机制实时显示到LCD。

本文件没有对外接口，直接在main.lua中require "camera_preview"就可以加载运行。
]]

-- 12号GPIO配置（AirCAMERA_1032摄像头供电控制引脚），需要拉高使能
gpio.setup(12, 1, gpio.PULLUP)
-- 关闭hardfault自动复位，方便调试摄像头异常
mcu.hardfault(0)

-- 全局变量
local usb_app_id = nil                       -- USB摄像头应用ID
local frame_type = camera.FORMAT_MJPG        -- 使用MJPEG格式
local sensor_w = 1024                        -- 目标分辨率宽度
local sensor_h = 576                         -- 目标分辨率高度
local frame_buff0 = nil                      -- 双缓冲：帧缓冲0
local frame_buff1 = nil                      -- 双缓冲：帧缓冲1

-- USB事件回调函数
-- 作用：监听USB摄像头的连接和断开事件
local function usb_cb(usb_id, class, app_id, event, param1, param2, param3)
    if event == usb.EV_CONNECT then
        if class == usb.CAMERA then
            log.info("camera_preview", "usb摄像头已连接，app id", app_id,
                "hub地址", param1, "端口", param2, "地址", param3)
        end
    end
    if event == usb.EV_DISCONNECT then
        if class == usb.CAMERA then
            log.info("camera_preview", "usb摄像头已断开，app id", app_id,
                "hub地址", param1, "端口", param2, "地址", param3)
        end
    end
end

-- 摄像头事件回调函数
-- 作用：处理USB摄像头连接、断开、收到新帧数据、接收异常等事件
local function camera_cb(app_id, event, param)
    -- 接收到新一帧图像数据，仅打印日志（画面由底层preview机制自动显示到LCD）
    if event == usb.EV_NEW_RX then
        if param == 0 then
            log.info("camera_preview", "新帧数据，buff0长度", frame_buff0:used())
        elseif param == 1 then
            log.info("camera_preview", "新帧数据，buff1长度", frame_buff1:used())
        end
        return
    end

    -- USB摄像头连接事件：枚举摄像头支持的格式和分辨率，启动数据流
    if event == usb.EV_CONNECT then
        log.info("camera_preview", "usb摄像头已连接，app id", app_id)
        usb_app_id = app_id

        -- 创建双缓冲帧数据区，按分辨率自适应大小
        -- 公式：宽 × 高（足够容纳任意质量的MJPEG压缩帧，留有充足余量）
        local buff_size = math.ceil(sensor_w * sensor_h)
        log.info("camera_preview", "创建frame_buff，每个缓冲区大小", buff_size, "字节")
        collectgarbage()
        frame_buff0 = zbuff.create(buff_size)
        frame_buff1 = zbuff.create(buff_size)

        -- 遍历USB摄像头支持的所有格式和分辨率
        local res, format_num = camera.get_usb_config(usb_app_id, camera.CONF_UVC_FORMAT)
        log.info("camera_preview", "总共有", format_num, "种数据流格式")

        local found = false
        local fallback_w, fallback_h = 800, 600  -- 备用分辨率
        local fallback_format_index, fallback_frame_index = nil, nil

        for format_index = 1, format_num, 1 do
            local res, type, frame_num = camera.get_usb_config(usb_app_id, camera.CONF_UVC_FORMAT, format_index)
            log.info("camera_preview", "数据流序号", format_index, "格式", type, "图像数", frame_num)

            for frame_index = 1, frame_num, 1 do
                local res, fps, w, h = camera.get_usb_config(usb_app_id, camera.CONF_UVC_RESOLUTION,
                    format_index, frame_index)
                log.info("camera_preview", "  分辨率", w, "x", h, "fps", fps, "格式", type)

                -- 记录备用分辨率的位置（用于目标分辨率不可用时回退）
                if w == fallback_w and h == fallback_h then
                    fallback_format_index = format_index
                    fallback_frame_index = frame_index
                end

                -- 优先匹配目标分辨率 + MJPEG格式
                if w == sensor_w and h == sensor_h and type == frame_type then
                    log.info("camera_preview", "找到匹配分辨率", w, "x", h, "(MJPEG)")
                    camera.set_usb_config(usb_app_id, camera.CONF_UVC_RESOLUTION, format_index, frame_index)
                    found = true
                    break
                end
            end
            if found then break end
        end

        -- 没有目标分辨率则使用备用分辨率
        if not found and fallback_format_index and fallback_frame_index then
            log.warn("camera_preview", "未找到", sensor_w .. "x" .. sensor_h,
                "，使用备用分辨率", fallback_w .. "x" .. fallback_h)
            camera.set_usb_config(usb_app_id, camera.CONF_UVC_RESOLUTION,
                fallback_format_index, fallback_frame_index)
            sensor_w = fallback_w
            sensor_h = fallback_h
            found = true
        end

        -- 配置双缓冲，启动持续推流（mode=0表示循环模式）
        camera.cache(camera.USB, usb_app_id, frame_buff0, frame_buff1)
        camera.stream(camera.USB, usb_app_id, 0)
        return
    end

    -- USB摄像头断开事件
    if event == usb.EV_DISCONNECT then
        log.info("camera_preview", "usb摄像头 app id", app_id, "已断开")
        usb_app_id = nil
        return
    end

    -- USB摄像头接收数据异常
    if event == usb.EV_RX_ERR then
        log.info("camera_preview", "usb摄像头接收数据异常")
        return
    end
end

-- 摄像头初始化函数
-- 作用：开启摄像头预览功能，注册回调，切换USB为主机模式并上电
local function camera_app_init()
    -- 开启摄像头预览功能（画面将由底层直接送到LCD显示）
    camera.preview(camera.USB, true)
    -- 注册USB回调函数
    usb.on(0, usb_cb)
    -- 注册摄像头回调函数
    camera.on(camera.USB, "usb_raw", camera_cb)
    -- 确保USB外设是掉电状态
    pm.power(pm.USB, false)
    -- USB设置成主机模式
    usb.mode(0, usb.HOST)
    -- USB上电初始化开始工作
    pm.power(pm.USB, true)
    log.info("camera_preview", "初始化完成，等待摄像头连接...")
end

-- 在协程中延迟2秒后初始化，给系统留出准备时间
local function init_camera_in_coroutine()
    sys.wait(2000)
    camera_app_init()
end

-- 创建摄像头初始化任务
sys.taskInit(init_camera_in_coroutine)
