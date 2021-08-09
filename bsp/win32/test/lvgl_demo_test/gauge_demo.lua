local gauge_demo = {}


function gauge_demo.demo()
    --Create a gauge*/
    local gauge1 = lvgl.gauge_create(lvgl.scr_act(), nil);
    lvgl.gauge_set_needle_count(gauge1, 3, lvgl.color_make(0x00, 0x00, 0xFF), lvgl.color_make(0xFF, 0xA5, 0x00), lvgl.color_make(0x80, 0x00, 0x80));
    lvgl.obj_set_size(gauge1, 200, 200);
    lvgl.obj_align(gauge1, nil, lvgl.ALIGN_CENTER, 0, 0);

    --Set the values*/
    lvgl.gauge_set_value(gauge1, 0, 10);
    lvgl.gauge_set_value(gauge1, 1, 20);
    lvgl.gauge_set_value(gauge1, 2, 30);
end

return gauge_demo
