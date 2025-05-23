--- 模块功能：lvglDemo
-- @module lvglDemo
-- @release 2025.03.17
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "lvglDemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

pm.ioVol(pm.IOVOL_ALL_GPIO, 3300) -- 设置GPIO电平
-- 添加硬狗防止程序卡死
if wdt then
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end

-- 根据不同的BSP返回不同的值
function lcd_pin()
    return lcd.HWID_0, 36, 0xff, 0xff, 160 -- 注意:EC718P有硬件lcd驱动接口, 无需使用spi,当然spi驱动也支持
    -- return 0,1,10,8,22
end

local spi_id, pin_reset, pin_dc, pin_cs, bl = lcd_pin()

if spi_id ~= lcd.HWID_0 then
    spi_lcd = spi.deviceSetup(spi_id, pin_cs, 0, 0, 8, 20 * 1000 * 1000, spi.MSB, 1, 0)
    port = "device"
else
    port = spi_id
end

-- mcu.altfun(mcu.I2C, 1, 19, 2, 0)
-- mcu.altfun(mcu.I2C, 1, 20, 2, 0)

-- lcd_use_buff = true

sys.taskInit(function()
    sys.wait(500) 
    -- gpio.setup(147, 1, gpio.PULLUP)
    -- gpio.setup(153, 1, gpio.PULLUP)
    gpio.setup(164, 1, gpio.PULLUP)

    gpio.setup(141, 1, gpio.PULLUP)
    sys.wait(2000)
    -- -- lcd.init("jd9261t_inited",{port = port,pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 0,w = 480,h = 480,xoffset = 0,yoffset = 0,interface_mode=lcd.QSPI_MODE,bus_speed=70000000,flush_rate=658,vbp=19,vfp=108,vs=2})
    lcd.init("st7796",{port = port,pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 0,w = 320,h = 480,xoffset = 0,yoffset = 0},spi_lcd)
	
    gpio.setup(160, 1, gpio.PULLUP) -- 单独拉高背光

    -- 开启缓冲区, 刷屏速度回加快, 但也消耗2倍屏幕分辨率的内存
    if lcd_use_buff then
        lcd.setupBuff(nil, true) -- 使用sys内存, 只需要选一种
        -- lcd.setupBuff()       -- 使用lua内存, 只需要选一种
        lcd.autoFlush(false)
    end

    if tp then
        log.info("tp", "tp init")
        local function tp_callBack(tp_device,tp_data)
            sys.publish("TP",tp_device,tp_data)
            log.info("TP",tp_data[1].x,tp_data[1].y,tp_data[1].event)
        end

        -- local softI2C = i2c.createSoft(20, 21, 2) -- SCL, SDA
        -- local softI2C = i2c.createSoft(28, 26, 1) -- SCL, SDA
        -- tp_device = tp.init("jd9261t_inited",{port=softI2C, pin_rst = 27,pin_int = gpio.CHG_DET,w = width,h = height,int_type=gpio.FALLING, refresh_rate = 60},tp_callBack)

        -- tp_device = tp.init("jd9261t_inited",{port=0, pin_rst = 20,pin_int = gpio.WAKEUP0,w = width,h = height,int_type=gpio.FALLING, refresh_rate = 60},tp_callBack)
        local i2c_id = 0
        i2c.setup(i2c_id, i2c.SLOW)
        tp_device = tp.init("gt911",{port=i2c_id, pin_rst = 20,pin_int = gpio.WAKEUP0,},tp_callBack)

        -- gpio.setup(gpio.WAKEUP0, function ()
        --     log.info("tp", "tp interrupt")
        -- end, gpio.PULLUP, gpio.FALLING)
        if tp_device then
            print(tp_device)
            sys.taskInit(function()
                while 1 do 
                    local result, tp_device, tp_data = sys.waitUntil("TP")
                    if result then
                        lcd.drawPoint(tp_data[1].x, tp_data[1].y, 0xF800)
                        lcd.flush()
                    end
                end
            end)
        end
    end


    while 1 do 
        lcd.clear()
        -- log.info("wiki", "https://wiki.luatos.com/api/lcd.html")
        -- -- API 文档 https://wiki.luatos.com/api/lcd.html
        -- if lcd.showImage then
        --     -- 注意, jpg需要是常规格式, 不能是渐进式JPG
        --     -- 如果无法解码, 可以用画图工具另存为,新文件就能解码了
        --     lcd.showImage(40,0,"/luadb/logo.jpg")
        --     sys.wait(100)
        -- end
        -- log.info("lcd.drawLine", lcd.drawLine(20,20,150,20,0x001F))
        -- log.info("lcd.drawRectangle", lcd.drawRectangle(20,40,120,70,0xF800))
        -- log.info("lcd.drawCircle", lcd.drawCircle(50,50,20,0x0CE0))

        if lcd_use_buff then
            lcd.flush()
        end

        sys.wait(5000)
    end

    -- log.info("lvgl", lvgl.init())
    -- -- lvgl.demo_widgets()
    -- local background = lvgl.obj_create(nil, nil)
    -- local scr = lvgl.obj_create(background, nil)
    -- -- local btn = lvgl.btn_create(scr)
    -- local label = lvgl.label_create(scr)
    -- -- lvgl.obj_align(label, lvgl.scr_act(), lvgl.ALIGN_LEFT_MID, 0, 0)
    -- lvgl.obj_set_width(background, 480)
    -- lvgl.obj_set_height(background, 480)
    -- lvgl.obj_set_width(scr, 480)
    -- lvgl.obj_set_height(scr, 480)

    -- local font = lvgl.font_get("opposans_m_12") --中文字体
    -- lvgl.obj_set_style_local_text_font(lvgl.scr_act(), lvgl.OBJ_PART_MAIN, lvgl.STATE_DEFAULT, font)

    -- lvgl.obj_align(label, lvgl.scr_act(), lvgl.ALIGN_OUT_TOP_LEFT, 0, 40);    -- 设置label的位置
    -- lvgl.label_set_text(label, "4G/WiFi/BLE/GNSS/Gsensor/电源管理\r\n6路串口/60个IO/TTS/通话/LCD/485/...\r\n合宙工业引擎Air8000,国内海外均支持")


    -- local img = lvgl.img_create(scr)
    -- lvgl.img_set_src(img, "/luadb/hz.png")
    -- lvgl.obj_align(img, lvgl.scr_act(), lvgl.ALIGN_CENTER, 0, 50)

    -- lvgl.scr_load(scr)
    -- lvgl.indev_drv_register("pointer", "emulator")
end)



-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
