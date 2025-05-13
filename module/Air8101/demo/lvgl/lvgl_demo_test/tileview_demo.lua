local tileview_demo = {}

function tileview_demo.demo()

    local LV_VER_RES = lvgl.disp_get_ver_res(lvgl.disp_get_default())
    local LV_HOR_RES = lvgl.disp_get_hor_res(lvgl.disp_get_default())

    local valid_pos = {{0,0}, {0, 1}, {1,1}};
    local tileview;
    tileview = lvgl.tileview_create(lvgl.scr_act(), nil);
    lvgl.tileview_set_valid_positions(tileview, valid_pos, 3);
    lvgl.tileview_set_edge_flash(tileview, true);

    local tile1 = lvgl.obj_create(tileview, nil);
    lvgl.obj_set_size(tile1, LV_HOR_RES, LV_VER_RES);
    lvgl.tileview_add_element(tileview, tile1);

    --Tile1: just a label
    local label = lvgl.label_create(tile1, nil);
    lvgl.label_set_text(label, "Scroll down");
    lvgl.obj_align(label, nil, lvgl.ALIGN_CENTER, 0, 0);

    --Tile2: a list
    local list = lvgl.list_create(tileview, nil);
    lvgl.obj_set_size(list, LV_HOR_RES, LV_VER_RES);
    lvgl.obj_set_pos(list, 0, LV_VER_RES);
    lvgl.list_set_scroll_propagation(list, true);
    lvgl.list_set_scrollbar_mode(list, lvgl.SCROLLBAR_MODE_OFF);

    lvgl.list_add_btn(list, nil, "One");
    lvgl.list_add_btn(list, nil, "Two");
    lvgl.list_add_btn(list, nil, "Three");
    lvgl.list_add_btn(list, nil, "Four");
    lvgl.list_add_btn(list, nil, "Five");
    lvgl.list_add_btn(list, nil, "Six");
    lvgl.list_add_btn(list, nil, "Seven");
    lvgl.list_add_btn(list, nil, "Eight");

    --Tile3: a button
    local tile3 = lvgl.obj_create(tileview, tile1);
    lvgl.obj_set_pos(tile3, LV_HOR_RES, LV_VER_RES);
    lvgl.tileview_add_element(tileview, tile3);

    local btn = lvgl.btn_create(tile3, nil);
    lvgl.obj_align(btn, nil, lvgl.ALIGN_CENTER, 0, 0);
    lvgl.tileview_add_element(tileview, btn);
    label = lvgl.label_create(btn, nil);
    lvgl.label_set_text(label, "No scroll up");
end

return tileview_demo
