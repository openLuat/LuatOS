--[[
@module  airui_camsnap
@summary AIRUI 摄像头拍照演示页面（基于底层 camera API，与预览互不冲突）
@version 1.0
@date    2026.07.01
@author  江访
@usage
本文件演示 USB 摄像头单次拍照 + LCD 显示功能。
与 airui_camera_preview (excamera) 完全独立，使用底层 camera API，互不冲突。
流程：点击拍照 → 启动 stream → 接收一帧 MJPEG → 停止 stream → 保存文件 → 显示到 LCD

注意：
- 拍照通过 sys.publish 发消息，由主任务协程处理
- 拍照流程结束后自动停止 stream，不会持续占用带宽

对外接口：
1、airui_camsnap.init(params)：页面初始化，创建 UI
2、airui_camsnap.cleanup()：页面清理，释放资源
]]

local airui_camsnap = {}

-- UI 元素
local main_container = nil
local status_label = nil
local photo_btn = nil
local photo_image = nil

-- 摄像头配置选择
-- CAM_CONFIG = 1: 640x480 摄像头 (AirCAMERA_1032 默认参数)
-- CAM_CONFIG = 2: 960x480 @ 20fps 摄像头 (2:1 宽屏)
-- CAM_CONFIG = 3: 800x480 @ 20fps 摄像头
-- CAM_CONFIG = 4: 480x320 @ 20fps 摄像头 (最省内存，解码仅需 307KB)
local CAM_CONFIG = 4

-- 摄像头传感器分辨率
local CAM_SENSOR_W, CAM_SENSOR_H
-- 照片显示区域尺寸
local PHOTO_W, PHOTO_H
-- 右侧面板起始X和宽度
local PANEL_X, PANEL_W

if CAM_CONFIG == 4 then
    -- 480x320 低分辨率摄像头 (w*h*2 = 307KB，解码内存安全)
    CAM_SENSOR_W = 480
    CAM_SENSOR_H = 320
    PHOTO_W = 480
    PHOTO_H = 320
    PANEL_X = 510
    PANEL_W = 500
elseif CAM_CONFIG == 3 then
    -- 800x480 宽屏摄像头 (w*h*2 = 750KB)
    CAM_SENSOR_W = 800
    CAM_SENSOR_H = 480
    PHOTO_W = 640
    PHOTO_H = 384
    PANEL_X = 660
    PANEL_W = 350
elseif CAM_CONFIG == 2 then
    -- 960x480 宽屏摄像头 (w*h*2 = 900KB)
    CAM_SENSOR_W = 960
    CAM_SENSOR_H = 480
    PHOTO_W = 640
    PHOTO_H = 320
    PANEL_X = 660
    PANEL_W = 350
else
    -- 默认 640x480 摄像头 (AirCAMERA_1032)
    CAM_SENSOR_W = 640
    CAM_SENSOR_H = 480
    PHOTO_W = 640
    PHOTO_H = 470
    PANEL_X = 670
    PANEL_W = 340
end

local LCD_W = 1024
local LCD_H = 600

-- 布局尺寸
local PHOTO_X = 10
local PHOTO_Y = 70
local PANEL_Y = 75
local PANEL_H = 460
local BTN_W = PANEL_W
local BTN_H = 48
local BTN_GAP = 14

-- 颜色
local COLOR_BG = 0xF5F5F5
local COLOR_TITLE_BG = 0x007AFF
local COLOR_TITLE_TEXT = 0xFFFFFF
local COLOR_BORDER = 0xDDDDDD
local COLOR_PANEL_BG = 0x1E1E2E
local COLOR_BLUE = 0x1565C0
local COLOR_GREEN = 0x2E7D32
local COLOR_RED = 0xC62828
local COLOR_ORANGE = 0xEF6C00

-- 摄像头相关变量
local usb_app_id = nil        -- USB 摄像头应用 ID
local frame_buff = nil        -- 帧数据缓冲区
local capturing = false       -- 是否正在拍照
local camera_ready = false    -- 摄像头是否就绪
local save_path = "/ram/snapshot.jpg"

-- 更新状态标签
local function update_status(text)
    if status_label then
        status_label:set_text(text)
    end
    log.info("airui_camsnap", text)
end

-- 同步拍照按钮状态
local function sync_photo_btn()
    if not photo_btn then
        return
    end
    if capturing then
        photo_btn:set_text("拍照中...")
        photo_btn:set_style({bg_color = COLOR_ORANGE, pressed_bg_color = COLOR_ORANGE, text_color = 0xFFFFFF})
    elseif not camera_ready then
        photo_btn:set_text("等待摄像头")
        photo_btn:set_style({bg_color = COLOR_RED, pressed_bg_color = COLOR_RED, text_color = 0xFFFFFF})
    else
        photo_btn:set_text("拍照")
        photo_btn:set_style({bg_color = COLOR_BLUE, pressed_bg_color = COLOR_BLUE, text_color = 0xFFFFFF})
    end
end

-- 保存帧数据到文件并在 LCD 上显示
local function save_and_display(data_len)
    -- 保存照片到文件
    local file = io.open(save_path, "wb")
    if not file then
        update_status("文件打开失败")
        return
    end
    local block_data = frame_buff:toStr(0, data_len)
    file:write(block_data)
    file:close()
    log.info("airui_camsnap", "照片已保存到", save_path, "大小", data_len)

    -- 销毁旧的 photo_image，重新创建以确保刷新显示
    if photo_image and not photo_image:is_destroyed() then
        photo_image:destroy()
    end

    -- 直接原图显示，不做缩放
    -- 照片小于预览区时居中显示，以实际像素点对点呈现
    local img_w = CAM_SENSOR_W
    local img_h = CAM_SENSOR_H
    if img_w > PHOTO_W then img_w = PHOTO_W end
    if img_h > PHOTO_H then img_h = PHOTO_H end
    local img_x = PHOTO_X + math.floor((PHOTO_W - img_w) / 2)
    local img_y = PHOTO_Y + math.floor((PHOTO_H - img_h) / 2)

    photo_image = airui.image({
        parent = main_container,
        x = img_x, y = img_y,
        w = img_w, h = img_h,
        src = save_path,
    })

    update_status(string.format("拍照完成 (%d bytes)", data_len))
end

-- 摄像头事件回调（直接使用底层 camera API，不依赖 excamera）
local function camera_cb(app_id, event, param)
    -- 收到新帧
    if event == usb.EV_NEW_RX then
        if capturing then
            capturing = false
            local data_len = frame_buff:used()
            log.info("airui_camsnap", "收到帧数据, 长度", data_len)

            -- 立即停止 stream
            camera.stop(camera.USB)

            -- 发布事件由主任务处理保存/显示
            sys.publish("SNAPSHOT_DONE", data_len)
        end
        return
    end

    -- USB 摄像头连接
    if event == usb.EV_CONNECT then
        usb_app_id = app_id
        log.info("airui_camsnap", "USB摄像头已连接, app_id", app_id)

        -- 创建帧缓冲区
        local buff_size = math.ceil(CAM_SENSOR_W * CAM_SENSOR_H)
        if not frame_buff then
            frame_buff = zbuff.create(buff_size)
            log.info("airui_camsnap", "创建帧缓冲区, 大小", buff_size)
        end

        -- 枚举分辨率，匹配 MJPEG
        local res, format_num = camera.get_usb_config(app_id, camera.CONF_UVC_FORMAT)
        log.info("airui_camsnap", "格式数量", format_num)

        local found = false
        for fmt = 1, format_num do
            res, ftype, frame_num = camera.get_usb_config(app_id, camera.CONF_UVC_FORMAT, fmt)
            for frm = 1, frame_num do
                res, fps, w, h = camera.get_usb_config(app_id, camera.CONF_UVC_RESOLUTION, fmt, frm)
                if w == CAM_SENSOR_W and h == CAM_SENSOR_H and ftype == camera.FORMAT_MJPG then
                    log.info("airui_camsnap", "匹配", w, "x", h, "MJPEG")
                    camera.set_usb_config(app_id, camera.CONF_UVC_RESOLUTION, fmt, frm)
                    found = true
                    break
                end
            end
            if found then break end
        end

        if not found then
            log.warn("airui_camsnap", "未匹配到", CAM_SENSOR_W, "x", CAM_SENSOR_H, "MJPEG，使用默认")
        end

        -- 配置单缓冲（拍照只用一路缓冲）
        camera.cache(camera.USB, app_id, frame_buff, frame_buff)

        camera_ready = true
        update_status("摄像头就绪，点击拍照")
        sync_photo_btn()
        return
    end

    -- USB 摄像头断开
    if event == usb.EV_DISCONNECT then
        log.info("airui_camsnap", "USB摄像头已断开")
        usb_app_id = nil
        camera_ready = false
        capturing = false
        update_status("摄像头已断开")
        sync_photo_btn()
        return
    end

    -- 接收异常
    if event == usb.EV_RX_ERR then
        log.warn("airui_camsnap", "接收数据异常")
        if capturing then
            capturing = false
            camera.stop(camera.USB)
            update_status("拍照异常")
            sync_photo_btn()
        end
        return
    end
end

-- 摄像头初始化（独立流程，不依赖 excamera）
local function camera_init()
    -- 12号GPIO拉高（AirCAMERA_1032摄像头供电控制引脚）
    gpio.setup(12, 1, gpio.PULLUP)

    -- 注册摄像头事件回调
    camera.on(camera.USB, "usb_raw", camera_cb)

    -- USB掉电，重置USB栈
    pm.power(pm.USB, false)
    sys.wait(500)

    -- 设置为主机模式
    usb.mode(0, usb.HOST)

    -- USB上电
    pm.power(pm.USB, true)

    update_status("等待USB摄像头连接...")
end

-- 触发拍照
local function do_capture()
    if not camera_ready then
        update_status("摄像头未就绪")
        return
    end
    if capturing then
        return
    end

    capturing = true
    sync_photo_btn()
    update_status("拍照中...")

    -- 启动 stream，收到一帧后 camera_cb 会停止 stream
    camera.stream(camera.USB, usb_app_id, 0)

    -- 等待拍照完成（超时5秒）
    local _, data_len = sys.waitUntil("SNAPSHOT_DONE", 5000)
    if data_len then
        save_and_display(data_len)
    else
        update_status("拍照超时")
        capturing = false
        camera.stop(camera.USB)
    end
end

-- 创建 UI
function airui_camsnap.create_ui()
    main_container = airui.container({
        x = 0, y = 0, w = LCD_W, h = LCD_H,
        color = COLOR_BG,
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0, y = 0, w = LCD_W, h = 60,
        color = COLOR_TITLE_BG,
    })
    airui.label({
        parent = title_bar,
        text = "摄像头拍照演示",
        x = 20, y = 15, w = 300, h = 30,
        font_size = 20, color = COLOR_TITLE_TEXT,
    })

    -- 返回按钮
    airui.button({
        parent = title_bar,
        x = 900, y = 15, w = 100, h = 35,
        text = "返回", font_size = 16,
        on_click = function()
            sys.publish("SNAPSHOT_PAGE_CMD", "go_back")
        end,
    })

    -- 照片显示区域边框
    airui.container({
        parent = main_container,
        x = PHOTO_X - 1, y = PHOTO_Y - 1,
        w = PHOTO_W + 2, h = PHOTO_H + 2,
        color = COLOR_BORDER, radius = 4,
    })

    -- 照片显示组件（初始显示空白）
    photo_image = airui.image({
        parent = main_container,
        x = PHOTO_X, y = PHOTO_Y,
        w = PHOTO_W, h = PHOTO_H,
        src = "",
    })

    -- 右侧控制面板
    airui.container({
        parent = main_container,
        x = PANEL_X, y = PANEL_Y,
        w = PANEL_W, h = PANEL_H,
        color = COLOR_PANEL_BG, radius = 8,
    })

    -- 面板标题
    airui.label({
        parent = main_container,
        x = PANEL_X + 12, y = PANEL_Y + 12,
        w = PANEL_W - 24, h = 28,
        text = "拍照控制", font_size = 18,
        color = 0xCDD6F4,
    })

    -- 面板分隔线
    airui.container({
        parent = main_container,
        x = PANEL_X + 8, y = PANEL_Y + 48,
        w = PANEL_W - 16, h = 1,
        color = 0x45475A,
    })

    -- 状态标签
    status_label = airui.label({
        parent = main_container,
        x = PANEL_X + 12, y = PANEL_Y + 62,
        w = PANEL_W - 24, h = 44,
        text = "初始化中...", font_size = 15,
        color = 0x9399B2,
    })

    -- 分辨率信息
    airui.label({
        parent = main_container,
        x = PANEL_X + 12, y = PANEL_Y + 106,
        w = PANEL_W - 24, h = 22,
        text = string.format("分辨率 %dx%d  MJPEG", CAM_SENSOR_W, CAM_SENSOR_H),
        font_size = 13, color = 0x9399B2,
    })

    -- 拍照按钮
    local by = PANEL_Y + 150
    photo_btn = airui.button({
        parent = main_container,
        x = PANEL_X, y = by, w = BTN_W, h = BTN_H,
        text = "等待摄像头", font_size = 20,
        style = {
            bg_color = COLOR_RED, pressed_bg_color = COLOR_RED,
            text_color = 0xFFFFFF, radius = 8, border_width = 0,
        },
        on_click = function()
            sys.publish("SNAPSHOT_PAGE_CMD", "capture")
        end,
    })

    -- 底部状态栏
    local status_bar = airui.container({
        parent = main_container,
        x = 0, y = 550, w = LCD_W, h = 50,
        color = 0xE0E0E0,
    })
    airui.label({
        parent = status_bar,
        text = "基于底层 camera API - 独立拍照，不与预览冲突",
        x = 20, y = 14, w = 800, h = 22,
        font_size = 14, color = 0x666666,
    })

    sync_photo_btn()
    update_status("初始化USB摄像头...")
end

-- 页面初始化
function airui_camsnap.init(params)
    airui_camsnap.create_ui()

    -- 在协程中初始化摄像头和事件循环
    sys.taskInit(function()
        -- 硬件初始化
        camera_init()

        -- 命令循环
        while true do
            local _, cmd = sys.waitUntil("SNAPSHOT_PAGE_CMD")
            if cmd == "capture" then
                do_capture()
                sync_photo_btn()
            elseif cmd == "go_back" then
                -- 让 cleanup() 统一清理，直接返回上级页面
                go_back()
                return
            end
        end
    end)
end

-- 页面清理
function airui_camsnap.cleanup()
    -- 停止和关闭摄像头
    if usb_app_id then
        camera.stop(camera.USB)
        camera.close(usb_app_id)
        usb_app_id = nil
    end
    camera_ready = false
    capturing = false
    -- 取消注册回调
    camera.on(camera.USB, "usb_raw", nil)

    -- 销毁 UI
    if photo_image and not photo_image:is_destroyed() then
        photo_image:destroy()
    end
    photo_image = nil
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    status_label = nil
    photo_btn = nil
    if frame_buff then
        frame_buff:free()
        frame_buff = nil
    end
end

return airui_camsnap
