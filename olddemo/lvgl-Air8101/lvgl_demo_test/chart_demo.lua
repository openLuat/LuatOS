local chart_demo = {}

--demo1
function chart_demo.demo1()
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

--demo2
function chart_demo.demo2()
    --Create a chart
    local chart;
    chart = lvgl.chart_create(lvgl.scr_act(), nil);
    lvgl.obj_set_size(chart, 200, 150);
    lvgl.obj_align(chart, nil, lvgl.ALIGN_CENTER, 0, 0);
    lvgl.chart_set_type(chart, lvgl.CHART_TYPE_LINE);   --Show lines and points too

    --Add a faded are effect
    lvgl.obj_set_style_local_bg_opa(chart, lvgl.CHART_PART_SERIES, lvgl.STATE_DEFAULT, lvgl.OPA_50); --Max. opa.
    lvgl.obj_set_style_local_bg_grad_dir(chart, lvgl.CHART_PART_SERIES, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
    lvgl.obj_set_style_local_bg_main_stop(chart, lvgl.CHART_PART_SERIES, lvgl.STATE_DEFAULT, 255);    --Max opa on the top
    lvgl.obj_set_style_local_bg_grad_stop(chart, lvgl.CHART_PART_SERIES, lvgl.STATE_DEFAULT, 0);      --Transparent on the bottom

    --Add two data series
    local ser1 = lvgl.chart_add_series(chart, lvgl.color_make(0xFF, 0x00, 0x00));
    local ser2 = lvgl.chart_add_series(chart, lvgl.color_make(0x00, 0x80, 0x00));
    --Set the next points on 'ser1'
    lvgl.chart_set_next(chart, ser1, 31);
    lvgl.chart_set_next(chart, ser1, 66);
    lvgl.chart_set_next(chart, ser1, 10);
    lvgl.chart_set_next(chart, ser1, 89);
    lvgl.chart_set_next(chart, ser1, 63);
    lvgl.chart_set_next(chart, ser1, 56);
    lvgl.chart_set_next(chart, ser1, 32);
    lvgl.chart_set_next(chart, ser1, 35);
    lvgl.chart_set_next(chart, ser1, 57);
    lvgl.chart_set_next(chart, ser1, 85);

    --Directly set points on 'ser2'
    lvgl.chart_set_next(chart, ser2, 92);
    lvgl.chart_set_next(chart, ser2, 71);
    lvgl.chart_set_next(chart, ser2, 61);
    lvgl.chart_set_next(chart, ser2, 15);
    lvgl.chart_set_next(chart, ser2, 21);
    lvgl.chart_set_next(chart, ser2, 35);
    lvgl.chart_set_next(chart, ser2, 35);
    lvgl.chart_set_next(chart, ser2, 58);
    lvgl.chart_set_next(chart, ser2, 31);
    lvgl.chart_set_next(chart, ser2, 53);

    lvgl.chart_refresh(chart); --Required after direct set
end

return chart_demo
