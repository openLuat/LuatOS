--- 模块功能：lvgldemo
-- @module lvgl
-- @author Dozingfiretruck
-- @release 2021.01.25

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "lvgldemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

--[[
-- LCD接法示例, 以Air105开发板的HSPI为例
LCD管脚       Air105管脚
GND          GND
VCC          3.3V
SCL          (PC15/SPI0_SCK)
SDA          (PC13/SPI0_MOSI)
RES          (PC12)
DC           (PE8)
CS           (PC14)
BL           (PE9)


提示:
1. 只使用SPI的时钟线(SCK)和数据输出线(MOSI), 其他均为GPIO脚
2. 数据输入(MISO)和片选(CS), 虽然是SPI, 但已复用为GPIO, 并非固定,是可以自由修改成其他脚
]]

--添加硬狗防止程序卡死
wdt.init(9000)--初始化watchdog设置为9s
sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗

log.info("hello luatos")

spi_lcd = spi.deviceSetup(5,pin.PC14,0,0,8,96*1000*1000,spi.MSB,1,1)

-- log.info("lcd.init",
-- lcd.init("gc9a01",{port = "device",pin_dc = pin.PE8,pin_rst = pin.PC12,pin_pwr = pin.PE9,direction = 0,w = 240,h = 320,xoffset = 0,yoffset = 0},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7789",{port = "device",pin_dc = pin.PE8, pin_rst = pin.PC12,pin_pwr = pin.PE9,direction = 0,w = 240,h = 240,xoffset = 0,yoffset = 0},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7789",{port = "device",pin_dc = pin.PE8, pin_rst = pin.PC12,pin_pwr = pin.PE9,direction = 3,w = 240,h = 240,xoffset = 80,yoffset = 0},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7789",{port = "device",pin_dc = pin.PE8, pin_rst = pin.PC12,pin_pwr = pin.PE9,direction = 3,w = 320,h = 240,xoffset = 0,yoffset = 0},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7789",{port = "device",pin_dc = pin.PE8, pin_rst = pin.PC12,pin_pwr = pin.PE9,direction = 0,w = 240,h = 320,xoffset = 0,yoffset = 0},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7735",{port = "device",pin_dc = pin.PE8, pin_rst = pin.PC12,pin_pwr = pin.PE9,direction = 0,w = 128,h = 160,xoffset = 2,yoffset = 1},spi_lcd))

--[[ 此为合宙售卖的0.96寸TFT LCD LCD 分辨率:160X80 屏幕ic:st7735s 购买地址:https://item.taobao.com/item.htm?id=661054472686]]
--lcd.init("st7735v",{port = "device",pin_dc = pin.PE08, pin_pwr = pin.PE09, pin_rst = pin.PC12,direction = 1,w = 160,h = 80,xoffset = 0,yoffset = 24},spi_lcd)
--如果显示颜色相反，请解开下面一行的注释，关闭反色
--lcd.invoff()
--如果显示依旧不正常，可以尝试老版本的板子的驱动
--lcd.init("st7735s",{port = "device",pin_dc = pin.PE08, pin_pwr = pin.PE09, pin_rst = pin.PC12,direction = 2,w = 160,h = 80,xoffset = 0,yoffset = 0},spi_lcd)

-- log.info("lcd.init",
-- lcd.init("st7735s",{port = "device",pin_dc = pin.PE8,pin_rst = pin.PC12,pin_pwr = pin.PE9,direction = 2,w = 160,h = 80,xoffset = 1,yoffset = 26},spi_lcd))
log.info("lcd.init",
lcd.init("gc9306x",{port = "device",pin_dc = pin.PE8,pin_rst = pin.PC12,pin_pwr = pin.PE9,direction = 0,w = 240,h = 320,xoffset = 0,yoffset = 0},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("ili9341",{port = "device",pin_dc = pin.PE8, pin_rst = pin.PC12,pin_pwr = pin.PE9,direction = 0,w = 240,h = 320,xoffset = 0,yoffset = 0},spi_lcd))


log.info("lvgl", lvgl.init())
local scr = lvgl.obj_create(nil, nil)
local btn = lvgl.btn_create(scr)

local font = lvgl.font_get("opposans_m_16") --根据你自己的固件编译了哪个字体就用哪个字体


lvgl.obj_align(btn, lvgl.scr_act(), lvgl.ALIGN_CENTER, 0, 0)
local label = lvgl.label_create(btn)

--有中文字体的才能显示中文
--lvgl.label_set_text(label, "LuatOS!")
lvgl.label_set_text(label, "你好!")
lvgl.scr_load(scr)
--以下是加载字体方法，二选一
--方法一
lvgl.obj_set_style_local_text_font(lvgl.scr_act(), lvgl.OBJ_PART_MAIN, lvgl.STATE_DEFAULT, font)
--方法二
--local style = lvgl.style_create()
--lvgl.style_set_text_font(style, lvgl.STATE_DEFAULT, font)
--lvgl.obj_add_style(lvgl.scr_act(),lvgl.OBJ_PART_MAIN, style)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!


