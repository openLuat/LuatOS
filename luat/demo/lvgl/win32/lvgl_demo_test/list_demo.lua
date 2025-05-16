local list_demo = {}

local function event_handler(obj, event)
    if(event == lvgl.EVENT_CLICKED) then
        print(string.format("Clicked: %s\n", lvgl.list_get_btn_text(obj)));
    end
end

function list_demo.demo()
    --Create a list
    local list1 = lvgl.list_create(lvgl.scr_act(), nil);
    lvgl.obj_set_size(list1, 160, 200);
    lvgl.obj_align(list1, nil, lvgl.ALIGN_CENTER, 0, 0);

    --Add buttons to the list
    local list_btn;

    list_btn = lvgl.list_add_btn(list1, lvgl.SYMBOL_FILE, "New");
    lvgl.obj_set_event_cb(list_btn, event_handler);

    list_btn = lvgl.list_add_btn(list1, lvgl.SYMBOL_DIRECTORY, "Open");
    lvgl.obj_set_event_cb(list_btn, event_handler);

    list_btn = lvgl.list_add_btn(list1, lvgl.SYMBOL_CLOSE, "Delete");
    lvgl.obj_set_event_cb(list_btn, event_handler);

    list_btn = lvgl.list_add_btn(list1, lvgl.SYMBOL_EDIT, "Edit");
    lvgl.obj_set_event_cb(list_btn, event_handler);

    list_btn = lvgl.list_add_btn(list1, lvgl.SYMBOL_SAVE, "Save");
    lvgl.obj_set_event_cb(list_btn, event_handler);

    list_btn = lvgl.list_add_btn(list1, lvgl.SYMBOL_BELL, "Notify");
    lvgl.obj_set_event_cb(list_btn, event_handler);

    list_btn = lvgl.list_add_btn(list1, lvgl.SYMBOL_BATTERY_FULL, "Battery");
    lvgl.obj_set_event_cb(list_btn, event_handler);
end

return list_demo
