local img_demo = {}

--demo1
function img_demo.demo()
    local img1 = lvgl.img_create(lvgl.scr_act(), nil);
    lvgl.img_set_src(img1, "/img/img_cogwheel_argb.png");
    lvgl.obj_align(img1, nil, lvgl.ALIGN_CENTER, 0, -20);

    local img2 = lvgl.img_create(lvgl.scr_act(), nil);
    lvgl.img_set_src(img2, LV_SYMBOL_OK.."Accept");
    lvgl.obj_align(img2, img1, lvgl.ALIGN_OUT_BOTTOM_MID, 0, 20);
end

return img_demo
