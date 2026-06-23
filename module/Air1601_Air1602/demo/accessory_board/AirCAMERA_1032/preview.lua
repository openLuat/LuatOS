--[[
@module  preview
@summary AirCAMERA_1032 USB摄像头 + excamera扩展库 + AIRUI camera组件预览
@version 1.2
@date    2026.06.23
@author  江访
@usage
本demo使用excamera扩展库 + AIRUI camera组件实现USB摄像头实时画面预览。
布局：左侧全屏预览画面，右侧操作控制面板。

注意：
- 预览组件只允许同时存在一个
- 所有按钮操作通过 sys.publish/CAMERA_CMD 转主任务协程执行
  （excamera.close 含 sys.wait，只能在协程中调用）
]]

local excamera = require "excamera"

-- 全局变量
local camera_widget = nil     -- AIRUI camera组件
local status_label = nil      -- 状态标签
local toggle_btn = nil        -- 开始/停止切换按钮
local ctrl_btn = nil          -- 销毁/创建切换按钮

-- 目标分辨率
local SENSOR_W = 640
local SENSOR_H = 480
local LCD_W = 1024
local LCD_H = 600

-- 布局尺寸
local PREVIEW_X = 0
local PREVIEW_Y = 0
local PREVIEW_W = 680          -- 左侧预览区域宽度
local PREVIEW_H = 600

local PANEL_X = 690            -- 右侧面板起始X
local PANEL_W = LCD_W - PANEL_X - 16  -- 右侧面板宽度（~318）
local PANEL_H = 560
local PANEL_Y = 20

local BTN_W = PANEL_W
local BTN_H = 48
local BTN_GAP = 14

-- 12号GPIO拉高（AirCAMERA_1032摄像头供电控制引脚）
gpio.setup(12, 1, gpio.PULLUP)
-- 关闭hardfault自动复位，方便调试摄像头异常
mcu.hardfault(0)

-- 状态枚举
local STATE_IDLE = 0
local STATE_CREATED = 1
local STATE_PREVIEWING = 2
local STATE_WAITING = 3
local app_state = STATE_IDLE

-- 颜色
local COLOR_BLUE = 0x1565C0
local COLOR_ORANGE = 0xEF6C00
local COLOR_GREEN = 0x2E7D32
local COLOR_RED = 0xC62828
local COLOR_PANEL_BG = 0x1E1E2E
local COLOR_TEXT = 0xCDD6F4
local COLOR_TEXT_DIM = 0x9399B2
local COLOR_BORDER = 0x45475A

-- 更新状态标签
local function update_status(text)
    if status_label then
        status_label:set_text(text)
    end
    log.info("preview", text)
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

-- 创建AIRUI camera组件
local function create_widget()
    if camera_widget and not camera_widget:is_destroyed() then
        return true
    end
    camera_widget = airui.camera({
        parent = airui.screen,
        x = PREVIEW_X, y = PREVIEW_Y,
        w = PREVIEW_W, h = PREVIEW_H,
        auto_start = false,
    })
    if not camera_widget then
        update_status("camera组件创建失败")
        return false
    end
    app_state = STATE_CREATED
    update_status("组件已创建")
    return true
end

-- 销毁组件
local function destroy_widget()
    if camera_widget and not camera_widget:is_destroyed() then
        camera_widget:destroy()
    end
    camera_widget = nil
    app_state = STATE_IDLE
    update_status("组件已销毁")
end

-- 注册并启动AIRUI camera控件
local function register_camera_widget()
    if not camera_widget or camera_widget:is_destroyed() then
        return false
    end
    camera_widget:register()
    camera_widget:start()
    app_state = STATE_PREVIEWING
    sync_toggle_btn()
    update_status("预览运行中 " .. SENSOR_W .. "x" .. SENSOR_H)
    return true
end

-- excamera预览回调：收到摄像头连接事件后注册AIRUI控件
local function preview_callback(event, ...)
    if event == "connected" then
        local app_id = select(1, ...)
        log.info("preview", "USB摄像头已连接, app_id:", app_id)
        register_camera_widget()
    elseif event == "disconnected" then
        app_state = STATE_CREATED
        sync_toggle_btn()
        update_status("摄像头已断开")
    elseif event == "error" then
        local msg = select(1, ...)
        log.warn("preview", "摄像头错误:", msg)
    end
end

-- 开始预览
local function start_preview()
    if not camera_widget or camera_widget:is_destroyed() then
        log.warn("preview", "请先创建组件")
        return
    end
    if app_state == STATE_PREVIEWING or app_state == STATE_WAITING then
        return
    end

    local usb_param = {
        id = camera.USB,
        sensor_width = SENSOR_W,
        sensor_height = SENSOR_H,
        usb_port = 1,
        work_mode = 2,
        save_path = "/ram/photo.jpg"
    }

    local ok = excamera.open(usb_param)
    if not ok then
        update_status("摄像头打开失败")
        return
    end
    ok = excamera.preview(preview_callback)
    if ok then
        app_state = STATE_WAITING
        sync_toggle_btn()
        update_status("等待摄像头连接...")
    else
        update_status("预览启动失败")
        excamera.close()
    end
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
    app_state = STATE_CREATED
    sync_toggle_btn()
    update_status("预览已停止")
end

-- 辅：创建按钮
local function new_btn(text, x, y, w, h, color, cb)
    return airui.button({
        parent = airui.screen,
        x = x, y = y, w = w, h = h,
        text = text, font_size = 20,
        style = {
            bg_color = color, pressed_bg_color = color,
            text_color = 0xFFFFFF, radius = 8, border_width = 0,
        },
        on_click = cb,
    })
end

-- 按钮回调：发消息转协程
local function on_toggle()
    sys.publish("CAMERA_CMD", "toggle")
end
local function on_ctrl()
    sys.publish("CAMERA_CMD", "ctrl")
end

-- 主任务
sys.taskInit(function()
    -- 左侧：预览画面分隔线（竖线装饰）
    airui.container({
        parent = airui.screen,
        x = PREVIEW_W, y = 0, w = 2, h = LCD_H,
        color = COLOR_BORDER,
    })

    -- 右侧：控制面板背景
    airui.container({
        parent = airui.screen,
        x = PANEL_X, y = PANEL_Y, w = PANEL_W, h = PANEL_H,
        color = COLOR_PANEL_BG, radius = 12,
    })

    -- 面板标题
    airui.label({
        parent = airui.screen,
        x = PANEL_X, y = PANEL_Y + 16, w = PANEL_W, h = 32,
        text = "摄像头控制", font_size = 22,
        color = COLOR_TEXT,
    })

    -- 分隔线
    airui.label({
        parent = airui.screen,
        x = PANEL_X + 8, y = PANEL_Y + 56, w = PANEL_W - 16, h = 1,
        text = "", font_size = 1,
        style = {bg_color = COLOR_BORDER, border_width = 0},
    })

    -- 状态标签
    status_label = airui.label({
        parent = airui.screen,
        x = PANEL_X + 8, y = PANEL_Y + 72, w = PANEL_W - 16, h = 48,
        text = "初始化中...", font_size = 16,
        color = COLOR_TEXT_DIM,
    })

    -- 分辨率信息
    airui.label({
        parent = airui.screen,
        x = PANEL_X + 8, y = PANEL_Y + 118, w = PANEL_W - 16, h = 24,
        text = string.format("分辨率 %dx%d  MJPEG", SENSOR_W, SENSOR_H),
        font_size = 14, color = COLOR_TEXT_DIM,
    })

    -- 按钮起始Y
    local by = PANEL_Y + 170

    -- 切换按钮（开始/停止预览）
    toggle_btn = new_btn("开始预览", PANEL_X, by, BTN_W, BTN_H, COLOR_BLUE, on_toggle)
    by = by + BTN_H + BTN_GAP

    -- 控制按钮（创建/销毁组件）
    ctrl_btn = new_btn("创建组件", PANEL_X, by, BTN_W, BTN_H, COLOR_GREEN, on_ctrl)

    -- 自动创建组件
    create_widget()
    sync_ctrl_btn()
    sync_toggle_btn()
    update_status("点击开始预览启动摄像头")

    -- 消息循环
    while true do
        local _, cmd = sys.waitUntil("CAMERA_CMD")
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
        end
    end
end)
