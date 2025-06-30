-- local LCD_GPIO = gpio.setup(141, 1, gpio.PULLUP)
-- local LCD_RST = gpio.setup(164, 1, gpio.PULLUP)

-- --[[
-- -- LCD接法示例
-- LCD管脚       Air780E管脚    Air101/Air103管脚   Air105管脚         
-- GND          GND            GND                 GND                 
-- VCC          3.3V           3.3V                3.3V                
-- SCL          (GPIO11)       (PB02/SPI0_SCK)     (PC15/HSPI_SCK)     
-- SDA          (GPIO09)       (PB05/SPI0_MOSI)    (PC13/HSPI_MOSI)    
-- RES          (GPIO01)       (PB03/GPIO19)       (PC12/HSPI_MISO)    
-- DC           (GPIO10)       (PB01/GPIO17)       (PE08)              
-- CS           (GPIO08)       (PB04/GPIO20)       (PC14/HSPI_CS)      
-- BL(可以不接)  (GPIO22)       (PB00/GPIO16)       (PE09)              


-- 提示:
-- 1. 只使用SPI的时钟线(SCK)和数据输出线(MOSI), 其他均为GPIO脚
-- 2. 数据输入(MISO)和片选(CS), 虽然是SPI, 但已复用为GPIO, 并非固定,是可以自由修改成其他脚
-- 3. 若使用多个SPI设备, 那么RES/CS请选用非SPI功能脚
-- 4. BL可以不接的, 若使用Air10x屏幕扩展板,对准排针插上即可
-- ]]

-- -- 添加硬狗防止程序卡死
-- if wdt then
--     wdt.init(9000) -- 初始化watchdog设置为9s
--     sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
-- end






