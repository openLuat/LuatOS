-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "thermal_imaging"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
local sys = require "sys"

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

local rtos_bsp = rtos.bsp():lower()
if rtos_bsp=="air101" or rtos_bsp=="air103" then
    mcu.setClk(240)
    spi_lcd = spi.deviceSetup(0,pin.PB04,0,0,8,20*1000*1000,spi.MSB,1,0)
    lcd.init("st7735",{port = "device",pin_dc = pin.PB01, pin_pwr = pin.PB00, pin_rst = pin.PB03,direction = 3,w = 160,h = 128,xoffset = 1,yoffset = 2},spi_lcd)
elseif rtos_bsp=="air105" then
    spi_lcd = spi.deviceSetup(5,pin.PC14,0,0,8,48*1000*1000,spi.MSB,1,0)
    lcd.init("st7735",{port = "device",pin_dc = pin.PE08 ,pin_rst = pin.PC12,pin_pwr = pin.PE09,direction = 3,w = 160,h = 128,xoffset = 1,yoffset = 2},spi_lcd)
    lcd.setupBuff()
    lcd.autoFlush(false)
elseif rtos_bsp=="esp32c3" then
    spi_lcd = spi.deviceSetup(2, 7, 0, 0, 8, 40000000, spi.MSB, 1, 0)
    lcd.init("st7735",{port = "device",pin_dc = 6, pin_pwr = 11,pin_rst = 10,direction = 3,w = 160,h = 128,xoffset = 1,yoffset = 2},spi_lcd)
end

lcd.clear(0x0000)

sys.taskInit(function()
    local skew_x = 16
    local skew_y = 16
    local fold = 4
    if mlx90640.init(0,i2c.FAST,mlx90640.FPS4HZ) then
        log.info("mlx90640", "init ok")
        sys.wait(500) -- 稍等片刻
        while 1 do
            local temp_max = {temp = 0,x = 0,y = 0}
            mlx90640.feed() -- 取一帧数据
            local temp,index = mlx90640.max_temp()
            mlx90640.draw2lcd(skew_x, skew_y, fold)
            temp_max.temp = math.floor(temp)
            temp_max.x = (index%32)*fold+skew_x
            temp_max.y = (math.floor (index/32))*fold+skew_y
            if temp_max.x-fold<skew_x then
                temp_max.x = skew_x+fold
            elseif temp_max.x+fold>32*fold+skew_x then
                temp_max.x = 32*fold+skew_x-fold
            end
            if temp_max.y-fold<skew_y then
                temp_max.y = skew_y+fold
            elseif temp_max.y+fold>24*fold+skew_y then
                temp_max.y = 24*fold+skew_y-fold
            end
            lcd.drawCircle(temp_max.x,temp_max.y,fold/2,0x001F)

            lcd.drawStr(temp_max.x,temp_max.y,temp_max.temp)
            if rtos_bsp=="air105" then lcd.flush() end
            sys.wait(100)
        end
    else
        log.info("mlx90640", "init fail")
    end
end)



-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
