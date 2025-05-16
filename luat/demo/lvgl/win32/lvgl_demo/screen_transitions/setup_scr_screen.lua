local setup = {}

local ui = {}

local function screen_btn1event_handler( obj, event)
	if event == lvgl.EVENT_CLICKED then
		lvgl.obj_clean(lvgl.scr_act())
		ui = {}
		setup.setup_scr_screen2(ui)
	end
end

local function screen2_btn1_1event_handler( obj, event)
	if event == lvgl.EVENT_CLICKED then
		lvgl.obj_clean(lvgl.scr_act())
		ui = {}
		setup.setup_scr_screen(ui)
	end
end

function setup.setup_scr_screen(ui)
	--Write codes screen
	ui.screen = lvgl.obj_create(nil, nil)

	--Write codes screen_label0
	ui.screen_label0 = lvgl.label_create(ui.screen, nil)
	lvgl.label_set_text(ui.screen_label0, "screen1")
	lvgl.label_set_long_mode(ui.screen_label0, lvgl.LABEL_LONG_BREAK)
	lvgl.label_set_align(ui.screen_label0, lvgl.LABEL_ALIGN_CENTER)

	--Write style lvgl.LABEL_PART_MAIN for screen_label0
	-- local style_screen_label0_main
	-- lvgl.style_init(style_screen_label0_main)
	local style_screen_label0_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_screen_label0_main
	lvgl.style_set_radius(style_screen_label0_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_bg_color(style_screen_label0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen_label0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen_label0_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_label0_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_text_color(style_screen_label0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.style_set_text_font(style_screen_label0_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_12"))
	lvgl.style_set_text_letter_space(style_screen_label0_main, lvgl.STATE_DEFAULT, 2)
	lvgl.style_set_pad_left(style_screen_label0_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_right(style_screen_label0_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_top(style_screen_label0_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_bottom(style_screen_label0_main, lvgl.STATE_DEFAULT, 0)
	lvgl.obj_add_style(ui.screen_label0, lvgl.LABEL_PART_MAIN, style_screen_label0_main)
	lvgl.obj_set_pos(ui.screen_label0, 180, 240)
	lvgl.obj_set_size(ui.screen_label0, 100, 0)

	--Write codes screen_btn1
	ui.screen_btn1 = lvgl.btn_create(ui.screen, nil)

	--Write style lvgl.BTN_PART_MAIN for screen_btn1
	-- local style_screen_btn1_main
	-- lvgl.style_init(style_screen_btn1_main)
	local style_screen_btn1_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_screen_btn1_main
	lvgl.style_set_radius(style_screen_btn1_main, lvgl.STATE_DEFAULT, 50)
	lvgl.style_set_bg_color(style_screen_btn1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen_btn1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen_btn1_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_btn1_main, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_border_color(style_screen_btn1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_border_width(style_screen_btn1_main, lvgl.STATE_DEFAULT, 2)
	lvgl.style_set_border_opa(style_screen_btn1_main, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_outline_color(style_screen_btn1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9))
	lvgl.style_set_outline_opa(style_screen_btn1_main, lvgl.STATE_DEFAULT, 255)

	--Write style state: lvgl.STATE_FOCUSED for style_screen_btn1_main
	lvgl.style_set_radius(style_screen_btn1_main, lvgl.STATE_FOCUSED, 50)
	lvgl.style_set_bg_color(style_screen_btn1_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen_btn1_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen_btn1_main, lvgl.STATE_FOCUSED, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_btn1_main, lvgl.STATE_FOCUSED, 255)
	lvgl.style_set_border_color(style_screen_btn1_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_border_width(style_screen_btn1_main, lvgl.STATE_FOCUSED, 2)
	lvgl.style_set_border_opa(style_screen_btn1_main, lvgl.STATE_FOCUSED, 255)
	lvgl.style_set_outline_color(style_screen_btn1_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xd4, 0xd7, 0xd9))
	lvgl.style_set_outline_opa(style_screen_btn1_main, lvgl.STATE_FOCUSED, 255)

	--Write style state: lvgl.STATE_PRESSED for style_screen_btn1_main
	lvgl.style_set_radius(style_screen_btn1_main, lvgl.STATE_PRESSED, 50)
	lvgl.style_set_bg_color(style_screen_btn1_main, lvgl.STATE_PRESSED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen_btn1_main, lvgl.STATE_PRESSED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen_btn1_main, lvgl.STATE_PRESSED, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_btn1_main, lvgl.STATE_PRESSED, 255)
	lvgl.style_set_border_color(style_screen_btn1_main, lvgl.STATE_PRESSED, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_border_width(style_screen_btn1_main, lvgl.STATE_PRESSED, 2)
	lvgl.style_set_border_opa(style_screen_btn1_main, lvgl.STATE_PRESSED, 255)
	lvgl.style_set_outline_color(style_screen_btn1_main, lvgl.STATE_PRESSED, lvgl.color_make(0xd4, 0xd7, 0xd9))
	lvgl.style_set_outline_opa(style_screen_btn1_main, lvgl.STATE_PRESSED, 100)

	--Write style state: lvgl.STATE_CHECKED for style_screen_btn1_main
	lvgl.style_set_radius(style_screen_btn1_main, lvgl.STATE_CHECKED, 50)
	lvgl.style_set_bg_color(style_screen_btn1_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen_btn1_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen_btn1_main, lvgl.STATE_CHECKED, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_btn1_main, lvgl.STATE_CHECKED, 255)
	lvgl.style_set_border_color(style_screen_btn1_main, lvgl.STATE_CHECKED, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_border_width(style_screen_btn1_main, lvgl.STATE_CHECKED, 2)
	lvgl.style_set_border_opa(style_screen_btn1_main, lvgl.STATE_CHECKED, 255)
	lvgl.style_set_outline_color(style_screen_btn1_main, lvgl.STATE_CHECKED, lvgl.color_make(0xd4, 0xd7, 0xd9))
	lvgl.style_set_outline_opa(style_screen_btn1_main, lvgl.STATE_CHECKED, 255)
	lvgl.obj_add_style(ui.screen_btn1, lvgl.BTN_PART_MAIN, style_screen_btn1_main)
	lvgl.obj_set_pos(ui.screen_btn1, 345, 235)
	lvgl.obj_set_size(ui.screen_btn1, 100, 25)
	ui.screen_btn1_label = lvgl.label_create(ui.screen_btn1, nil)
	lvgl.label_set_text(ui.screen_btn1_label, "next screen")
	lvgl.obj_set_style_local_text_color(ui.screen_btn1_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.obj_set_style_local_text_font(ui.screen_btn1_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_12"))

	--Write codes screen_gauge2
	ui.screen_gauge2 = lvgl.gauge_create(ui.screen, nil)

	--Write style lvgl.GAUGE_PART_MAIN for screen_gauge2
	-- local style_screen_gauge2_main
	-- lvgl.style_init(style_screen_gauge2_main)
	local style_screen_gauge2_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_screen_gauge2_main
	lvgl.style_set_bg_color(style_screen_gauge2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen_gauge2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen_gauge2_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_gauge2_main, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_text_color(style_screen_gauge2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x39, 0x3c, 0x41))
	lvgl.style_set_text_font(style_screen_gauge2_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_12"))
	lvgl.style_set_text_letter_space(style_screen_gauge2_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_inner(style_screen_gauge2_main, lvgl.STATE_DEFAULT, 15)
	lvgl.style_set_line_color(style_screen_gauge2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x8b, 0x89, 0x8b))
	lvgl.style_set_line_width(style_screen_gauge2_main, lvgl.STATE_DEFAULT, 3)
	lvgl.style_set_line_opa(style_screen_gauge2_main, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_scale_grad_color(style_screen_gauge2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x8b, 0x89, 0x8b))
	lvgl.style_set_scale_end_color(style_screen_gauge2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0xa1, 0xb5))
	lvgl.style_set_scale_width(style_screen_gauge2_main, lvgl.STATE_DEFAULT, 9)
	lvgl.style_set_scale_border_width(style_screen_gauge2_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_scale_end_border_width(style_screen_gauge2_main, lvgl.STATE_DEFAULT, 5)
	lvgl.style_set_scale_end_line_width(style_screen_gauge2_main, lvgl.STATE_DEFAULT, 4)
	lvgl.obj_add_style(ui.screen_gauge2, lvgl.GAUGE_PART_MAIN, style_screen_gauge2_main)

	--Write style lvgl.GAUGE_PART_MAJOR for screen_gauge2
	-- local style_screen_gauge2_major
	-- lvgl.style_init(style_screen_gauge2_major)
	local style_screen_gauge2_major = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_screen_gauge2_major
	lvgl.style_set_line_color(style_screen_gauge2_major, lvgl.STATE_DEFAULT, lvgl.color_make(0x8b, 0x89, 0x8b))
	lvgl.style_set_line_width(style_screen_gauge2_major, lvgl.STATE_DEFAULT, 5)
	lvgl.style_set_line_opa(style_screen_gauge2_major, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_scale_grad_color(style_screen_gauge2_major, lvgl.STATE_DEFAULT, lvgl.color_make(0x8b, 0x89, 0x8b))
	lvgl.style_set_scale_end_color(style_screen_gauge2_major, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0xa1, 0xb5))
	lvgl.style_set_scale_width(style_screen_gauge2_major, lvgl.STATE_DEFAULT, 16)
	lvgl.style_set_scale_end_line_width(style_screen_gauge2_major, lvgl.STATE_DEFAULT, 5)
	lvgl.obj_add_style(ui.screen_gauge2, lvgl.GAUGE_PART_MAJOR, style_screen_gauge2_major)

	--Write style lvgl.GAUGE_PART_NEEDLE for screen_gauge2
	-- local style_screen_gauge2_needle
	-- lvgl.style_init(style_screen_gauge2_needle)
	local style_screen_gauge2_needle = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_screen_gauge2_needle
	lvgl.style_set_size(style_screen_gauge2_needle, lvgl.STATE_DEFAULT, 21)
	lvgl.style_set_bg_color(style_screen_gauge2_needle, lvgl.STATE_DEFAULT, lvgl.color_make(0x41, 0x48, 0x5a))
	lvgl.style_set_bg_grad_color(style_screen_gauge2_needle, lvgl.STATE_DEFAULT, lvgl.color_make(0x41, 0x48, 0x5a))
	lvgl.style_set_bg_grad_dir(style_screen_gauge2_needle, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_gauge2_needle, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_pad_inner(style_screen_gauge2_needle, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_line_width(style_screen_gauge2_needle, lvgl.STATE_DEFAULT, 4)
	lvgl.style_set_line_opa(style_screen_gauge2_needle, lvgl.STATE_DEFAULT, 255)
	lvgl.obj_add_style(ui.screen_gauge2, lvgl.GAUGE_PART_NEEDLE, style_screen_gauge2_needle)
	lvgl.obj_set_pos(ui.screen_gauge2, 147, 20)
	lvgl.obj_set_size(ui.screen_gauge2, 200, 200)
	lvgl.gauge_set_scale(ui.screen_gauge2, 300, 37, 19)
	lvgl.gauge_set_range(ui.screen_gauge2, 0, 180)
	-- local lvgl.color_t needle_colors_screen_gauge2[1]
	-- needle_colors_screen_gauge2[0] = lvgl.color_make(0xff, 0x00, 0x00)
	-- lvgl.gauge_set_needle_count(ui.screen_gauge2, 1, needle_colors_screen_gauge2)
	lvgl.gauge_set_needle_count(ui.screen_gauge2, 1, lvgl.color_make(0xff, 0x00, 0x00))
	lvgl.gauge_set_critical_value(ui.screen_gauge2, 120)
	lvgl.gauge_set_value(ui.screen_gauge2, 0, 0)

	lvgl.obj_set_event_cb(ui.screen_btn1, screen_btn1event_handler)
	lvgl.scr_load(ui.screen)
end

function setup.setup_scr_screen2(ui)
	--Write codes screen2
	ui.screen2 = lvgl.obj_create(nil, nil)

	--Write codes screen2_label0
	ui.screen2_label0 = lvgl.label_create(ui.screen2, nil)
	lvgl.label_set_text(ui.screen2_label0, "screen2")
	lvgl.label_set_long_mode(ui.screen2_label0, lvgl.LABEL_LONG_BREAK)
	lvgl.label_set_align(ui.screen2_label0, lvgl.LABEL_ALIGN_CENTER)

	--Write style lvgl.LABEL_PART_MAIN for screen2_label0
	-- local style_screen2_label0_main
	-- lvgl.style_init(style_screen2_label0_main)
	local style_screen2_label0_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_screen2_label0_main
	lvgl.style_set_radius(style_screen2_label0_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_bg_color(style_screen2_label0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen2_label0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen2_label0_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen2_label0_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_text_color(style_screen2_label0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.style_set_text_font(style_screen2_label0_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_12"))
	lvgl.style_set_text_letter_space(style_screen2_label0_main, lvgl.STATE_DEFAULT, 2)
	lvgl.style_set_pad_left(style_screen2_label0_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_right(style_screen2_label0_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_top(style_screen2_label0_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_bottom(style_screen2_label0_main, lvgl.STATE_DEFAULT, 0)
	lvgl.obj_add_style(ui.screen2_label0, lvgl.LABEL_PART_MAIN, style_screen2_label0_main)
	lvgl.obj_set_pos(ui.screen2_label0, 180, 240)
	lvgl.obj_set_size(ui.screen2_label0, 100, 0)

	--Write codes screen2_btn1_1
	ui.screen2_btn1_1 = lvgl.btn_create(ui.screen2, nil)

	--Write style lvgl.BTN_PART_MAIN for screen2_btn1_1
	-- local style_screen2_btn1_1_main
	-- lvgl.style_init(style_screen2_btn1_1_main)
	local style_screen2_btn1_1_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_screen2_btn1_1_main
	lvgl.style_set_radius(style_screen2_btn1_1_main, lvgl.STATE_DEFAULT, 50)
	lvgl.style_set_bg_color(style_screen2_btn1_1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen2_btn1_1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen2_btn1_1_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen2_btn1_1_main, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_border_color(style_screen2_btn1_1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_border_width(style_screen2_btn1_1_main, lvgl.STATE_DEFAULT, 2)
	lvgl.style_set_border_opa(style_screen2_btn1_1_main, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_outline_color(style_screen2_btn1_1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9))
	lvgl.style_set_outline_opa(style_screen2_btn1_1_main, lvgl.STATE_DEFAULT, 255)

	--Write style state: lvgl.STATE_FOCUSED for style_screen2_btn1_1_main
	lvgl.style_set_radius(style_screen2_btn1_1_main, lvgl.STATE_FOCUSED, 50)
	lvgl.style_set_bg_color(style_screen2_btn1_1_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen2_btn1_1_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen2_btn1_1_main, lvgl.STATE_FOCUSED, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen2_btn1_1_main, lvgl.STATE_FOCUSED, 255)
	lvgl.style_set_border_color(style_screen2_btn1_1_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_border_width(style_screen2_btn1_1_main, lvgl.STATE_FOCUSED, 2)
	lvgl.style_set_border_opa(style_screen2_btn1_1_main, lvgl.STATE_FOCUSED, 255)
	lvgl.style_set_outline_color(style_screen2_btn1_1_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xd4, 0xd7, 0xd9))
	lvgl.style_set_outline_opa(style_screen2_btn1_1_main, lvgl.STATE_FOCUSED, 255)

	--Write style state: lvgl.STATE_PRESSED for style_screen2_btn1_1_main
	lvgl.style_set_radius(style_screen2_btn1_1_main, lvgl.STATE_PRESSED, 50)
	lvgl.style_set_bg_color(style_screen2_btn1_1_main, lvgl.STATE_PRESSED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen2_btn1_1_main, lvgl.STATE_PRESSED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen2_btn1_1_main, lvgl.STATE_PRESSED, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen2_btn1_1_main, lvgl.STATE_PRESSED, 255)
	lvgl.style_set_border_color(style_screen2_btn1_1_main, lvgl.STATE_PRESSED, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_border_width(style_screen2_btn1_1_main, lvgl.STATE_PRESSED, 2)
	lvgl.style_set_border_opa(style_screen2_btn1_1_main, lvgl.STATE_PRESSED, 255)
	lvgl.style_set_outline_color(style_screen2_btn1_1_main, lvgl.STATE_PRESSED, lvgl.color_make(0xd4, 0xd7, 0xd9))
	lvgl.style_set_outline_opa(style_screen2_btn1_1_main, lvgl.STATE_PRESSED, 100)

	--Write style state: lvgl.STATE_CHECKED for style_screen2_btn1_1_main
	lvgl.style_set_radius(style_screen2_btn1_1_main, lvgl.STATE_CHECKED, 50)
	lvgl.style_set_bg_color(style_screen2_btn1_1_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen2_btn1_1_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen2_btn1_1_main, lvgl.STATE_CHECKED, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen2_btn1_1_main, lvgl.STATE_CHECKED, 255)
	lvgl.style_set_border_color(style_screen2_btn1_1_main, lvgl.STATE_CHECKED, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_border_width(style_screen2_btn1_1_main, lvgl.STATE_CHECKED, 2)
	lvgl.style_set_border_opa(style_screen2_btn1_1_main, lvgl.STATE_CHECKED, 255)
	lvgl.style_set_outline_color(style_screen2_btn1_1_main, lvgl.STATE_CHECKED, lvgl.color_make(0xd4, 0xd7, 0xd9))
	lvgl.style_set_outline_opa(style_screen2_btn1_1_main, lvgl.STATE_CHECKED, 255)
	lvgl.obj_add_style(ui.screen2_btn1_1, lvgl.BTN_PART_MAIN, style_screen2_btn1_1_main)
	lvgl.obj_set_pos(ui.screen2_btn1_1, 30, 235)
	lvgl.obj_set_size(ui.screen2_btn1_1, 100, 25)
	ui.screen2_btn1_1_label = lvgl.label_create(ui.screen2_btn1_1, nil)
	lvgl.label_set_text(ui.screen2_btn1_1_label, "next screen")
	lvgl.obj_set_style_local_text_color(ui.screen2_btn1_1_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.obj_set_style_local_text_font(ui.screen2_btn1_1_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_12"))

	--Write codes screen2_chart2
	ui.screen2_chart2 = lvgl.chart_create(ui.screen2, nil)

	--Write style lvgl.CHART_PART_BG for screen2_chart2
	-- local style_screen2_chart2_bg
	-- lvgl.style_init(style_screen2_chart2_bg)
	local style_screen2_chart2_bg = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_screen2_chart2_bg
	lvgl.style_set_bg_color(style_screen2_chart2_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen2_chart2_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen2_chart2_bg, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen2_chart2_bg, lvgl.STATE_DEFAULT, 255)

	--Write style state: lvgl.STATE_FOCUSED for style_screen2_chart2_bg
	lvgl.style_set_border_color(style_screen2_chart2_bg, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_border_width(style_screen2_chart2_bg, lvgl.STATE_FOCUSED, 0)
	lvgl.obj_add_style(ui.screen2_chart2, lvgl.CHART_PART_BG, style_screen2_chart2_bg)

	--Write style lvgl.CHART_PART_SERIES_BG for screen2_chart2
	-- local style_screen2_chart2_series_bg
	-- lvgl.style_init(style_screen2_chart2_series_bg)
	local style_screen2_chart2_series_bg = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_screen2_chart2_series_bg
	lvgl.style_set_line_color(style_screen2_chart2_series_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xe8, 0xe8, 0xe8))
	lvgl.style_set_line_width(style_screen2_chart2_series_bg, lvgl.STATE_DEFAULT, 2)
	lvgl.style_set_line_opa(style_screen2_chart2_series_bg, lvgl.STATE_DEFAULT, 255)
	lvgl.obj_add_style(ui.screen2_chart2, lvgl.CHART_PART_SERIES_BG, style_screen2_chart2_series_bg)
	lvgl.obj_set_pos(ui.screen2_chart2, 129, 36)
	lvgl.obj_set_size(ui.screen2_chart2, 205, 155)
	lvgl.chart_set_type(ui.screen2_chart2,lvgl.CHART_TYPE_LINE)
	lvgl.chart_set_range(ui.screen2_chart2,0,100)
	lvgl.chart_set_div_line_count(ui.screen2_chart2, 3, 5)
	local screen2_chart2_0 = lvgl.chart_add_series(ui.screen2_chart2, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.chart_set_next(ui.screen2_chart2, screen2_chart2_0,20)
	lvgl.chart_set_next(ui.screen2_chart2, screen2_chart2_0,30)
	lvgl.chart_set_next(ui.screen2_chart2, screen2_chart2_0,40)
	lvgl.chart_set_next(ui.screen2_chart2, screen2_chart2_0,10)
	lvgl.chart_set_next(ui.screen2_chart2, screen2_chart2_0,50)
	lvgl.chart_set_next(ui.screen2_chart2, screen2_chart2_0,70)
	lvgl.chart_set_next(ui.screen2_chart2, screen2_chart2_0,30)
	lvgl.chart_set_next(ui.screen2_chart2, screen2_chart2_0,10)
	lvgl.chart_set_next(ui.screen2_chart2, screen2_chart2_0,30)

	--Init events for screen
	lvgl.obj_set_event_cb(ui.screen2_btn1_1, screen2_btn1_1event_handler)
	lvgl.scr_load(ui.screen2)
end

function setup.setup_ui()
	setup.setup_scr_screen(ui)
end

return setup