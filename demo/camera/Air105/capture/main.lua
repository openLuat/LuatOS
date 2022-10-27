

PROJECT = "camerademo"
VERSION = "1.0.0"

sys = require("sys")

--[[
-- LCD接法示例, 以Air105开发板的HSPI(SPI5)为例
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

-- local uartid = 1 -- 根据实际设备选取不同的uartid
-- --初始化
-- local result = uart.setup(
--     uartid,--串口id
--     115200,--波特率
--     8,--数据位
--     1--停止位
-- )

local camera_pwdn = gpio.setup(pin.PD06, 1, gpio.PULLUP) -- PD06 camera_pwdn引脚
local camera_rst = gpio.setup(pin.PD07, 1, gpio.PULLUP) -- PD07 camera_rst引脚

camera_rst(0)

-- 拍照, 自然就是RGB输出了
local camera_id = camera.init(GC032A_InitReg)--屏幕输出rgb图像

log.info("摄像头启动")
camera.start(camera_id)--开始指定的camera

gpio.setup(pin.PA10, function()
    sys.publish("CAPTURE", true)
end, gpio.PULLUP,gpio.FALLING)

sys.taskInit(function()

    local spiId = 2
    local result = spi.setup(
        spiId,--串口id
        255, -- 不使用默认CS脚
        0,--CPHA
        0,--CPOL
        8,--数据宽度
        400*1000  -- 初始化时使用较低的频率
    )
    local TF_CS = pin.PB3
    gpio.setup(TF_CS, 1)
    --fatfs.debug(1) -- 若挂载失败,可以尝试打开调试信息,查找原因
    fatfs.mount("SD", spiId, TF_CS, 24000000)
    local data, err = fatfs.getfree("SD")
    if data then
        log.info("fatfs", "getfree", json.encode(data))
    else
        log.info("fatfs", "err", err)
    end

    while 1 do
        result, data = sys.waitUntil("CAPTURE", 30000)
        if result==true and data==true then
            log.debug("摄像头捕获图像")
            os.remove("/sd/temp.jpg")
            camera.capture(camera_id, "/sd/temp.jpg", 1)

            -- camera.capture(camera_id, "/temp.jpg", 1)
            -- sys.wait(2000)
            -- local f = io.open("/temp.jpg", "r")
            -- local data
            -- if f then
            --     data = f:read("*a")
            --     log.info("fs", #data)
            --     f:close()
            -- end

            -- uart.write(uartid, data) --找个能保存数据的串口工具保存成文件就能在电脑上看了, 格式为JPG
        end
    end

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
