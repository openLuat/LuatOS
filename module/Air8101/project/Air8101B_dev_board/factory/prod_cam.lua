--[[
@module  prod_cam
@summary 产测项 CAM_TEST#：UVC 摄像头（AirCAMERA_1030/1031）抓一帧
@usage   CAM_TEST#
@return  string —— "OK" / "ERROR"
说明
1. UVC_EN(GPIO29) 先断电复位再上电，等 USB 枚举；
2. 抓帧存 ZBUFF，只判"抓到非空 JPEG"，不判画面内容；帧大小写日志；
3. 用完释放摄像头资源。
]]

local W, H = 640, 480

return function(arg)
    local excamera = require "excamera"
    local c = _G.project_config.hw.cam

    -- 断电复位：先拉低断掉摄像头供电，再拉高
    gpio.setup(c.en, 0)
    sys.wait(200)
    gpio.setup(c.en, 1)
    sys.wait(800)          -- 等供电稳定 + USB 设备枚举

    local opened = excamera.open({
        id            = camera.USB,
        sensor_width  = W,
        sensor_height = H,
        usb_port      = 1,
        save_path     = "ZBUFF",
    })
    if not opened then
        log.error("prod_cam", "摄像头打开失败（查 UVC 供电/UVC_EN、USB 线、摄像头）")
        return "ERROR"
    end

    local shot_ok, data = excamera.photo()
    local size = (shot_ok and data and data.used) and data:used() or 0

    pcall(excamera.close)   -- 收尾：产测不上传，直接释放

    log.info("prod_cam", "抓帧结果:", shot_ok, "大小:", size, "字节")
    if not shot_ok or size == 0 then
        log.error("prod_cam", "抓帧失败或数据为空")
        return "ERROR"
    end
    return "OK"
end
