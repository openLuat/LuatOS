local testlvgl = {}

local sys = require "sys"

--spi编号,配置,lcd配置请按实际情况修改！
--使用前请先先看详细阅读wiki文档 https://wiki.luatos.com/api/lcd.html

spi_lcd = spi.deviceSetup(2,7,0,0,8,40000000,spi.MSB,1,1)
log.info("lcd.init",
lcd.init("st7789",{port = "device",pin_dc = 6, pin_rst = 10,direction = 0,w = 240,h = 240,xoffset = 0,yoffset = 0},spi_lcd))

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

return testlvgl