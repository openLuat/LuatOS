

local prtusb = {}

function prtusb.setup_scr_prtusb(ui)

	--Write codes prtusb
	ui.prtusb = lvgl.obj_create(nil, nil);

	--Write codes prtusb_cont0
	ui.prtusb_cont0 = lvgl.cont_create(ui.prtusb, nil);

	--Write style lvgl.CONT_PART_MAIN for prtusb_cont0
	-- local style_prtusb_cont0_main;
	-- lvgl.style_init(style_prtusb_cont0_main);
	local style_prtusb_cont0_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_cont0_main
	lvgl.style_set_radius(style_prtusb_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_prtusb_cont0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_prtusb_cont0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_prtusb_cont0_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_cont0_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_prtusb_cont0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x99, 0x99, 0x99));
	lvgl.style_set_border_width(style_prtusb_cont0_main, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_border_opa(style_prtusb_cont0_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_pad_left(style_prtusb_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_prtusb_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_prtusb_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_prtusb_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.prtusb_cont0, lvgl.CONT_PART_MAIN, style_prtusb_cont0_main);
	lvgl.obj_set_pos(ui.prtusb_cont0, 0, 0);
	lvgl.obj_set_size(ui.prtusb_cont0, 480, 100);
	lvgl.obj_set_click(ui.prtusb_cont0, false);
	lvgl.cont_set_layout(ui.prtusb_cont0, lvgl.LAYOUT_OFF);
	lvgl.cont_set_fit(ui.prtusb_cont0, lvgl.FIT_NONE);

	--Write codes prtusb_cont2
	ui.prtusb_cont2 = lvgl.cont_create(ui.prtusb, nil);

	--Write style lvgl.CONT_PART_MAIN for prtusb_cont2
	-- local style_prtusb_cont2_main;
	-- lvgl.style_init(style_prtusb_cont2_main);
	local style_prtusb_cont2_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_cont2_main
	lvgl.style_set_radius(style_prtusb_cont2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_prtusb_cont2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff));
	lvgl.style_set_bg_grad_color(style_prtusb_cont2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff));
	lvgl.style_set_bg_grad_dir(style_prtusb_cont2_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_cont2_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_prtusb_cont2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x99, 0x99, 0x99));
	lvgl.style_set_border_width(style_prtusb_cont2_main, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_border_opa(style_prtusb_cont2_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_pad_left(style_prtusb_cont2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_prtusb_cont2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_prtusb_cont2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_prtusb_cont2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.prtusb_cont2, lvgl.CONT_PART_MAIN, style_prtusb_cont2_main);
	lvgl.obj_set_pos(ui.prtusb_cont2, 0, 100);
	lvgl.obj_set_size(ui.prtusb_cont2, 480, 172);
	lvgl.obj_set_click(ui.prtusb_cont2, false);
	lvgl.cont_set_layout(ui.prtusb_cont2, lvgl.LAYOUT_OFF);
	lvgl.cont_set_fit(ui.prtusb_cont2, lvgl.FIT_NONE);

	--Write codes prtusb_labeltitle
	ui.prtusb_labeltitle = lvgl.label_create(ui.prtusb, nil);
	lvgl.label_set_text(ui.prtusb_labeltitle, "从USB打印");
	lvgl.label_set_long_mode(ui.prtusb_labeltitle, lvgl.LABEL_LONG_BREAK);
	lvgl.label_set_align(ui.prtusb_labeltitle, lvgl.LABEL_ALIGN_CENTER);

	--Write style lvgl.LABEL_PART_MAIN for prtusb_labeltitle
	-- local style_prtusb_labeltitle_main;
	-- lvgl.style_init(style_prtusb_labeltitle_main);
	local style_prtusb_labeltitle_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_labeltitle_main
	lvgl.style_set_radius(style_prtusb_labeltitle_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_prtusb_labeltitle_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_prtusb_labeltitle_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_prtusb_labeltitle_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_labeltitle_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_text_color(style_prtusb_labeltitle_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_text_font(style_prtusb_labeltitle_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_22"));
	lvgl.style_set_text_letter_space(style_prtusb_labeltitle_main, lvgl.STATE_DEFAULT, 2);
	lvgl.style_set_pad_left(style_prtusb_labeltitle_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_prtusb_labeltitle_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_prtusb_labeltitle_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_prtusb_labeltitle_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.prtusb_labeltitle, lvgl.LABEL_PART_MAIN, style_prtusb_labeltitle_main);
	lvgl.obj_set_pos(ui.prtusb_labeltitle, 136, 30);
	lvgl.obj_set_size(ui.prtusb_labeltitle, 225, 0);

	--Write codes prtusb_cont4
	ui.prtusb_cont4 = lvgl.cont_create(ui.prtusb, nil);

	--Write style lvgl.CONT_PART_MAIN for prtusb_cont4
	-- local style_prtusb_cont4_main;
	-- lvgl.style_init(style_prtusb_cont4_main);
	local style_prtusb_cont4_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_cont4_main
	lvgl.style_set_radius(style_prtusb_cont4_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_prtusb_cont4_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff));
	lvgl.style_set_bg_grad_color(style_prtusb_cont4_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff));
	lvgl.style_set_bg_grad_dir(style_prtusb_cont4_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_cont4_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_prtusb_cont4_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x99, 0x99, 0x99));
	lvgl.style_set_border_width(style_prtusb_cont4_main, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_border_opa(style_prtusb_cont4_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_pad_left(style_prtusb_cont4_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_prtusb_cont4_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_prtusb_cont4_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_prtusb_cont4_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.prtusb_cont4, lvgl.CONT_PART_MAIN, style_prtusb_cont4_main);
	lvgl.obj_set_pos(ui.prtusb_cont4, 305, 80);
	lvgl.obj_set_size(ui.prtusb_cont4, 150, 130);
	lvgl.obj_set_click(ui.prtusb_cont4, false);
	lvgl.cont_set_layout(ui.prtusb_cont4, lvgl.LAYOUT_OFF);
	lvgl.cont_set_fit(ui.prtusb_cont4, lvgl.FIT_NONE);

	--Write codes prtusb_btnprint
	ui.prtusb_btnprint = lvgl.btn_create(ui.prtusb, nil);

	--Write style lvgl.BTN_PART_MAIN for prtusb_btnprint
	-- local style_prtusb_btnprint_main;
	-- lvgl.style_init(style_prtusb_btnprint_main);
	local style_prtusb_btnprint_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_btnprint_main
	lvgl.style_set_radius(style_prtusb_btnprint_main, lvgl.STATE_DEFAULT, 50);
	lvgl.style_set_bg_color(style_prtusb_btnprint_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x29, 0x30, 0x41));
	lvgl.style_set_bg_grad_color(style_prtusb_btnprint_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x29, 0x30, 0x41));
	lvgl.style_set_bg_grad_dir(style_prtusb_btnprint_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_btnprint_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_prtusb_btnprint_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_prtusb_btnprint_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_border_opa(style_prtusb_btnprint_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_outline_color(style_prtusb_btnprint_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_outline_opa(style_prtusb_btnprint_main, lvgl.STATE_DEFAULT, 255);

	--Write style state: lvgl.STATE_FOCUSED for style_prtusb_btnprint_main
	lvgl.style_set_radius(style_prtusb_btnprint_main, lvgl.STATE_FOCUSED, 50);
	lvgl.style_set_bg_color(style_prtusb_btnprint_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_prtusb_btnprint_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_prtusb_btnprint_main, lvgl.STATE_FOCUSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_btnprint_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_border_color(style_prtusb_btnprint_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_prtusb_btnprint_main, lvgl.STATE_FOCUSED, 2);
	lvgl.style_set_border_opa(style_prtusb_btnprint_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_outline_color(style_prtusb_btnprint_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_prtusb_btnprint_main, lvgl.STATE_FOCUSED, 255);

	--Write style state: lvgl.STATE_PRESSED for style_prtusb_btnprint_main
	lvgl.style_set_radius(style_prtusb_btnprint_main, lvgl.STATE_PRESSED, 50);
	lvgl.style_set_bg_color(style_prtusb_btnprint_main, lvgl.STATE_PRESSED, lvgl.color_make(0x00, 0xdd, 0x6f));
	lvgl.style_set_bg_grad_color(style_prtusb_btnprint_main, lvgl.STATE_PRESSED, lvgl.color_make(0x00, 0xdd, 0x6f));
	lvgl.style_set_bg_grad_dir(style_prtusb_btnprint_main, lvgl.STATE_PRESSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_btnprint_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_border_color(style_prtusb_btnprint_main, lvgl.STATE_PRESSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_prtusb_btnprint_main, lvgl.STATE_PRESSED, 2);
	lvgl.style_set_border_opa(style_prtusb_btnprint_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_outline_color(style_prtusb_btnprint_main, lvgl.STATE_PRESSED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_prtusb_btnprint_main, lvgl.STATE_PRESSED, 100);

	--Write style state: lvgl.STATE_CHECKED for style_prtusb_btnprint_main
	lvgl.style_set_radius(style_prtusb_btnprint_main, lvgl.STATE_CHECKED, 50);
	lvgl.style_set_bg_color(style_prtusb_btnprint_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_prtusb_btnprint_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_prtusb_btnprint_main, lvgl.STATE_CHECKED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_btnprint_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_border_color(style_prtusb_btnprint_main, lvgl.STATE_CHECKED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_prtusb_btnprint_main, lvgl.STATE_CHECKED, 2);
	lvgl.style_set_border_opa(style_prtusb_btnprint_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_outline_color(style_prtusb_btnprint_main, lvgl.STATE_CHECKED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_prtusb_btnprint_main, lvgl.STATE_CHECKED, 255);
	lvgl.obj_add_style(ui.prtusb_btnprint, lvgl.BTN_PART_MAIN, style_prtusb_btnprint_main);
	lvgl.obj_set_pos(ui.prtusb_btnprint, 320, 223);
	lvgl.obj_set_size(ui.prtusb_btnprint, 118, 40);
	ui.prtusb_btnprint_label = lvgl.label_create(ui.prtusb_btnprint, nil);
	lvgl.label_set_text(ui.prtusb_btnprint_label, "打印");
	lvgl.obj_set_style_local_text_color(ui.prtusb_btnprint_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.obj_set_style_local_text_font(ui.prtusb_btnprint_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_14"));

	--Write codes prtusb_back
	ui.prtusb_back = lvgl.btn_create(ui.prtusb, nil);

	--Write style lvgl.BTN_PART_MAIN for prtusb_back
	-- local style_prtusb_back_main;
	-- lvgl.style_init(style_prtusb_back_main);
	local style_prtusb_back_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_back_main
	lvgl.style_set_radius(style_prtusb_back_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_prtusb_back_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_prtusb_back_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_prtusb_back_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_back_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_prtusb_back_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_prtusb_back_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_border_opa(style_prtusb_back_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_outline_color(style_prtusb_back_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_prtusb_back_main, lvgl.STATE_DEFAULT, 0);

	--Write style state: lvgl.STATE_FOCUSED for style_prtusb_back_main
	lvgl.style_set_radius(style_prtusb_back_main, lvgl.STATE_FOCUSED, 50);
	lvgl.style_set_bg_color(style_prtusb_back_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_prtusb_back_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_prtusb_back_main, lvgl.STATE_FOCUSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_back_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_border_color(style_prtusb_back_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_prtusb_back_main, lvgl.STATE_FOCUSED, 2);
	lvgl.style_set_border_opa(style_prtusb_back_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_outline_color(style_prtusb_back_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_prtusb_back_main, lvgl.STATE_FOCUSED, 255);

	--Write style state: lvgl.STATE_PRESSED for style_prtusb_back_main
	lvgl.style_set_radius(style_prtusb_back_main, lvgl.STATE_PRESSED, 0);
	lvgl.style_set_bg_color(style_prtusb_back_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_prtusb_back_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_prtusb_back_main, lvgl.STATE_PRESSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_back_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_border_color(style_prtusb_back_main, lvgl.STATE_PRESSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_prtusb_back_main, lvgl.STATE_PRESSED, 0);
	lvgl.style_set_border_opa(style_prtusb_back_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_outline_color(style_prtusb_back_main, lvgl.STATE_PRESSED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_prtusb_back_main, lvgl.STATE_PRESSED, 0);

	--Write style state: lvgl.STATE_CHECKED for style_prtusb_back_main
	lvgl.style_set_radius(style_prtusb_back_main, lvgl.STATE_CHECKED, 50);
	lvgl.style_set_bg_color(style_prtusb_back_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_prtusb_back_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_prtusb_back_main, lvgl.STATE_CHECKED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_back_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_border_color(style_prtusb_back_main, lvgl.STATE_CHECKED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_prtusb_back_main, lvgl.STATE_CHECKED, 2);
	lvgl.style_set_border_opa(style_prtusb_back_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_outline_color(style_prtusb_back_main, lvgl.STATE_CHECKED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_prtusb_back_main, lvgl.STATE_CHECKED, 255);
	lvgl.obj_add_style(ui.prtusb_back, lvgl.BTN_PART_MAIN, style_prtusb_back_main);
	lvgl.obj_set_pos(ui.prtusb_back, 50, 25);
	lvgl.obj_set_size(ui.prtusb_back, 30, 30);
	ui.prtusb_back_label = lvgl.label_create(ui.prtusb_back, nil);
	lvgl.label_set_text(ui.prtusb_back_label, "");
	lvgl.obj_set_style_local_text_color(ui.prtusb_back_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));

	--Write codes prtusb_swcolor
	ui.prtusb_swcolor = lvgl.switch_create(ui.prtusb, nil);

	--Write style lvgl.SWITCH_PART_BG for prtusb_swcolor
	-- local style_prtusb_swcolor_bg;
	-- lvgl.style_init(style_prtusb_swcolor_bg);
	local style_prtusb_swcolor_bg = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_swcolor_bg
	lvgl.style_set_radius(style_prtusb_swcolor_bg, lvgl.STATE_DEFAULT, 100);
	lvgl.style_set_bg_color(style_prtusb_swcolor_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_bg_grad_color(style_prtusb_swcolor_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_bg_grad_dir(style_prtusb_swcolor_bg, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_swcolor_bg, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.prtusb_swcolor, lvgl.SWITCH_PART_BG, style_prtusb_swcolor_bg);

	--Write style lvgl.SWITCH_PART_INDIC for prtusb_swcolor
	-- local style_prtusb_swcolor_indic;
	-- lvgl.style_init(style_prtusb_swcolor_indic);
	local style_prtusb_swcolor_indic = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_swcolor_indic
	lvgl.style_set_radius(style_prtusb_swcolor_indic, lvgl.STATE_DEFAULT, 100);
	lvgl.style_set_bg_color(style_prtusb_swcolor_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0xa1, 0xb5));
	lvgl.style_set_bg_grad_color(style_prtusb_swcolor_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0xa1, 0xb5));
	lvgl.style_set_bg_grad_dir(style_prtusb_swcolor_indic, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_swcolor_indic, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.prtusb_swcolor, lvgl.SWITCH_PART_INDIC, style_prtusb_swcolor_indic);

	--Write style lvgl.SWITCH_PART_KNOB for prtusb_swcolor
	-- local style_prtusb_swcolor_knob;
	-- lvgl.style_init(style_prtusb_swcolor_knob);
	local style_prtusb_swcolor_knob = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_swcolor_knob
	lvgl.style_set_radius(style_prtusb_swcolor_knob, lvgl.STATE_DEFAULT, 100);
	lvgl.style_set_bg_color(style_prtusb_swcolor_knob, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_prtusb_swcolor_knob, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_prtusb_swcolor_knob, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_swcolor_knob, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.prtusb_swcolor, lvgl.SWITCH_PART_KNOB, style_prtusb_swcolor_knob);
	lvgl.obj_set_pos(ui.prtusb_swcolor, 323, 175);
	lvgl.obj_set_size(ui.prtusb_swcolor, 40, 20);
	lvgl.switch_set_anim_time(ui.prtusb_swcolor, 600);

	--Write codes prtusb_labelcopy
	ui.prtusb_labelcopy = lvgl.label_create(ui.prtusb, nil);
	lvgl.label_set_text(ui.prtusb_labelcopy, "份数");
	lvgl.label_set_long_mode(ui.prtusb_labelcopy, lvgl.LABEL_LONG_BREAK);
	lvgl.label_set_align(ui.prtusb_labelcopy, lvgl.LABEL_ALIGN_CENTER);

	--Write style lvgl.LABEL_PART_MAIN for prtusb_labelcopy
	-- local style_prtusb_labelcopy_main;
	-- lvgl.style_init(style_prtusb_labelcopy_main);
	local style_prtusb_labelcopy_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_labelcopy_main
	lvgl.style_set_radius(style_prtusb_labelcopy_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_prtusb_labelcopy_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_prtusb_labelcopy_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_prtusb_labelcopy_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_labelcopy_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_text_color(style_prtusb_labelcopy_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00));
	lvgl.style_set_text_font(style_prtusb_labelcopy_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_16"));
	lvgl.style_set_text_letter_space(style_prtusb_labelcopy_main, lvgl.STATE_DEFAULT, 2);
	lvgl.style_set_pad_left(style_prtusb_labelcopy_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_prtusb_labelcopy_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_prtusb_labelcopy_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_prtusb_labelcopy_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.prtusb_labelcopy, lvgl.LABEL_PART_MAIN, style_prtusb_labelcopy_main);
	lvgl.obj_set_pos(ui.prtusb_labelcopy, 348, 80);
	lvgl.obj_set_size(ui.prtusb_labelcopy, 64, 0);

	--Write codes prtusb_up
	ui.prtusb_up = lvgl.btn_create(ui.prtusb, nil);

	--Write style lvgl.BTN_PART_MAIN for prtusb_up
	-- local style_prtusb_up_main;
	-- lvgl.style_init(style_prtusb_up_main);
	local style_prtusb_up_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_up_main
	lvgl.style_set_radius(style_prtusb_up_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_prtusb_up_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_prtusb_up_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_prtusb_up_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_up_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_prtusb_up_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_prtusb_up_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_border_opa(style_prtusb_up_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_outline_color(style_prtusb_up_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_outline_opa(style_prtusb_up_main, lvgl.STATE_DEFAULT, 255);

	--Write style state: lvgl.STATE_FOCUSED for style_prtusb_up_main
	lvgl.style_set_radius(style_prtusb_up_main, lvgl.STATE_FOCUSED, 0);
	lvgl.style_set_bg_color(style_prtusb_up_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_prtusb_up_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_prtusb_up_main, lvgl.STATE_FOCUSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_up_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_border_color(style_prtusb_up_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_prtusb_up_main, lvgl.STATE_FOCUSED, 0);
	lvgl.style_set_border_opa(style_prtusb_up_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_outline_color(style_prtusb_up_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_outline_opa(style_prtusb_up_main, lvgl.STATE_FOCUSED, 255);

	--Write style state: lvgl.STATE_PRESSED for style_prtusb_up_main
	lvgl.style_set_radius(style_prtusb_up_main, lvgl.STATE_PRESSED, 0);
	lvgl.style_set_bg_color(style_prtusb_up_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_prtusb_up_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_prtusb_up_main, lvgl.STATE_PRESSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_up_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_border_color(style_prtusb_up_main, lvgl.STATE_PRESSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_prtusb_up_main, lvgl.STATE_PRESSED, 0);
	lvgl.style_set_border_opa(style_prtusb_up_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_outline_color(style_prtusb_up_main, lvgl.STATE_PRESSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_outline_opa(style_prtusb_up_main, lvgl.STATE_PRESSED, 100);

	--Write style state: lvgl.STATE_CHECKED for style_prtusb_up_main
	lvgl.style_set_radius(style_prtusb_up_main, lvgl.STATE_CHECKED, 50);
	lvgl.style_set_bg_color(style_prtusb_up_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_prtusb_up_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_prtusb_up_main, lvgl.STATE_CHECKED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_up_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_border_color(style_prtusb_up_main, lvgl.STATE_CHECKED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_prtusb_up_main, lvgl.STATE_CHECKED, 2);
	lvgl.style_set_border_opa(style_prtusb_up_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_outline_color(style_prtusb_up_main, lvgl.STATE_CHECKED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_prtusb_up_main, lvgl.STATE_CHECKED, 255);
	lvgl.obj_add_style(ui.prtusb_up, lvgl.BTN_PART_MAIN, style_prtusb_up_main);
	lvgl.obj_set_pos(ui.prtusb_up, 417, 110);
	lvgl.obj_set_size(ui.prtusb_up, 20, 20);
	ui.prtusb_up_label = lvgl.label_create(ui.prtusb_up, nil);
	lvgl.label_set_text(ui.prtusb_up_label, "");
	lvgl.obj_set_style_local_text_color(ui.prtusb_up_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00));

	--Write codes prtusb_down
	ui.prtusb_down = lvgl.btn_create(ui.prtusb, nil);

	--Write style lvgl.BTN_PART_MAIN for prtusb_down
	-- local style_prtusb_down_main;
	-- lvgl.style_init(style_prtusb_down_main);
	local style_prtusb_down_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_down_main
	lvgl.style_set_radius(style_prtusb_down_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_prtusb_down_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_prtusb_down_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_prtusb_down_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_down_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_prtusb_down_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_border_width(style_prtusb_down_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_border_opa(style_prtusb_down_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_outline_color(style_prtusb_down_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_outline_opa(style_prtusb_down_main, lvgl.STATE_DEFAULT, 255);

	--Write style state: lvgl.STATE_FOCUSED for style_prtusb_down_main
	lvgl.style_set_radius(style_prtusb_down_main, lvgl.STATE_FOCUSED, 0);
	lvgl.style_set_bg_color(style_prtusb_down_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_prtusb_down_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_prtusb_down_main, lvgl.STATE_FOCUSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_down_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_border_color(style_prtusb_down_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_prtusb_down_main, lvgl.STATE_FOCUSED, 0);
	lvgl.style_set_border_opa(style_prtusb_down_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_outline_color(style_prtusb_down_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_outline_opa(style_prtusb_down_main, lvgl.STATE_FOCUSED, 255);

	--Write style state: lvgl.STATE_PRESSED for style_prtusb_down_main
	lvgl.style_set_radius(style_prtusb_down_main, lvgl.STATE_PRESSED, 0);
	lvgl.style_set_bg_color(style_prtusb_down_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_prtusb_down_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_prtusb_down_main, lvgl.STATE_PRESSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_down_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_border_color(style_prtusb_down_main, lvgl.STATE_PRESSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_prtusb_down_main, lvgl.STATE_PRESSED, 0);
	lvgl.style_set_border_opa(style_prtusb_down_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_outline_color(style_prtusb_down_main, lvgl.STATE_PRESSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_outline_opa(style_prtusb_down_main, lvgl.STATE_PRESSED, 100);

	--Write style state: lvgl.STATE_CHECKED for style_prtusb_down_main
	lvgl.style_set_radius(style_prtusb_down_main, lvgl.STATE_CHECKED, 50);
	lvgl.style_set_bg_color(style_prtusb_down_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_prtusb_down_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_prtusb_down_main, lvgl.STATE_CHECKED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_down_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_border_color(style_prtusb_down_main, lvgl.STATE_CHECKED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_prtusb_down_main, lvgl.STATE_CHECKED, 2);
	lvgl.style_set_border_opa(style_prtusb_down_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_outline_color(style_prtusb_down_main, lvgl.STATE_CHECKED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_prtusb_down_main, lvgl.STATE_CHECKED, 255);
	lvgl.obj_add_style(ui.prtusb_down, lvgl.BTN_PART_MAIN, style_prtusb_down_main);
	lvgl.obj_set_pos(ui.prtusb_down, 322, 110);
	lvgl.obj_set_size(ui.prtusb_down, 20, 20);
	ui.prtusb_down_label = lvgl.label_create(ui.prtusb_down, nil);
	lvgl.label_set_text(ui.prtusb_down_label, "");
	lvgl.obj_set_style_local_text_color(ui.prtusb_down_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00));

	--Write codes prtusb_labelcnt
	ui.prtusb_labelcnt = lvgl.label_create(ui.prtusb, nil);
	lvgl.label_set_text(ui.prtusb_labelcnt, "1");
	lvgl.label_set_long_mode(ui.prtusb_labelcnt, lvgl.LABEL_LONG_BREAK);
	lvgl.label_set_align(ui.prtusb_labelcnt, lvgl.LABEL_ALIGN_CENTER);

	--Write style lvgl.LABEL_PART_MAIN for prtusb_labelcnt
	-- local style_prtusb_labelcnt_main;
	-- lvgl.style_init(style_prtusb_labelcnt_main);
	local style_prtusb_labelcnt_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_labelcnt_main
	lvgl.style_set_radius(style_prtusb_labelcnt_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_prtusb_labelcnt_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_prtusb_labelcnt_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_prtusb_labelcnt_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_labelcnt_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_text_color(style_prtusb_labelcnt_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00));
	lvgl.style_set_text_font(style_prtusb_labelcnt_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_16"));
	lvgl.style_set_text_letter_space(style_prtusb_labelcnt_main, lvgl.STATE_DEFAULT, 2);
	lvgl.style_set_pad_left(style_prtusb_labelcnt_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_prtusb_labelcnt_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_prtusb_labelcnt_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_prtusb_labelcnt_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.prtusb_labelcnt, lvgl.LABEL_PART_MAIN, style_prtusb_labelcnt_main);
	lvgl.obj_set_pos(ui.prtusb_labelcnt, 351, 108);
	lvgl.obj_set_size(ui.prtusb_labelcnt, 56, 0);

	--Write codes prtusb_labelcolor
	ui.prtusb_labelcolor = lvgl.label_create(ui.prtusb, nil);
	lvgl.label_set_text(ui.prtusb_labelcolor, "Color");
	lvgl.label_set_long_mode(ui.prtusb_labelcolor, lvgl.LABEL_LONG_BREAK);
	lvgl.label_set_align(ui.prtusb_labelcolor, lvgl.LABEL_ALIGN_CENTER);

	--Write style lvgl.LABEL_PART_MAIN for prtusb_labelcolor
	-- local style_prtusb_labelcolor_main;
	-- lvgl.style_init(style_prtusb_labelcolor_main);
	local style_prtusb_labelcolor_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_labelcolor_main
	lvgl.style_set_radius(style_prtusb_labelcolor_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_prtusb_labelcolor_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_prtusb_labelcolor_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_prtusb_labelcolor_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_labelcolor_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_text_color(style_prtusb_labelcolor_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00));
	lvgl.style_set_text_font(style_prtusb_labelcolor_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_16"));
	lvgl.style_set_text_letter_space(style_prtusb_labelcolor_main, lvgl.STATE_DEFAULT, 2);
	lvgl.style_set_pad_left(style_prtusb_labelcolor_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_prtusb_labelcolor_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_prtusb_labelcolor_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_prtusb_labelcolor_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.prtusb_labelcolor, lvgl.LABEL_PART_MAIN, style_prtusb_labelcolor_main);
	lvgl.obj_set_pos(ui.prtusb_labelcolor, 314, 146);
	lvgl.obj_set_size(ui.prtusb_labelcolor, 50, 0);

	--Write codes prtusb_labelvert
	ui.prtusb_labelvert = lvgl.label_create(ui.prtusb, nil);
	lvgl.label_set_text(ui.prtusb_labelvert, "Verical");
	lvgl.label_set_long_mode(ui.prtusb_labelvert, lvgl.LABEL_LONG_BREAK);
	lvgl.label_set_align(ui.prtusb_labelvert, lvgl.LABEL_ALIGN_CENTER);

	--Write style lvgl.LABEL_PART_MAIN for prtusb_labelvert
	-- local style_prtusb_labelvert_main;
	-- lvgl.style_init(style_prtusb_labelvert_main);
	local style_prtusb_labelvert_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_labelvert_main
	lvgl.style_set_radius(style_prtusb_labelvert_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_prtusb_labelvert_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_prtusb_labelvert_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_prtusb_labelvert_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_labelvert_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_text_color(style_prtusb_labelvert_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00));
	lvgl.style_set_text_font(style_prtusb_labelvert_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_16"));
	lvgl.style_set_text_letter_space(style_prtusb_labelvert_main, lvgl.STATE_DEFAULT, 2);
	lvgl.style_set_pad_left(style_prtusb_labelvert_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_prtusb_labelvert_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_prtusb_labelvert_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_prtusb_labelvert_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.prtusb_labelvert, lvgl.LABEL_PART_MAIN, style_prtusb_labelvert_main);
	lvgl.obj_set_pos(ui.prtusb_labelvert, 380, 146);
	lvgl.obj_set_size(ui.prtusb_labelvert, 70, 0);

	--Write codes prtusb_swvert
	ui.prtusb_swvert = lvgl.switch_create(ui.prtusb, nil);

	--Write style lvgl.SWITCH_PART_BG for prtusb_swvert
	-- local style_prtusb_swvert_bg;
	-- lvgl.style_init(style_prtusb_swvert_bg);
	local style_prtusb_swvert_bg = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_swvert_bg
	lvgl.style_set_radius(style_prtusb_swvert_bg, lvgl.STATE_DEFAULT, 100);
	lvgl.style_set_bg_color(style_prtusb_swvert_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_bg_grad_color(style_prtusb_swvert_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_bg_grad_dir(style_prtusb_swvert_bg, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_swvert_bg, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.prtusb_swvert, lvgl.SWITCH_PART_BG, style_prtusb_swvert_bg);

	--Write style lvgl.SWITCH_PART_INDIC for prtusb_swvert
	-- local style_prtusb_swvert_indic;
	-- lvgl.style_init(style_prtusb_swvert_indic);
	local style_prtusb_swvert_indic = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_swvert_indic
	lvgl.style_set_radius(style_prtusb_swvert_indic, lvgl.STATE_DEFAULT, 100);
	lvgl.style_set_bg_color(style_prtusb_swvert_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0xa1, 0xb5));
	lvgl.style_set_bg_grad_color(style_prtusb_swvert_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0xa1, 0xb5));
	lvgl.style_set_bg_grad_dir(style_prtusb_swvert_indic, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_swvert_indic, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.prtusb_swvert, lvgl.SWITCH_PART_INDIC, style_prtusb_swvert_indic);

	--Write style lvgl.SWITCH_PART_KNOB for prtusb_swvert
	-- local style_prtusb_swvert_knob;
	-- lvgl.style_init(style_prtusb_swvert_knob);
	local style_prtusb_swvert_knob = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_swvert_knob
	lvgl.style_set_radius(style_prtusb_swvert_knob, lvgl.STATE_DEFAULT, 100);
	lvgl.style_set_bg_color(style_prtusb_swvert_knob, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_prtusb_swvert_knob, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_prtusb_swvert_knob, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_swvert_knob, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.prtusb_swvert, lvgl.SWITCH_PART_KNOB, style_prtusb_swvert_knob);
	lvgl.obj_set_pos(ui.prtusb_swvert, 390, 175);
	lvgl.obj_set_size(ui.prtusb_swvert, 40, 20);
	lvgl.switch_set_anim_time(ui.prtusb_swvert, 100);

	--Write codes prtusb_list16
	ui.prtusb_list16 = lvgl.list_create(ui.prtusb, nil);
	lvgl.list_set_edge_flash(ui.prtusb_list16, true);
	lvgl.list_set_anim_time(ui.prtusb_list16, 255);

	--Write style lvgl.LIST_PART_BG for prtusb_list16
	-- local style_prtusb_list16_bg;
	-- lvgl.style_init(style_prtusb_list16_bg);
	local style_prtusb_list16_bg = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_list16_bg
	lvgl.style_set_radius(style_prtusb_list16_bg, lvgl.STATE_DEFAULT, 3);
	lvgl.style_set_border_color(style_prtusb_list16_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xe1, 0xe6, 0xee));
	lvgl.style_set_border_width(style_prtusb_list16_bg, lvgl.STATE_DEFAULT, 1);
	lvgl.obj_add_style(ui.prtusb_list16, lvgl.LIST_PART_BG, style_prtusb_list16_bg);

	--Write style lvgl.LIST_PART_SCROLLABLE for prtusb_list16
	-- local style_prtusb_list16_scrollable;
	-- lvgl.style_init(style_prtusb_list16_scrollable);
	local style_prtusb_list16_scrollable = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_list16_scrollable
	lvgl.style_set_radius(style_prtusb_list16_scrollable, lvgl.STATE_DEFAULT, 3);
	lvgl.style_set_bg_color(style_prtusb_list16_scrollable, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_prtusb_list16_scrollable, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_prtusb_list16_scrollable, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_list16_scrollable, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.prtusb_list16, lvgl.LIST_PART_SCROLLABLE, style_prtusb_list16_scrollable);

	--Write style lvgl.BTN_PART_MAIN for prtusb_list16
	-- local style_prtusb_list16_main_child;
	-- lvgl.style_init(style_prtusb_list16_main_child);
	local style_prtusb_list16_main_child = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_list16_main_child
	lvgl.style_set_radius(style_prtusb_list16_main_child, lvgl.STATE_DEFAULT, 3);
	lvgl.style_set_bg_color(style_prtusb_list16_main_child, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_prtusb_list16_main_child, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_prtusb_list16_main_child, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_list16_main_child, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_text_color(style_prtusb_list16_main_child, lvgl.STATE_DEFAULT, lvgl.color_make(0x0D, 0x30, 0x55));

	--Write style state: lvgl.STATE_PRESSED for style_prtusb_list16_main_child
	lvgl.style_set_radius(style_prtusb_list16_main_child, lvgl.STATE_PRESSED, 3);
	lvgl.style_set_bg_color(style_prtusb_list16_main_child, lvgl.STATE_PRESSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_prtusb_list16_main_child, lvgl.STATE_PRESSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_prtusb_list16_main_child, lvgl.STATE_PRESSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_list16_main_child, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_text_color(style_prtusb_list16_main_child, lvgl.STATE_PRESSED, lvgl.color_make(0x0D, 0x30, 0x55));
	lvgl.obj_set_pos(ui.prtusb_list16, 31, 83);
	lvgl.obj_set_size(ui.prtusb_list16, 240, 100);
	-- lvgl.obj_t *prtusb_list16_btn;
	prtusb_list16_btn = lvgl.list_add_btn(ui.prtusb_list16, lvgl.SYMBOL_FILE, "Contract 12.pdf");
	lvgl.obj_add_style(prtusb_list16_btn, lvgl.BTN_PART_MAIN, style_prtusb_list16_main_child);
	prtusb_list16_btn = lvgl.list_add_btn(ui.prtusb_list16, lvgl.SYMBOL_FILE, "Scanned_05_21.pdf");
	lvgl.obj_add_style(prtusb_list16_btn, lvgl.BTN_PART_MAIN, style_prtusb_list16_main_child);
	prtusb_list16_btn = lvgl.list_add_btn(ui.prtusb_list16, lvgl.SYMBOL_FILE, "Photo_2.jpg");
	lvgl.obj_add_style(prtusb_list16_btn, lvgl.BTN_PART_MAIN, style_prtusb_list16_main_child);
	prtusb_list16_btn = lvgl.list_add_btn(ui.prtusb_list16, lvgl.SYMBOL_FILE, "Photo_3.jpg");
	lvgl.obj_add_style(prtusb_list16_btn, lvgl.BTN_PART_MAIN, style_prtusb_list16_main_child);

	--Write codes prtusb_ddlist1
	ui.prtusb_ddlist1 = lvgl.dropdown_create(ui.prtusb, nil);
	lvgl.dropdown_set_options(ui.prtusb_ddlist1, "最好\n通常\n一般");
	lvgl.dropdown_set_max_height(ui.prtusb_ddlist1, 90);

	--Write style lvgl.DROPDOWN_PART_MAIN for prtusb_ddlist1
	-- local style_prtusb_ddlist1_main;
	-- lvgl.style_init(style_prtusb_ddlist1_main);
	local style_prtusb_ddlist1_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_ddlist1_main
	lvgl.style_set_radius(style_prtusb_ddlist1_main, lvgl.STATE_DEFAULT, 3);
	lvgl.style_set_bg_color(style_prtusb_ddlist1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_prtusb_ddlist1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_prtusb_ddlist1_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_ddlist1_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_prtusb_ddlist1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xe1, 0xe6, 0xee));
	lvgl.style_set_border_width(style_prtusb_ddlist1_main, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_text_color(style_prtusb_ddlist1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x0D, 0x30, 0x55));
	lvgl.style_set_text_font(style_prtusb_ddlist1_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_12"));
	lvgl.style_set_text_line_space(style_prtusb_ddlist1_main, lvgl.STATE_DEFAULT, 20);
	lvgl.obj_add_style(ui.prtusb_ddlist1, lvgl.DROPDOWN_PART_MAIN, style_prtusb_ddlist1_main);

	--Write style lvgl.DROPDOWN_PART_SELECTED for prtusb_ddlist1
	-- local style_prtusb_ddlist1_selected;
	-- lvgl.style_init(style_prtusb_ddlist1_selected);
	local style_prtusb_ddlist1_selected = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_ddlist1_selected
	lvgl.style_set_radius(style_prtusb_ddlist1_selected, lvgl.STATE_DEFAULT, 3);
	lvgl.style_set_bg_color(style_prtusb_ddlist1_selected, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0xa1, 0xb5));
	lvgl.style_set_bg_grad_color(style_prtusb_ddlist1_selected, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0xa1, 0xb5));
	lvgl.style_set_bg_grad_dir(style_prtusb_ddlist1_selected, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_ddlist1_selected, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_prtusb_ddlist1_selected, lvgl.STATE_DEFAULT, lvgl.color_make(0xe1, 0xe6, 0xee));
	lvgl.style_set_border_width(style_prtusb_ddlist1_selected, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_text_color(style_prtusb_ddlist1_selected, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_text_font(style_prtusb_ddlist1_selected, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_12"));
	lvgl.obj_add_style(ui.prtusb_ddlist1, lvgl.DROPDOWN_PART_SELECTED, style_prtusb_ddlist1_selected);

	--Write style lvgl.DROPDOWN_PART_LIST for prtusb_ddlist1
	-- local style_prtusb_ddlist1_list;
	-- lvgl.style_init(style_prtusb_ddlist1_list);
	local style_prtusb_ddlist1_list = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_ddlist1_list
	lvgl.style_set_radius(style_prtusb_ddlist1_list, lvgl.STATE_DEFAULT, 3);
	lvgl.style_set_bg_color(style_prtusb_ddlist1_list, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_prtusb_ddlist1_list, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_prtusb_ddlist1_list, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_ddlist1_list, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_prtusb_ddlist1_list, lvgl.STATE_DEFAULT, lvgl.color_make(0xe1, 0xe6, 0xee));
	lvgl.style_set_border_width(style_prtusb_ddlist1_list, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_text_color(style_prtusb_ddlist1_list, lvgl.STATE_DEFAULT, lvgl.color_make(0x0D, 0x30, 0x55));
	lvgl.style_set_text_font(style_prtusb_ddlist1_list, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_12"));
	lvgl.obj_add_style(ui.prtusb_ddlist1, lvgl.DROPDOWN_PART_LIST, style_prtusb_ddlist1_list);
	lvgl.obj_set_pos(ui.prtusb_ddlist1, 28, 220);
	lvgl.obj_set_width(ui.prtusb_ddlist1, 100);

	--Write codes prtusb_ddlist2
	ui.prtusb_ddlist2 = lvgl.dropdown_create(ui.prtusb, nil);
	lvgl.dropdown_set_options(ui.prtusb_ddlist2, "72 DPI\n96 DPI\n150 DPI\n300 DPI\n600 DPI\n900 DPI\n1200 DPI");
	lvgl.dropdown_set_max_height(ui.prtusb_ddlist2, 90);

	--Write style lvgl.DROPDOWN_PART_MAIN for prtusb_ddlist2
	-- local style_prtusb_ddlist2_main;
	-- lvgl.style_init(style_prtusb_ddlist2_main);
	local style_prtusb_ddlist2_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_ddlist2_main
	lvgl.style_set_radius(style_prtusb_ddlist2_main, lvgl.STATE_DEFAULT, 3);
	lvgl.style_set_bg_color(style_prtusb_ddlist2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_prtusb_ddlist2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_prtusb_ddlist2_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_ddlist2_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_prtusb_ddlist2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xe1, 0xe6, 0xee));
	lvgl.style_set_border_width(style_prtusb_ddlist2_main, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_text_color(style_prtusb_ddlist2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x0D, 0x30, 0x55));
	lvgl.style_set_text_font(style_prtusb_ddlist2_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_12"));
	lvgl.style_set_text_line_space(style_prtusb_ddlist2_main, lvgl.STATE_DEFAULT, 20);
	lvgl.obj_add_style(ui.prtusb_ddlist2, lvgl.DROPDOWN_PART_MAIN, style_prtusb_ddlist2_main);

	--Write style lvgl.DROPDOWN_PART_SELECTED for prtusb_ddlist2
	-- local style_prtusb_ddlist2_selected;
	-- lvgl.style_init(style_prtusb_ddlist2_selected);
	local style_prtusb_ddlist2_selected = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_ddlist2_selected
	lvgl.style_set_radius(style_prtusb_ddlist2_selected, lvgl.STATE_DEFAULT, 3);
	lvgl.style_set_bg_color(style_prtusb_ddlist2_selected, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0xa1, 0xb5));
	lvgl.style_set_bg_grad_color(style_prtusb_ddlist2_selected, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0xa1, 0xb5));
	lvgl.style_set_bg_grad_dir(style_prtusb_ddlist2_selected, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_ddlist2_selected, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_prtusb_ddlist2_selected, lvgl.STATE_DEFAULT, lvgl.color_make(0xe1, 0xe6, 0xee));
	lvgl.style_set_border_width(style_prtusb_ddlist2_selected, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_text_color(style_prtusb_ddlist2_selected, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_text_font(style_prtusb_ddlist2_selected, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_12"));
	lvgl.obj_add_style(ui.prtusb_ddlist2, lvgl.DROPDOWN_PART_SELECTED, style_prtusb_ddlist2_selected);

	--Write style lvgl.DROPDOWN_PART_LIST for prtusb_ddlist2
	-- local style_prtusb_ddlist2_list;
	-- lvgl.style_init(style_prtusb_ddlist2_list);
	local style_prtusb_ddlist2_list = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtusb_ddlist2_list
	lvgl.style_set_radius(style_prtusb_ddlist2_list, lvgl.STATE_DEFAULT, 3);
	lvgl.style_set_bg_color(style_prtusb_ddlist2_list, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_prtusb_ddlist2_list, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_prtusb_ddlist2_list, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtusb_ddlist2_list, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_prtusb_ddlist2_list, lvgl.STATE_DEFAULT, lvgl.color_make(0xe1, 0xe6, 0xee));
	lvgl.style_set_border_width(style_prtusb_ddlist2_list, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_text_color(style_prtusb_ddlist2_list, lvgl.STATE_DEFAULT, lvgl.color_make(0x0D, 0x30, 0x55));
	lvgl.style_set_text_font(style_prtusb_ddlist2_list, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_12"));
	lvgl.obj_add_style(ui.prtusb_ddlist2, lvgl.DROPDOWN_PART_LIST, style_prtusb_ddlist2_list);
	lvgl.obj_set_pos(ui.prtusb_ddlist2, 166, 220);
	lvgl.obj_set_width(ui.prtusb_ddlist2, 100);
end

return prtusb
