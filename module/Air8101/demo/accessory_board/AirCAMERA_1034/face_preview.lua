--[[
@module  face_preview
@summary Air8101B V3.0 开发板上使用 AirCAMERA_1034 实时预览、拍照和人脸录入、验证
@usage
在 main.lua 中加载本模块。AirCAMERA_1034 接开发板的 USB-A 口，LCD 默认使用
AirLCD_1100（1024×600）和 GT911，硬件参数见 board.lua。
使用人脸功能时，UART1 的 TX/RX 交叉连接摄像头 UART、两端共地，并附加 exfacecam.lua。
使用存卡功能时，插入 TF 卡并打开开发板的 VBAT_SD 开关。
]]

local board      = require "board"
local ui         = require "ui"
local camera_app = require "camera_app"

local face
if board.CAM.type == "UVC" and board.FACE and uart then
    local ok, lib = pcall(require, "exfacecam")
    if ok and type(lib) == "table" then
        face = lib
    else
        log.info("main", "人脸功能需要附加 exfacecam.lua")
    end
end

local busy = false
local pump_on, pump_running = false, false
local retrying = false
local drawn_frames = 0

-- 停预览泵：先置标志，再等当前这一帧抓完（避免和拍照抢摄像头）
local function stop_pump()
    pump_on = false
    for _ = 1, 150 do
        if not pump_running then break end
        sys.wait(20)
    end
end

-- 启预览泵：连续抓帧 → 解码上屏，直到状态离开 preview
local function start_pump()
    if pump_running then return end
    pump_on = true
    sys.taskInit(function()
        pump_running = true
        log.info("main", "预览泵启动")
        local n, t0 = 0, mcu.ticks()
        local interval = board.PREVIEW_INTERVAL or 250
        while pump_on and ui.state() == "preview" do
            local frame_t0 = mcu.ticks()
            local call_ok, got = pcall(camera_app.grab)
            if not call_ok then
                log.error("main", "grab 异常", got)
                sys.wait(500)
            elseif got then
                local draw_ok, drawn = pcall(ui.draw_frame, camera_app.frame_path())
                if not draw_ok then
                    log.error("main", "draw_frame 异常", drawn)
                    sys.wait(300)
                elseif drawn then
                    n = n + 1
                    drawn_frames = drawn_frames + 1
                    if n % 20 == 0 then
                        log.info("main", "预览帧", n, "耗时", mcu.ticks() - t0, "ticks")
                    end
                end
                -- 按 board.PREVIEW_INTERVAL 控制节奏：刷得越勤整屏拷贝越频繁，闪得越明显
                local dt = mcu.ticks() - frame_t0
                if dt < interval then
                    sys.wait(interval - dt)
                end
            else
                sys.wait(150)
            end
        end
        pump_running = false
        log.info("main", "预览泵退出", n, "帧")
    end)
end

-- ============================ 界面信息 ============================

-- 首页那行硬件信息：保持纯 ASCII，ascii 文字模式下也能正常显示
local function hw_info()
    local c = board.CAM
    local fw = (rtos.version and rtos.version()) or "?"
    if c.type == "DVP" then
        return string.format("DVP %dx%d  I2C%d  FW %s", c.dvp_w, c.dvp_h, c.dvp_i2c_id, fw)
    end
    return string.format("UVC Auto  USB%d  FW %s", c.usb_port, fw)
end

-- ============================ 动作 ============================

-- 摄像头没就绪时定时自动重试（插拔摄像头后不用手动点）
local function start_retry()
    if retrying then return end
    retrying = true
    sys.taskInit(function()
        for i = 1, 2 do
            sys.wait(4000)
            if ui.state() ~= "error" then
                retrying = false
                return
            end
            if not busy then
                busy = true          -- 重试期间挡住手动点击，避免两个 init 并发
                log.info("main", "自动重试摄像头", i)
                ui.set_state("error", "msg_retry", i)
                -- 重试用浅试（deep 的主机复位实测救不回热插拔，别把时间耗在这）
                local ok = camera_app.start_preview(false)
                busy = false
                if ok then
                    local w, h = camera_app.resolution()
                    ui.set_res_label(string.format("%dX%d", w, h))
                    ui.set_state("preview", "msg_preview", w, h)
                    ui.render(true)
                    start_pump()
                    retrying = false
                    return
                end
            end
        end
        retrying = false
        log.info("main", "自动重试结束")
        if ui.state() == "error" then
            -- 热插拔后该固件的 UVC 连接拉不起来：重启一次走开机路径（只重启一次）
            if board.AUTO_REBOOT_ON_CAM_FAIL and camera_app.try_reboot_once() then
                return
            end
            ui.set_state("error", "msg_cam_fail")
        end
    end)
end

-- 开始 / 停止预览
local function do_preview(auto)
    if busy then return end
    if not camera_app.available() then
        ui.set_state("error", "err_no_lib")
        return
    end

    if ui.state() == "preview" then
        busy = true
        ui.set_state("starting", "msg_stopping")
        sys.taskInit(function()
            stop_pump()
            -- pcall 兜底：任务里一旦抛错，busy 会永远为 true，界面就再也点不动了
            local ok, err = pcall(camera_app.stop)
            if not ok then log.error("main", "stop 异常", err) end
            ui.clear_photo()
            ui.set_state("idle", "msg_stopped")
            busy = false
        end)
        return
    end

    busy = true
    ui.set_state("starting", "msg_starting")
    sys.taskInit(function()
        -- 开机自动预览只跑第一轮，避免没插摄像头时把启动拖太久；
        -- 手动点按钮 / 自动重试则带上 USB 主机复位再试一轮
        local call_ok, ok, err = pcall(camera_app.start_preview, not auto)
        if not call_ok then ok, err = false, "err_preview" end
        if ok then
            local w, h = camera_app.resolution()
            ui.set_res_label(string.format("%dX%d", w, h))
            ui.set_state("preview", "msg_preview", w, h)
            ui.render(true)
            start_pump()
        else
            ui.set_state("error", err or "err_preview")
            if err == "err_cam_init" then
                start_retry()
            end
        end
        busy = false
    end)
end

-- 拍照
local function do_capture()
    if busy then return end
    if not camera_app.available() then
        ui.set_state("error", "err_no_lib")
        return
    end

    busy = true
    ui.set_state("capturing", "msg_capture")
    sys.taskInit(function()
        stop_pump()
        local call_ok, ok, err = pcall(camera_app.capture)
        if not call_ok then ok, err = false, "err_capture" end
        if ok then
            local w, h = camera_app.resolution()
            local kb = math.floor(camera_app.last_size() / 1024 + 0.5)
            ui.set_photo(camera_app.last_photo(), w, h)
            ui.set_state("photo", "msg_shot_done", kb)
        else
            ui.set_state("error", err or "err_capture")
        end
        busy = false
    end)
end

-- 保存到 TF 卡
local function do_save()
    if busy then return end
    if not camera_app.last_photo() then
        ui.set_state(ui.state(), "msg_no_photo")
        return
    end

    busy = true
    ui.set_state("photo", "msg_saving")
    sys.taskInit(function()
        local call_ok, ok, res, bytes = pcall(camera_app.save_to_sd)
        if not call_ok then ok, res = false, "err_write" end
        if ok then
            local kb = math.floor(bytes / 1024 + 0.5)
            ui.set_state("photo", "msg_saved", res, kb)
        else
            ui.set_state("photo", res or "err_write")
        end
        busy = false
    end)
end

-- 人脸模组只开 UART1，UVC 继续由预览泵抓帧。
local function run_face(enroll)
    if not face.open({ face_uart = board.FACE.uart_id }) then
        return "err_face_uart"
    end

    local start_frames = drawn_frames
    local prompt = enroll and "msg_face_enrolling" or "msg_face_verifying"
    ui.set_face_status(true, prompt)
    local hint = prompt
    local options = {
        timeout = board.FACE.timeout,
        on_state = function(state)
            local next_hint = state == 0 and prompt or "msg_face_adjust"
            if next_hint ~= hint then
                hint = next_hint
                ui.set_face_status(true, hint)
            end
        end,
    }

    if enroll then
        -- 省略 admin，按 exfacecam 的默认值录入普通用户。
        options.name = string.format("UVC_TEST_%d_%d", os.time(), mcu.ticks())
        local ok, user_id = face.register(options)
        log.info("main", "人脸录入", ok, user_id, "期间绘制帧数", drawn_frames - start_frames)
        if ok then return "msg_face_enrolled", tostring(user_id or "?") end
        if user_id == face.MR_FAILED4_FACEENROLLED then return "msg_face_exists" end
        return "err_face_enroll", tostring(user_id or "unknown")
    end

    local ok, result = face.verify(options)
    local user_id = ok and type(result) == "table" and result.user_id
    log.info("main", "人脸验证", ok, user_id, "期间绘制帧数", drawn_frames - start_frames)
    if type(user_id) == "number" then return "msg_face_verified", user_id end
    return "err_face_verify", ok and "missing ID" or tostring(result or "unknown")
end

local function do_face(enroll)
    if busy or not face or ui.state() ~= "preview" then return end
    if not camera_app.hold_uvc_power(true) then
        ui.set_face_status(false, "msg_face_retry")
        return
    end

    busy = true
    ui.set_face_status(true, "msg_face_opening")
    sys.taskInit(function()
        local ok, msg, detail = pcall(run_face, enroll)
        pcall(face.close)
        camera_app.hold_uvc_power(false)
        busy = false
        if not ok then
            log.error("main", "人脸操作异常", msg)
            ui.set_face_status(false, "err_face")
        else
            ui.set_face_status(false, msg, detail)
        end
    end)
end

-- 切换分辨率：按 board.CAM.sensor_list 循环，选中档位写 fskv 持久化
local function do_res()
    if busy then return end
    local w, h = camera_app.next_mode()
    log.info("main", "切换分辨率 ->", w, h)

    busy = true
    local was_preview = (ui.state() == "preview")
    ui.set_state("starting", "msg_switching")
    sys.taskInit(function()
        stop_pump()
        camera_app.stop()
        camera_app.set_preferred(w, h)

        if was_preview then
            local ok = camera_app.start_preview(true)
            if ok then
                local rw, rh = camera_app.resolution()
                ui.set_res_label(string.format("%dX%d", rw, rh))
                ui.set_state("preview", "msg_preview", rw, rh)
                ui.render(true)
                start_pump()
            else
                ui.set_res_label(string.format("%dX%d", w, h))
                ui.set_state("error", "err_cam_init")
            end
        else
            ui.set_res_label(string.format("%dX%d", w, h))
            ui.set_state("idle", "msg_ready")
        end
        busy = false
    end)
end

-- 重置：停预览 + 删临时照片 + 回到首页
local function do_reset()
    if busy then return end
    busy = true
    ui.set_state("starting", "msg_resetting")
    sys.taskInit(function()
        stop_pump()
        local ok, err = pcall(function()
            camera_app.stop()
            camera_app.clear_photo()
        end)
        if not ok then log.error("main", "reset 异常", err) end
        ui.clear_photo()
        ui.set_state("idle", "msg_ready")
        busy = false
    end)
end

-- ============================ 主流程 ============================

sys.taskInit(function()
    -- 1. 屏幕上电
    board.power_on()

    -- Air8101B 的 UVC 可在 RGB 屏和触摸初始化前完成枚举。
    -- 首选档需要较长等待时，先显示界面，再由自动预览流程开流。
    local first = camera_app.candidate_list()[1]
    if board.AUTO_PREVIEW and board.CAM.type == "UVC" and camera_app.available()
        and first and not first[3] then
        local called, result = pcall(camera_app.start_preview, false, true)
        if not called then log.warn("main", "UVC 启动异常", result) end
    end

    -- 2. 显示屏
    if not board.lcd_init() then
        log.error("main", "LCD 初始化失败：检查屏型号(h050iwv/hx8282)、排线、LCD_EN(GPIO55)")
        camera_app.stop()
        return
    end

    -- 3. 界面（字体：有 TTF 用 hzfont 显示中文，没有就退回 ASCII 位图字体）
    ui.init(hw_info(), board.FONT, face ~= nil)
    local w, h = camera_app.resolution()
    if w > 0 and h > 0 then
        ui.set_res_label(string.format("%dX%d", w, h))
    end
    ui.render(true)
    log.info("main", "文字模式", ui.text_mode())

    -- 4. 触摸（软件 I2C，GT911）
    if not board.tp_init(function(ev, x, y)
        sys.publish("CAM_UI_TOUCH", ev, x, y)
    end) then
        log.error("main", "触摸初始化失败：界面可显示但无法点击，检查 TP 排线/SCL38/SDA39")
    end

    -- 5. 按钮动作协程
    sys.taskInit(function()
        while true do
            local ok, action = sys.waitUntil("CAM_UI_ACTION")
            if ok then
                log.info("main", "按钮", action)
                if action == "preview" then
                    do_preview()
                elseif action == "capture" then
                    do_capture()
                elseif action == "save" then
                    do_save()
                elseif action == "res" then
                    do_res()
                elseif action == "clear" then
                    do_reset()
                elseif action == "enroll" or action == "verify" then
                    do_face(action == "enroll")
                end
            end
        end
    end)

    log.info("main", "界面就绪", hw_info())

    -- 开机自动进实时预览：预览是这个 demo 的主场景，不该让用户先找按钮
    if board.AUTO_PREVIEW then
        sys.taskInit(function()
            sys.wait(300)
            do_preview(true)
        end)
    end

    -- 6. UI 主循环：等触摸（200ms 超时），每轮刷新一次叠加层
    while true do
        local ok, ev, x, y = sys.waitUntil("CAM_UI_TOUCH", 200)
        if ok then
            ui.touch(ev, x, y)
        end
        ui.tick()
    end
end)
