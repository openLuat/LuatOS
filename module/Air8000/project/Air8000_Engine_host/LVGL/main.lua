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
    return lcd.HWID_0, 36, 0xff, 0xff, 21 -- 注意:EC718P有硬件lcd驱动接口, 无需使用spi,当然spi驱动也支持
    -- return lcd.HWID_0, 36, 0xff, 0xff, 25 -- 注意:EC718P有硬件lcd驱动接口, 无需使用spi,当然spi驱动也支持
end

local spi_id, pin_reset, pin_dc, pin_cs, bl = lcd_pin()

local port = spi_id
local tp_i2c_id = 1
local width, height = 480, 480


lcd.init("jd9261t_inited",{port = port,pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset, tp_pin_rst = 141, direction = 0,w = width,h = height,xoffset = 0,yoffset = 0,interface_mode=lcd.QSPI_MODE,bus_speed=60000000,flush_rate=658,vbp=10,vfp=108,vs=2})
lcd_use_buff = true

sys.taskInit(function()
    lcd.setupBuff(nil, true) -- 使用sys内存, 只需要选一种
    lcd.autoFlush(false)
end)

log.info("lvgl", lvgl.init())

local background = lvgl.obj_create(nil, nil)
local scr = lvgl.obj_create(background, nil)

local label = lvgl.label_create(scr)

lvgl.obj_set_width(background, width)
lvgl.obj_set_height(background, height)
lvgl.obj_set_width(scr, width)
lvgl.obj_set_height(scr, height)

local font = lvgl.font_get("opposans_m_12") --中文字体
lvgl.obj_set_style_local_text_font(lvgl.scr_act(), lvgl.OBJ_PART_MAIN, lvgl.STATE_DEFAULT, font)

lvgl.obj_align(label, lvgl.scr_act(), lvgl.ALIGN_OUT_TOP_LEFT, 0, 40);    -- 设置label的位置
lvgl.label_set_text(label, "4G/WiFi/BLE/GNSS/Gsensor/电源管理\r\n6路串口/60个IO/TTS/通话/LCD/485/...\r\n合宙工业引擎Air8000,国内海外均支持")

local img = lvgl.img_create(scr)
lvgl.img_set_src(img, "/luadb/hz.png")
lvgl.img_set_zoom(img, 281)
lvgl.obj_align(img, lvgl.scr_act(), lvgl.ALIGN_CENTER, 0, 0)

lvgl.scr_load(scr)
lvgl.indev_drv_register("pointer", "emulator")

if tp then
    log.info("tp", "tp init")
    local function tp_callBack(tp_device,tp_data)
        sys.publish("TP",tp_device,tp_data)
		log.info("TP",tp_data[1].x,tp_data[1].y,tp_data[1].event)
    end

    -- local softI2C = i2c.createSoft(20, 21, 2) -- SCL, SDA
    -- local softI2C = i2c.createSoft(28, 26, 1) -- SCL, SDA
    -- tp_device = tp.init("jd9261t_inited",{port=softI2C, pin_rst = 27,pin_int = gpio.CHG_DET,w = width,h = height,int_type=gpio.FALLING, refresh_rate = 60},tp_callBack)

    tp_device = tp.init("jd9261t_inited",{port=tp_i2c_id, pin_rst = 255,pin_int = 140,w = width,h = height,int_type=gpio.FALLING, refresh_rate = 60},tp_callBack)

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

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
