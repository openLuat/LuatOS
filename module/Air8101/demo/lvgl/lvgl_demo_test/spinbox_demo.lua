local spinbox_demo = {}

local spinbox

local function lv_spinbox_increment_event_cb(btn, e)
    if(e == lvgl.EVENT_SHORT_CLICKED or e == lvgl.EVENT_LONG_PRESSED_REPEAT) then
        lvgl.spinbox_increment(spinbox);
    end
end

local function lv_spinbox_decrement_event_cb(btn, e)
    if(e == lvgl.EVENT_SHORT_CLICKED or e == lvgl.EVENT_LONG_PRESSED_REPEAT) then
        lvgl.spinbox_decrement(spinbox);
    end
end

function spinbox_demo.demo()
    spinbox = lvgl.spinbox_create(lvgl.scr_act(), nil);
    lvgl.spinbox_set_range(spinbox, -1000, 90000);
    lvgl.spinbox_set_digit_format(spinbox, 5, 2);
    lvgl.spinbox_step_prev(spinbox);
    lvgl.obj_set_width(spinbox, 100);
    lvgl.obj_align(spinbox, nil, lvgl.ALIGN_CENTER, 0, 0);

    local h = lvgl.obj_get_height(spinbox);
    local btn = lvgl.btn_create(lvgl.scr_act(), nil);
    lvgl.obj_set_size(btn, h, h);
    lvgl.obj_align(btn, spinbox, lvgl.ALIGN_OUT_RIGHT_MID, 5, 0);
    lvgl.theme_apply(btn, lvgl.THEME_SPINBOX_BTN);
    lvgl.obj_set_style_local_value_str(btn, lvgl.BTN_PART_MAIN, lvgl.STATE_DEFAULT, LV_SYMBOL_PLUS);
    lvgl.obj_set_event_cb(btn, lv_spinbox_increment_event_cb);

    btn = lvgl.btn_create(lvgl.scr_act(), btn);
    lvgl.obj_align(btn, spinbox, lvgl.ALIGN_OUT_LEFT_MID, -5, 0);
    lvgl.obj_set_event_cb(btn, lv_spinbox_decrement_event_cb);
    lvgl.obj_set_style_local_value_str(btn, lvgl.BTN_PART_MAIN, lvgl.STATE_DEFAULT, LV_SYMBOL_MINUS);
end

return spinbox_demo
