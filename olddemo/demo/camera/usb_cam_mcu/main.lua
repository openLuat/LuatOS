PROJECT = "usb_cam_demo"
VERSION = "1.0.0"

log.style(1)

gpio.setup(12, 1, gpio.PULLUP) -- 输出高，内部上拉可选

lcd.init("custom", {
	port = lcd.RGB,
	hbp = 140,
	hspw = 20,
	hfp = 160,
	vbp = 20,
	vspw = 3,
	vfp = 12,
	bus_speed = 50 * 1000 * 1000,
	pin_pwr = 2,
	pin_rst = 15,
	direction = 0,
	w = 1024,
	h = 600
})


local uartid = 3 -- 根据实际设备选取不同的uartid
local result = uart.setup(uartid, -- 串口id
    2000000, -- 波特率
    8, -- 数据位
    1 -- 停止位
)
-- 摄像头图像基本参数，格式，长，宽
local frame_type = 1    --mjpg
local sensor_w = 1920
local sensor_h = 1080
local usb_app_id = nil
-- 双缓冲接收图像数据
local frame_buff0 = zbuff.create(sensor_w * sensor_h)
local frame_buff1 = zbuff.create(sensor_w * sensor_h)
-- 保存从串口发出的图像数据
local send_buff = zbuff.create(sensor_w * sensor_h)
local test_cnt = 0

local function usb_cb(usb_id, class, app_id, event, param1, param2, param3)
    if event == usb.EV_CONNECT then
        if class == usb.CAMERA then
            log.info("usb摄像头已连接，使用app id", app_id, "位于hub地址", param1, "端口",param2, "地址", param3)
        end
    end
    if event == usb.EV_DISCONNECT then
        if class == usb.CAMERA then
            log.info("usb摄像头已断开，使用app id", app_id, "位于hub地址", param1, "端口",param2, "地址", param3)
        end
    end
end
-- 注册摄像头回调函数
local function  camera_cb(app_id, event, param)
    if event == usb.EV_NEW_RX then
        if param == 0 then
            log.info("usb摄像头接收数据，位于buffer0 ,数据长度", frame_buff0:used())
            test_cnt = test_cnt + 1
            if test_cnt == 10 then
                log.info("发送1帧数据给电脑")
                send_buff:del()
                send_buff:copy(0, frame_buff0)
                uart.tx(uartid, send_buff)
                
            end
        end
        if param == 1 then
            log.info("usb摄像头接收数据，位于buffer1 ,数据长度", frame_buff1:used())
        end
        return
    end
    if event == usb.EV_CONNECT then
        log.info("usb摄像头已连接，使用app id", app_id, "位于hub端口", param)
        usb_app_id = app_id
        local res, format_num, format_index, frame_num, frame_index, type, fps, w, h
        res, format_num= camera.get_usb_config(usb_app_id, camera.CONF_UVC_FORMAT)
        log.info("总共有", format_num, "种数据流格式")
        for format_index = 1, format_num, 1 do
            res, type, frame_num = camera.get_usb_config(usb_app_id, camera.CONF_UVC_FORMAT, format_index)
            log.info("数据流序号", format_index, "数据流格式", type, "总共有", frame_num, "图像格式")
            for frame_index = 1, frame_num, 1 do
                res, fps, w, h = camera.get_usb_config(usb_app_id, camera.CONF_UVC_RESOLUTION, format_index, frame_index)
                log.info("图像格式序号", frame_index, "图像格式", type, "帧率", fps, "图像宽度", w, "图像高度", h)
            end
        end
        log.info("设置图像格式", frame_type, sensor_w, sensor_h)
        camera.set_usb_config(usb_app_id, camera.CONF_UVC_RESOLUTION, frame_type, sensor_w, sensor_h)
        --camera.set_usb_config(usb_app_id, camera.CONF_UVC_RESOLUTION, 1, 5)
        camera.cache(camera.USB, usb_app_id, frame_buff0, frame_buff1)
        camera.stream(camera.USB, usb_app_id)
        return

    end
    if event == usb.EV_DISCONNECT then
        log.info("usb摄像头 app id", app_id, "已经断开")
        usb_app_id = nil
        return
    end
    if event == usb.EV_RX_ERR then
        log.info("usb摄像头接收数据，发生异常") 
        return
    end
    if event == usb.EV_ERR_STOP then
        log.info("usb摄像头接收数据发生异常，已经停止工作")
        usb.reset_device(0, app_id)
        usb_app_id = nil
        return
    end
end
usb.on(0, usb_cb)
--usb.debug(0, true)
camera.preview(camera.USB, true)
camera.on(camera.USB, "usb_raw", camera_cb)
pm.power(pm.USB, false)		--确保USB外设是掉电状态
usb.mode(0, usb.HOST)		--usb设置成主机模式
pm.power(pm.USB, true)		--USB上电初始化开始工作

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
