PROJECT = "usb_cam_demo"
VERSION = "1.0.0"

log.style(1)

-- 摄像头图像基本参数，格式，长，宽
local frame_type = 1    --mjpg
local w = 1024
local h = 768
local camera_id = nil
-- 双缓冲接收图像数据
local frame_buff0 = zbuff.create(w * h)
local frame_buff1 = zbuff.create(w * h)
-- 注册摄像头回调函数
local function  cb(app_id, event, param)
    if event == usb.EX_RX then
        if param == 0 then
            log.info("usb摄像头接收数据，位于buffer0 ,数据长度", frame_buff0:used())
        end
        if param == 1 then
            log.info("usb摄像头接收数据，位于buffer1 ,数据长度", frame_buff1:used())
        end
        return
    end
    if event == usb.EV_CONNECT then
        log.info("usb摄像头已连接，使用app id，位于hub端口", app_id, param)
        camera_id = app_id
        local res, format_num, format_index, frame_num, frame_index, type, fps, w, h
        res, format_num = camera.get_usb_config(camera_id, camera.CONF_UVC_FORMAT)
        log.info("总共有", format_num, "种数据流格式")
        for format_index = 0, format_num, 1 do
            res, type, frame_num = camera.get_usb_config(camera_id, camera.CONF_UVC_FORMAT, format_index)
            log.info("数据流序号", format_index, "数据流格式", type, "总共有", frame_num, "图像格式")
            for frame_index = 0, frame_num, 1 do
                res, fps, w, h = camera.get_usb_config(camera_id, camera.CONF_UVC_RESOLUTION, format_index, frame_index)
                log.info("图像格式序号", frame_index, "图像格式", type, "帧率", fps, "图像宽度", w, "图像高度", h)
            end
        end
        camera.set_usb_config(camera_id, camera.CONF_UVC_RESOLUTION, 1, w, h)
        camera.start(camera_id)
        return

    end
    if event == usb.EV_DISCONNECT then
        log.info("usb摄像头 app id", app_id, "已经断开")
        camera_id = nil
        return
    end
end

camera.on(camera.USB, "usb_raw", cb)
pm.power(pm.USB, false)		--确保USB外设是掉电状态
usb.mode(0, usb.HOST)		--usb设置成主机模式
pm.power(pm.USB, true)		--USB上电初始化开始工作

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
