local cpicker_demo = {}

function cpicker_demo.demo()
    local cpicker
    cpicker = lvgl.cpicker_create(lvgl.scr_act(), nil)
    lvgl.obj_set_size(cpicker, 200, 200)
    lvgl.obj_align(cpicker, nil, lvgl.ALIGN_CENTER, 0, 0)
end

return cpicker_demo
