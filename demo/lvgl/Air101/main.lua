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
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

-- UI带屏的项目一般不需要低功耗了吧, 设置到最高性能
if mcu and (rtos.bsp():lower() == "air101" or rtos.bsp():lower() == "air103") then
    mcu.setClk(240)
end
log.info("main", "ask for help", "https://wiki.luatos.com/")

spi_lcd = spi.deviceSetup(0,pin.PB04,0,0,8,20*1000*1000,spi.MSB,1,1)

--[[ 此为合宙售卖的2.4寸TFT LCD 分辨率:240X320 屏幕ic:GC9306 购买地址:https://item.taobao.com/item.htm?spm=a1z10.5-c.w4002-24045920841.39.6c2275a1Pa8F9o&id=655959696358]]
-- lcd.init("gc9a01",{port = "device",pin_dc = pin.PB01, pin_pwr = pin.PB00,pin_rst = pin.PB03,direction = 0,w = 240,h = 320,xoffset = 0,yoffset = 0},spi_lcd)

--[[ 此为合宙售卖的1.8寸TFT LCD LCD 分辨率:128X160 屏幕ic:st7735 购买地址:https://item.taobao.com/item.htm?spm=a1z10.5-c.w4002-24045920841.19.6c2275a1Pa8F9o&id=560176729178]]
-- lcd.init("st7735",{port = "device",pin_dc = pin.PB01, pin_pwr = pin.PB00,pin_rst = pin.PB03,direction = 0,w = 128,h = 160,xoffset = 2,yoffset = 1},spi_lcd)

--[[ 此为合宙售卖的1.54寸TFT LCD LCD 分辨率:240X240 屏幕ic:st7789 购买地址:https://item.taobao.com/item.htm?spm=a1z10.5-c.w4002-24045920841.20.391445d5Ql4uJl&id=659456700222]]
-- lcd.init("st7789",{port = "device",pin_dc = pin.PB01, pin_pwr = pin.PB00,pin_rst = pin.PB03,direction = 0,w = 240,h = 240,xoffset = 0,yoffset = 0},spi_lcd)

--[[ 此为合宙售卖的0.96寸TFT LCD LCD 分辨率:160X80 屏幕ic:st7735s 购买地址:https://item.taobao.com/item.htm?id=661054472686]]
lcd.init("st7735v",{port = "device",pin_dc = pin.PB01, pin_pwr = pin.PB00,pin_rst = pin.PB03,direction = 1,w = 160,h = 80,xoffset = 0,yoffset = 24},spi_lcd)
--如果显示颜色相反，请解开下面一行的注释，关闭反色
--lcd.invoff()
--如果显示依旧不正常，可以尝试老版本的板子的驱动
--lcd.init("st7735s",{port = "device",pin_dc = pin.PB01, pin_pwr = pin.PB00,pin_rst = pin.PB03,direction = 2,w = 160,h = 80,xoffset = 1,yoffset = 26},spi_lcd)

sys.taskInit(function()
    sys.wait(100)
    log.info("lvgl", lvgl.init())
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
    local font_16 = lvgl.font_load("/luadb/16_test_fonts.bin")
    local font_20 = lvgl.font_load("/luadb/20_test_fonts.bin")
    if font_16 == nil or font_20 == nil then
        log.warn("lvgl", "pls add font bins")
        return
    end
    lvgl.obj_set_style_local_text_font(scr, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, font_16)

    local qrcode = nil
    if lvgl.qrcode_create then
        qrcode = lvgl.qrcode_create(scr, 100)
    else
        log.warn("lvgl", "no qrcode for lvgl found")
    end

    lvgl.scr_load(scr)

    local qrcode_count = 1
    local qrcode_cnt = "https://qq.com/" .. tostring(qrcode_count)

    while 1 do
        qrcode_count = 1
        sys.wait(1000)
        lvgl.obj_set_style_local_text_font(scr, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, font_20)
        sys.wait(1000)
        lvgl.obj_set_style_local_text_font(scr, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, font_16)
        sys.wait(1000)
        if qrcode then
            qrcode_cnt = "https://qq.com/" .. tostring(qrcode_count)
            --lvgl.qrcode_update(qrcode, qrcode_cnt)
        end
        log.info("lvgl", "update complete")
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


