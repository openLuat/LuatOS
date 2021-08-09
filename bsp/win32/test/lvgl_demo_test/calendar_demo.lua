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
    -- lvgl.calendar_date_t today;
    -- local today = lvgl.calendar_date_t()
    -- today.year = 2018;
    -- today.month = 10;
    -- today.day = 23;

    -- lvgl.calendar_set_today_date(calendar, today);
    -- lvgl.calendar_set_showed_date(calendar, today);

    -- --Highlight a few days
    -- static lvgl.calendar_date_t highlighted_days[3];       --Only its pointer will be saved so should be static
    -- highlighted_days[0].year = 2018;
    -- highlighted_days[0].month = 10;
    -- highlighted_days[0].day = 6;

    -- highlighted_days[1].year = 2018;
    -- highlighted_days[1].month = 10;
    -- highlighted_days[1].day = 11;

    -- highlighted_days[2].year = 2018;
    -- highlighted_days[2].month = 11;
    -- highlighted_days[2].day = 22;

    -- lvgl.calendar_set_highlighted_dates(calendar, highlighted_days, 3);
end

return calendar_demo
