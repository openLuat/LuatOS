local win_demo = {}

function win_demo.demo()
    --Create a window
    local win = lvgl.win_create(lvgl.scr_act(), nil);
    lvgl.win_set_title(win, "Window title");                        --Set the title


    --Add control button to the header
    local close_btn = lvgl.win_add_btn(win, LV_SYMBOL_CLOSE);           --Add close button and use built-in close action
    lvgl.obj_set_event_cb(close_btn, lvgl.win_close_event_cb);
    lvgl.win_add_btn(win, LV_SYMBOL_SETTINGS);        --Add a setup button

    --Add some dummy content
    local txt = lvgl.label_create(win, nil);
    lvgl.label_set_text(txt,
[[This is the content of the window
You can add control buttons to
the window header
The content area becomes
automatically scrollable is it's 
large enough.
You can scroll the content
See the scroll bar on the right!]]);
end

return win_demo
