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
local function camera_cb(id, param)
    if zbuff_id == 0 then
        log.info("图像数据长度", frame_buff0:used())
    end
    if zbuff_id == 1 then
        log.info("图像数据长度", frame_buff1:used())
    end
end
-- camera.on(camera_id, "scanned", camera_cb)
-- 注册USB回调函数
local function usb_cb(bus_id, class_type, app_id, event)
    if event == usb.EV_CONNECT then
        if class_type == usb.CAMERA then
            log.info("usb摄像头已连接，使用app id", app_id)
        end
    end
    if event == usb.EV_DISCONNECT then
        if class_type == usb.CAMERA then
            log.info("usb摄像头 app id", app_id, "已经断开")
        end
    end
end
usb.on(0, usb_cb)
pm.power(pm.USB, false)		--确保USB外设是掉电状态
usb.mode(0, usb.HOST)		--usb设置成主机模式
pm.power(pm.USB, true)		--USB上电初始化开始工作
-- 初始化摄像头并处理拍照和上传图片的操作
local function camera_test()
end

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
