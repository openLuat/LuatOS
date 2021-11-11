--加载sys库
_G.sys = require("sys")

log.info("lvgl", lvgl.init(480,320))

sys.taskInit(function()
    local label
    local btn1 = lvgl.btn_create(lvgl.scr_act(), nil)
    lvgl.obj_set_event_cb(btn1, function(btn, state)
        log.info("abc", "hi", btn, state)
    end)
    lvgl.obj_align(btn1, nil, lvgl.ALIGN_CENTER, 0, 0)
    
    label = lvgl.label_create(btn1, nil)
    lvgl.label_set_text(label, "Button")
    
    lvgl.indev_drv_register("pointer", "emulator")
end)

sys.taskInit(function()
    while true do
        sys.wait(1000)
        lvgl.indev_point_emulator_update(240, 160, 1)
        sys.wait(50)
        lvgl.indev_point_emulator_update(240, 160, 0)
    end

end)

sys.run()
