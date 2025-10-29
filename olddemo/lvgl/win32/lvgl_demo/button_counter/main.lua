--[[
@module  lvgl
@summary button_counter_demo
@author  Dozingfiretruck
@version 1.0
@date    2021.07.12
]]

_G.sys = require "sys"

log.info("sys", "from win32")

local ui = {}
local counter = 0

local function screen_plusevent_handler(obj, event)
	if event == lvgl.EVENT_CLICKED then
		counter = counter+1
		lvgl.obj_set_style_local_text_font(ui.screen_counter, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_16"))
		lvgl.label_set_text(ui.screen_counter, string.format("%d",counter))
	end
end

local function screen_minusevent_handler(obj, event)
	if event == lvgl.EVENT_CLICKED then
		if counter>0 then counter = counter-1 end
		lvgl.obj_set_style_local_text_font(ui.screen_counter, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_16"))
		lvgl.label_set_text(ui.screen_counter, string.format("%d",counter))
	end
end

sys.taskInit(function ()
    sys.wait(1000)

    log.info("lvgl", lvgl.init(480,320))

	--Write codes screen
	ui.screen = lvgl.obj_create(nil, nil)

	--Write codes screen_counter
	ui.screen_counter = lvgl.label_create(ui.screen, nil)
	lvgl.label_set_text(ui.screen_counter, "0")
	lvgl.label_set_long_mode(ui.screen_counter, lvgl.LABEL_LONG_BREAK)
	lvgl.label_set_align(ui.screen_counter, lvgl.LABEL_ALIGN_CENTER)

	--Write style lvgl.LABEL_PART_MAIN for screen_counter
	-- local style_screen_counter_main
	-- lvgl.style_init(style_screen_counter_main)
	local style_screen_counter_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_screen_counter_main
	lvgl.style_set_radius(style_screen_counter_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_bg_color(style_screen_counter_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen_counter_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen_counter_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_counter_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_text_color(style_screen_counter_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.style_set_text_font(style_screen_counter_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_16"))
	lvgl.style_set_text_letter_space(style_screen_counter_main, lvgl.STATE_DEFAULT, 2)
	lvgl.style_set_pad_left(style_screen_counter_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_right(style_screen_counter_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_top(style_screen_counter_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_bottom(style_screen_counter_main, lvgl.STATE_DEFAULT, 0)
	lvgl.obj_add_style(ui.screen_counter, lvgl.LABEL_PART_MAIN, style_screen_counter_main)
	lvgl.obj_set_pos(ui.screen_counter, 183, 54)
	lvgl.obj_set_size(ui.screen_counter, 100, 0)

	--Write codes screen_plus
	ui.screen_plus = lvgl.btn_create(ui.screen, nil)

	--Write style lvgl.BTN_PART_MAIN for screen_plus
	-- local style_screen_plus_main
	-- lvgl.style_init(style_screen_plus_main)
	local style_screen_plus_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_screen_plus_main
	lvgl.style_set_radius(style_screen_plus_main, lvgl.STATE_DEFAULT, 50)
	lvgl.style_set_bg_color(style_screen_plus_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen_plus_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen_plus_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_plus_main, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_border_color(style_screen_plus_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_border_width(style_screen_plus_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_border_opa(style_screen_plus_main, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_outline_color(style_screen_plus_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_outline_opa(style_screen_plus_main, lvgl.STATE_DEFAULT, 255)

	--Write style state: lvgl.STATE_FOCUSED for style_screen_plus_main
	lvgl.style_set_radius(style_screen_plus_main, lvgl.STATE_FOCUSED, 50)
	lvgl.style_set_bg_color(style_screen_plus_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen_plus_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen_plus_main, lvgl.STATE_FOCUSED, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_plus_main, lvgl.STATE_FOCUSED, 255)
	lvgl.style_set_border_color(style_screen_plus_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_border_width(style_screen_plus_main, lvgl.STATE_FOCUSED, 1)
	lvgl.style_set_border_opa(style_screen_plus_main, lvgl.STATE_FOCUSED, 255)
	lvgl.style_set_outline_color(style_screen_plus_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_outline_opa(style_screen_plus_main, lvgl.STATE_FOCUSED, 255)

	--Write style state: lvgl.STATE_PRESSED for style_screen_plus_main
	lvgl.style_set_radius(style_screen_plus_main, lvgl.STATE_PRESSED, 50)
	lvgl.style_set_bg_color(style_screen_plus_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2e, 0x7c, 0xb8))
	lvgl.style_set_bg_grad_color(style_screen_plus_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2e, 0x7c, 0xb8))
	lvgl.style_set_bg_grad_dir(style_screen_plus_main, lvgl.STATE_PRESSED, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_plus_main, lvgl.STATE_PRESSED, 255)
	lvgl.style_set_border_color(style_screen_plus_main, lvgl.STATE_PRESSED, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_border_width(style_screen_plus_main, lvgl.STATE_PRESSED, 0)
	lvgl.style_set_border_opa(style_screen_plus_main, lvgl.STATE_PRESSED, 255)
	lvgl.style_set_outline_color(style_screen_plus_main, lvgl.STATE_PRESSED, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_outline_opa(style_screen_plus_main, lvgl.STATE_PRESSED, 100)

	--Write style state: lvgl.STATE_CHECKED for style_screen_plus_main
	lvgl.style_set_radius(style_screen_plus_main, lvgl.STATE_CHECKED, 50)
	lvgl.style_set_bg_color(style_screen_plus_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen_plus_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen_plus_main, lvgl.STATE_CHECKED, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_plus_main, lvgl.STATE_CHECKED, 255)
	lvgl.style_set_border_color(style_screen_plus_main, lvgl.STATE_CHECKED, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_border_width(style_screen_plus_main, lvgl.STATE_CHECKED, 2)
	lvgl.style_set_border_opa(style_screen_plus_main, lvgl.STATE_CHECKED, 255)
	lvgl.style_set_outline_color(style_screen_plus_main, lvgl.STATE_CHECKED, lvgl.color_make(0xd4, 0xd7, 0xd9))
	lvgl.style_set_outline_opa(style_screen_plus_main, lvgl.STATE_CHECKED, 255)
	lvgl.obj_add_style(ui.screen_plus, lvgl.BTN_PART_MAIN, style_screen_plus_main)
	lvgl.obj_set_pos(ui.screen_plus, 86, 150)
	lvgl.obj_set_size(ui.screen_plus, 100, 50)
	ui.screen_plus_label = lvgl.label_create(ui.screen_plus, nil)
	lvgl.label_set_text(ui.screen_plus_label, "Plus")
	lvgl.obj_set_style_local_text_color(ui.screen_plus_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.obj_set_style_local_text_font(ui.screen_plus_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_16"))

	--Write codes screen_minus
	ui.screen_minus = lvgl.btn_create(ui.screen, nil)

	--Write style lvgl.BTN_PART_MAIN for screen_minus
	-- local style_screen_minus_main
	-- lvgl.style_init(style_screen_minus_main)
	local style_screen_minus_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_screen_minus_main
	lvgl.style_set_radius(style_screen_minus_main, lvgl.STATE_DEFAULT, 50)
	lvgl.style_set_bg_color(style_screen_minus_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen_minus_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen_minus_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_minus_main, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_border_color(style_screen_minus_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_border_width(style_screen_minus_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_border_opa(style_screen_minus_main, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_outline_color(style_screen_minus_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_outline_opa(style_screen_minus_main, lvgl.STATE_DEFAULT, 255)

	--Write style state: lvgl.STATE_FOCUSED for style_screen_minus_main
	lvgl.style_set_radius(style_screen_minus_main, lvgl.STATE_FOCUSED, 50)
	lvgl.style_set_bg_color(style_screen_minus_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen_minus_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen_minus_main, lvgl.STATE_FOCUSED, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_minus_main, lvgl.STATE_FOCUSED, 255)
	lvgl.style_set_border_color(style_screen_minus_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_border_width(style_screen_minus_main, lvgl.STATE_FOCUSED, 1)
	lvgl.style_set_border_opa(style_screen_minus_main, lvgl.STATE_FOCUSED, 255)
	lvgl.style_set_outline_color(style_screen_minus_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_outline_opa(style_screen_minus_main, lvgl.STATE_FOCUSED, 255)

	--Write style state: lvgl.STATE_PRESSED for style_screen_minus_main
	lvgl.style_set_radius(style_screen_minus_main, lvgl.STATE_PRESSED, 50)
	lvgl.style_set_bg_color(style_screen_minus_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2e, 0x7c, 0xb8))
	lvgl.style_set_bg_grad_color(style_screen_minus_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2e, 0x7c, 0xb8))
	lvgl.style_set_bg_grad_dir(style_screen_minus_main, lvgl.STATE_PRESSED, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_minus_main, lvgl.STATE_PRESSED, 255)
	lvgl.style_set_border_color(style_screen_minus_main, lvgl.STATE_PRESSED, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_border_width(style_screen_minus_main, lvgl.STATE_PRESSED, 0)
	lvgl.style_set_border_opa(style_screen_minus_main, lvgl.STATE_PRESSED, 255)
	lvgl.style_set_outline_color(style_screen_minus_main, lvgl.STATE_PRESSED, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_outline_opa(style_screen_minus_main, lvgl.STATE_PRESSED, 100)

	--Write style state: lvgl.STATE_CHECKED for style_screen_minus_main
	lvgl.style_set_radius(style_screen_minus_main, lvgl.STATE_CHECKED, 50)
	lvgl.style_set_bg_color(style_screen_minus_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen_minus_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen_minus_main, lvgl.STATE_CHECKED, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_minus_main, lvgl.STATE_CHECKED, 255)
	lvgl.style_set_border_color(style_screen_minus_main, lvgl.STATE_CHECKED, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_border_width(style_screen_minus_main, lvgl.STATE_CHECKED, 2)
	lvgl.style_set_border_opa(style_screen_minus_main, lvgl.STATE_CHECKED, 255)
	lvgl.style_set_outline_color(style_screen_minus_main, lvgl.STATE_CHECKED, lvgl.color_make(0xd4, 0xd7, 0xd9))
	lvgl.style_set_outline_opa(style_screen_minus_main, lvgl.STATE_CHECKED, 255)
	lvgl.obj_add_style(ui.screen_minus, lvgl.BTN_PART_MAIN, style_screen_minus_main)
	lvgl.obj_set_pos(ui.screen_minus, 270, 150)
	lvgl.obj_set_size(ui.screen_minus, 100, 50)
	ui.screen_minus_label = lvgl.label_create(ui.screen_minus, nil)
	lvgl.label_set_text(ui.screen_minus_label, "Minus")
	lvgl.obj_set_style_local_text_color(ui.screen_minus_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.obj_set_style_local_text_font(ui.screen_minus_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_16"))


	lvgl.obj_set_event_cb(ui.screen_plus, screen_plusevent_handler)
	lvgl.obj_set_event_cb(ui.screen_minus, screen_minusevent_handler)

    lvgl.scr_load(ui.screen)

    while true do
        sys.wait(1000)
		log.info("main", os.date())
    end
end)

sys.run()
