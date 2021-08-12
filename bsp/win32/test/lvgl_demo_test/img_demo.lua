local img_demo = {}

--demo1
function img_demo.demo1()
    local img1 = lvgl.img_create(lvgl.scr_act(), nil);
    lvgl.img_set_src(img1, "/img/img_cogwheel_argb.png");
    lvgl.obj_align(img1, nil, lvgl.ALIGN_CENTER, 0, -20);

    local img2 = lvgl.img_create(lvgl.scr_act(), nil);
    lvgl.img_set_src(img2, LV_SYMBOL_OK.."Accept");
    lvgl.obj_align(img2, img1, lvgl.ALIGN_OUT_BOTTOM_MID, 0, 20);
end

local red_slider, green_slider, blue_slider, intense_slider
local  img1;
local SLIDER_WIDTH = 15

local function lv_ex_img_2(void)
    --Create 4 sliders to adjust RGB color and re-color intensity
    -- create_sliders();

    -- Now create the actual image 
    img1 = lvgl.img_create(lvgl.scr_act(), nil);
    -- lvgl.img_set_src(img1, img_cogwheel_argb);
    lvgl.obj_align(img1, nil, lvgl.ALIGN_IN_RIGHT_MID, -20, 0);
end
local function slider_event_cb(slider, event)
    if event == lvgl.EVENT_VALUE_CHANGED then
        -- Recolor the image based on the sliders' values 
        local color  = lvgl.color_make(lvgl.slider_get_value(red_slider), lvgl.slider_get_value(green_slider), lvgl.slider_get_value(blue_slider));
        local intense = lvgl.slider_get_value(intense_slider);
        lvgl.obj_set_style_local_image_recolor_opa(img1, lvgl.IMG_PART_MAIN, lvgl.STATE_DEFAULT, intense);
        lvgl.obj_set_style_local_image_recolor(img1, lvgl.IMG_PART_MAIN, lvgl.STATE_DEFAULT, color);
    end
end
--demo2
-- function img_demo.demo2()
--     -- Create a set of RGB sliders 
--     -- Use the red one as a base for all the settings 
--     red_slider = lvgl.slider_create(lvgl.scr_act(), nil);
--     lvgl.slider_set_range(red_slider, 0, 255);
--     lvgl.obj_set_size(red_slider, SLIDER_WIDTH, 200); -- Be sure it's a vertical slider 
--     -- lvgl.obj_set_style_local_bg_color(red_slider, lvgl.SLIDER_PART_INDIC, lvgl.STATE_DEFAULT, lvgl.COLOR_RED);
--     lvgl.obj_set_style_local_bg_color(blue_slider, lvgl.SLIDER_PART_INDIC, lvgl.STATE_DEFAULT, lvgl.color_make(0xFF, 0x00, 0x00));
--     lvgl.obj_set_event_cb(red_slider, slider_event_cb);

--     -- Copy it for the other three sliders 
--     green_slider = lvgl.slider_create(lvgl.scr_act(), red_slider);
--     lvgl.obj_set_style_local_bg_color(green_slider, lvgl.SLIDER_PART_INDIC, lvgl.STATE_DEFAULT, lvgl.COLOR_LIME);

--     blue_slider = lvgl.slider_create(lvgl.scr_act(), red_slider);
--     -- lvgl.obj_set_style_local_bg_color(blue_slider, lvgl.SLIDER_PART_INDIC, lvgl.STATE_DEFAULT, lvgl.COLOR_BLUE);
--     lvgl.obj_set_style_local_bg_color(blue_slider, lvgl.SLIDER_PART_INDIC, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0xFF));

--     intense_slider = lvgl.slider_create(lvgl.scr_act(), red_slider);
--     -- lvgl.obj_set_style_local_bg_color(intense_slider, lvgl.SLIDER_PART_INDIC, lvgl.STATE_DEFAULT, lvgl.COLOR_GRAY);
--     lvgl.obj_set_style_local_bg_color(blue_slider, lvgl.SLIDER_PART_INDIC, lvgl.STATE_DEFAULT, lvgl.color_make(0x80, 0x80, 0x80));
--     lvgl.slider_set_value(intense_slider, 255, lvgl.ANIM_OFF);

--     lvgl.obj_align(red_slider, nil, lvgl.ALIGN_IN_LEFT_MID, 20, 0);
--     lvgl.obj_align(green_slider, red_slider, lvgl.ALIGN_OUT_RIGHT_MID, 20, 0);
--     lvgl.obj_align(blue_slider, green_slider, lvgl.ALIGN_OUT_RIGHT_MID, 20, 0);
--     lvgl.obj_align(intense_slider, blue_slider, lvgl.ALIGN_OUT_RIGHT_MID, 20, 0);
-- end

return img_demo
