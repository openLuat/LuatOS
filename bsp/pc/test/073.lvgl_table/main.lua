--加载sys库
_G.sys = require("sys")

log.info("初始化lvgl")
log.info("lvgl", lvgl.init(640, 480))

sys.taskInit(function()
    -- local label
    
    -- local btn1 = lvgl.btn_create(lvgl.scr_act(), nil)
    -- lvgl.obj_set_event_cb(btn1, function(btn, state)
    --     log.info("abc", "hi", btn, state)
    -- end)
    -- lvgl.obj_align(btn1, nil, lvgl.ALIGN_CENTER, 0, 0)
    
    -- label = lvgl.label_create(btn1, nil)
    -- lvgl.label_set_text(label, "Button")
    
    -- lvgl.indev_drv_register("pointer", "emulator")

    local table = lvgl.table_create(lvgl.scr_act(), nil);
    lvgl.table_set_col_cnt(table, 2);
    lvgl.table_set_row_cnt(table, 4);
    lvgl.obj_align(table, nil, lvgl.ALIGN_CENTER, 0, 0);

    --Make the cells of the first row center aligned 
    lvgl.table_set_cell_align(table, 0, 0, lvgl.LABEL_ALIGN_CENTER);
    lvgl.table_set_cell_align(table, 0, 1, lvgl.LABEL_ALIGN_CENTER);

    --Align the price values to the right in the 2nd column
    lvgl.table_set_cell_align(table, 1, 1, lvgl.LABEL_ALIGN_RIGHT);
    lvgl.table_set_cell_align(table, 2, 1, lvgl.LABEL_ALIGN_RIGHT);
    lvgl.table_set_cell_align(table, 3, 1, lvgl.LABEL_ALIGN_RIGHT);

    lvgl.table_set_cell_type(table, 0, 0, 2);
    lvgl.table_set_cell_type(table, 0, 1, 2);


    --Fill the first column
    lvgl.table_set_cell_value(table, 0, 0, "Name");
    lvgl.table_set_cell_value(table, 1, 0, "Apple");
    lvgl.table_set_cell_value(table, 2, 0, "Banana");
    lvgl.table_set_cell_value(table, 3, 0, "Citron");

    --Fill the second column
    lvgl.table_set_cell_value(table, 0, 1, "Price");
    lvgl.table_set_cell_value(table, 1, 1, "$7");
    lvgl.table_set_cell_value(table, 2, 1, "$4");
    lvgl.table_set_cell_value(table, 3, 1, "$6");

    lvgl.obj_set_event_cb(table, function(obj, state)
        -- log.info("abc", "hi", obj, state, lvgl.EVENT_CLICKED)
        if state == lvgl.EVENT_CLICKED then
            log.info("table", lvgl.table_get_pressed_cell(obj))
        end
    end)
    log.info("table", table)

    -- while 1 do
    --     sys.wait(1000)
    --     log.info("table", lvgl.table_get_pressed_cell(table))
    -- end
end)

-- sys.taskInit(function()
--     while true do
--         sys.wait(1000)
--         lvgl.indev_point_emulator_update(240, 160, 1)
--         sys.wait(50)
--         lvgl.indev_point_emulator_update(240, 160, 0)
--     end

-- end)

sys.run()
