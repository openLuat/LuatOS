local led_demo = {}

function led_demo.demo()
    --Create a LED and switch it OFF
    local led1  = lvgl.led_create(lvgl.scr_act(), nil);
    lvgl.obj_align(led1, nil, lvgl.ALIGN_CENTER, -80, 0);
    lvgl.led_off(led1);

    --Copy the previous LED and set a brightness
    local led2  = lvgl.led_create(lvgl.scr_act(), led1);
    lvgl.obj_align(led2, nil, lvgl.ALIGN_CENTER, 0, 0);
    lvgl.led_set_bright(led2, 190);

    --Copy the previous LED and switch it ON
    local led3  = lvgl.led_create(lvgl.scr_act(), led1);
    lvgl.obj_align(led3, nil, lvgl.ALIGN_CENTER, 80, 0);
    lvgl.led_on(led3);
end

return led_demo
