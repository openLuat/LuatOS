local calendar_demo = {}

local function event_handler(obj, event)
    if(event == lvgl.EVENT_VALUE_CHANGED) then
            local date = lvgl.calendar_get_pressed_date(obj);
            -- print(string.format("Clicked date: %02d.%02d.%d\n", date.day, date.month, date.year))
    end
end

function calendar_demo.demo()
    local calendar = lvgl.calendar_create(lvgl.scr_act(), nil);
    lvgl.obj_set_size(calendar, 235, 235);
    lvgl.obj_align(calendar, nil, lvgl.ALIGN_CENTER, 0, 0);
    lvgl.obj_set_event_cb(calendar, event_handler);

    --Make the date number smaller to be sure they fit into their area
    lvgl.obj_set_style_local_text_font(calendar, lvgl.CALENDAR_PART_DATE, lvgl.STATE_DEFAULT, lvgl.theme_get_font_small());

    --Set today's date
    local today = lvgl.calendar_date_t()
    today.year = 2018;
    today.month = 10;
    today.day = 23;

    lvgl.calendar_set_today_date(calendar, today);
    lvgl.calendar_set_showed_date(calendar, today);

    local highlighted_days1 = lvgl.calendar_date_t()
    highlighted_days1.year = 2018;
    highlighted_days1.month = 10;
    highlighted_days1.day = 6;

    local highlighted_days2 = lvgl.calendar_date_t()
    highlighted_days2.year = 2018;
    highlighted_days2.month = 10;
    highlighted_days2.day = 11;

    local highlighted_days3 = lvgl.calendar_date_t()
    highlighted_days3.year = 2018;
    highlighted_days3.month = 10;
    highlighted_days3.day = 12;

    local highlighted_days = {highlighted_days1,highlighted_days2,highlighted_days3}
    lvgl.calendar_set_highlighted_dates(calendar, highlighted_days, 3);
end

return calendar_demo
