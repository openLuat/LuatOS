sys = require("sys")

sys.taskInit(function ()
    sys.wait(1000)

    lvgl.init()

    local screen_label4 = lvgl.label_create(nil, nil)
    lvgl.label_set_text(screen_label4, "这是一个中文字体测试程序abcdABCD1234")
    --local font = lvgl.font_load("/lv_font_opposans_m_24.bin") -- /OPPOSans.bin
    local font = lvgl.font_load("/OPPOSans.bin")
    log.info("font", font)
    lvgl.obj_set_style_local_text_font(screen_label4, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, font)
    lvgl.scr_load(screen_label4)
end)


sys.run()
