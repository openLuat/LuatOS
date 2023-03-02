--[[
@module  lvgl
@summary slider_pregress_demo
@author  Dozingfiretruck
@version 1.0
@date    2021.07.12
]]

sys = require("sys")

log.info("sys", "from win32")

local ui = {}

local function screen_slider0event_handler(obj, event)
    if event == lvgl.EVENT_VALUE_CHANGED then
            local slider_value = lvgl.slider_get_value(ui.screen_slider0)
            lvgl.obj_set_style_local_image_opa(ui.screen_img2, lvgl.IMG_PART_MAIN, lvgl.STATE_DEFAULT,  slider_value * 2.5)
            lvgl.label_set_text(ui.screen_label4, slider_value)
    end
end

sys.taskInit(function ()
    sys.wait(1000)

    log.info("lvgl", lvgl.init(480,320))

    --Write codes screen
    ui.screen = lvgl.obj_create(nil, nil)

    --Write codes screen_img2
    ui.screen_img2 = lvgl.img_create(ui.screen, nil)

    --Write style LV_IMG_PART_MAIN for screen_img2
	-- local style_screen_img2_main
	-- lvgl.style_init(style_screen_img2_main)
    local style_screen_img2_main = lvgl.style_create()

    --Write style state: LV_STATE_DEFAULT for style_screen_img2_main
    lvgl.style_set_image_recolor(style_screen_img2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_image_recolor_opa(style_screen_img2_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_image_opa(style_screen_img2_main, lvgl.STATE_DEFAULT, 125)
	lvgl.obj_add_style(ui.screen_img2, lvgl.IMG_PART_MAIN, style_screen_img2_main)
	lvgl.obj_set_pos(ui.screen_img2, 214, 34)
	lvgl.obj_set_size(ui.screen_img2, 224, 174)
	lvgl.obj_set_click(ui.screen_img2, true)
    lvgl.img_set_src(ui.screen_img2,"/scan_example.png")
	lvgl.img_set_pivot(ui.screen_img2, 0,0)
	lvgl.img_set_angle(ui.screen_img2, 0)

    --Write codes screen_slider0
    ui.screen_slider0 = lvgl.slider_create(ui.screen, nil)

    --//Write style LV_SLIDER_PART_INDIC for screen_slider0
	-- local style_screen_slider0_indic
	-- lvgl.style_init(style_screen_slider0_indic)
    local style_screen_slider0_indic = lvgl.style_create()

	lvgl.style_set_radius(style_screen_slider0_indic, lvgl.STATE_DEFAULT, 50)
	lvgl.style_set_bg_color(style_screen_slider0_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0x02, 0xa2, 0xb1))
	lvgl.style_set_bg_grad_color(style_screen_slider0_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0x02, 0xa2, 0xb1))
	lvgl.style_set_bg_grad_dir(style_screen_slider0_indic, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_slider0_indic, lvgl.STATE_DEFAULT, 255)
	lvgl.obj_add_style(ui.screen_slider0, lvgl.SLIDER_PART_INDIC, style_screen_slider0_indic)


    --Write style lvgl.SLIDER_PART_BG for screen_slider0
	-- local style_screen_slider0_bg
	-- lvgl.style_init(style_screen_slider0_bg)
    local style_screen_slider0_bg = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_screen_slider0_bg
	lvgl.style_set_radius(style_screen_slider0_bg, lvgl.STATE_DEFAULT, 50)
	lvgl.style_set_bg_color(style_screen_slider0_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9))
	lvgl.style_set_bg_grad_color(style_screen_slider0_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9))
	lvgl.style_set_bg_grad_dir(style_screen_slider0_bg, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_slider0_bg, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_outline_color(style_screen_slider0_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9))
	lvgl.style_set_outline_opa(style_screen_slider0_bg, lvgl.STATE_DEFAULT, 0)

	--Write style state: lvgl.STATE_FOCUSED for style_screen_slider0_bg
	lvgl.style_set_outline_color(style_screen_slider0_bg, lvgl.STATE_FOCUSED, lvgl.color_make(0xd4, 0xd7, 0xd9))
	lvgl.style_set_outline_opa(style_screen_slider0_bg, lvgl.STATE_FOCUSED, 255)
	lvgl.obj_add_style(ui.screen_slider0, lvgl.SLIDER_PART_BG, style_screen_slider0_bg)

	--Write style lvgl.SLIDER_PART_KNOB for screen_slider0
	-- local lvgl.style_t style_screen_slider0_knob
	-- lvgl.style_init(style_screen_slider0_knob)
    local style_screen_slider0_knob = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_screen_slider0_knob
	lvgl.style_set_radius(style_screen_slider0_knob, lvgl.STATE_DEFAULT, 50)
	lvgl.style_set_bg_color(style_screen_slider0_knob, lvgl.STATE_DEFAULT, lvgl.color_make(0x02, 0xa2, 0xb1))
	lvgl.style_set_bg_grad_color(style_screen_slider0_knob, lvgl.STATE_DEFAULT, lvgl.color_make(0x02, 0xa2, 0xb1))
	lvgl.style_set_bg_grad_dir(style_screen_slider0_knob, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_slider0_knob, lvgl.STATE_DEFAULT, 255)
	lvgl.obj_add_style(ui.screen_slider0, lvgl.SLIDER_PART_KNOB, style_screen_slider0_knob)
	lvgl.obj_set_pos(ui.screen_slider0, 29, 144)
	lvgl.obj_set_size(ui.screen_slider0, 160, 8)
	lvgl.slider_set_range(ui.screen_slider0,0, 100)
	lvgl.slider_set_value(ui.screen_slider0,50,false)

	--Write codes screen_label3
	ui.screen_label3 = lvgl.label_create(ui.screen, nil)
	lvgl.label_set_text(ui.screen_label3, "Please slide")
	--lvgl.label_set_text(ui.screen_label3, "中文测试")
	lvgl.label_set_long_mode(ui.screen_label3, lvgl.LABEL_LONG_BREAK)
	lvgl.label_set_align(ui.screen_label3, lvgl.LABEL_ALIGN_CENTER)

	--Write style lvgl.LABEL_PART_MAIN for screen_label3
	-- local lvgl.style_t style_screen_label3_main
	-- lvgl.style_init(style_screen_label3_main)
    local style_screen_label3_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_screen_label3_main
	lvgl.style_set_radius(style_screen_label3_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_bg_color(style_screen_label3_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen_label3_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen_label3_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_label3_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_text_color(style_screen_label3_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.style_set_text_font(style_screen_label3_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_12"))
	lvgl.style_set_text_letter_space(style_screen_label3_main, lvgl.STATE_DEFAULT, 2)
	lvgl.style_set_pad_left(style_screen_label3_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_right(style_screen_label3_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_top(style_screen_label3_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_bottom(style_screen_label3_main, lvgl.STATE_DEFAULT, 0)
	lvgl.obj_add_style(ui.screen_label3, lvgl.LABEL_PART_MAIN, style_screen_label3_main)
	lvgl.obj_set_pos(ui.screen_label3, 58, 174)
	lvgl.obj_set_size(ui.screen_label3, 100, 0)

	--Write codes screen_label4
	ui.screen_label4 = lvgl.label_create(ui.screen, nil)
	lvgl.label_set_text(ui.screen_label4, "50")
	lvgl.label_set_long_mode(ui.screen_label4, lvgl.LABEL_LONG_BREAK)
	lvgl.label_set_align(ui.screen_label4, lvgl.LABEL_ALIGN_CENTER)

	--Write style lvgl.LABEL_PART_MAIN for screen_label4
	-- local lvgl.style_t style_screen_label4_main
	-- lvgl.style_init(style_screen_label4_main)
    local style_screen_label4_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_screen_label4_main
	lvgl.style_set_radius(style_screen_label4_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_bg_color(style_screen_label4_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen_label4_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen_label4_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_label4_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_text_color(style_screen_label4_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.style_set_text_font(style_screen_label4_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_48"))
	lvgl.style_set_text_letter_space(style_screen_label4_main, lvgl.STATE_DEFAULT, 2)
	lvgl.style_set_pad_left(style_screen_label4_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_right(style_screen_label4_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_top(style_screen_label4_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_bottom(style_screen_label4_main, lvgl.STATE_DEFAULT, 0)
	lvgl.obj_add_style(ui.screen_label4, lvgl.LABEL_PART_MAIN, style_screen_label4_main)
	lvgl.obj_set_pos(ui.screen_label4, 55, 43)
	lvgl.obj_set_size(ui.screen_label4, 100, 0)

    lvgl.obj_set_event_cb(ui.screen_slider0, screen_slider0event_handler)

    lvgl.scr_load(ui.screen)

    while true do
        sys.wait(500)
    end
end)

sys.run()
