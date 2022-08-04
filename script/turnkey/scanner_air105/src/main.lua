

PROJECT = "scanner"
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
    wdt.init(15000)--初始化watchdog设置为15s
    sys.timerLoopStart(wdt.feed, 10000)--10s喂一次狗
end

spi_lcd = spi.deviceSetup(5,pin.PC14,0,0,8,48*1000*1000,spi.MSB,1,1)

-- log.info("lcd.init",
-- lcd.init("st7735s",{port = "device",pin_dc = pin.PE08 ,pin_rst = pin.PC12,pin_pwr = pin.PE09,direction = 2,w = 160,h = 80,xoffset = 1,yoffset = 26},spi_lcd))

-- log.info("lcd.init",
-- lcd.init("st7789",{port = "device",pin_dc = pin.PE08 ,pin_rst = pin.PC12,pin_pwr = pin.PE09,direction = 0,w = 240,h = 320,xoffset = 0,yoffset = 0},spi_lcd))

log.info("lcd.init",
lcd.init("st7735",{port = "device",pin_dc = pin.PE08 ,pin_rst = pin.PC12,pin_pwr = pin.PE09,direction = 0,w = 128,h = 160,xoffset = 0,yoffset = 0},spi_lcd))

-- log.info("lcd.init",
-- lcd.init("gc9306x",{port = "device",pin_dc = pin.PE08 ,pin_rst = pin.PC12,pin_pwr = pin.PE09,direction = 0,w = 240,h = 320,xoffset = 0,yoffset = 0},spi_lcd))

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
local tick_scan = 0

camera.on(0, "scanned", function(id, str)
    if type(str) == 'string' then
        log.info("扫码结果", str)
        -- air105每次扫码仅需200ms, 当目标一维码或二维码持续被识别, 本函数会反复触发
        -- 鉴于某些场景需要间隔时间输出, 下列代码就是演示间隔输出
        -- if mcu.ticks() - tick < 1000 then
        --     return
        -- end
        -- tick_scan = mcu.ticks()
        -- 输出内容可以经过加工后输出, 例如带上换行(回车键)
        usbapp.vhid_upload(0, str.."\r\n")
        
    elseif str == false then
        log.error("摄像头没有数据")
    end
end)

local camera_pwdn = gpio.setup(pin.PD06, 1, gpio.PULLUP) -- PD06 camera_pwdn引脚
local camera_rst = gpio.setup(pin.PD07, 1, gpio.PULLUP) -- PD07 camera_rst引脚

usbapp.start(0)

sys.taskInit(function()
    camera_rst(0)
    local camera_id = camera.init(GC032A_InitReg_Gray)--屏幕输出灰度图像并扫码

    log.info("摄像头启动")
    camera.start(camera_id)--开始指定的camera
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
