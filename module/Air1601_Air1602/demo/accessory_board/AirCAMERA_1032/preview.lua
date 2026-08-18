--[[
@module  preview
@summary AirCAMERA_1032 USB摄像头 + excamera扩展库 + AIRUI camera组件预览（支持四种fit模式切换）
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
local fit_btns = {}           -- fit模式按钮表
local widget_registered = false  -- 标记是否已注册到解码通道

-- 目标分辨率
local SENSOR_W = 1280
local SENSOR_H = 720
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

-- fit按钮尺寸
local FIT_BTN_W = math.min(PANEL_W - 16, 160)
local FIT_BTN_H = 36
local FIT_BTN_GAP = 8

-- fit模式列表
local FIT_MODES = { "center", "contain", "cover", "stretch" }
local current_fit = "cover"   -- 默认fit模式

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
local COLOR_FIT_IDLE = 0x45475A
local COLOR_FIT_ACTIVE = 0x1E88E5

-- 生成状态文本（含源、视口、fit）
local function status_fit_text()
    return string.format("源%d×%d→视口%d×%d fit=%s", SENSOR_W, SENSOR_H, PREVIEW_W, PREVIEW_H, current_fit)
end

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
    if app_state == STATE_WAITING then
        toggle_btn:set_text("连接中...")
        toggle_btn:set_style({bg_color = 0x888888, pressed_bg_color = 0x888888, text_color = 0xFFFFFF})
    elseif app_state == STATE_PREVIEWING then
        toggle_btn:set_text("停止预览")
        toggle_btn:set_style({bg_color = COLOR_ORANGE, pressed_bg_color = COLOR_ORANGE, text_color = 0xFFFFFF})
    else
        toggle_btn:set_text("开始预览")
        toggle_btn:set_style({bg_color = COLOR_BLUE, pressed_bg_color = COLOR_BLUE, text_color = 0xFFFFFF})
    end
end

-- 同步fit按钮状态
local function sync_fit_btns()
    for mode, btn in pairs(fit_btns) do
        local active = (mode == current_fit)
        local color = active and COLOR_FIT_ACTIVE or COLOR_FIT_IDLE
        btn:set_style({bg_color = color, pressed_bg_color = color, text_color = 0xFFFFFF})
    end
end

-- 应用fit模式
local function apply_fit(mode)
    current_fit = mode
    if camera_widget and not camera_widget:is_destroyed() then
        camera_widget:set_fit(mode)
    end
    sync_fit_btns()
    if app_state == STATE_PREVIEWING then
        update_status("预览中 " .. status_fit_text())
    else
        update_status("已选 fit=" .. mode)
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
        fit = current_fit,
        auto_start = false,
    })
    if not camera_widget then
        update_status("camera组件创建失败")
        return false
    end
    app_state = STATE_CREATED
    widget_registered = false
    update_status(string.format("组件已创建 %dx%d fit=%s", PREVIEW_W, PREVIEW_H, current_fit))
    return true
end

-- 注册AIRUI camera控件（绑定到解码通道，但不启动显示）
local function register_camera_widget()
    if not camera_widget or camera_widget:is_destroyed() then
        return false
    end
    camera_widget:register()
    widget_registered = true
    app_state = STATE_CREATED   -- 已注册但未预览
    sync_toggle_btn()
    update_status("摄像头已连接，点击“开始预览”显示画面")
    return true
end

-- excamera预览回调：收到摄像头连接事件后注册AIRUI控件（但不启动显示）
local function preview_callback(event, ...)
    if event == "connected" then
        local app_id = select(1, ...)
        log.info("preview", "USB摄像头已连接, app_id:", app_id)

        -- ========== 遍历并打印摄像头支持的所有分辨率 ==========
        local res, format_num = camera.get_usb_config(app_id, camera.CONF_UVC_FORMAT)
        log.info("preview", "UVC格式数量:", format_num)
        for format_index = 1, format_num do
            local res, ftype, frame_num = camera.get_usb_config(app_id, camera.CONF_UVC_FORMAT, format_index)
            log.info("preview", string.format("  格式索引 %d, 类型: %d, 帧数: %d", format_index, ftype, frame_num))
            for frame_index = 1, frame_num do
                local res, fps, w, h = camera.get_usb_config(app_id, camera.CONF_UVC_RESOLUTION, format_index, frame_index)
                log.info("preview", string.format("    分辨率 %dx%d, 帧率: %d fps", w, h, fps))
            end
        end
        -- ==========================================================

        register_camera_widget()
    elseif event == "disconnected" then
        if camera_widget and not camera_widget:is_destroyed() then
            camera_widget:stop()
        end
        widget_registered = false
        app_state = STATE_CREATED
        sync_toggle_btn()
        update_status("摄像头已断开")
    elseif event == "error" then
        local msg = select(1, ...)
        log.warn("preview", "摄像头错误:", msg)
    end
end

-- 初始化USB数据流（只在程序启动时调用一次，保持常开）
local function init_usb_stream()
    if app_state == STATE_PREVIEWING or app_state == STATE_WAITING then
        return true
    end
    local usb_param = {
        id = camera.USB,
        sensor_width = SENSOR_W,
        sensor_height = SENSOR_H,
        usb_port = 1,
        work_mode = 2,
        save_path = "/ram/photo.jpg",
        fps = 15,
    }
    local ok = excamera.open(usb_param)
    if not ok then
        update_status("摄像头打开失败")
        return false
    end
    ok = excamera.preview(preview_callback)
    if ok then
        app_state = STATE_WAITING
        sync_toggle_btn()
        update_status("等待摄像头连接...")
        return true
    else
        update_status("预览启动失败")
        excamera.close()
        return false
    end
end

-- 开始预览（仅启动控件显示，不重复打开USB流）
local function start_preview()
    if not camera_widget or camera_widget:is_destroyed() then
        log.warn("preview", "请先创建组件")
        return
    end
    if not widget_registered then
        update_status("摄像头尚未连接，请等待...")
        return
    end
    if app_state == STATE_PREVIEWING then
        return
    end
    camera_widget:start()
    app_state = STATE_PREVIEWING
    sync_toggle_btn()
    update_status("预览中 " .. status_fit_text())
end

-- 停止预览（仅停止控件显示，不关闭USB流）
local function stop_preview()
    if app_state ~= STATE_PREVIEWING then
        return
    end
    if camera_widget and not camera_widget:is_destroyed() then
        camera_widget:stop()
    end
    app_state = STATE_CREATED
    sync_toggle_btn()
    update_status("预览已停止 fit=" .. current_fit)
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
    if app_state == STATE_WAITING then
        return  -- 等待连接中忽略操作
    end
    sys.publish("CAMERA_CMD", "toggle")
end
local function on_fit(mode)
    return function()
        sys.publish("CAMERA_CMD", "fit", mode)
    end
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
    by = by + BTN_H + BTN_GAP + 8

    -- 分隔线
    airui.label({
        parent = airui.screen,
        x = PANEL_X + 8, y = by, w = PANEL_W - 16, h = 1,
        text = "", font_size = 1,
        style = {bg_color = COLOR_BORDER, border_width = 0},
    })
    by = by + 12

    -- fit模式标题
    airui.label({
        parent = airui.screen,
        x = PANEL_X, y = by, w = PANEL_W, h = 24,
        text = "适配模式", font_size = 16,
        color = COLOR_TEXT_DIM, align = airui.TEXT_ALIGN_CENTER,
    })
    by = by + 28

    -- 创建fit按钮
    for _, mode in ipairs(FIT_MODES) do
        local btn_x = PANEL_X + (PANEL_W - FIT_BTN_W) // 2
        local color = (mode == current_fit) and COLOR_FIT_ACTIVE or COLOR_FIT_IDLE
        fit_btns[mode] = airui.button({
            parent = airui.screen,
            x = btn_x, y = by, w = FIT_BTN_W, h = FIT_BTN_H,
            text = mode,
            font_size = 16,
            style = {
                bg_color = color, pressed_bg_color = color,
                text_color = 0xFFFFFF, radius = 6, border_width = 0,
            },
            on_click = on_fit(mode),
        })
        by = by + FIT_BTN_H + FIT_BTN_GAP
    end

    -- 自动创建组件
    create_widget()
    sync_toggle_btn()
    sync_fit_btns()
    update_status("点击开始预览启动摄像头")

    -- 初始化USB数据流（常开）
    init_usb_stream()

    -- 消息循环
    while true do
        local _, cmd, arg = sys.waitUntil("CAMERA_CMD")
        if cmd == "toggle" then
            if app_state == STATE_PREVIEWING then
                stop_preview()
            else
                start_preview()
            end
            sync_toggle_btn()
            sync_fit_btns()
        elseif cmd == "fit" and arg then
            apply_fit(arg)
            sync_fit_btns()
        end
    end
end)