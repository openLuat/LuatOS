--[[
@module  airui_camera_preview
@summary AIRUI 摄像头预览演示页面（基于 excamera 扩展库）
@version 1.2
@date    2026.06.23
@author  江访
@usage
本文件演示 excamera 扩展库的 USB 摄像头预览功能。
布局：左侧预览画面，右侧控制面板，标准标题栏与状态栏，与其他演示页面一致。

注意：
- excamera.close() 含 sys.wait，只能在协程中调用
- 按钮 on_click 通过 sys.publish 发消息，由主任务协程处理

对外接口：
1、airui_camera_preview.init(params)：页面初始化，创建 UI
2、airui_camera_preview.cleanup()：页面清理，释放资源
]]

local excamera = require("excamera")

local airui_camera_preview = {}

-- UI 元素
local main_container = nil
local status_label = nil
local toggle_btn = nil
local ctrl_btn = nil
local camera_widget = nil

-- 摄像头配置
local CAM_SENSOR_W = 640
local CAM_SENSOR_H = 480
local LCD_W = 1024
local LCD_H = 600

-- 布局尺寸
local PREVIEW_X = 10
local PREVIEW_Y = 70
local PREVIEW_W = 640
local PREVIEW_H = 470

local PANEL_X = 670
local PANEL_Y = 75
local PANEL_W = 340
local PANEL_H = 460

local BTN_W = PANEL_W
local BTN_H = 48
local BTN_GAP = 14

-- 颜色
local COLOR_BLUE = 0x1565C0
local COLOR_ORANGE = 0xEF6C00
local COLOR_GREEN = 0x2E7D32
local COLOR_RED = 0xC62828
local COLOR_BG = 0xF5F5F5
local COLOR_TITLE_BG = 0x007AFF
local COLOR_TITLE_TEXT = 0xFFFFFF
local COLOR_BORDER = 0xDDDDDD
local COLOR_PANEL_BG = 0x1E1E2E

-- 状态
local STATE_IDLE = 0
local STATE_PREVIEWING = 1
local STATE_WAITING = 2
local app_state = STATE_IDLE

-- 更新状态标签
local function update_status(text)
    if status_label then
        status_label:set_text(text)
    end
    log.info("airui_camera_preview", text)
end

-- 同步切换按钮
local function sync_toggle_btn()
    if not toggle_btn then
        return
    end
    if app_state == STATE_PREVIEWING or app_state == STATE_WAITING then
        toggle_btn:set_text("停止预览")
        toggle_btn:set_style({bg_color = COLOR_ORANGE, pressed_bg_color = COLOR_ORANGE, text_color = 0xFFFFFF})
    else
        toggle_btn:set_text("开始预览")
        toggle_btn:set_style({bg_color = COLOR_BLUE, pressed_bg_color = COLOR_BLUE, text_color = 0xFFFFFF})
    end
end

-- 同步控制按钮
local function sync_ctrl_btn()
    if not ctrl_btn then
        return
    end
    if camera_widget and not camera_widget:is_destroyed() then
        ctrl_btn:set_text("销毁组件")
        ctrl_btn:set_style({bg_color = COLOR_RED, pressed_bg_color = COLOR_RED, text_color = 0xFFFFFF})
    else
        ctrl_btn:set_text("创建组件")
        ctrl_btn:set_style({bg_color = COLOR_GREEN, pressed_bg_color = COLOR_GREEN, text_color = 0xFFFFFF})
    end
end

-- 创建组件
local function create_widget()
    if camera_widget and not camera_widget:is_destroyed() then
        return true
    end
    camera_widget = airui.camera({
        parent = main_container,
        x = PREVIEW_X, y = PREVIEW_Y,
        w = PREVIEW_W, h = PREVIEW_H,
        auto_start = false,
    })
    if not camera_widget then
        update_status("camera组件创建失败")
        return false
    end
    update_status("组件已创建")
    return true
end

-- 销毁组件
local function destroy_widget()
    if camera_widget and not camera_widget:is_destroyed() then
        camera_widget:destroy()
    end
    camera_widget = nil
    update_status("组件已销毁")
end

-- 预览事件回调
local function preview_event_cb(event, param)
    if event == "connected" then
        local app_id = param
        log.info("airui_camera_preview", "USB摄像头已连接, app_id:", app_id)
        if camera_widget and not camera_widget:is_destroyed() then
            camera_widget:register()
            camera_widget:start()
        end
        app_state = STATE_PREVIEWING
        update_status("摄像头已连接，预览中...")
    elseif event == "disconnected" then
        app_state = STATE_IDLE
        update_status("摄像头已断开")
    elseif event == "error" then
        update_status("异常: " .. tostring(param))
    end
end

-- 开始预览
local function start_preview()
    if app_state == STATE_PREVIEWING or app_state == STATE_WAITING then
        return
    end
    -- 12号GPIO拉高（AirCAMERA_1032摄像头供电控制引脚）
    gpio.setup(12, 1, gpio.PULLUP)

    local usb_param = {
        id = camera.USB,
        sensor_width = CAM_SENSOR_W,
        sensor_height = CAM_SENSOR_H,
        usb_port = 1,
        work_mode = 2,
        save_path = "/ram/preview.jpg",
    }
    local ok = excamera.open(usb_param)
    if not ok then
        update_status("摄像头初始化失败")
        return
    end
    ok = excamera.preview(preview_event_cb)
    if not ok then
        update_status("预览启动失败")
        excamera.close()
        return
    end
    app_state = STATE_WAITING
    sync_toggle_btn()
    update_status("等待USB摄像头连接...")
end

-- 停止预览
local function stop_preview()
    if app_state ~= STATE_PREVIEWING and app_state ~= STATE_WAITING then
        return
    end
    if camera_widget and not camera_widget:is_destroyed() then
        camera_widget:stop()
    end
    excamera.close()
    app_state = STATE_IDLE
    sync_toggle_btn()
    update_status("预览已停止")
end

-- 创建 UI
function airui_camera_preview.create_ui()
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
        text = "摄像头预览演示",
        x = 20, y = 15, w = 300, h = 30,
        font_size = 20, color = COLOR_TITLE_TEXT,
    })

    -- 返回按钮
    airui.button({
        parent = title_bar,
        x = 900, y = 15, w = 100, h = 35,
        text = "返回", font_size = 16,
        on_click = function()
            sys.publish("CAMERA_PAGE_CMD", "go_back")
        end,
    })

    -- 预览画面边框
    airui.container({
        parent = main_container,
        x = PREVIEW_X - 1, y = PREVIEW_Y - 1,
        w = PREVIEW_W + 2, h = PREVIEW_H + 2,
        color = COLOR_BORDER, radius = 4,
    })

    -- AIRUI camera 预览组件
    camera_widget = airui.camera({
        parent = main_container,
        x = PREVIEW_X, y = PREVIEW_Y,
        w = PREVIEW_W, h = PREVIEW_H,
        auto_start = false,
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
        text = "控制面板", font_size = 18,
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

    -- 按钮区域
    local by = PANEL_Y + 150

    toggle_btn = airui.button({
        parent = main_container,
        x = PANEL_X, y = by, w = BTN_W, h = BTN_H,
        text = "开始预览", font_size = 20,
        style = {
            bg_color = COLOR_BLUE, pressed_bg_color = COLOR_BLUE,
            text_color = 0xFFFFFF, radius = 8, border_width = 0,
        },
        on_click = function()
            sys.publish("CAMERA_PAGE_CMD", "toggle")
        end,
    })
    by = by + BTN_H + BTN_GAP

    ctrl_btn = airui.button({
        parent = main_container,
        x = PANEL_X, y = by, w = BTN_W, h = BTN_H,
        text = "创建组件", font_size = 20,
        style = {
            bg_color = COLOR_GREEN, pressed_bg_color = COLOR_GREEN,
            text_color = 0xFFFFFF, radius = 8, border_width = 0,
        },
        on_click = function()
            sys.publish("CAMERA_PAGE_CMD", "ctrl")
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
        text = "基于 excamera 扩展库 - AirCAMERA_1032 USB摄像头预览",
        x = 20, y = 14, w = 800, h = 22,
        font_size = 14, color = 0x666666,
    })

    -- 自动创建组件
    create_widget()
    sync_ctrl_btn()
    sync_toggle_btn()
    update_status("请点击开始预览启动摄像头")
end

-- 页面初始化
function airui_camera_preview.init(params)
    airui_camera_preview.create_ui()
    sys.taskInit(function()
        while true do
            local _, cmd = sys.waitUntil("CAMERA_PAGE_CMD")
            if cmd == "toggle" then
                if app_state == STATE_PREVIEWING or app_state == STATE_WAITING then
                    stop_preview()
                else
                    start_preview()
                end
                sync_toggle_btn()
                sync_ctrl_btn()
            elseif cmd == "ctrl" then
                if camera_widget and not camera_widget:is_destroyed() then
                    if app_state == STATE_PREVIEWING or app_state == STATE_WAITING then
                        stop_preview()
                    end
                    destroy_widget()
                else
                    create_widget()
                end
                sync_toggle_btn()
                sync_ctrl_btn()
            elseif cmd == "go_back" then
                go_back()
                return
            end
        end
    end)
end

-- 页面清理
function airui_camera_preview.cleanup()
    if app_state == STATE_PREVIEWING or app_state == STATE_WAITING then
        stop_preview()
    end
    if camera_widget and not camera_widget:is_destroyed() then
        camera_widget:destroy()
    end
    camera_widget = nil
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    status_label = nil
    toggle_btn = nil
    ctrl_btn = nil
    app_state = STATE_IDLE
end

return airui_camera_preview
