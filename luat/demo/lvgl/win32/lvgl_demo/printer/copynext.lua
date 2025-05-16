

local copynext = {}

function copynext.setup_scr_copynext(ui)

	--Write codes copynext
	ui.copynext = lvgl.obj_create(nil, nil);

	--Write codes copynext_cont1
	ui.copynext_cont1 = lvgl.cont_create(ui.copynext, nil);

	--Write style lvgl.CONT_PART_MAIN for copynext_cont1
	-- local style_copynext_cont1_main;
	-- lvgl.style_init(style_copynext_cont1_main);
	local style_copynext_cont1_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copynext_cont1_main
	lvgl.style_set_radius(style_copynext_cont1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_copynext_cont1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_copynext_cont1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_copynext_cont1_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_cont1_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_copynext_cont1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x99, 0x99, 0x99));
	lvgl.style_set_border_width(style_copynext_cont1_main, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_border_opa(style_copynext_cont1_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_pad_left(style_copynext_cont1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_copynext_cont1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_copynext_cont1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_copynext_cont1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.copynext_cont1, lvgl.CONT_PART_MAIN, style_copynext_cont1_main);
	lvgl.obj_set_pos(ui.copynext_cont1, 0, 0);
	lvgl.obj_set_size(ui.copynext_cont1, 480, 100);
	lvgl.obj_set_click(ui.copynext_cont1, false);
	lvgl.cont_set_layout(ui.copynext_cont1, lvgl.LAYOUT_OFF);
	lvgl.cont_set_fit(ui.copynext_cont1, lvgl.FIT_NONE);

	--Write codes copynext_cont2
	ui.copynext_cont2 = lvgl.cont_create(ui.copynext, nil);

	--Write style lvgl.CONT_PART_MAIN for copynext_cont2
	-- local style_copynext_cont2_main;
	-- lvgl.style_init(style_copynext_cont2_main);
	local style_copynext_cont2_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copynext_cont2_main
	lvgl.style_set_radius(style_copynext_cont2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_copynext_cont2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff));
	lvgl.style_set_bg_grad_color(style_copynext_cont2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff));
	lvgl.style_set_bg_grad_dir(style_copynext_cont2_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_cont2_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_copynext_cont2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x99, 0x99, 0x99));
	lvgl.style_set_border_width(style_copynext_cont2_main, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_border_opa(style_copynext_cont2_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_pad_left(style_copynext_cont2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_copynext_cont2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_copynext_cont2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_copynext_cont2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.copynext_cont2, lvgl.CONT_PART_MAIN, style_copynext_cont2_main);
	lvgl.obj_set_pos(ui.copynext_cont2, 0, 100);
	lvgl.obj_set_size(ui.copynext_cont2, 480, 172);
	lvgl.obj_set_click(ui.copynext_cont2, false);
	lvgl.cont_set_layout(ui.copynext_cont2, lvgl.LAYOUT_OFF);
	lvgl.cont_set_fit(ui.copynext_cont2, lvgl.FIT_NONE);

	--Write codes copynext_label1
	ui.copynext_label1 = lvgl.label_create(ui.copynext, nil);
	lvgl.label_set_text(ui.copynext_label1, "调整图像");
	lvgl.label_set_long_mode(ui.copynext_label1, lvgl.LABEL_LONG_BREAK);
	lvgl.label_set_align(ui.copynext_label1, lvgl.LABEL_ALIGN_CENTER);

	--Write style lvgl.LABEL_PART_MAIN for copynext_label1
	-- local style_copynext_label1_main;
	-- lvgl.style_init(style_copynext_label1_main);
	local style_copynext_label1_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copynext_label1_main
	lvgl.style_set_radius(style_copynext_label1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_copynext_label1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_copynext_label1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_copynext_label1_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_label1_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_text_color(style_copynext_label1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_text_font(style_copynext_label1_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_22"));
	lvgl.style_set_text_letter_space(style_copynext_label1_main, lvgl.STATE_DEFAULT, 2);
	lvgl.style_set_pad_left(style_copynext_label1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_copynext_label1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_copynext_label1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_copynext_label1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.copynext_label1, lvgl.LABEL_PART_MAIN, style_copynext_label1_main);
	lvgl.obj_set_pos(ui.copynext_label1, 136, 30);
	lvgl.obj_set_size(ui.copynext_label1, 225, 0);

	--Write codes copynext_img3
	ui.copynext_img3 = lvgl.img_create(ui.copynext, nil);

	--Write style lvgl.IMG_PART_MAIN for copynext_img3
	-- local style_copynext_img3_main;
	-- lvgl.style_init(style_copynext_img3_main);
	local style_copynext_img3_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copynext_img3_main
	lvgl.style_set_image_recolor(style_copynext_img3_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_image_recolor_opa(style_copynext_img3_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_image_opa(style_copynext_img3_main, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.copynext_img3, lvgl.IMG_PART_MAIN, style_copynext_img3_main);
	lvgl.obj_set_pos(ui.copynext_img3, 27, 75);
	lvgl.obj_set_size(ui.copynext_img3, 250, 150);
	lvgl.obj_set_click(ui.copynext_img3, true);
	lvgl.img_set_src(ui.copynext_img3,"/images/example_alpha_250x150.png");
	lvgl.img_set_pivot(ui.copynext_img3, 0,0);
	lvgl.img_set_angle(ui.copynext_img3, 0);

	--Write codes copynext_cont4
	ui.copynext_cont4 = lvgl.cont_create(ui.copynext, nil);

	--Write style lvgl.CONT_PART_MAIN for copynext_cont4
	-- local style_copynext_cont4_main;
	-- lvgl.style_init(style_copynext_cont4_main);
	local style_copynext_cont4_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copynext_cont4_main
	lvgl.style_set_radius(style_copynext_cont4_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_copynext_cont4_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff));
	lvgl.style_set_bg_grad_color(style_copynext_cont4_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff));
	lvgl.style_set_bg_grad_dir(style_copynext_cont4_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_cont4_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_copynext_cont4_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x99, 0x99, 0x99));
	lvgl.style_set_border_width(style_copynext_cont4_main, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_border_opa(style_copynext_cont4_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_pad_left(style_copynext_cont4_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_copynext_cont4_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_copynext_cont4_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_copynext_cont4_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.copynext_cont4, lvgl.CONT_PART_MAIN, style_copynext_cont4_main);
	lvgl.obj_set_pos(ui.copynext_cont4, 305, 80);
	lvgl.obj_set_size(ui.copynext_cont4, 150, 130);
	lvgl.obj_set_click(ui.copynext_cont4, false);
	lvgl.cont_set_layout(ui.copynext_cont4, lvgl.LAYOUT_OFF);
	lvgl.cont_set_fit(ui.copynext_cont4, lvgl.FIT_NONE);

	--Write codes copynext_ddlist2
	ui.copynext_ddlist2 = lvgl.dropdown_create(ui.copynext, nil);
	lvgl.dropdown_set_options(ui.copynext_ddlist2, "72 DPI\n96 DPI\n150 DPI\n300 DPI\n600 DPI\n900 DPI\n1200 DPI");
	lvgl.dropdown_set_max_height(ui.copynext_ddlist2, 90);

	--Write style lvgl.DROPDOWN_PART_MAIN for copynext_ddlist2
	-- local style_copynext_ddlist2_main;
	-- lvgl.style_init(style_copynext_ddlist2_main);
	local style_copynext_ddlist2_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copynext_ddlist2_main
	lvgl.style_set_radius(style_copynext_ddlist2_main, lvgl.STATE_DEFAULT, 3);
	lvgl.style_set_bg_color(style_copynext_ddlist2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_copynext_ddlist2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_copynext_ddlist2_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_ddlist2_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_copynext_ddlist2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xe1, 0xe6, 0xee));
	lvgl.style_set_border_width(style_copynext_ddlist2_main, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_text_color(style_copynext_ddlist2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x0D, 0x30, 0x55));
	lvgl.style_set_text_font(style_copynext_ddlist2_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_12"));
	lvgl.style_set_text_line_space(style_copynext_ddlist2_main, lvgl.STATE_DEFAULT, 20);
	lvgl.obj_add_style(ui.copynext_ddlist2, lvgl.DROPDOWN_PART_MAIN, style_copynext_ddlist2_main);

	--Write style lvgl.DROPDOWN_PART_SELECTED for copynext_ddlist2
	-- local style_copynext_ddlist2_selected;
	-- lvgl.style_init(style_copynext_ddlist2_selected);
	local style_copynext_ddlist2_selected = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copynext_ddlist2_selected
	lvgl.style_set_radius(style_copynext_ddlist2_selected, lvgl.STATE_DEFAULT, 3);
	lvgl.style_set_bg_color(style_copynext_ddlist2_selected, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0xa1, 0xb5));
	lvgl.style_set_bg_grad_color(style_copynext_ddlist2_selected, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0xa1, 0xb5));
	lvgl.style_set_bg_grad_dir(style_copynext_ddlist2_selected, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_ddlist2_selected, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_copynext_ddlist2_selected, lvgl.STATE_DEFAULT, lvgl.color_make(0xe1, 0xe6, 0xee));
	lvgl.style_set_border_width(style_copynext_ddlist2_selected, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_text_color(style_copynext_ddlist2_selected, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_text_font(style_copynext_ddlist2_selected, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_12"));
	lvgl.obj_add_style(ui.copynext_ddlist2, lvgl.DROPDOWN_PART_SELECTED, style_copynext_ddlist2_selected);

	--Write style lvgl.DROPDOWN_PART_LIST for copynext_ddlist2
	-- local style_copynext_ddlist2_list;
	-- lvgl.style_init(style_copynext_ddlist2_list);
	local style_copynext_ddlist2_list = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copynext_ddlist2_list
	lvgl.style_set_radius(style_copynext_ddlist2_list, lvgl.STATE_DEFAULT, 3);
	lvgl.style_set_bg_color(style_copynext_ddlist2_list, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_copynext_ddlist2_list, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_copynext_ddlist2_list, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_ddlist2_list, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_copynext_ddlist2_list, lvgl.STATE_DEFAULT, lvgl.color_make(0xe1, 0xe6, 0xee));
	lvgl.style_set_border_width(style_copynext_ddlist2_list, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_text_color(style_copynext_ddlist2_list, lvgl.STATE_DEFAULT, lvgl.color_make(0x0D, 0x30, 0x55));
	lvgl.style_set_text_font(style_copynext_ddlist2_list, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_12"));
	lvgl.obj_add_style(ui.copynext_ddlist2, lvgl.DROPDOWN_PART_LIST, style_copynext_ddlist2_list);
	lvgl.obj_set_pos(ui.copynext_ddlist2, 166, 237);
	lvgl.obj_set_width(ui.copynext_ddlist2, 100);

	--Write codes copynext_btncopyback
	ui.copynext_btncopyback = lvgl.btn_create(ui.copynext, nil);

	--Write style lvgl.BTN_PART_MAIN for copynext_btncopyback
	-- local style_copynext_btncopyback_main;
	-- lvgl.style_init(style_copynext_btncopyback_main);
	local style_copynext_btncopyback_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copynext_btncopyback_main
	lvgl.style_set_radius(style_copynext_btncopyback_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_copynext_btncopyback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_copynext_btncopyback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_copynext_btncopyback_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_btncopyback_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_copynext_btncopyback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_copynext_btncopyback_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_border_opa(style_copynext_btncopyback_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_outline_color(style_copynext_btncopyback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_copynext_btncopyback_main, lvgl.STATE_DEFAULT, 0);

	--Write style state: lvgl.STATE_FOCUSED for style_copynext_btncopyback_main
	lvgl.style_set_radius(style_copynext_btncopyback_main, lvgl.STATE_FOCUSED, 50);
	lvgl.style_set_bg_color(style_copynext_btncopyback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_copynext_btncopyback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_copynext_btncopyback_main, lvgl.STATE_FOCUSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_btncopyback_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_border_color(style_copynext_btncopyback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_copynext_btncopyback_main, lvgl.STATE_FOCUSED, 2);
	lvgl.style_set_border_opa(style_copynext_btncopyback_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_outline_color(style_copynext_btncopyback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_copynext_btncopyback_main, lvgl.STATE_FOCUSED, 255);

	--Write style state: lvgl.STATE_PRESSED for style_copynext_btncopyback_main
	lvgl.style_set_radius(style_copynext_btncopyback_main, lvgl.STATE_PRESSED, 0);
	lvgl.style_set_bg_color(style_copynext_btncopyback_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_copynext_btncopyback_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_copynext_btncopyback_main, lvgl.STATE_PRESSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_btncopyback_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_border_color(style_copynext_btncopyback_main, lvgl.STATE_PRESSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_copynext_btncopyback_main, lvgl.STATE_PRESSED, 0);
	lvgl.style_set_border_opa(style_copynext_btncopyback_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_outline_color(style_copynext_btncopyback_main, lvgl.STATE_PRESSED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_copynext_btncopyback_main, lvgl.STATE_PRESSED, 0);

	--Write style state: lvgl.STATE_CHECKED for style_copynext_btncopyback_main
	lvgl.style_set_radius(style_copynext_btncopyback_main, lvgl.STATE_CHECKED, 50);
	lvgl.style_set_bg_color(style_copynext_btncopyback_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_copynext_btncopyback_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_copynext_btncopyback_main, lvgl.STATE_CHECKED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_btncopyback_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_border_color(style_copynext_btncopyback_main, lvgl.STATE_CHECKED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_copynext_btncopyback_main, lvgl.STATE_CHECKED, 2);
	lvgl.style_set_border_opa(style_copynext_btncopyback_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_outline_color(style_copynext_btncopyback_main, lvgl.STATE_CHECKED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_copynext_btncopyback_main, lvgl.STATE_CHECKED, 255);
	lvgl.obj_add_style(ui.copynext_btncopyback, lvgl.BTN_PART_MAIN, style_copynext_btncopyback_main);
	lvgl.obj_set_pos(ui.copynext_btncopyback, 50, 25);
	lvgl.obj_set_size(ui.copynext_btncopyback, 30, 30);
	ui.copynext_btncopyback_label = lvgl.label_create(ui.copynext_btncopyback, nil);
	lvgl.label_set_text(ui.copynext_btncopyback_label, "");
	lvgl.obj_set_style_local_text_color(ui.copynext_btncopyback_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));

	--Write codes copynext_swcolor
	ui.copynext_swcolor = lvgl.switch_create(ui.copynext, nil);

	--Write style lvgl.SWITCH_PART_BG for copynext_swcolor
	-- local style_copynext_swcolor_bg;
	-- lvgl.style_init(style_copynext_swcolor_bg);
	local style_copynext_swcolor_bg = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copynext_swcolor_bg
	lvgl.style_set_radius(style_copynext_swcolor_bg, lvgl.STATE_DEFAULT, 100);
	lvgl.style_set_bg_color(style_copynext_swcolor_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_bg_grad_color(style_copynext_swcolor_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_bg_grad_dir(style_copynext_swcolor_bg, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_swcolor_bg, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.copynext_swcolor, lvgl.SWITCH_PART_BG, style_copynext_swcolor_bg);

	--Write style lvgl.SWITCH_PART_INDIC for copynext_swcolor
	-- local style_copynext_swcolor_indic;
	-- lvgl.style_init(style_copynext_swcolor_indic);
	local style_copynext_swcolor_indic = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copynext_swcolor_indic
	lvgl.style_set_radius(style_copynext_swcolor_indic, lvgl.STATE_DEFAULT, 100);
	lvgl.style_set_bg_color(style_copynext_swcolor_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0xa1, 0xb5));
	lvgl.style_set_bg_grad_color(style_copynext_swcolor_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0xa1, 0xb5));
	lvgl.style_set_bg_grad_dir(style_copynext_swcolor_indic, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_swcolor_indic, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.copynext_swcolor, lvgl.SWITCH_PART_INDIC, style_copynext_swcolor_indic);

	--Write style lvgl.SWITCH_PART_KNOB for copynext_swcolor
	-- local style_copynext_swcolor_knob;
	-- lvgl.style_init(style_copynext_swcolor_knob);
	local style_copynext_swcolor_knob = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copynext_swcolor_knob
	lvgl.style_set_radius(style_copynext_swcolor_knob, lvgl.STATE_DEFAULT, 100);
	lvgl.style_set_bg_color(style_copynext_swcolor_knob, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_copynext_swcolor_knob, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_copynext_swcolor_knob, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_swcolor_knob, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.copynext_swcolor, lvgl.SWITCH_PART_KNOB, style_copynext_swcolor_knob);
	lvgl.obj_set_pos(ui.copynext_swcolor, 323, 175);
	lvgl.obj_set_size(ui.copynext_swcolor, 40, 20);
	lvgl.switch_set_anim_time(ui.copynext_swcolor, 600);

	--Write codes copynext_labelcopy
	ui.copynext_labelcopy = lvgl.label_create(ui.copynext, nil);
	lvgl.label_set_text(ui.copynext_labelcopy, "份数");
	lvgl.label_set_long_mode(ui.copynext_labelcopy, lvgl.LABEL_LONG_BREAK);
	lvgl.label_set_align(ui.copynext_labelcopy, lvgl.LABEL_ALIGN_CENTER);

	--Write style lvgl.LABEL_PART_MAIN for copynext_labelcopy
	-- local style_copynext_labelcopy_main;
	-- lvgl.style_init(style_copynext_labelcopy_main);
	local style_copynext_labelcopy_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copynext_labelcopy_main
	lvgl.style_set_radius(style_copynext_labelcopy_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_copynext_labelcopy_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_copynext_labelcopy_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_copynext_labelcopy_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_labelcopy_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_text_color(style_copynext_labelcopy_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00));
	lvgl.style_set_text_font(style_copynext_labelcopy_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_16"));
	lvgl.style_set_text_letter_space(style_copynext_labelcopy_main, lvgl.STATE_DEFAULT, 2);
	lvgl.style_set_pad_left(style_copynext_labelcopy_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_copynext_labelcopy_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_copynext_labelcopy_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_copynext_labelcopy_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.copynext_labelcopy, lvgl.LABEL_PART_MAIN, style_copynext_labelcopy_main);
	lvgl.obj_set_pos(ui.copynext_labelcopy, 348, 80);
	lvgl.obj_set_size(ui.copynext_labelcopy, 64, 0);

	--Write codes copynext_up
	ui.copynext_up = lvgl.btn_create(ui.copynext, nil);

	--Write style lvgl.BTN_PART_MAIN for copynext_up
	-- local style_copynext_up_main;
	-- lvgl.style_init(style_copynext_up_main);
	local style_copynext_up_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copynext_up_main
	lvgl.style_set_radius(style_copynext_up_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_copynext_up_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_copynext_up_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_copynext_up_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_up_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_copynext_up_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_copynext_up_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_border_opa(style_copynext_up_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_outline_color(style_copynext_up_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_outline_opa(style_copynext_up_main, lvgl.STATE_DEFAULT, 255);

	--Write style state: lvgl.STATE_FOCUSED for style_copynext_up_main
	lvgl.style_set_radius(style_copynext_up_main, lvgl.STATE_FOCUSED, 0);
	lvgl.style_set_bg_color(style_copynext_up_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_copynext_up_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_copynext_up_main, lvgl.STATE_FOCUSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_up_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_border_color(style_copynext_up_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_copynext_up_main, lvgl.STATE_FOCUSED, 0);
	lvgl.style_set_border_opa(style_copynext_up_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_outline_color(style_copynext_up_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_outline_opa(style_copynext_up_main, lvgl.STATE_FOCUSED, 255);

	--Write style state: lvgl.STATE_PRESSED for style_copynext_up_main
	lvgl.style_set_radius(style_copynext_up_main, lvgl.STATE_PRESSED, 0);
	lvgl.style_set_bg_color(style_copynext_up_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_copynext_up_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_copynext_up_main, lvgl.STATE_PRESSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_up_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_border_color(style_copynext_up_main, lvgl.STATE_PRESSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_copynext_up_main, lvgl.STATE_PRESSED, 0);
	lvgl.style_set_border_opa(style_copynext_up_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_outline_color(style_copynext_up_main, lvgl.STATE_PRESSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_outline_opa(style_copynext_up_main, lvgl.STATE_PRESSED, 100);

	--Write style state: lvgl.STATE_CHECKED for style_copynext_up_main
	lvgl.style_set_radius(style_copynext_up_main, lvgl.STATE_CHECKED, 50);
	lvgl.style_set_bg_color(style_copynext_up_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_copynext_up_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_copynext_up_main, lvgl.STATE_CHECKED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_up_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_border_color(style_copynext_up_main, lvgl.STATE_CHECKED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_copynext_up_main, lvgl.STATE_CHECKED, 2);
	lvgl.style_set_border_opa(style_copynext_up_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_outline_color(style_copynext_up_main, lvgl.STATE_CHECKED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_copynext_up_main, lvgl.STATE_CHECKED, 255);
	lvgl.obj_add_style(ui.copynext_up, lvgl.BTN_PART_MAIN, style_copynext_up_main);
	lvgl.obj_set_pos(ui.copynext_up, 417, 110);
	lvgl.obj_set_size(ui.copynext_up, 20, 20);
	ui.copynext_up_label = lvgl.label_create(ui.copynext_up, nil);
	lvgl.label_set_text(ui.copynext_up_label, "");
	lvgl.obj_set_style_local_text_color(ui.copynext_up_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00));

	--Write codes copynext_down
	ui.copynext_down = lvgl.btn_create(ui.copynext, nil);

	--Write style lvgl.BTN_PART_MAIN for copynext_down
	-- local style_copynext_down_main;
	-- lvgl.style_init(style_copynext_down_main);
	local style_copynext_down_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copynext_down_main
	lvgl.style_set_radius(style_copynext_down_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_copynext_down_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_copynext_down_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_copynext_down_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_down_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_copynext_down_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_copynext_down_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_border_opa(style_copynext_down_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_outline_color(style_copynext_down_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_outline_opa(style_copynext_down_main, lvgl.STATE_DEFAULT, 255);

	--Write style state: lvgl.STATE_FOCUSED for style_copynext_down_main
	lvgl.style_set_radius(style_copynext_down_main, lvgl.STATE_FOCUSED, 0);
	lvgl.style_set_bg_color(style_copynext_down_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_copynext_down_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_copynext_down_main, lvgl.STATE_FOCUSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_down_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_border_color(style_copynext_down_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_copynext_down_main, lvgl.STATE_FOCUSED, 0);
	lvgl.style_set_border_opa(style_copynext_down_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_outline_color(style_copynext_down_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_outline_opa(style_copynext_down_main, lvgl.STATE_FOCUSED, 255);

	--Write style state: lvgl.STATE_PRESSED for style_copynext_down_main
	lvgl.style_set_radius(style_copynext_down_main, lvgl.STATE_PRESSED, 0);
	lvgl.style_set_bg_color(style_copynext_down_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_copynext_down_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_copynext_down_main, lvgl.STATE_PRESSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_down_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_border_color(style_copynext_down_main, lvgl.STATE_PRESSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_copynext_down_main, lvgl.STATE_PRESSED, 0);
	lvgl.style_set_border_opa(style_copynext_down_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_outline_color(style_copynext_down_main, lvgl.STATE_PRESSED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_copynext_down_main, lvgl.STATE_PRESSED, 100);

	--Write style state: lvgl.STATE_CHECKED for style_copynext_down_main
	lvgl.style_set_radius(style_copynext_down_main, lvgl.STATE_CHECKED, 50);
	lvgl.style_set_bg_color(style_copynext_down_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_copynext_down_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_copynext_down_main, lvgl.STATE_CHECKED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_down_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_border_color(style_copynext_down_main, lvgl.STATE_CHECKED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_copynext_down_main, lvgl.STATE_CHECKED, 2);
	lvgl.style_set_border_opa(style_copynext_down_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_outline_color(style_copynext_down_main, lvgl.STATE_CHECKED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_copynext_down_main, lvgl.STATE_CHECKED, 255);
	lvgl.obj_add_style(ui.copynext_down, lvgl.BTN_PART_MAIN, style_copynext_down_main);
	lvgl.obj_set_pos(ui.copynext_down, 322, 110);
	lvgl.obj_set_size(ui.copynext_down, 20, 20);
	ui.copynext_down_label = lvgl.label_create(ui.copynext_down, nil);
	lvgl.label_set_text(ui.copynext_down_label, "");
	lvgl.obj_set_style_local_text_color(ui.copynext_down_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00));

	--Write codes copynext_labelcnt
	ui.copynext_labelcnt = lvgl.label_create(ui.copynext, nil);
	lvgl.label_set_text(ui.copynext_labelcnt, "1");
	lvgl.label_set_long_mode(ui.copynext_labelcnt, lvgl.LABEL_LONG_BREAK);
	lvgl.label_set_align(ui.copynext_labelcnt, lvgl.LABEL_ALIGN_CENTER);

	--Write style lvgl.LABEL_PART_MAIN for copynext_labelcnt
	-- local style_copynext_labelcnt_main;
	-- lvgl.style_init(style_copynext_labelcnt_main);
	local style_copynext_labelcnt_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copynext_labelcnt_main
	lvgl.style_set_radius(style_copynext_labelcnt_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_copynext_labelcnt_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_copynext_labelcnt_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_copynext_labelcnt_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_labelcnt_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_text_color(style_copynext_labelcnt_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00));
	lvgl.style_set_text_font(style_copynext_labelcnt_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_16"));
	lvgl.style_set_text_letter_space(style_copynext_labelcnt_main, lvgl.STATE_DEFAULT, 2);
	lvgl.style_set_pad_left(style_copynext_labelcnt_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_copynext_labelcnt_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_copynext_labelcnt_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_copynext_labelcnt_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.copynext_labelcnt, lvgl.LABEL_PART_MAIN, style_copynext_labelcnt_main);
	lvgl.obj_set_pos(ui.copynext_labelcnt, 351, 108);
	lvgl.obj_set_size(ui.copynext_labelcnt, 56, 0);

	--Write codes copynext_labelcolor
	ui.copynext_labelcolor = lvgl.label_create(ui.copynext, nil);
	lvgl.label_set_text(ui.copynext_labelcolor, "Color");
	lvgl.label_set_long_mode(ui.copynext_labelcolor, lvgl.LABEL_LONG_BREAK);
	lvgl.label_set_align(ui.copynext_labelcolor, lvgl.LABEL_ALIGN_CENTER);

	--Write style lvgl.LABEL_PART_MAIN for copynext_labelcolor
	-- local style_copynext_labelcolor_main;
	-- lvgl.style_init(style_copynext_labelcolor_main);
	local style_copynext_labelcolor_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copynext_labelcolor_main
	lvgl.style_set_radius(style_copynext_labelcolor_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_copynext_labelcolor_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_copynext_labelcolor_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_copynext_labelcolor_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_labelcolor_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_text_color(style_copynext_labelcolor_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00));
	lvgl.style_set_text_font(style_copynext_labelcolor_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_16"));
	lvgl.style_set_text_letter_space(style_copynext_labelcolor_main, lvgl.STATE_DEFAULT, 2);
	lvgl.style_set_pad_left(style_copynext_labelcolor_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_copynext_labelcolor_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_copynext_labelcolor_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_copynext_labelcolor_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.copynext_labelcolor, lvgl.LABEL_PART_MAIN, style_copynext_labelcolor_main);
	lvgl.obj_set_pos(ui.copynext_labelcolor, 314, 146);
	lvgl.obj_set_size(ui.copynext_labelcolor, 50, 0);

	--Write codes copynext_labelvert
	ui.copynext_labelvert = lvgl.label_create(ui.copynext, nil);
	lvgl.label_set_text(ui.copynext_labelvert, "Verical");
	lvgl.label_set_long_mode(ui.copynext_labelvert, lvgl.LABEL_LONG_BREAK);
	lvgl.label_set_align(ui.copynext_labelvert, lvgl.LABEL_ALIGN_CENTER);

	--Write style lvgl.LABEL_PART_MAIN for copynext_labelvert
	-- local style_copynext_labelvert_main;
	-- lvgl.style_init(style_copynext_labelvert_main);
	local style_copynext_labelvert_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copynext_labelvert_main
	lvgl.style_set_radius(style_copynext_labelvert_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_copynext_labelvert_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_copynext_labelvert_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_copynext_labelvert_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_labelvert_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_text_color(style_copynext_labelvert_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00));
	lvgl.style_set_text_font(style_copynext_labelvert_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_16"));
	lvgl.style_set_text_letter_space(style_copynext_labelvert_main, lvgl.STATE_DEFAULT, 2);
	lvgl.style_set_pad_left(style_copynext_labelvert_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_copynext_labelvert_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_copynext_labelvert_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_copynext_labelvert_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.copynext_labelvert, lvgl.LABEL_PART_MAIN, style_copynext_labelvert_main);
	lvgl.obj_set_pos(ui.copynext_labelvert, 380, 146);
	lvgl.obj_set_size(ui.copynext_labelvert, 70, 0);

	--Write codes copynext_swvert
	ui.copynext_swvert = lvgl.switch_create(ui.copynext, nil);

	--Write style lvgl.SWITCH_PART_BG for copynext_swvert
	-- local style_copynext_swvert_bg;
	-- lvgl.style_init(style_copynext_swvert_bg);
	local style_copynext_swvert_bg = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copynext_swvert_bg
	lvgl.style_set_radius(style_copynext_swvert_bg, lvgl.STATE_DEFAULT, 100);
	lvgl.style_set_bg_color(style_copynext_swvert_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_bg_grad_color(style_copynext_swvert_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_bg_grad_dir(style_copynext_swvert_bg, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_swvert_bg, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.copynext_swvert, lvgl.SWITCH_PART_BG, style_copynext_swvert_bg);

	--Write style lvgl.SWITCH_PART_INDIC for copynext_swvert
	-- local style_copynext_swvert_indic;
	-- lvgl.style_init(style_copynext_swvert_indic);
	local style_copynext_swvert_indic = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copynext_swvert_indic
	lvgl.style_set_radius(style_copynext_swvert_indic, lvgl.STATE_DEFAULT, 100);
	lvgl.style_set_bg_color(style_copynext_swvert_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0xa1, 0xb5));
	lvgl.style_set_bg_grad_color(style_copynext_swvert_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0xa1, 0xb5));
	lvgl.style_set_bg_grad_dir(style_copynext_swvert_indic, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_swvert_indic, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.copynext_swvert, lvgl.SWITCH_PART_INDIC, style_copynext_swvert_indic);

	--Write style lvgl.SWITCH_PART_KNOB for copynext_swvert
	-- local style_copynext_swvert_knob;
	-- lvgl.style_init(style_copynext_swvert_knob);
	local style_copynext_swvert_knob = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copynext_swvert_knob
	lvgl.style_set_radius(style_copynext_swvert_knob, lvgl.STATE_DEFAULT, 100);
	lvgl.style_set_bg_color(style_copynext_swvert_knob, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_copynext_swvert_knob, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_copynext_swvert_knob, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_swvert_knob, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.copynext_swvert, lvgl.SWITCH_PART_KNOB, style_copynext_swvert_knob);
	lvgl.obj_set_pos(ui.copynext_swvert, 390, 175);
	lvgl.obj_set_size(ui.copynext_swvert, 40, 20);
	lvgl.switch_set_anim_time(ui.copynext_swvert, 100);

	--Write codes copynext_ddlist1
	ui.copynext_ddlist1 = lvgl.dropdown_create(ui.copynext, nil);
	lvgl.dropdown_set_options(ui.copynext_ddlist1, "最好\n通常\n一般");
	lvgl.dropdown_set_max_height(ui.copynext_ddlist1, 90);

	--Write style lvgl.DROPDOWN_PART_MAIN for copynext_ddlist1
	-- local style_copynext_ddlist1_main;
	-- lvgl.style_init(style_copynext_ddlist1_main);
	local style_copynext_ddlist1_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copynext_ddlist1_main
	lvgl.style_set_radius(style_copynext_ddlist1_main, lvgl.STATE_DEFAULT, 3);
	lvgl.style_set_bg_color(style_copynext_ddlist1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_copynext_ddlist1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_copynext_ddlist1_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_ddlist1_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_copynext_ddlist1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xe1, 0xe6, 0xee));
	lvgl.style_set_border_width(style_copynext_ddlist1_main, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_text_color(style_copynext_ddlist1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x0D, 0x30, 0x55));
	lvgl.style_set_text_font(style_copynext_ddlist1_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_12"));
	lvgl.style_set_text_line_space(style_copynext_ddlist1_main, lvgl.STATE_DEFAULT, 20);
	lvgl.obj_add_style(ui.copynext_ddlist1, lvgl.DROPDOWN_PART_MAIN, style_copynext_ddlist1_main);

	--Write style lvgl.DROPDOWN_PART_SELECTED for copynext_ddlist1
	-- local style_copynext_ddlist1_selected;
	-- lvgl.style_init(style_copynext_ddlist1_selected);
	local style_copynext_ddlist1_selected = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copynext_ddlist1_selected
	lvgl.style_set_radius(style_copynext_ddlist1_selected, lvgl.STATE_DEFAULT, 3);
	lvgl.style_set_bg_color(style_copynext_ddlist1_selected, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0xa1, 0xb5));
	lvgl.style_set_bg_grad_color(style_copynext_ddlist1_selected, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0xa1, 0xb5));
	lvgl.style_set_bg_grad_dir(style_copynext_ddlist1_selected, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_ddlist1_selected, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_copynext_ddlist1_selected, lvgl.STATE_DEFAULT, lvgl.color_make(0xe1, 0xe6, 0xee));
	lvgl.style_set_border_width(style_copynext_ddlist1_selected, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_text_color(style_copynext_ddlist1_selected, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_text_font(style_copynext_ddlist1_selected, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_12"));
	lvgl.obj_add_style(ui.copynext_ddlist1, lvgl.DROPDOWN_PART_SELECTED, style_copynext_ddlist1_selected);

	--Write style lvgl.DROPDOWN_PART_LIST for copynext_ddlist1
	-- local style_copynext_ddlist1_list;
	-- lvgl.style_init(style_copynext_ddlist1_list);
	local style_copynext_ddlist1_list = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copynext_ddlist1_list
	lvgl.style_set_radius(style_copynext_ddlist1_list, lvgl.STATE_DEFAULT, 3);
	lvgl.style_set_bg_color(style_copynext_ddlist1_list, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_copynext_ddlist1_list, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_copynext_ddlist1_list, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_ddlist1_list, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_copynext_ddlist1_list, lvgl.STATE_DEFAULT, lvgl.color_make(0xe1, 0xe6, 0xee));
	lvgl.style_set_border_width(style_copynext_ddlist1_list, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_text_color(style_copynext_ddlist1_list, lvgl.STATE_DEFAULT, lvgl.color_make(0x0D, 0x30, 0x55));
	lvgl.style_set_text_font(style_copynext_ddlist1_list, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_12"));
	lvgl.obj_add_style(ui.copynext_ddlist1, lvgl.DROPDOWN_PART_LIST, style_copynext_ddlist1_list);
	lvgl.obj_set_pos(ui.copynext_ddlist1, 28, 237);
	lvgl.obj_set_width(ui.copynext_ddlist1, 100);

	--Write codes copynext_print
	ui.copynext_print = lvgl.btn_create(ui.copynext, nil);

	--Write style lvgl.BTN_PART_MAIN for copynext_print
	-- local style_copynext_print_main;
	-- lvgl.style_init(style_copynext_print_main);
	local style_copynext_print_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copynext_print_main
	lvgl.style_set_radius(style_copynext_print_main, lvgl.STATE_DEFAULT, 50);
	lvgl.style_set_bg_color(style_copynext_print_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_copynext_print_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_copynext_print_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_print_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_copynext_print_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_copynext_print_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_border_opa(style_copynext_print_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_outline_color(style_copynext_print_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_outline_opa(style_copynext_print_main, lvgl.STATE_DEFAULT, 255);

	--Write style state: lvgl.STATE_FOCUSED for style_copynext_print_main
	lvgl.style_set_radius(style_copynext_print_main, lvgl.STATE_FOCUSED, 50);
	lvgl.style_set_bg_color(style_copynext_print_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_copynext_print_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_copynext_print_main, lvgl.STATE_FOCUSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_print_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_border_color(style_copynext_print_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_copynext_print_main, lvgl.STATE_FOCUSED, 0);
	lvgl.style_set_border_opa(style_copynext_print_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_outline_color(style_copynext_print_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_outline_opa(style_copynext_print_main, lvgl.STATE_FOCUSED, 255);

	--Write style state: lvgl.STATE_PRESSED for style_copynext_print_main
	lvgl.style_set_radius(style_copynext_print_main, lvgl.STATE_PRESSED, 50);
	lvgl.style_set_bg_color(style_copynext_print_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_copynext_print_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_copynext_print_main, lvgl.STATE_PRESSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_print_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_border_color(style_copynext_print_main, lvgl.STATE_PRESSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_copynext_print_main, lvgl.STATE_PRESSED, 0);
	lvgl.style_set_border_opa(style_copynext_print_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_outline_color(style_copynext_print_main, lvgl.STATE_PRESSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_outline_opa(style_copynext_print_main, lvgl.STATE_PRESSED, 100);

	--Write style state: lvgl.STATE_CHECKED for style_copynext_print_main
	lvgl.style_set_radius(style_copynext_print_main, lvgl.STATE_CHECKED, 50);
	lvgl.style_set_bg_color(style_copynext_print_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_copynext_print_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_copynext_print_main, lvgl.STATE_CHECKED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copynext_print_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_border_color(style_copynext_print_main, lvgl.STATE_CHECKED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_copynext_print_main, lvgl.STATE_CHECKED, 2);
	lvgl.style_set_border_opa(style_copynext_print_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_outline_color(style_copynext_print_main, lvgl.STATE_CHECKED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_copynext_print_main, lvgl.STATE_CHECKED, 255);
	lvgl.obj_add_style(ui.copynext_print, lvgl.BTN_PART_MAIN, style_copynext_print_main);
	lvgl.obj_set_pos(ui.copynext_print, 320, 223);
	lvgl.obj_set_size(ui.copynext_print, 118, 40);
	ui.copynext_print_label = lvgl.label_create(ui.copynext_print, nil);
	lvgl.label_set_text(ui.copynext_print_label, "打印");
	lvgl.obj_set_style_local_text_color(ui.copynext_print_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.obj_set_style_local_text_font(ui.copynext_print_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_14"));
end

return copynext
