

PROJECT = "camerademo"
VERSION = "1.0.0"

sys = require("sys")

--[[
-- LCD接法示例, 以Air105开发板的HSPI为例
LCD管脚       Air105管脚
GND          GND
VCC          3.3V
SCL          (PC15/HSPI_SCK)
SDA          (PC13/HSPI_MOSI)
RES          (PC12/HSPI_MISO)
DC           (PE08) --开发板上的U3_RX
CS           (PC14/HSPI_CS)
BL           (PE09) --开发板上的U3_TX


提示:
1. 只使用SPI的时钟线(SCK)和数据输出线(MOSI), 其他均为GPIO脚
2. 数据输入(MISO)和片选(CS), 虽然是SPI, 但已复用为GPIO, 并非固定,是可以自由修改成其他脚
]]

if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

spi_lcd = spi.deviceSetup(5,pin.PC14,0,0,8,48*1000*1000,spi.MSB,1,1)

-- log.info("lcd.init",
-- lcd.init("st7735s",{port = "device",pin_dc = pin.PE08 ,pin_rst = pin.PC12,pin_pwr = pin.PE09,direction = 2,w = 160,h = 80,xoffset = 1,yoffset = 26},spi_lcd))

log.info("lcd.init",
lcd.init("st7789",{port = "device",pin_dc = pin.PE08 ,pin_rst = pin.PC12,pin_pwr = pin.PE09,direction = 0,w = 240,h = 320,xoffset = 0,yoffset = 0},spi_lcd))

-- log.info("lcd.init",
-- lcd.init("st7735",{port = "device",pin_dc = pin.PE08 ,pin_rst = pin.PC12,pin_pwr = pin.PE09,direction = 0,w = 128,h = 160,xoffset = 2,yoffset = 1},spi_lcd))

-- log.info("lcd.init",
-- lcd.init("gc9306x",{port = "device",pin_dc = pin.PE08 ,pin_rst = pin.PC12,pin_pwr = pin.PE09,direction = 0,w = 240,h = 320,xoffset = 0,yoffset = 0},spi_lcd))

--GC032A输出rgb图像初始化命令
local GC032A_InitReg =
{
	zbar_scan = 0,--是否为扫码
    draw_lcd = 1,--是否向lcd输出
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

--GC032A输出灰度图像初始化命令
local GC032A_InitReg_Gray =
{
	zbar_scan = 1,--是否为扫码
    draw_lcd = 1,--是否向lcd输出
    i2c_id = 0,
	i2c_addr = 0x21,
    pwm_id = 5;
    pwm_period  = 24*1000*1000,
    pwm_pulse = 0,
	sensor_width = 640,
	sensor_height = 480,
    color_bit = 16,
	init_cmd ="/luadb/GC032A_InitReg_Gray.txt"--此方法将初始化指令写在外部文件,支持使用 # 进行注释
}



--注册摄像头事件回调
camera.on(0, "scanned", function(id, str)
    if type(str) == 'string' then
        log.info("扫码结果", str)
    else
        log.info("拍照结果", str)

    end
end)

local camera_pwdn = gpio.setup(pin.PD06, 1, gpio.PULLUP) -- PD06 camera_pwdn引脚
local camera_rst = gpio.setup(pin.PD07, 1, gpio.PULLUP) -- PD07 camera_rst引脚

sys.taskInit(function()
    camera_rst(0)

    --下面两行只开一行！一个是屏幕输出rgb图像,一个是屏幕输出灰度图像并扫码
    -- local camera_id = camera.init(GC032A_InitReg)--屏幕输出rgb图像
    local camera_id = camera.init(GC032A_InitReg_Gray)--屏幕输出灰度图像并扫码


    log.info("摄像头启动")
    camera.start(camera_id)--开始指定的camera
    sys.wait(2000)
    -- log.info("摄像头停止")
    -- camera.stop(camera_id)--停止指定的camera
    -- sys.wait(2000)
    -- log.info("摄像头启动")
    -- camera.start(camera_id)--开始指定的camera
    -- sys.wait(2000)
    -- log.info("摄像头关闭")
    -- camera_rst(1)
    -- camera.close(camera_id)
    --下面的功能必须有支持camera.close的固件才能打开
    -- log.info("摄像头重新初始化")
    -- camera_rst(0)
    -- camera_id = camera.init(GC032A_InitReg_Gray)--屏幕输出灰度图像并扫码
    -- log.info("摄像头启动")
    -- camera.start(camera_id)--开始指定的camera
    --下面的功能必须有支持拍照的固件才能打开
    -- camera_rst(0)
    -- camera_id = camera.init(GC032A_InitReg)--屏幕输出灰度图像并扫码
    -- log.info("摄像头启动")
    -- camera.start(camera_id)--开始指定的camera
    -- sys.wait(2000)
    -- log.debug("摄像头捕获图像")
    -- camera.capture(camera_id, "/temp.jpg", 1)
    -- sys.wait(2000)
    -- local f = io.open("/temp.jpg", "r")
    -- local data
    -- if f then
    --     data = f:read("*a")
    --     log.info("fs", #data)
    --     f:close()
    -- end
    -- local uartid = 2 -- 根据实际设备选取不同的uartid

    -- --初始化
    -- local result = uart.setup(
    --     uartid,--串口id
    --     115200,--波特率
    --     8,--数据位
    --     1--停止位
    -- )
    -- uart.write(uartid, data) --找个能保存数据的串口工具保存成文件就能在电脑上看了
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
