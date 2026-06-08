--[[
@module  photo_uart_post
@summary AirUVC_1000 USB摄像头单次拍照+LCD显示+UART上传应用模块
@version 1.0
@date    2026.06.08
@author  江访
@usage
本demo主要使用Air1601 + AirUVC_1000 USB摄像头完成以下功能：
1、初始化USB主机模式，连接USB摄像头；
2、初始化UART3（2000000波特率，8N1）用于上传照片到电脑；
3、遍历USB摄像头支持的格式和分辨率，只选择MJPEG格式 + 1024x576；
4、接收一帧图像数据后停止流，将照片保存到/ram/photo.jpg；
5、通过UART3将照片二进制数据发送到电脑；
6、调用lcd.showImage将照片显示到LCD屏幕；
7、拍照完成后关闭摄像头流，不再循环拍照。

电脑端可使用 uart_receiver.py 接收照片数据。

本文件没有对外接口，直接在main.lua中require "photo_uart_post"就可以加载运行。
]]

-- 12号GPIO配置（AirUVC_1000摄像头供电控制引脚），需要拉高使能
gpio.setup(12, 1, gpio.PULLUP)

-- UART配置（用于上传照片到电脑）
local uartid = 3                              -- 使用UART3
local uart_baud = 2000000                     -- 波特率2Mbps
local send_buff = zbuff.create(800 * 600)     -- 发送缓冲区（足够容纳一张1024x576 JPEG照片）

-- 初始化UART
local uart_result = uart.setup(uartid, uart_baud, 8, 1)
log.info("photo_uart_post", "UART初始化结果", uart_result)

-- 摄像头参数
local frame_type = camera.FORMAT_MJPG         -- 使用MJPEG格式
local sensor_w = 1024                         -- 目标分辨率宽度
local sensor_h = 576                          -- 目标分辨率高度
local usb_app_id = nil                        -- USB摄像头应用ID
local captured = false                        -- 是否已拍照标志位（用于保证只拍一张）
local save_path = "/ram/photo.jpg"            -- 照片保存路径

-- 双缓冲帧数据区，按分辨率自适应大小
-- 公式：宽 × 高（足够容纳任意质量的MJPEG压缩帧，留有充足余量）
local buff_size = math.ceil(sensor_w * sensor_h)
log.info("photo_uart_post", "按分辨率自适应缓冲区大小", buff_size, "字节")
local frame_buff0 = zbuff.create(buff_size)
local frame_buff1 = zbuff.create(buff_size)

-- USB事件回调函数
-- 作用：监听USB摄像头的连接和断开事件
local function usb_cb(usb_id, class, app_id, event, param1, param2, param3)
    if event == usb.EV_CONNECT then
        if class == usb.CAMERA then
            log.info("photo_uart_post", "usb摄像头已连接，app id", app_id,
                "hub地址", param1, "端口", param2, "地址", param3)
        end
    end
    if event == usb.EV_DISCONNECT then
        if class == usb.CAMERA then
            log.info("photo_uart_post", "usb摄像头已断开，app id", app_id,
                "hub地址", param1, "端口", param2, "地址", param3)
            usb_app_id = nil
            captured = false
        end
    end
end

-- 摄像头事件回调函数
-- 作用：处理USB摄像头连接、断开、收到新帧、接收异常等事件
local function camera_cb(app_id, event, param)
    -- 接收到一帧图像数据
    if event == usb.EV_NEW_RX then
        -- 只拍一次，避免重复处理
        if not captured then
            -- 根据param判断使用哪个缓冲区
            local current_buff = frame_buff0
            local buff_name = "buffer0"
            if param == 1 then
                current_buff = frame_buff1
                buff_name = "buffer1"
            end

            local data_len = current_buff:used()
            log.info("photo_uart_post", "接收到图像数据，位于", buff_name, "长度", data_len)
            captured = true

            -- 保存照片到文件
            local file = io.open(save_path, "w")
            if file then
                local block_data = current_buff:toStr(0, data_len)
                file:write(block_data)
                file:close()
                log.info("photo_uart_post", "照片已保存到", save_path, "大小", data_len)

                -- 通过UART上传照片到电脑
                log.info("photo_uart_post", "开始通过UART上传照片...")
                send_buff:del()
                send_buff:copy(0, current_buff)
                uart.tx(uartid, send_buff)
                log.info("photo_uart_post", "照片已通过UART发送，大小", data_len)

                -- 在LCD上显示照片
                lcd.clear(0x0000)
                local result = lcd.showImage(0, 0, save_path)
                log.info("photo_uart_post", "lcd.showImage返回值", result)
                lcd.flush()
                log.info("photo_uart_post", "照片显示完成")
            else
                log.error("photo_uart_post", "无法打开文件", save_path)
            end

            -- 关闭摄像头流，释放资源
            if usb_app_id then
                log.info("photo_uart_post", "关闭摄像头流")
                camera.stop(camera.USB)
            end
        end
        return
    end

    -- USB摄像头连接事件：枚举摄像头支持的格式和分辨率，启动数据流
    if event == usb.EV_CONNECT then
        log.info("photo_uart_post", "usb摄像头已连接，app id", app_id)
        usb_app_id = app_id

        -- 枚举USB摄像头支持的所有格式和分辨率
        local res, format_num = camera.get_usb_config(usb_app_id, camera.CONF_UVC_FORMAT)
        log.info("photo_uart_post", "总共有", format_num, "种数据流格式")

        local found = false
        for format_index = 1, format_num, 1 do
            local res, type, frame_num = camera.get_usb_config(usb_app_id, camera.CONF_UVC_FORMAT, format_index)
            log.info("photo_uart_post", "数据流序号", format_index, "格式", type, "图像数", frame_num)

            -- 只处理MJPEG格式
            if type == camera.FORMAT_MJPG then
                for frame_index = 1, frame_num, 1 do
                    local res, fps, w, h = camera.get_usb_config(usb_app_id, camera.CONF_UVC_RESOLUTION,
                        format_index, frame_index)
                    log.info("photo_uart_post", "  分辨率", w, "x", h, "fps", fps)

                    if w == sensor_w and h == sensor_h then
                        log.info("photo_uart_post", "找到匹配分辨率", w, "x", h, "(MJPEG)")
                        camera.set_usb_config(usb_app_id, camera.CONF_UVC_RESOLUTION, format_index, frame_index)
                        found = true
                        break
                    end
                end
                if found then break end
            else
                log.info("photo_uart_post", "跳过非MJPEG格式")
            end
        end

        if not found then
            log.warn("photo_uart_post", "未找到匹配分辨率，使用默认设置")
            camera.set_usb_config(usb_app_id, camera.CONF_UVC_RESOLUTION, frame_type, sensor_w, sensor_h)
        end

        -- 配置双缓冲并启动数据流
        camera.cache(camera.USB, usb_app_id, frame_buff0, frame_buff1)
        camera.stream(camera.USB, usb_app_id)
        return
    end

    -- USB摄像头断开事件
    if event == usb.EV_DISCONNECT then
        log.info("photo_uart_post", "usb摄像头 app id", app_id, "已断开")
        usb_app_id = nil
        captured = false
        return
    end

    -- USB摄像头接收数据异常
    if event == usb.EV_RX_ERR then
        log.info("photo_uart_post", "usb摄像头接收数据异常")
        return
    end

    -- USB摄像头接收数据异常并已停止工作
    if event == usb.EV_ERR_STOP then
        log.info("photo_uart_post", "usb摄像头接收数据异常，已停止工作")
        usb.reset_device(0, app_id)
        usb_app_id = nil
        return
    end
end

-- 在协程中延迟初始化（给硬件留出稳定时间）
sys.taskInit(function()
    sys.wait(100)
    log.info("photo_uart_post", "初始化USB摄像头...")

    -- 注册USB回调和摄像头回调
    usb.on(0, usb_cb)
    camera.on(camera.USB, "usb_raw", camera_cb)

    -- 切换USB为主机模式并上电
    pm.power(pm.USB, false)
    usb.mode(0, usb.HOST)
    pm.power(pm.USB, true)

    log.info("photo_uart_post", "USB摄像头初始化完成，等待摄像头连接...")

    -- 在LCD上显示提示信息
    lcd.clear(0x0000)
    lcd.setFont(lcd.font_opposansm16)
    lcd.setColor(0xFFFF, 0x0000)
    lcd.drawStr(20, 100, "AirUVC_1000 photo + UART")
    lcd.drawStr(20, 140, "Waiting camera...")
    lcd.flush()

    -- 保持任务运行
    while true do
        sys.wait(1000)
    end
end)
