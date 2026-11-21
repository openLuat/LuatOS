--[[
@module  camera_app
@summary USB 摄像头供电、MJPEG 抓帧和资源释放
@version 001.999.000
@date    2026.11.21
@usage
打开选中的分辨率，将 JPEG 保存到 RAM 文件，供 LCD 预览模块解码。
]]

local board = require "board"

-- 每次抓帧覆盖同一个 RAM 文件，供 lcd.image2raw() 读取。
local preview = { path = "/ram/air1032_preview.jpg" }
local streaming = false
local frame_ready = false

-- 收到有效抓帧回调后，等待帧的协程可以继续绘制。
local function on_frame(_, size)
    if (type(size) == "number" and size > 0) or size == true then
        frame_ready = true
    end
end

-- RGB LCD 提交画面前先停止本次抓帧，避免与固件内置预览通路冲突。
function preview.grab(timeout_ms)
    if not streaming then return false end
    frame_ready = false
    if not camera.start(camera.USB) then return false end
    local accepted = camera.capture(camera.USB, preview.path, 1)
    if accepted then
        local started = mcu.ticks()
        while not frame_ready and mcu.ticks() - started < timeout_ms do
            sys.wait(20)
        end
    end
    camera.stop(camera.USB)
    return accepted and frame_ready
end

-- 先关闭已打开的摄像头，再切断开发板 USB-A 口的摄像头供电。
function preview.close()
    if streaming then
        camera.close(camera.USB)
        streaming = false
    end
    gpio.setup(board.CAM.uvc_en, 0)
end

-- 每次打开前做一次断电恢复。重试延长低电平时间，首帧成功后交给预览协程。
function preview.open(mode, retry)
    preview.close()
    sys.wait(retry and 2000 or 200)
    gpio.setup(board.CAM.uvc_en, 1)
    sys.wait(board.CAM.startup_ms)

    local id = camera.init({
        id = camera.USB,
        sensor_width = mode.w,
        sensor_height = mode.h,
        usb_port = board.CAM.usb_port,
    })
    log.info("air1032", "camera.init", mode.w, mode.h, id)
    if id ~= 0 and id ~= 1 and id ~= true then
        preview.close()
        return false, "USB camera open failed"
    end

    streaming = true
    camera.on(camera.USB, "scanned", on_frame)
    os.remove(preview.path)
    if not preview.grab(board.CAM.first_frame_ms) then
        preview.close()
        return false, "First frame timed out"
    end
    return true
end

return preview
