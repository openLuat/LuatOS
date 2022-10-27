-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "touch"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

-- v0006及以后版本可用pin方式, 请升级到最新固件 https://gitee.com/openLuat/LuatOS/releases
spi_lcd = spi.deviceSetup(0,pin.PB04,0,0,8,20*1000*1000,spi.MSB,1,1)

--[[ 此为合宙售卖的0.96寸TFT LCD LCD 分辨率:160X80 屏幕ic:st7735s 购买地址:https://item.taobao.com/item.htm?id=661054472686]]
lcd.init("st7735v",{port = "device",pin_dc = pin.PB01, pin_pwr = pin.PB00,pin_rst = pin.PB03,direction = 1,w = 160,h = 80,xoffset = 0,yoffset = 24},spi_lcd)
--如果显示颜色相反，请解开下面一行的注释，关闭反色
--lcd.invoff()
--如果显示依旧不正常，可以尝试老版本的板子的驱动
--lcd.init("st7735s",{port = "device",pin_dc = pin.PB01, pin_pwr = pin.PB00,pin_rst = pin.PB03,direction = 2,w = 160,h = 80,xoffset = 1,yoffset = 26},spi_lcd)

local function event_handler(obj, event)
    if(event == lvgl.EVENT_CLICKED) then
            print("Clicked")
    elseif(event == lvgl.EVENT_VALUE_CHANGED) then
            print("Toggled")
    end
end

local function demo1()
local label

local btn2 = lvgl.btn_create(lvgl.scr_act(), nil)
lvgl.obj_set_event_cb(btn2, event_handler)
lvgl.obj_align(btn2, nil, lvgl.ALIGN_CENTER, 0, 0)
lvgl.btn_set_checkable(btn2, true)
lvgl.btn_toggle(btn2)
lvgl.btn_set_fit2(btn2, lvgl.FIT_NONE, lvgl.FIT_TIGHT)

label = lvgl.label_create(btn2, nil)
lvgl.label_set_text(label, "Toggled")
end

gpio.setup(pin.PA04,
    function(val)
        if val==0 then
            lvgl.indev_point_emulator_update(80,40,1)
        else
            lvgl.indev_point_emulator_update(80,40,0)
        end
    end, gpio.PULLUP)


sys.taskInit(function()
    log.info("lvgl", lvgl.init())
    demo1()
    lvgl.indev_drv_register("pointer", "emulator")
    while 1 do
        sys.wait(1000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
