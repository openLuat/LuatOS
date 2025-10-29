--[[
@module  lvgl
@summary switch_widget_demo
@author  Dozingfiretruck
@version 1.0
@date    2021.07.12
]]

sys = require("sys")

log.info("sys", "from win32")

local ui = {}

local function screen_sw2event_handler( obj, event)
	if event == lvgl.EVENT_VALUE_CHANGED then
		sw_state = lvgl.switch_get_state(ui.screen_sw2)
		if sw_state==false then
			lvgl.obj_set_hidden(ui.screen_ddlist1, true)
			lvgl.obj_set_hidden(ui.screen_roller1, false)
		else
			lvgl.obj_set_hidden(ui.screen_roller1, true)
			lvgl.obj_set_hidden(ui.screen_ddlist1, false)
		end
	end
end


sys.taskInit(function ()
    sys.wait(1000)

    log.info("lvgl", lvgl.init(480,320))

	--Write codes screen
	ui.screen = lvgl.obj_create(nil, nil)

	--Write codes screen_ddlist1
	ui.screen_ddlist1 = lvgl.dropdown_create(ui.screen, nil)
	lvgl.dropdown_set_options(ui.screen_ddlist1, "list1\nlist2\nlist3")
	lvgl.dropdown_set_max_height(ui.screen_ddlist1, 90)

	--Write style lvgl.DROPDOWN_PART_MAIN for screen_ddlist1
	local style_screen_ddlist1_main = lvgl.style_t()
	lvgl.style_init(style_screen_ddlist1_main)
	-- local style_screen_ddlist1_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_screen_ddlist1_main
	lvgl.style_set_radius(style_screen_ddlist1_main, lvgl.STATE_DEFAULT, 3)
	lvgl.style_set_bg_color(style_screen_ddlist1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen_ddlist1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen_ddlist1_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_ddlist1_main, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_border_color(style_screen_ddlist1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xe1, 0xe6, 0xee))
	lvgl.style_set_border_width(style_screen_ddlist1_main, lvgl.STATE_DEFAULT, 1)
	lvgl.style_set_text_color(style_screen_ddlist1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x0D, 0x30, 0x55))
	lvgl.style_set_text_font(style_screen_ddlist1_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_12"))
	lvgl.style_set_text_line_space(style_screen_ddlist1_main, lvgl.STATE_DEFAULT, 20)
	lvgl.obj_add_style(ui.screen_ddlist1, lvgl.DROPDOWN_PART_MAIN, style_screen_ddlist1_main)

	--Write style lvgl.DROPDOWN_PART_SELECTED for screen_ddlist1
	-- local style_screen_ddlist1_selected
	-- lvgl.style_init(style_screen_ddlist1_selected)
	local style_screen_ddlist1_selected = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_screen_ddlist1_selected
	lvgl.style_set_radius(style_screen_ddlist1_selected, lvgl.STATE_DEFAULT, 3)
	lvgl.style_set_bg_color(style_screen_ddlist1_selected, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0xa1, 0xb5))
	lvgl.style_set_bg_grad_color(style_screen_ddlist1_selected, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0xa1, 0xb5))
	lvgl.style_set_bg_grad_dir(style_screen_ddlist1_selected, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_ddlist1_selected, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_border_color(style_screen_ddlist1_selected, lvgl.STATE_DEFAULT, lvgl.color_make(0xe1, 0xe6, 0xee))
	lvgl.style_set_border_width(style_screen_ddlist1_selected, lvgl.STATE_DEFAULT, 1)
	lvgl.style_set_text_color(style_screen_ddlist1_selected, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_text_font(style_screen_ddlist1_selected, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_12"))
	lvgl.obj_add_style(ui.screen_ddlist1, lvgl.DROPDOWN_PART_SELECTED, style_screen_ddlist1_selected)

	--Write style lvgl.DROPDOWN_PART_LIST for screen_ddlist1
	-- local style_screen_ddlist1_list
	-- lvgl.style_init(style_screen_ddlist1_list)
	local style_screen_ddlist1_list = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_screen_ddlist1_list
	lvgl.style_set_radius(style_screen_ddlist1_list, lvgl.STATE_DEFAULT, 3)
	lvgl.style_set_bg_color(style_screen_ddlist1_list, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen_ddlist1_list, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen_ddlist1_list, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_ddlist1_list, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_border_color(style_screen_ddlist1_list, lvgl.STATE_DEFAULT, lvgl.color_make(0xe1, 0xe6, 0xee))
	lvgl.style_set_border_width(style_screen_ddlist1_list, lvgl.STATE_DEFAULT, 1)
	lvgl.style_set_text_color(style_screen_ddlist1_list, lvgl.STATE_DEFAULT, lvgl.color_make(0x0D, 0x30, 0x55))
	lvgl.style_set_text_font(style_screen_ddlist1_list, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_12"))
	lvgl.obj_add_style(ui.screen_ddlist1, lvgl.DROPDOWN_PART_LIST, style_screen_ddlist1_list)
	lvgl.obj_set_pos(ui.screen_ddlist1, 260, 30)
	lvgl.obj_set_width(ui.screen_ddlist1, 130)

	--Write codes screen_roller1
	ui.screen_roller1 = lvgl.roller_create(ui.screen, nil)

	--Write style lvgl.ROLLER_PART_BG for screen_roller1
	-- local style_screen_roller1_bg
	-- lvgl.style_init(style_screen_roller1_bg)
	local style_screen_roller1_bg = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_screen_roller1_bg
	lvgl.style_set_radius(style_screen_roller1_bg, lvgl.STATE_DEFAULT, 5)
	lvgl.style_set_bg_color(style_screen_roller1_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen_roller1_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen_roller1_bg, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_roller1_bg, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_border_color(style_screen_roller1_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xdf, 0xe7, 0xed))
	lvgl.style_set_border_width(style_screen_roller1_bg, lvgl.STATE_DEFAULT, 1)
	lvgl.style_set_text_color(style_screen_roller1_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0x33, 0x33, 0x33))

	--Write style state: lvgl.STATE_FOCUSED for style_screen_roller1_bg
	lvgl.style_set_radius(style_screen_roller1_bg, lvgl.STATE_FOCUSED, 5)
	lvgl.style_set_bg_color(style_screen_roller1_bg, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen_roller1_bg, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen_roller1_bg, lvgl.STATE_FOCUSED, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_roller1_bg, lvgl.STATE_FOCUSED, 255)
	lvgl.style_set_border_color(style_screen_roller1_bg, lvgl.STATE_FOCUSED, lvgl.color_make(0xdf, 0xe7, 0xed))
	lvgl.style_set_border_width(style_screen_roller1_bg, lvgl.STATE_FOCUSED, 1)
	lvgl.style_set_text_color(style_screen_roller1_bg, lvgl.STATE_FOCUSED, lvgl.color_make(0x33, 0x33, 0x33))
	lvgl.obj_add_style(ui.screen_roller1, lvgl.ROLLER_PART_BG, style_screen_roller1_bg)

	--Write style lvgl.ROLLER_PART_SELECTED for screen_roller1
	-- local style_screen_roller1_selected
	-- lvgl.style_init(style_screen_roller1_selected)
	local style_screen_roller1_selected = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_screen_roller1_selected
	lvgl.style_set_bg_color(style_screen_roller1_selected, lvgl.STATE_DEFAULT, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_bg_grad_color(style_screen_roller1_selected, lvgl.STATE_DEFAULT, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_bg_grad_dir(style_screen_roller1_selected, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_roller1_selected, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_text_color(style_screen_roller1_selected, lvgl.STATE_DEFAULT, lvgl.color_make(0xFF, 0xFF, 0xFF))
	lvgl.obj_add_style(ui.screen_roller1, lvgl.ROLLER_PART_SELECTED, style_screen_roller1_selected)
	lvgl.obj_set_pos(ui.screen_roller1, 90, 30)
	lvgl.roller_set_options(ui.screen_roller1,"1\n2\n3\n4\n5",lvgl.ROLLER_MODE_INIFINITE)
	lvgl.obj_set_style_local_text_font(ui.screen_roller1, lvgl.ROLLER_PART_BG, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_12"))
	lvgl.obj_set_style_local_text_font(ui.screen_roller1, lvgl.ROLLER_PART_BG, lvgl.STATE_FOCUSED, lvgl.font_get("opposans_m_12"))
	lvgl.obj_set_style_local_text_font(ui.screen_roller1, lvgl.ROLLER_PART_SELECTED, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_12"))
	lvgl.roller_set_visible_row_count(ui.screen_roller1,5)

	--Write codes screen_sw2
	ui.screen_sw2 = lvgl.switch_create(ui.screen, nil)

	--Write style lvgl.SWITCH_PART_BG for screen_sw2
	-- local style_screen_sw2_bg
	-- lvgl.style_init(style_screen_sw2_bg)
	local style_screen_sw2_bg = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_screen_sw2_bg
	lvgl.style_set_radius(style_screen_sw2_bg, lvgl.STATE_DEFAULT, 100)
	lvgl.style_set_bg_color(style_screen_sw2_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9))
	lvgl.style_set_bg_grad_color(style_screen_sw2_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9))
	lvgl.style_set_bg_grad_dir(style_screen_sw2_bg, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_sw2_bg, lvgl.STATE_DEFAULT, 255)
	lvgl.obj_add_style(ui.screen_sw2, lvgl.SWITCH_PART_BG, style_screen_sw2_bg)

	--Write style lvgl.SWITCH_PART_INDIC for screen_sw2
	-- local style_screen_sw2_indic
	-- lvgl.style_init(style_screen_sw2_indic)
	local style_screen_sw2_indic = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_screen_sw2_indic
	lvgl.style_set_radius(style_screen_sw2_indic, lvgl.STATE_DEFAULT, 100)
	lvgl.style_set_bg_color(style_screen_sw2_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0xa1, 0xb5))
	lvgl.style_set_bg_grad_color(style_screen_sw2_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0xa1, 0xb5))
	lvgl.style_set_bg_grad_dir(style_screen_sw2_indic, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_sw2_indic, lvgl.STATE_DEFAULT, 255)
	lvgl.obj_add_style(ui.screen_sw2, lvgl.SWITCH_PART_INDIC, style_screen_sw2_indic)

	--Write style lvgl.SWITCH_PART_KNOB for screen_sw2
	-- local style_screen_sw2_knob
	-- lvgl.style_init(style_screen_sw2_knob)
	local style_screen_sw2_knob = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_screen_sw2_knob
	lvgl.style_set_radius(style_screen_sw2_knob, lvgl.STATE_DEFAULT, 100)
	lvgl.style_set_bg_color(style_screen_sw2_knob, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen_sw2_knob, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen_sw2_knob, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_sw2_knob, lvgl.STATE_DEFAULT, 255)
	lvgl.obj_add_style(ui.screen_sw2, lvgl.SWITCH_PART_KNOB, style_screen_sw2_knob)
	lvgl.obj_set_pos(ui.screen_sw2, 195, 203)
	lvgl.obj_set_size(ui.screen_sw2, 40, 20)
	lvgl.switch_set_anim_time(ui.screen_sw2, 200)

	--Write codes screen_label3
	ui.screen_label3 = lvgl.label_create(ui.screen, nil)
	lvgl.label_set_text(ui.screen_label3, "roller")
	lvgl.label_set_long_mode(ui.screen_label3, lvgl.LABEL_LONG_BREAK)
	lvgl.label_set_align(ui.screen_label3, lvgl.LABEL_ALIGN_CENTER)

	--Write style lvgl.LABEL_PART_MAIN for screen_label3
	-- local style_screen_label3_main
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
	lvgl.obj_set_pos(ui.screen_label3, 65, 205)
	lvgl.obj_set_size(ui.screen_label3, 100, 0)

	--Write codes screen_label4
	ui.screen_label4 = lvgl.label_create(ui.screen, nil)
	lvgl.label_set_text(ui.screen_label4, "select")
	lvgl.label_set_long_mode(ui.screen_label4, lvgl.LABEL_LONG_BREAK)
	lvgl.label_set_align(ui.screen_label4, lvgl.LABEL_ALIGN_CENTER)

	--Write style lvgl.LABEL_PART_MAIN for screen_label4
	-- local style_screen_label4_main
	-- lvgl.style_init(style_screen_label4_main)
	local style_screen_label4_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_screen_label4_main
	lvgl.style_set_radius(style_screen_label4_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_bg_color(style_screen_label4_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_screen_label4_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_screen_label4_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_screen_label4_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_text_color(style_screen_label4_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.style_set_text_font(style_screen_label4_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_12"))
	lvgl.style_set_text_letter_space(style_screen_label4_main, lvgl.STATE_DEFAULT, 2)
	lvgl.style_set_pad_left(style_screen_label4_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_right(style_screen_label4_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_top(style_screen_label4_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_bottom(style_screen_label4_main, lvgl.STATE_DEFAULT, 0)
	lvgl.obj_add_style(ui.screen_label4, lvgl.LABEL_PART_MAIN, style_screen_label4_main)
	lvgl.obj_set_pos(ui.screen_label4, 261, 205)
	lvgl.obj_set_size(ui.screen_label4, 100, 0)

	lvgl.obj_set_event_cb(ui.screen_sw2, screen_sw2event_handler)

    lvgl.scr_load(ui.screen)

    while true do
        sys.wait(500)
    end
end)

sys.run()
