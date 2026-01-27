-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "iRTU"
VERSION = "5.0.0"

PRODUCT_KEY = "0LkZx9Kn3tOhtW7uod48xhilVNrVsScV" --618DTU正式版本的key固定为它
-- PRODUCT_KEY = "z1OoDfAP2LDtOStiMQTVDfXO6RkrWeBG" --618DTU测试版本的key固定为它


log.info("main", PROJECT, VERSION)

-- 一定要添加sys.lua !!!!
_G.sys = require("sys")
_G.sysplus = require("sysplus")
pm.power(pm.GPS, false)

require "libnet"
require "lbsLoc"

db = require("db")

local hw_font_drv = require("hw_font_drv")
local main_page = require("main_page")

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end
ver = rtos.bsp()

sys.taskInit(function()
    -- 打开ch390供电脚
    gpio.setup(140, 1, gpio.PULLUP)
    gpio.setup(12, 1)
    sys.wait(200)

    log.info("init_lcd")
    hw_font_drv.init_lcd()
    local tp_device = hw_font_drv.init_tp()

    local ret = airui.init(320, 480, airui.COLOR_FORMAT_RGB565)
    if not ret then
        log.error("airui", "init failed")
        return
    end

    airui.font_load({
        type = "hzfont",
        path = nil,
        size = 14,
        cache_size = 2048,
        antialias = 2,
    })

    airui.indev_bind_touch(tp_device)

    main_page.create_page()
    main_page.show_page()

    sys.publish("MAIN_PAGE_DONE")

    while true do
        airui.refresh()
        sys.wait(30)
    end
end)

sys.taskInit(function()
    sys.waitUntil("MAIN_PAGE_DONE")
    log.info("default task start")
    local irtu_main = require "irtu_main" -- irtu主程序
end)

mcu.hardfault(1)--死机重启

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
