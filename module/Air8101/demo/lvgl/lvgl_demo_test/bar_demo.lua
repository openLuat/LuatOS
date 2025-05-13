local bar_demo = {}

function bar_demo.demo()
    local bar1 = lvgl.bar_create(lvgl.scr_act(), nil)
    lvgl.obj_set_size(bar1, 200, 20)
    lvgl.obj_align(bar1, nil, lvgl.ALIGN_CENTER, 0, 0)
    lvgl.bar_set_anim_time(bar1, 2000)
    lvgl.bar_set_value(bar1, 100, lvgl.ANIM_ON)
end

return bar_demo
