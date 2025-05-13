local objmask_demo = {}

function objmask_demo.demo()
    --Set a very visible color for the screen to clearly see what happens*/
    lvgl.obj_set_style_local_bg_color(lvgl.scr_act(), lvgl.OBJ_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.color_hex3(0xf33));

    local om = lvgl.objmask_create(lvgl.scr_act(), nil);
    lvgl.obj_set_size(om, 200, 200);
    lvgl.obj_align(om, nil, lvgl.ALIGN_CENTER, 0, 0);
    local label = lvgl.label_create(om, nil);
    lvgl.label_set_long_mode(label, lvgl.LABEL_LONG_BREAK);
    lvgl.label_set_align(label, lvgl.LABEL_ALIGN_CENTER);
    lvgl.obj_set_width(label, 180);
    lvgl.label_set_text(label, "This label will be masked out. See how it works.");
    lvgl.obj_align(label, nil, lvgl.ALIGN_IN_TOP_MID, 0, 20);

    local cont = lvgl.cont_create(om, nil);
    lvgl.obj_set_size(cont, 180, 100);
    lvgl.obj_set_drag(cont, true);
    lvgl.obj_align(cont, nil, lvgl.ALIGN_IN_BOTTOM_MID, 0, -10);

    local btn = lvgl.btn_create(cont, nil);
    lvgl.obj_align(btn, nil, lvgl.ALIGN_CENTER, 0, 0);
    lvgl.obj_set_style_local_value_str(btn, lvgl.BTN_PART_MAIN, lvgl.STATE_DEFAULT, "Button");

    lvgl.refr_now(nil);
    sys.wait(1000)
    
    local a = lvgl.area_t()
    local r1 = lvgl.draw_mask_radius_param_t()
    a.x1 = 10;
    a.y1 = 10;
    a.x2 = 190;
    a.y2 = 190;
    -- lvgl.draw_mask_radius_init(r1, a, lvgl.RADIUS_CIRCLE, false);
    lvgl.draw_mask_radius_init(r1, a, 0x7FFF, false);
    lvgl.objmask_add_mask(om, r1);
    
    lvgl.refr_now(nil);
    sys.wait(1000)

    a.x1 = 100;
    a.y1 = 100;
    a.x2 = 150;
    a.y2 = 150;
    -- lvgl.draw_mask_radius_init(r1, a, lvgl.RADIUS_CIRCLE, true);
    lvgl.draw_mask_radius_init(r1, a, 0x7FFF, false);
    lvgl.objmask_add_mask(om, r1);

    lvgl.refr_now(nil);
    sys.wait(1000)

    local l1 = lvgl.draw_mask_line_param_t()
    lvgl.draw_mask_line_points_init(l1, 0, 0, 100, 200, lvgl.DRAW_MASK_LINE_SIDE_TOP);
    lvgl.objmask_add_mask(om, l1);

    lvgl.refr_now(nil);
    sys.wait(1000)

    local f1 = lvgl.draw_mask_fade_param_t()
    a.x1 = 100;
    a.y1 = 0;
    a.x2 = 200;
    a.y2 = 200;
    -- lvgl.draw_mask_fade_init(f1, a, lvgl.OPA_TRANSP, 0, lvgl.OPA_COVER, 150);
    lvgl.draw_mask_fade_init(f1, a, 0, 0, 255, 150);
    lvgl.objmask_add_mask(om, f1);
end

return objmask_demo
