--[[
@module  preview
@summary AirCAMERA_1032 USB摄像头 + excamera扩展库 + AIRUI camera组件预览
@version 1.0
@date    2026.06.23
@author  江访
@usage
本demo使用excamera扩展库 + AIRUI camera组件实现USB摄像头实时画面预览。
画面嵌入AIRUI组件树，切换按钮与画面共存。

核心流程：
1. LCD驱动初始化（main.lua中完成）
2. 触摸初始化 → 绑定AIRUI输入
3. airui.camera 创建预览控件 + 操作按钮
4. 点击"开始预览" → excamera.open() + preview() → 画面自动推送到组件
5. 点击"停止预览" → 停止推流，释放摄像头资源

注意：
- 预览组件只允许同时存在一个
- 所有按钮操作通过 sys.publish/CAMERA_CMD 转主任务协程执行
  （excamera.close 含 sys.wait，只能在协程中调用）
]]




-- excamera扩展库
local excamera = require "excamera"

-- 全局变量
local camera_widget = nil     -- AIRUI camera组件
local status_label = nil      -- 状态标签
local toggle_btn = nil        -- 开始/停止切换按钮
local ctrl_btn = nil          -- 销毁/创建切换按钮

-- 目标分辨率（与LCD匹配）
local SENSOR_W = 640
local SENSOR_H = 480
local LCD_W = 1024
local LCD_H = 600

-- 摄像头控件区域（左侧画面）
local CAM_X = 0
local CAM_Y = 50
local CAM_W = SENSOR_W
local CAM_H = SENSOR_H

-- 右侧按钮区域
local BTN_X = 660
local BTN_W = 340
local BTN_H = 50
local BTN_GAP = 12
local BTN_START_Y = 80

-- 状态枚举
local STATE_PREVIEW_IDLE = 0      -- 无控件/无预览
local STATE_CREATED = 1           -- 控件已创建，未预览
local STATE_PREVIEWING = 2        -- 预览运行中
local app_state = STATE_PREVIEW_IDLE

-- 12号GPIO拉高（AirCAMERA_1032摄像头供电控制引脚）
gpio.setup(12, 1, gpio.PULLUP)
-- 关闭hardfault自动复位，方便调试摄像头异常
mcu.hardfault(0)

-- 更新状态标签
local function update_status(text)
    if status_label then
        status_label:set_text(text)
    end
    log.info("preview", text)
end

-- 按钮状态颜色
local COLOR_BLUE = 0x1565C0      -- 开始预览
local COLOR_ORANGE = 0xEF6C00    -- 停止预览
local COLOR_GREEN = 0x2E7D32     -- 创建组件
local COLOR_RED = 0xC62828       -- 销毁组件

-- 同步切换按钮状态（文字+颜色）
local function sync_toggle_btn()
    if not toggle_btn then
        return
    end
    if app_state == STATE_PREVIEWING then
        toggle_btn:set_text("停止预览")
        toggle_btn:set_style({bg_color = COLOR_ORANGE, pressed_bg_color = COLOR_ORANGE, text_color = 0xFFFFFF})
    else
        toggle_btn:set_text("开始预览")
        toggle_btn:set_style({bg_color = COLOR_BLUE, pressed_bg_color = COLOR_BLUE, text_color = 0xFFFFFF})
    end
end

-- 同步控制按钮状态（文字+颜色）
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
        log.warn("camera_preview_airui", "控件已存在")
        return true
    end
    camera_widget = airui.camera({
        parent = airui.screen,
        x = CAM_X, y = CAM_Y,
        w = CAM_W, h = CAM_H,
        auto_start = false,
    })
    if not camera_widget then
        update_status("AIRUI camera控件创建失败")
        return false
    end
    app_state = STATE_CREATED
    update_status("控件已创建")
    return true
end

-- 销毁组件
local function destroy_widget()
    if camera_widget and not camera_widget:is_destroyed() then
        camera_widget:destroy()
    end
    camera_widget = nil
    app_state = STATE_PREVIEW_IDLE
    update_status("控件已销毁")
end

-- 注册并启动AIRUI camera控件
local function register_camera_widget()
    if not camera_widget or camera_widget:is_destroyed() then
        log.warn("camera_preview_airui", "widget not available")
        return false
    end
    camera_widget:register()
    camera_widget:start()
    app_state = STATE_PREVIEWING
    update_status("预览运行中 " .. SENSOR_W .. "x" .. SENSOR_H)
    return true
end

-- excamera预览回调：收到摄像头连接事件后注册AIRUI控件
local function preview_callback(event, ...)
    if event == "connected" then
        local app_id = select(1, ...)
        log.info("camera_preview_airui", "USB摄像头已连接, app_id:", app_id)
        register_camera_widget()
    elseif event == "disconnected" then
        local app_id = select(1, ...)
        log.info("camera_preview_airui", "USB摄像头已断开, app_id:", app_id)
        app_state = STATE_CREATED
        update_status("摄像头已断开")
    elseif event == "error" then
        local msg = select(1, ...)
        log.warn("camera_preview_airui", "摄像头错误:", msg)
    elseif event == "frame" then
        -- 帧数据由底层自动推送到AIRUI camera控件
    end
end

-- 开始预览（在协程中执行）
local function start_preview()
    if not camera_widget or camera_widget:is_destroyed() then
        log.warn("camera_preview_airui", "请先创建控件")
        return
    end

    if app_state == STATE_PREVIEWING then
        log.warn("camera_preview_airui", "预览已在运行")
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
        -- 先切到等待状态，按钮显示"停止预览"禁止用户重复点击
        -- EV_CONNECT 触发后 register_camera_widget() 会同步切到 STATE_PREVIEWING
        app_state = STATE_PREVIEWING
        sync_toggle_btn()
        update_status("等待摄像头连接...")
    else
        update_status("预览启动失败")
        excamera.close()
    end
end

-- 停止预览（在协程中执行，excamera.close含sys.wait）
local function stop_preview()
    if camera_widget and not camera_widget:is_destroyed() then
        camera_widget:stop()
    end
    excamera.close()
    app_state = STATE_CREATED
    update_status("预览已停止")
end

-- 辅助函数：创建按钮（返回按钮对象）
local function create_button(text, x, y, w, h, color, cb)
    local btn = airui.button({
        parent = airui.screen,
        x = x, y = y, w = w, h = h,
        text = text,
        font_size = 20,
        style = {
            bg_color = color,
            pressed_bg_color = color,
            text_color = 0xFFFFFF,
            radius = 8,
            border_width = 0,
        },
        on_click = cb,
    })
    return btn
end

-- 按钮回调：只发布消息，不执行耗时操作
-- （on_click在LVGL事件循环中运行，非协程，不能调用sys.wait）
local function on_toggle_preview()
    sys.publish("CAMERA_CMD", "toggle_preview")
end

local function on_ctrl_widget()
    sys.publish("CAMERA_CMD", "ctrl_widget")
end

-- 主任务
sys.taskInit(function()
    -- 1. 创建状态标签
    status_label = airui.label({
        parent = airui.screen,
        x = 10, y = 10, w = 620, h = 30,
        text = "等待初始化...",
        font_size = 18,
    })
    update_status("初始化中...")

    -- 2. 自动创建摄像头控件
    create_widget()

    -- 3. 右侧创建操作按钮
    local by = BTN_START_Y

    toggle_btn = create_button("开始预览", BTN_X, by, BTN_W, BTN_H, COLOR_BLUE, on_toggle_preview)
    by = by + BTN_H + BTN_GAP

    ctrl_btn = create_button("创建组件", BTN_X, by, BTN_W, BTN_H, COLOR_GREEN, on_ctrl_widget)
    by = by + BTN_H + BTN_GAP

    sync_ctrl_btn()
    sync_toggle_btn()

    -- 4. 等待用户点击"开始预览"按钮启动
    -- 不自动启动，给用户点击"开始预览"的机会
    update_status("请点击开始预览")

    -- 5. 消息循环：处理按钮发来的命令
    while true do
        local _, cmd = sys.waitUntil("CAMERA_CMD")
        if cmd == "toggle_preview" then
            if app_state == STATE_PREVIEWING then
                stop_preview()
            else
                start_preview()
            end
            sync_toggle_btn()
            sync_ctrl_btn()
        elseif cmd == "ctrl_widget" then
            if camera_widget and not camera_widget:is_destroyed() then
                -- 如果预览运行中，先停止
                if app_state == STATE_PREVIEWING then
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