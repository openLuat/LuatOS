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
SPI0
SPI0_SCK               (PB2)
SPI0_MISO              (PB3)
SPI0_MOSI              (PB5)
]]

--添加硬狗防止程序卡死
if wdt then
    wdt.init(15000)--初始化watchdog设置为15s
    sys.timerLoopStart(wdt.feed, 10000)--10s喂一次狗
end

log.info("main", "ask for help", "https://wiki.luatos.com/")

spi_lcd = spi.deviceSetup(0,pin.PB04,0,0,8,20*1000*1000,spi.MSB,1,1)

-- log.info("lcd.init",
-- lcd.init("gc9a01",{port = "device",pin_dc = pin.PB01, pin_pwr = pin.PB00,pin_rst = pin.PB03,direction = 0,w = 240,h = 320,xoffset = 0,yoffset = 0},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7789",{port = "device",pin_dc = pin.PB01, pin_pwr = pin.PB00,pin_rst = pin.PB03,direction = 0,w = 240,h = 240,xoffset = 0,yoffset = 0},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7789",{port = "device",pin_dc = pin.PB01, pin_pwr = pin.PB00,pin_rst = pin.PB03,direction = 3,w = 240,h = 240,xoffset = 80,yoffset = 0},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7789",{port = "device",pin_dc = pin.PB01, pin_pwr = pin.PB00,pin_rst = pin.PB03,direction = 3,w = 320,h = 240,xoffset = 0,yoffset = 0},spi_lcd))
log.info("lcd.init",
lcd.init("st7735",{port = "device",pin_dc = pin.PB01, pin_pwr = pin.PB00,pin_rst = pin.PB03,direction = 0,w = 128,h = 160,xoffset = 0,yoffset = 0},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7735v",{port = "device",pin_dc = pin.PB01, pin_pwr = pin.PB00,pin_rst = pin.PB03,direction = 1,w = 160,h = 80,xoffset = 0,yoffset = 24},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7735s",{port = "device",pin_dc = pin.PB01, pin_pwr = pin.PB00,pin_rst = pin.PB03,direction = 2,w = 160,h = 80,xoffset = 1,yoffset = 26},spi_lcd))

sys.taskInit(function()
    sys.wait(100)
    log.info("lvgl", lvgl.init())
    -- lvgl.disp_set_bg_color(nil, lvgl.color_hex(0x999999))
    if lvgl.theme_set_act then
        -- 切换主题
        -- lvgl.theme_set_act("default")
        -- lvgl.theme_set_act("mono")
        lvgl.theme_set_act("empty")
        -- lvgl.theme_set_act("material_light")
        -- lvgl.theme_set_act("material_dark")
        -- lvgl.theme_set_act("material_no_transition")
        -- lvgl.theme_set_act("material_no_focus")
    end
    local scr = lvgl.obj_create()
    local btn = lvgl.btn_create(scr)
    lvgl.obj_align(btn, lvgl.scr_act(), lvgl.ALIGN_CENTER, 0, 0)
    local label = lvgl.label_create(btn)
    lvgl.label_set_text(label, "LuatOS!")
    local font = lvgl.font_load("/luadb/16_test_fonts.bin")
    lvgl.obj_set_style_local_text_font(scr, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, font)

    lvgl.scr_load(scr)
    while 1 do
        sys.wait(1000)
        lvgl.font_free(font)
        local font = lvgl.font_load("/luadb/20_test_fonts.bin")
        lvgl.obj_set_style_local_text_font(scr, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, font)
        sys.wait(1000)
        lvgl.font_free(font)
        local font = lvgl.font_load("/luadb/16_test_fonts.bin")
        lvgl.obj_set_style_local_text_font(scr, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, font)
    end
end)

sys.taskInit(function()
    uart.setup(1, 115200)
    uart.on (1, "receive", function(id, len)
        local data = uart.read(id, 512)
        if data then
            log.info("uart", "recv", #data, data:toHex())
            -- 演示一下回显
            uart.write(1, data)
        end
    end)
    -- 演示定时发送数据
    while 1 do
        log.info("uart", "repeat uart write OK")
        sys.wait(500)
        uart.write(1, "OK\r\n")
    end
end)

-- 演示通过topic接收需要发送的数据
sys.subscribe("UART1_WRITE", function (data)
    uart.write(1, data)
end)

-- 演示fdb的使用
if fdb then
    sys.taskInit(function()
        fdb.kvdb_init("onchip_flash")
        local count = 1
        while 1 do
            sys.wait(1000)
            fdb.kv_set("my_int", count)
            count = count + 1
            log.info("fdb", "my_int", fdb.kv_get("my_int"))
        end
    end)
else
    log.info("fdb", "fdb lib not found")
end

-- sys.taskInit(function()
--     while 1 do
--         log.info("help", "https://wiki.luatos.com")
--         sys.wait(500)
--     end
-- end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!


