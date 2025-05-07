--- 模块功能：lcddemo
-- @module lcd
-- @author Dozingfiretruck
-- @release 2021.01.25
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "lcddemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

pm.ioVol(pm.IOVOL_ALL_GPIO, 3300) -- 设置GPIO电平 3.3V

-- 添加硬狗防止程序卡死
if wdt then
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end

lcd.init("jd9261t_inited",{port = lcd.HWID_0,pin_dc = 0xff, pin_pwr = 24, pin_rst = 36,direction = 0,w = 480,h = 480,xoffset = 0,yoffset = 0,interface_mode=lcd.QSPI_MODE,bus_speed=60000000,flush_rate=658,vbp=19,vfp=108,vs=2})


sys.taskInit(function()
    lcd.setupBuff(nil, true) -- 使用sys内存, 只需要选一种
    lcd.autoFlush(false)

    log.info("lvgl", lvgl.init())

    local scr = lvgl.obj_create(nil, nil)
    local btn = lvgl.btn_create(scr)
    lvgl.obj_align(btn, lvgl.scr_act(), lvgl.ALIGN_CENTER, 0, 0)

    local label = lvgl.label_create(btn)
    local flag = true

    lvgl.label_set_text(label, "LuatOS!")
    lvgl.scr_load(scr)
    lvgl.indev_drv_register("pointer", "emulator")

    local function btn_cb(obj, event)
        if event == lvgl.EVENT_SHORT_CLICKED then
            log.info("short click")        if flag then
                lvgl.label_set_text(label, "LuatOS!")
                flag = false
            else
                lvgl.label_set_text(label, "hello world!")
                flag = true
            end
        end
    end
    lvgl.obj_set_event_cb(btn, btn_cb)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
