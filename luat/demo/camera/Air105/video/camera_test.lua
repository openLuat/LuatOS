--上位机源码: https://gitee.com/openLuat/luatos-soc-air105 C#写的, 就能用, 勿生产
--编译好的工具：https://gitee.com/openLuat/luatos-soc-air105/attach_files
local GC032A_InitReg =
{
	zbar_scan = 0,--是否为扫码, 扫码模式会显示灰度图像!!!
    draw_lcd = 0,--是否向lcd输出, 若没有接lcd显示屏就不用设置为1
    i2c_id = 0,
	i2c_addr = 0x21,
    pwm_id = 5;
    pwm_period  = 24*1000*1000, -- 摄像头的时钟线的波特率
    pwm_pulse = 0,
	sensor_width = 640, -- GC032A摄像头的实际分辨率是30w,但内存不足,实际显示居中的1/4图像
	sensor_height = 480,
    color_bit = 16, -- 颜色空间是 RGB565
	init_cmd = "/luadb/GC032A_InitReg.txt"--此方法将初始化指令写在外部文件,支持使用 # 进行注释

}

local camera_pwdn = gpio.setup(pin.PD06, 1, gpio.PULLUP) -- PD06 camera_pwdn引脚
local camera_rst = gpio.setup(pin.PD07, 1, gpio.PULLUP) -- PD07 camera_rst引脚

usbapp.start(0)

sys.taskInit(function()
	camera_rst(0)
    uart.setup(
        uart.VUART_0,-- USB虚拟串口id
        115200,--波特率
        8,--数据位
        1--停止位
    )
	-- 拍照, 自然就是RGB输出了
	local camera_id = camera.init(GC032A_InitReg)--屏幕输出rgb图像

	log.info("摄像头启动")
    camera.video(camera_id, 320, 240, uart.VUART_0)
	log.info("摄像头启动完成")
end)

-- 以下是扫码的回调, 仅当zbar_scan=1时会有回调
camera.on(0, "scanned", function(id, str)
    if type(str) == 'string' then
        log.info("扫码结果", str)
        log.info(rtos.meminfo("sys"))
        -- air105每次扫码仅需200ms, 当目标一维码或二维码持续被识别, 本函数会反复触发
        -- 鉴于某些场景需要间隔时间输出, 下列代码就是演示间隔输出
        -- if mcu.ticks() - tick < 1000 then
        --     return
        -- end
        -- tick_scan = mcu.ticks()
        -- 输出内容可以经过加工后输出, 例如带上换行(回车键)
        usbapp.vhid_upload(0, str.."\r\n")
    elseif str == true then
    	log.info("拍照完成")
    elseif str == false then
        log.error("摄像头没有数据")
    end
end)
