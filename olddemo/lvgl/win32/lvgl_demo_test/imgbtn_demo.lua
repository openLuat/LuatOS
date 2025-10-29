local imgbtn_demo = {}

function imgbtn_demo.demo()
    --Darken the button when pressed
    -- local lvgl.style_t style;
    local style = lvgl.style_t()
    lvgl.style_init(style);
    lvgl.style_set_image_recolor_opa(style, lvgl.STATE_PRESSED, lvgl.OPA_30);
    lvgl.style_set_image_recolor(style, lvgl.STATE_PRESSED, lvgl.color_make(0x00, 0x00, 0x00));
    lvgl.style_set_text_color(style, lvgl.STATE_DEFAULT, lvgl.color_make(0xFF, 0xFF, 0xFF));

    --Create an Image button
    local imgbtn1 = lvgl.imgbtn_create(lvgl.scr_act(), nil);
    lvgl.imgbtn_set_src(imgbtn1, lvgl.BTN_STATE_RELEASED, "/img/imgbtn_green.png");
    lvgl.imgbtn_set_src(imgbtn1, lvgl.BTN_STATE_PRESSED, "/img/imgbtn_green.png");
    lvgl.imgbtn_set_src(imgbtn1, lvgl.BTN_STATE_CHECKED_RELEASED, "/img/imgbtn_blue.png");
    lvgl.imgbtn_set_src(imgbtn1, lvgl.BTN_STATE_CHECKED_PRESSED, "/img/imgbtn_blue.png");
    lvgl.imgbtn_set_checkable(imgbtn1, true);
    lvgl.obj_add_style(imgbtn1, lvgl.IMGBTN_PART_MAIN, style);
    lvgl.obj_align(imgbtn1, nil, lvgl.ALIGN_CENTER, 0, -40);

    --Create a label on the Image button
    local label = lvgl.label_create(imgbtn1, nil);
    lvgl.label_set_text(label, "Button");
end

return imgbtn_demo
