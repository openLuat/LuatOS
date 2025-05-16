

sys = require("sys")
local printer = require "printer"

log.info("sys", "from win32")

_G.guider_ui = {}

sys.taskInit(function ()
    log.info("lvgl", lvgl.init(480,320))
    printer.setup_ui(_G.guider_ui)
    printer.events_init(_G.guider_ui)
    printer.custom_init(_G.guider_ui)

    while true do
        local timetable = os.date("*t", os.time())
        local now_act = lvgl.scr_act()
        if now_act == _G.guider_ui.home then
            lvgl.label_set_text(_G.guider_ui.home_labeldate, string.format("%02d-%02d-%02d %02d:%02d:%02d",timetable.year,timetable.month,timetable.day,timetable.hour,timetable.min,timetable.sec))
        end
        sys.wait(500)
    end
end)

sys.run()
