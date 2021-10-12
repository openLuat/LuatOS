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

--添加硬狗防止程序卡死
wdt.init(15000)--初始化watchdog设置为15s
sys.timerLoopStart(wdt.feed, 10000)--10s喂一次狗

log.info("hello luatos")

local spi_lcd = spi.device_setup(0,20,0,0,8,2000000,spi.MSB,1,1)
log.info("lcd.init",
lcd.init("st7735s",{port = "device",pin_dc = 17, pin_pwr = 7,pin_rst = 19,direction = 2,w = 160,h = 80,xoffset = 1,yoffset = 26},spi_lcd))

log.info("lvgl", lvgl.init())
lvgl.disp_set_bg_color(nil, 0xFFFFFF)
local scr = lvgl.obj_create(nil, nil)
local btn = lvgl.btn_create(scr)
lvgl.obj_align(btn, lvgl.scr_act(), lvgl.ALIGN_CENTER, 0, 0)
local label = lvgl.label_create(btn)
lvgl.label_set_text(label, "LuatOS!")
lvgl.scr_load(scr)

sys.taskInit(function()
    while 1 do
        sys.wait(500)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!


