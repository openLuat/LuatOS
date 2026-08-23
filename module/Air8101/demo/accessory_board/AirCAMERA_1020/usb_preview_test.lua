--[[
@module  usb_preview_test
@summary Air8101 USB摄像头独立预览测试（不进入UI框架，直接预览）
@version 1.0
@date    2026.06.24
@author  江访
@usage
进入后自动启动USB摄像头预览，日志观察。
如需拍照，可后续扩展。
]]

local excamera = require "excamera"

-- USB摄像头参数
local SENSOR_W = 640
local SENSOR_H = 480
local PHOTO_PATH = "/ram/usb_preview.jpg"

-- 主任务
sys.taskInit(function()
    log.info("usb_preview_test", "启动USB摄像头预览...")

    local usb_param = {
        id = camera.USB,
        sensor_width = SENSOR_W,
        sensor_height = SENSOR_H,
        usb_port = 1,
        work_mode = 2,
        save_path = PHOTO_PATH,
    }

    local ok = excamera.open(usb_param)
    if not ok then
        log.error("usb_preview_test", "摄像头初始化失败")
        return
    end
    log.info("usb_preview_test", "摄像头初始化成功")

    ok = excamera.preview()
    if ok then
        log.info("usb_preview_test", "预览已启动，等待USB摄像头连接...")
    else
        log.error("usb_preview_test", "预览启动失败")
        excamera.close()
    end
end)
