
sys = require "sys"
log.info("lvgl", lvgl.init())

local function event_handler(obj, event)
    log.info("event", event)
end

sys.taskInit(function()
    local sw1 = lvgl.switch_create(lvgl.scr_act(), nil);
    lvgl.obj_align(sw1, nil, lvgl.ALIGN_CENTER, 0, -50);
    lvgl.obj_set_event_cb(sw1, event_handler);

    while 1 do
        sys.wait(1000)
        lvgl.switch_on(sw1, lvgl.ANIM_ON)
        sys.wait(1000)
        lvgl.switch_off(sw1, lvgl.ANIM_OFF)
    end
end)

sys.run()

