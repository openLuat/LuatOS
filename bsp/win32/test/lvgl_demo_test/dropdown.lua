local dropdown = {}

local function event_handler(obj, event)
    if(event == lvgl.EVENT_VALUE_CHANGED) then
        -- local buf;
        -- lvgl.dropdown_get_selected_str(obj, buf, sizeof(buf));
        -- printf("Option: %s\n", buf);
    end
end

function dropdown.demo()
    --Create a normal drop down list
    local ddlist = lvgl.dropdown_create(lvgl.scr_act(), nil);
    lvgl.dropdown_set_options(ddlist, 
[[Apple
Banana
Orange
Melon
Grape
Raspberry]]);

    lvgl.obj_align(ddlist, nil, lvgl.ALIGN_IN_TOP_MID, 0, 20);
    lvgl.obj_set_event_cb(ddlist, event_handler);
end

return dropdown
