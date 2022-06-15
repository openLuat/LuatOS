--[[

特别提醒: 本demo已经有更好的替代品: raw_mode, 请使用新版demo, 效果比本demo好很多.

这是Air105+摄像头, 通过USB传输JPG到上位机显示图片的示例, 速率2fps, 色彩空间 RGB565, 不要期望太高
本demo不需要lcd屏,但lcd的代码暂不可省略

本demo需要V0006, 20220331之后编译的固件版本, 老版本不可用

测试流程:
1. 先选取最新固件, 配合本demo的main.lua及GC032A_InitReg.txt, 两个文件都需要下载到设备
2. 断开USB, 将拨动开关切换到另一端, 切勿带电操作!!!
3. 重新插入USB
4. 打开上位机, 选择正确的COM口, 然后开始读取

-- USB驱动下载 https://doc.openluat.com/wiki/21?wiki_page_id=2070
-- USB驱动与 合宙Cat.1的USB驱动是一致的

上位机下载: https://gitee.com/openLuat/luatos-soc-air105/attach_files
上位机源码: https://gitee.com/openLuat/luatos-soc-air105 C#写的, 就能用, 勿生产


]]

PROJECT = "usbcamera"
VERSION = "1.0.0"

local sys = require "sys"

if wdt then
    wdt.init(15000)--初始化watchdog设置为15s
    sys.timerLoopStart(wdt.feed, 10000)--10s喂一次狗
end

spi_lcd = spi.deviceSetup(5,pin.PC14,0,0,8,48*1000*1000,spi.MSB,1,1)
log.info("lcd.init",
lcd.init("st7789",{port = "device",pin_dc = pin.PE08 ,pin_rst = pin.PC12,pin_pwr = pin.PE09,direction = 0,w = 240,h = 320,xoffset = 0,yoffset = 0},spi_lcd))

--GC032A输出rgb图像初始化命令
local GC032A_InitReg =
{
	zbar_scan = 0,--是否为扫码
    draw_lcd = 0,--是否向lcd输出
    i2c_id = 0,
	i2c_addr = 0x21,
    pwm_id = 5;
    pwm_period  = 12*1000*1000,
    pwm_pulse = 0,
	sensor_width = 640,
	sensor_height = 480,
    color_bit = 16,
	init_cmd ="/luadb/GC032A_InitReg.txt"--此方法将初始化指令写在外部文件,支持使用 # 进行注释
}

local uartid = uart.VUART_0 -- 根据实际设备选取不同的uartid
--初始化
local result = uart.setup(
    uartid,--串口id
    115200,--波特率
    8,--数据位
    1--停止位
)

local camera_pwdn = gpio.setup(pin.PD06, 1, gpio.PULLUP) -- PD06 camera_pwdn引脚
local camera_rst = gpio.setup(pin.PD07, 1, gpio.PULLUP) -- PD07 camera_rst引脚

camera_rst(0)

-- 拍照, 自然就是RGB输出了
local camera_id = camera.init(GC032A_InitReg)--屏幕输出rgb图像

log.info("摄像头启动")
camera.start(camera_id)--开始指定的camera
log.info("摄像头启动完成")

usbapp.start(0)

camera.on(0, "scanned", function()
    sys.publish("scanned")
end)

sys.taskInit(function()
    
    while 1 do
            -- 稍微等待一下
            sys.wait(100)
            log.debug("摄像头捕获图像")
            -- 删除老的图片,避免重复显示
            os.remove("/temp.jpg")
            camera.capture(camera_id, "/temp.jpg", 1)
            sys.waitUntil("scanned", 1000)
            local f = io.open("/temp.jpg", "r")
            local data
            if f then -- 若文件存在, 必然能打开并读取, 否则肯定拍照失败了
                data = f:read("*a")
                log.info("fs", #data)
                f:close()

                -- 请使用上位机读取
                uart.write(uart.VUART_0, "Air105 USB JPG " .. tostring(#data) .. "\r\n")
                uart.write(uart.VUART_0, data)
            end
    end
    
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
