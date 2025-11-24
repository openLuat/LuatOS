
sys = require "sys"
log.info("lvgl", lvgl.init())

local function event_handler(obj, event)
    log.info("event", event)
end

sys.taskInit(function()
    local scr = lvgl.obj_create(nil, nil)
    local btn = lvgl.btn_create(scr)
    local btn2 = lvgl.btn_create(scr)
    lvgl.obj_align(btn, lvgl.scr_act(), lvgl.ALIGN_CENTER, 0, 0)
    lvgl.obj_align(btn2, lvgl.scr_act(), lvgl.ALIGN_CENTER, 0, 50)
    local label = lvgl.label_create(btn)
    local label2 = lvgl.label_create(btn2)
    lvgl.label_set_text(label, "LuatOS!")
    lvgl.label_set_text(label2, "共和国")
    local font = lvgl.font_get("opposans_m_10")
    lvgl.obj_set_style_local_text_font(label2, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, font);
    
    lvgl.scr_load(scr)

    sys.wait(1000)
    -- lvgl.obj_set_style_local_text_font(label2, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_102"));
end)

sys.run()

