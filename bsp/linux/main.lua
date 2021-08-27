

local sys = require "sys"

log.info("sys", "from linux")

sys.taskInit(function ()
    sys.wait(1000)

    --lvgl.init()
    local scr = lvgl.obj_create()
    local btn = lvgl.btn_create(scr)
    local label = lvgl.label_create(btn)
    lvgl.label_set_text("hi")

    lvgl.load(scr)
end)

sys.run()

