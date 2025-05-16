local gauge_demo = {}

--demo1
function gauge_demo.demo1()
    --Describe the color for the needles
    local needle_colors = {lvgl.COLOR_BLUE,lvgl.COLOR_ORANGE,lvgl.COLOR_PURPLE}
    --Create a gauge*/
    local gauge1 = lvgl.gauge_create(lvgl.scr_act(), nil);
    lvgl.gauge_set_needle_count(gauge1, 3, needle_colors);
    lvgl.obj_set_size(gauge1, 200, 200);
    lvgl.obj_align(gauge1, nil, lvgl.ALIGN_CENTER, 0, 0);

    --Set the values*/
    lvgl.gauge_set_value(gauge1, 0, 10);
    lvgl.gauge_set_value(gauge1, 1, 20);
    lvgl.gauge_set_value(gauge1, 2, 30);
end

--demo2
function gauge_demo.demo2()
    --Describe the color for the needles
    local needle_colors = {lvgl.COLOR_BLUE,lvgl.COLOR_ORANGE,lvgl.COLOR_PURPLE}

    -- lvgl.IMG_DECLARE(img_hand);

    --Create a gauge*/
    local gauge1 = lvgl.gauge_create(lvgl.scr_act(), nil);
    lvgl.gauge_set_needle_count(gauge1, 3, needle_colors);
    lvgl.obj_set_size(gauge1, 200, 200);
    lvgl.obj_align(gauge1, nil, lvgl.ALIGN_CENTER, 0, 0);

    -- lvgl.gauge_set_needle_img(gauge1, img_hand, 4, 4);
    --Allow recoloring of the images according to the needles' color
    lvgl.obj_set_style_local_image_recolor_opa(gauge1, lvgl.GAUGE_PART_NEEDLE, lvgl.STATE_DEFAULT, lvgl.OPA_COVER);

    --Set the values*/
    lvgl.gauge_set_value(gauge1, 0, 10);
    lvgl.gauge_set_value(gauge1, 1, 20);
    lvgl.gauge_set_value(gauge1, 2, 30);
end

return gauge_demo