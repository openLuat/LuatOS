local switch_demo = {}

local function event_handler(obj, event)
    if(event == lvgl.EVENT_VALUE_CHANGED) then
        if lvgl.switch_get_state(obj) == true then
            print("State: On\n")
        else
            print("State: Off\n")
        end
    end
end

function switch_demo.demo()
    --Create a switch and apply the styles
    local sw1 = lvgl.switch_create(lvgl.scr_act(), nil);
    lvgl.obj_align(sw1, nil, lvgl.ALIGN_CENTER, 0, -50);
    lvgl.obj_set_event_cb(sw1, event_handler);

    --Copy the first switch and turn it ON
    local sw2 = lvgl.switch_create(lvgl.scr_act(), sw1);
    lvgl.switch_on(sw2, lvgl.ANIM_ON);
    lvgl.obj_align(sw2, nil, lvgl.ALIGN_CENTER, 0, 50);
end

return switch_demo
