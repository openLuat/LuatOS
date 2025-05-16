local msdbox_demo = {}

local function event_handler(obj, event)
    if(event == lvgl.EVENT_VALUE_CHANGED) then
        print(string.format("Button: %s\n", lvgl.msgbox_get_active_btn_text(obj)));
    end
end

function msdbox_demo.demo()
    local  btns ={"Apply", "Close", ""};

    local mbox1 = lvgl.msgbox_create(lvgl.scr_act(), NULL);
    lvgl.msgbox_set_text(mbox1, "A message box with two buttons.");
    lvgl.msgbox_add_btns(mbox1, btns);----
    lvgl.obj_set_width(mbox1, 200);
    lvgl.obj_set_event_cb(mbox1, event_handler);
    lvgl.obj_align(mbox1, nil, lvgl.ALIGN_CENTER, 0, 0); --Align to the corner
end

return msdbox_demo
