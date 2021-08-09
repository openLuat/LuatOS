local chart_demo = {}

function chart_demo.demo()
    --Create a chart
    local chart;
    chart = lvgl.chart_create(lvgl.scr_act(), nil);
    lvgl.obj_set_size(chart, 200, 150);
    lvgl.obj_align(chart, nil, lvgl.ALIGN_CENTER, 0, 0);
    lvgl.chart_set_type(chart, lvgl.CHART_TYPE_LINE);   --Show lines and points too*/

    --Add two data series
    local ser1 = lvgl.chart_add_series(chart, lvgl.color_make(0xFF, 0x00, 0x00));
    local ser2 = lvgl.chart_add_series(chart, lvgl.color_make(0x00, 0x80, 0x00));

    --Set the next points on 'ser1'
    lvgl.chart_set_next(chart, ser1, 10);
    lvgl.chart_set_next(chart, ser1, 10);
    lvgl.chart_set_next(chart, ser1, 10);
    lvgl.chart_set_next(chart, ser1, 10);
    lvgl.chart_set_next(chart, ser1, 10);
    lvgl.chart_set_next(chart, ser1, 10);
    lvgl.chart_set_next(chart, ser1, 10);
    lvgl.chart_set_next(chart, ser1, 30);
    lvgl.chart_set_next(chart, ser1, 70);
    lvgl.chart_set_next(chart, ser1, 90);

    lvgl.chart_set_next(chart, ser2, 90);
    lvgl.chart_set_next(chart, ser2, 70);
    lvgl.chart_set_next(chart, ser2, 65);
    lvgl.chart_set_next(chart, ser2, 65);
    lvgl.chart_set_next(chart, ser2, 65);
    lvgl.chart_set_next(chart, ser2, 65);
    lvgl.chart_set_next(chart, ser2, 65);
    lvgl.chart_set_next(chart, ser2, 65);
    lvgl.chart_set_next(chart, ser2, 65);
    lvgl.chart_set_next(chart, ser2, 65);

    lvgl.chart_refresh(chart); --Required after direct set
end

return chart_demo
