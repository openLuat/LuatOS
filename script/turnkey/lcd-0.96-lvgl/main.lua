PROJECT="LVGL"
VERSION="0.0.1"
sys=require"sys"

device = require"device"
key = require"key"
animation = require"animation"

-- HSPI 即 SPI5, 最高96M, 部分屏不支持, 所以这里写48M
spi_lcd = spi.deviceSetup(device.spi,device.spiCS,0,0,8,device.spiSpeed,spi.MSB,1,1)
lcd.init("st7735v",{port = "device",pin_dc=device.lcdDC,pin_rst=device.lcdRST,pin_pwr=device.lcdBL,direction = 2,w = 80,h = 160,xoffset = 24,yoffset = 0},spi_lcd)
lcd.invoff()--这个屏可能需要反显

log.info("lvgl", lvgl.init())

scr = lvgl.obj_create(nil, nil)

if device.useFont then
    local font_16 = lvgl.font_load("/luadb/16_test_fonts.bin")
    if not font_16 then
        log.info("font error","font not found")
    else
        lvgl.obj_set_style_local_text_font(scr, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, font_16)
    end
end

home = require"home"
about = require"about"

lvgl.scr_load(scr)


home.show()
key.setCb(home.keyCb)


sys.run()
