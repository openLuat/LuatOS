--- 模块功能：lvgldemo
-- @module lvgl
-- @author Dozingfiretruck
-- @release 2021.01.25

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "lvgldemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

log.info("hello luatos")
spi.setup(0, 20, 0, 0, 8, 40 * 1000 * 1000, spi.MSB, 1, 1)
-- log.info("lcd.init", lcd.init("st7789",{port = 0,pin_cs = 20,pin_dc = 23, pin_pwr = 7,pin_rst = 22,direction = 0,w = 240,h = 320}))
log.info("lcd.init", lcd.init("st7735",{port = 0,pin_cs = 20,pin_dc = 23, pin_pwr = 7,pin_rst = 22,direction = 0,w = 128,h = 160}))
log.info("lvgl", lvgl.init())
lvgl.disp_set_bg_color(nil, 0xFFFFFF)
local scr = lvgl.obj_create(nil, nil)
local btn = lvgl.btn_create(scr)
local btn2 = lvgl.btn_create(scr)
lvgl.obj_align(btn, lvgl.scr_act(), lvgl.ALIGN_CENTER, 0, 0)
lvgl.obj_align(btn2, lvgl.scr_act(), lvgl.ALIGN_CENTER, 0, 50)
local label = lvgl.label_create(btn)
local label2 = lvgl.label_create(btn2)
lvgl.label_set_text(label, "LuatOS!")
lvgl.label_set_text(label2, "Hi")
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


