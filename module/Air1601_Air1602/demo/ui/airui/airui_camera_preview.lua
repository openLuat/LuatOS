--[[
@module  airui_camera_preview
@summary exEasyUI 摄像头预览演示页面
@version 1.0
@date    2026.06.22
@author  江访
@usage
本文件演示 excamera 扩展库的 USB 摄像头预览功能。
用户在页面内可通过"开启预览"/"关闭预览"按钮控制摄像头预览，
预览画面由底层 camera.preview 自动输出到 LCD 屏幕。

本文件的对外接口有 2 个：
1、airui_camera_preview.init(params)：页面初始化，创建 UI
2、airui_camera_preview.cleanup()：页面清理，释放资源
]]
excamera = require("excamera") -- 摄像头预览库，供 airui_camera_preview 页面使用


local airui_camera_preview = {}

-- 页面 UI 元素
local main_container = nil
local status_label = nil

-- 摄像头配置参数
local CAM_SENSOR_W = 1024
local CAM_SENSOR_H = 576

-- 预览是否已启动，用于按钮状态切换
local preview_running = false

-- 预览事件回调函数：接收 excamera.preview 的事件通知
-- @usage
-- excamera.preview(preview_event_cb)
local function preview_event_cb(event, param)
    if event == "connected" then
        log.info("airui_camera_preview", "摄像头已连接")
        if status_label then
            status_label:set_text("摄像头已连接，预览中...")
        end
    elseif event == "disconnected" then
        log.info("airui_camera_preview", "摄像头已断开")
        if status_label then
            status_label:set_text("摄像头已断开")
        end
    elseif event == "error" then
        log.warn("airui_camera_preview", "预览异常", param)
        if status_label then
            status_label:set_text("异常: " .. tostring(param))
        end
    end
end

-- 开启预览按钮回调
local function start_preview_click_func()
    if preview_running then
        if status_label then
            status_label:set_text("预览已在运行中")
        end
        return
    end
    -- 12号GPIO配置（AirCAMERA_1032摄像头供电控制引脚），需要拉高使能
    gpio.setup(12, 1, gpio.PULLUP)
    -- 关闭hardfault自动复位，方便调试摄像头异常
    mcu.hardfault(0)
    -- 构造摄像头参数表，work_mode=2 表示预览模式
    local usb_camera_param = {
        id            = camera.USB,
        sensor_width  = CAM_SENSOR_W,
        sensor_height = CAM_SENSOR_H,
        usb_port      = 1,
        save_path     = "/ram/preview.jpg",
        work_mode     = 2,
    }

    -- 第一步：初始化摄像头
    local result = excamera.open(usb_camera_param)
    if not result then
        log.error("airui_camera_preview", "excamera.open 失败")
        if status_label then
            status_label:set_text("摄像头初始化失败，请检查硬件")
        end
        return
    end
    log.info("airui_camera_preview", "excamera.open 成功")

    -- 第二步：启动预览
    result = excamera.preview(preview_event_cb)
    if not result then
        log.error("airui_camera_preview", "excamera.preview 失败")
        if status_label then
            status_label:set_text("预览启动失败")
        end
        excamera.close()
        return
    end

    preview_running = true
    log.info("airui_camera_preview", "预览已启动")
    if status_label then
        status_label:set_text("预览已启动，等待USB摄像头连接...")
    end
end

-- 关闭预览按钮回调
local function stop_preview_click_func()
    if not preview_running then
        if status_label then
            status_label:set_text("预览未启动")
        end
        return
    end

    excamera.close()
    preview_running = false
    log.info("airui_camera_preview", "预览已停止")
    if status_label then
        status_label:set_text("预览已停止")
    end
end

-- 创建页面 UI
function airui_camera_preview.create_ui()
    -- 主容器（不设背景色，camera.preview 视频层可透出）
    main_container = airui.container({
        x = 0,
        y = 0,
        w = 1024,
        h = 600,
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 1024,
        h = 60,
        color = 0x333333,
    })

    airui.label({
        parent = title_bar,
        text = "摄像头预览演示",
        x = 20, y = 14, w = 300, h = 34,
        size = 24, color = 0xcccccc,
    })

    -- 返回按钮
    airui.button({
        parent = title_bar,
        x = 900, y = 12, w = 100, h = 38,
        text = "返回", size = 18,
        on_click = function() go_back() end,
    })

    -- 预览状态标签
    status_label = airui.label({
        parent = main_container,
        text = "点击下方按钮开启摄像头预览",
        x = 0, y = 68, w = 1024, h = 36,
        size = 22, color = 0xcccccc,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 分辨率说明
    airui.label({
        parent = main_container,
        text = string.format("分辨率：%d x %d  MJPEG格式", CAM_SENSOR_W, CAM_SENSOR_H),
        x = 0, y = 104, w = 1024, h = 28,
        size = 18, color = 0x999999,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 预览窗口外边框（半透明深色底+灰色边框，框出预览范围）
    airui.container({
        parent = main_container,
        x = 12, y = 142, w = 1000, h = 392,
        color = 0x222222, radius = 6,
        border_width = 2, border_color = 0x555555,
    })
    -- 预览窗口内部（完全透明，视频层在此透出）
    airui.container({
        parent = main_container,
        x = 14, y = 144, w = 996, h = 388,
        -- 不设 color，透明
    })

    -- 开启预览按钮
    airui.button({
        parent = main_container,
        x = 182, y = 480, w = 300, h = 52,
        text = "开启预览", size = 22,
        style = {
            bg_color = 0x2E7D32,
            pressed_bg_color = 0x1B5E20,
            text_color = 0xFFFFFF,
            radius = 8, border_width = 0,
        },
        on_click = function() start_preview_click_func() end,
    })

    -- 关闭预览按钮
    airui.button({
        parent = main_container,
        x = 542, y = 480, w = 300, h = 52,
        text = "关闭预览", size = 22,
        style = {
            bg_color = 0xC62828,
            pressed_bg_color = 0xB71C1C,
            text_color = 0xFFFFFF,
            radius = 8, border_width = 0,
        },
        on_click = function() stop_preview_click_func() end,
    })

    -- 底部状态栏
    local status_bar = airui.container({
        parent = main_container,
        x = 0, y = 550, w = 1024, h = 50,
        color = 0x222222,
    })
    airui.label({
        parent = status_bar,
        text = "基于 excamera 扩展库  —  预览画面自动输出到 LCD",
        x = 20, y = 14, w = 800, h = 22,
        size = 16, color = 0x888888,
    })
end

-- 页面初始化函数
-- @param params 页面参数（当前未使用）
function airui_camera_preview.init(params)
    airui_camera_preview.create_ui()
end

-- 页面清理函数：释放摄像头资源和 UI 资源
function airui_camera_preview.cleanup()
    -- 如果预览正在运行，停止预览
    if preview_running then
        excamera.close()
        preview_running = false
        log.info("airui_camera_preview", "退出时已停止预览")
    end

    -- 销毁 UI 元素
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    status_label = nil
end

return airui_camera_preview
