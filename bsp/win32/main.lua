

local sys = require "sys"

log.info("sys", "from win32")

sys.taskInit(function ()
    sys.wait(1000)

    log.info("lvgl", lvgl.init())

    lvgl.disp_set_bg_color(nil, 0xFFFFFF)
    local scr = lvgl.obj_create(nil, nil)
    local btn = lvgl.btn_create(scr)
    local btn2 = lvgl.btn_create(scr)
    lvgl.obj_align(btn, lvgl.scr_act(), lvgl.ALIGN_CENTER, 0, 0)
    lvgl.obj_align(btn2, lvgl.scr_act(), lvgl.ALIGN_CENTER, 0, 50)
    local label = lvgl.label_create(btn)
    local label2 = lvgl.label_create(btn2)
    lvgl.label_set_text(label, "LuatOS!")
    lvgl.label_set_text(label2, "Hi")
    --lvgl.disp_set_bg_color(lvgl.COLOR_WHITE)

    -- 二维码测试
    --local qrcode = lvgl.qrcode_create(scr, 100, 0x3333ff, 0xeeeeff)
    local qrcode = lvgl.qrcode_create(scr, 100)
    lvgl.qrcode_update(qrcode, "https://luatos.com")
    lvgl.obj_align(qrcode, lvgl.scr_act(), lvgl.ALIGN_CENTER, -100, -100)

    local gif = lvgl.gif_create(scr, "S/example.gif")
    if gif then
        lvgl.obj_align(gif, lvgl.scr_act(), lvgl.ALIGN_CENTER, 100, -100)
    end

    lvgl.scr_load(scr)

    lvgl.obj_set_event_cb(btn, function(obj, event)
        log.info("event", obj, event)
    end)

    log.info("abc", "=====================")

    while true do
        lvgl.obj_align(btn2, lvgl.scr_act(), lvgl.ALIGN_CENTER, 0, 50)
        sys.wait(500)
        lvgl.obj_align(btn2, lvgl.scr_act(), lvgl.ALIGN_CENTER, 50, 50)
        sys.wait(500)
        lvgl.obj_align(btn2, lvgl.scr_act(), lvgl.ALIGN_CENTER, 50, 0)
        sys.wait(500)
        lvgl.obj_align(btn2, lvgl.scr_act(), lvgl.ALIGN_CENTER, 0, 100)
        sys.wait(500)
    end
end)

sys.run()
