--[[
@module  usb_preview
@summary 启动 USB 预览并处理分辨率切换和 START / STOP
@version 001.999.000
@date    2026.11.21
@usage
由 main.lua 加载。预览协程串行处理摄像头开关、抓帧和 LCD 绘制。
]]

local board = require "board"
local preview = require "camera_app"
local ui = require "ui"

-- 默认选中第一个分辨率并自动预览。用请求序号判断等待期间有无新的触摸操作。
local selected, requested, revision = 1, true, 0
local interval_ms = 200
local frame_timeout_ms = 1200

-- 触摸回调只更新请求，摄像头的开关由预览协程处理。
sys.subscribe("AIR1032_CONTROL", function(command)
    if command == "start" or command == "stop" then
        local start = command == "start"
        if requested == start then return end
        requested = start
    elseif type(command) == "number" and board.CAM.modes[command] then
        selected, requested = command, true
    else
        return
    end
    log.info("air1032", "control", command)
    revision = revision + 1
    sys.publish("AIR1032_WAKE")
end)

sys.taskInit(function()
    board.power_on()
    if not board.lcd_init() then return end
    ui.init()
    ui.show(selected, requested, "Starting...")
    if not board.tp_init(ui.touch) then
        log.warn("air1032", "触摸初始化失败，继续自动预览")
    end
    if not camera then
        ui.show(selected, false, "Camera library missing")
        return
    end

    -- 固件带看门狗时，设置 9 秒超时，每 3 秒喂狗一次。
    if wdt then
        wdt.init(9000)
        sys.timerLoopStart(wdt.feed, 3000)
    end

    -- 先应用新的分辨率或开关请求，再继续逐帧抓取。等待期间收到新请求时跳过旧画面。
    local applied = -1
    local active, failures, frames = false, 0, 0
    while true do
        if applied ~= revision then
            applied = revision
            preview.close()
            active, failures, frames = false, 0, 0
            if requested then
                local mode = board.CAM.modes[selected]
                ui.show(selected, true, string.format("Opening %dx%d...", mode.w, mode.h))
                local ok, reason = preview.open(mode)
                -- 首次打开失败时，延长断电时间后重试一次。
                if not ok and applied == revision then
                    log.warn("air1032", "Retry", mode.w, mode.h, reason)
                    ok, reason = preview.open(mode, true)
                end
                if applied == revision then
                    if ok then
                        ui.show(selected, true, string.format("Live  %dx%d  MJPEG", mode.w, mode.h))
                        local drawn, w, h, crop_w, crop_h = ui.draw_frame(preview.path)
                        active = drawn
                        if active then
                            frames = 1
                            log.info("air1032", "first_display", mode.w, mode.h, "jpeg", w, h, "visible", crop_w, crop_h)
                        else
                            reason = "JPEG display failed"
                        end
                    end
                    if not active then
                        preview.close()
                        requested = false
                        ui.show(selected, false, reason or "Preview failed")
                        log.warn("air1032", "preview_failed", mode.w, mode.h, reason)
                    end
                end
            else
                ui.show(selected, false, "Stopped")
                log.info("air1032", "preview_stopped")
            end
        elseif active then
            local start = mcu.ticks()
            local got = preview.grab(frame_timeout_ms)
            if applied == revision then
                if got and ui.draw_frame(preview.path) then
                    failures = 0
                    frames = frames + 1
                    if frames % 20 == 0 then log.info("air1032", "preview_frames", frames) end
                else
                    failures = failures + 1
                    if failures >= 3 then
                        preview.close()
                        active, requested = false, false
                        ui.show(selected, false, "Preview stopped. Tap START to retry.")
                        log.warn("air1032", "preview_interrupted", frames)
                    end
                end
                local wait = interval_ms - (mcu.ticks() - start)
                if wait > 0 then sys.wait(wait) end
            end
        else
            sys.waitUntil("AIR1032_WAKE")
        end
    end
end)
