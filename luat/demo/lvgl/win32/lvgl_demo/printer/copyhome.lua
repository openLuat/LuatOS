

local copyhome = {}

function copyhome.setup_scr_copyhome(ui)

	--Write codes copyhome
	ui.copyhome = lvgl.obj_create(nil, nil);

	--Write codes copyhome_cont1
	ui.copyhome_cont1 = lvgl.cont_create(ui.copyhome, nil);

	--Write style lvgl.CONT_PART_MAIN for copyhome_cont1
	-- local style_copyhome_cont1_main;
	-- lvgl.style_init(style_copyhome_cont1_main);
	local style_copyhome_cont1_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copyhome_cont1_main
	lvgl.style_set_radius(style_copyhome_cont1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_copyhome_cont1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_copyhome_cont1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_copyhome_cont1_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copyhome_cont1_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_copyhome_cont1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x99, 0x99, 0x99));
	lvgl.style_set_border_width(style_copyhome_cont1_main, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_border_opa(style_copyhome_cont1_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_pad_left(style_copyhome_cont1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_copyhome_cont1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_copyhome_cont1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_copyhome_cont1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.copyhome_cont1, lvgl.CONT_PART_MAIN, style_copyhome_cont1_main);
	lvgl.obj_set_pos(ui.copyhome_cont1, 0, 0);
	lvgl.obj_set_size(ui.copyhome_cont1, 480, 100);
	lvgl.obj_set_click(ui.copyhome_cont1, false);
	lvgl.cont_set_layout(ui.copyhome_cont1, lvgl.LAYOUT_OFF);
	lvgl.cont_set_fit(ui.copyhome_cont1, lvgl.FIT_NONE);

	--Write codes copyhome_cont2
	ui.copyhome_cont2 = lvgl.cont_create(ui.copyhome, nil);

	--Write style lvgl.CONT_PART_MAIN for copyhome_cont2
	-- local style_copyhome_cont2_main;
	-- lvgl.style_init(style_copyhome_cont2_main);
	local style_copyhome_cont2_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copyhome_cont2_main
	lvgl.style_set_radius(style_copyhome_cont2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_copyhome_cont2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff));
	lvgl.style_set_bg_grad_color(style_copyhome_cont2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff));
	lvgl.style_set_bg_grad_dir(style_copyhome_cont2_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copyhome_cont2_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_copyhome_cont2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x99, 0x99, 0x99));
	lvgl.style_set_border_width(style_copyhome_cont2_main, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_border_opa(style_copyhome_cont2_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_pad_left(style_copyhome_cont2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_copyhome_cont2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_copyhome_cont2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_copyhome_cont2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.copyhome_cont2, lvgl.CONT_PART_MAIN, style_copyhome_cont2_main);
	lvgl.obj_set_pos(ui.copyhome_cont2, 0, 100);
	lvgl.obj_set_size(ui.copyhome_cont2, 480, 172);
	lvgl.obj_set_click(ui.copyhome_cont2, false);
	lvgl.cont_set_layout(ui.copyhome_cont2, lvgl.LAYOUT_OFF);
	lvgl.cont_set_fit(ui.copyhome_cont2, lvgl.FIT_NONE);

	--Write codes copyhome_label1
	ui.copyhome_label1 = lvgl.label_create(ui.copyhome, nil);
	lvgl.label_set_text(ui.copyhome_label1, "调整图像");
	lvgl.label_set_long_mode(ui.copyhome_label1, lvgl.LABEL_LONG_BREAK);
	lvgl.label_set_align(ui.copyhome_label1, lvgl.LABEL_ALIGN_CENTER);

	--Write style lvgl.LABEL_PART_MAIN for copyhome_label1
	-- local style_copyhome_label1_main;
	-- lvgl.style_init(style_copyhome_label1_main);
	local style_copyhome_label1_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copyhome_label1_main
	lvgl.style_set_radius(style_copyhome_label1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_copyhome_label1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_copyhome_label1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_copyhome_label1_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copyhome_label1_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_text_color(style_copyhome_label1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_text_font(style_copyhome_label1_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_22"));
	lvgl.style_set_text_letter_space(style_copyhome_label1_main, lvgl.STATE_DEFAULT, 2);
	lvgl.style_set_pad_left(style_copyhome_label1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_copyhome_label1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_copyhome_label1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_copyhome_label1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.copyhome_label1, lvgl.LABEL_PART_MAIN, style_copyhome_label1_main);
	lvgl.obj_set_pos(ui.copyhome_label1, 136, 30);
	lvgl.obj_set_size(ui.copyhome_label1, 225, 0);

	--Write codes copyhome_img3
	ui.copyhome_img3 = lvgl.img_create(ui.copyhome, nil);

	--Write style lvgl.IMG_PART_MAIN for copyhome_img3
	-- local style_copyhome_img3_main;
	-- lvgl.style_init(style_copyhome_img3_main);
	local style_copyhome_img3_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copyhome_img3_main
	lvgl.style_set_image_recolor(style_copyhome_img3_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_image_recolor_opa(style_copyhome_img3_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_image_opa(style_copyhome_img3_main, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.copyhome_img3, lvgl.IMG_PART_MAIN, style_copyhome_img3_main);
	lvgl.obj_set_pos(ui.copyhome_img3, 27, 75);
	lvgl.obj_set_size(ui.copyhome_img3, 300, 172);
	lvgl.obj_set_click(ui.copyhome_img3, true);
	lvgl.img_set_src(ui.copyhome_img3,"/images/example_alpha_300x172.png");
	lvgl.img_set_pivot(ui.copyhome_img3, 0,0);
	lvgl.img_set_angle(ui.copyhome_img3, 0);

	--Write codes copyhome_cont4
	ui.copyhome_cont4 = lvgl.cont_create(ui.copyhome, nil);

	--Write style lvgl.CONT_PART_MAIN for copyhome_cont4
	-- local style_copyhome_cont4_main;
	-- lvgl.style_init(style_copyhome_cont4_main);
	local style_copyhome_cont4_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copyhome_cont4_main
	lvgl.style_set_radius(style_copyhome_cont4_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_copyhome_cont4_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff));
	lvgl.style_set_bg_grad_color(style_copyhome_cont4_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff));
	lvgl.style_set_bg_grad_dir(style_copyhome_cont4_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copyhome_cont4_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_copyhome_cont4_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x99, 0x99, 0x99));
	lvgl.style_set_border_width(style_copyhome_cont4_main, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_border_opa(style_copyhome_cont4_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_pad_left(style_copyhome_cont4_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_copyhome_cont4_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_copyhome_cont4_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_copyhome_cont4_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.copyhome_cont4, lvgl.CONT_PART_MAIN, style_copyhome_cont4_main);
	lvgl.obj_set_pos(ui.copyhome_cont4, 368, 80);
	lvgl.obj_set_size(ui.copyhome_cont4, 80, 130);
	lvgl.obj_set_click(ui.copyhome_cont4, false);
	lvgl.cont_set_layout(ui.copyhome_cont4, lvgl.LAYOUT_OFF);
	lvgl.cont_set_fit(ui.copyhome_cont4, lvgl.FIT_NONE);

	--Write codes copyhome_btncopynext
	ui.copyhome_btncopynext = lvgl.btn_create(ui.copyhome, nil);

	--Write style lvgl.BTN_PART_MAIN for copyhome_btncopynext
	-- local style_copyhome_btncopynext_main;
	-- lvgl.style_init(style_copyhome_btncopynext_main);
	local style_copyhome_btncopynext_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copyhome_btncopynext_main
	lvgl.style_set_radius(style_copyhome_btncopynext_main, lvgl.STATE_DEFAULT, 50);
	lvgl.style_set_bg_color(style_copyhome_btncopynext_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x29, 0x30, 0x41));
	lvgl.style_set_bg_grad_color(style_copyhome_btncopynext_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x29, 0x30, 0x41));
	lvgl.style_set_bg_grad_dir(style_copyhome_btncopynext_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copyhome_btncopynext_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_copyhome_btncopynext_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_copyhome_btncopynext_main, lvgl.STATE_DEFAULT, 2);
	lvgl.style_set_border_opa(style_copyhome_btncopynext_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_outline_color(style_copyhome_btncopynext_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_copyhome_btncopynext_main, lvgl.STATE_DEFAULT, 255);

	--Write style state: lvgl.STATE_FOCUSED for style_copyhome_btncopynext_main
	lvgl.style_set_radius(style_copyhome_btncopynext_main, lvgl.STATE_FOCUSED, 50);
	lvgl.style_set_bg_color(style_copyhome_btncopynext_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_copyhome_btncopynext_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_copyhome_btncopynext_main, lvgl.STATE_FOCUSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copyhome_btncopynext_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_border_color(style_copyhome_btncopynext_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_copyhome_btncopynext_main, lvgl.STATE_FOCUSED, 2);
	lvgl.style_set_border_opa(style_copyhome_btncopynext_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_outline_color(style_copyhome_btncopynext_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_copyhome_btncopynext_main, lvgl.STATE_FOCUSED, 255);

	--Write style state: lvgl.STATE_PRESSED for style_copyhome_btncopynext_main
	lvgl.style_set_radius(style_copyhome_btncopynext_main, lvgl.STATE_PRESSED, 50);
	lvgl.style_set_bg_color(style_copyhome_btncopynext_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_copyhome_btncopynext_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_copyhome_btncopynext_main, lvgl.STATE_PRESSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copyhome_btncopynext_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_border_color(style_copyhome_btncopynext_main, lvgl.STATE_PRESSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_copyhome_btncopynext_main, lvgl.STATE_PRESSED, 2);
	lvgl.style_set_border_opa(style_copyhome_btncopynext_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_outline_color(style_copyhome_btncopynext_main, lvgl.STATE_PRESSED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_copyhome_btncopynext_main, lvgl.STATE_PRESSED, 100);

	--Write style state: lvgl.STATE_CHECKED for style_copyhome_btncopynext_main
	lvgl.style_set_radius(style_copyhome_btncopynext_main, lvgl.STATE_CHECKED, 50);
	lvgl.style_set_bg_color(style_copyhome_btncopynext_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_copyhome_btncopynext_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_copyhome_btncopynext_main, lvgl.STATE_CHECKED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copyhome_btncopynext_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_border_color(style_copyhome_btncopynext_main, lvgl.STATE_CHECKED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_copyhome_btncopynext_main, lvgl.STATE_CHECKED, 2);
	lvgl.style_set_border_opa(style_copyhome_btncopynext_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_outline_color(style_copyhome_btncopynext_main, lvgl.STATE_CHECKED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_copyhome_btncopynext_main, lvgl.STATE_CHECKED, 255);
	lvgl.obj_add_style(ui.copyhome_btncopynext, lvgl.BTN_PART_MAIN, style_copyhome_btncopynext_main);
	lvgl.obj_set_pos(ui.copyhome_btncopynext, 368, 221);
	lvgl.obj_set_size(ui.copyhome_btncopynext, 80, 40);
	ui.copyhome_btncopynext_label = lvgl.label_create(ui.copyhome_btncopynext, nil);
	lvgl.label_set_text(ui.copyhome_btncopynext_label, "下一步");
	lvgl.obj_set_style_local_text_color(ui.copyhome_btncopynext_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.obj_set_style_local_text_font(ui.copyhome_btncopynext_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_14"));

	--Write codes copyhome_sliderhue
	ui.copyhome_sliderhue = lvgl.slider_create(ui.copyhome, nil);

	--Write style lvgl.SLIDER_PART_INDIC for copyhome_sliderhue
	-- local style_copyhome_sliderhue_indic;
	-- lvgl.style_init(style_copyhome_sliderhue_indic);
	local style_copyhome_sliderhue_indic = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copyhome_sliderhue_indic
	lvgl.style_set_radius(style_copyhome_sliderhue_indic, lvgl.STATE_DEFAULT, 50);
	lvgl.style_set_bg_color(style_copyhome_sliderhue_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_bg_grad_color(style_copyhome_sliderhue_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0xdd, 0xd7, 0xd9));
	lvgl.style_set_bg_grad_dir(style_copyhome_sliderhue_indic, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copyhome_sliderhue_indic, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.copyhome_sliderhue, lvgl.SLIDER_PART_INDIC, style_copyhome_sliderhue_indic);

	--Write style lvgl.SLIDER_PART_BG for copyhome_sliderhue
	-- local style_copyhome_sliderhue_bg;
	-- lvgl.style_init(style_copyhome_sliderhue_bg);
	local style_copyhome_sliderhue_bg = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copyhome_sliderhue_bg
	lvgl.style_set_radius(style_copyhome_sliderhue_bg, lvgl.STATE_DEFAULT, 50);
	lvgl.style_set_bg_color(style_copyhome_sliderhue_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_bg_grad_color(style_copyhome_sliderhue_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_bg_grad_dir(style_copyhome_sliderhue_bg, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copyhome_sliderhue_bg, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_outline_color(style_copyhome_sliderhue_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_copyhome_sliderhue_bg, lvgl.STATE_DEFAULT, 0);

	--Write style state: lvgl.STATE_FOCUSED for style_copyhome_sliderhue_bg
	lvgl.style_set_outline_color(style_copyhome_sliderhue_bg, lvgl.STATE_FOCUSED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_copyhome_sliderhue_bg, lvgl.STATE_FOCUSED, 255);
	lvgl.obj_add_style(ui.copyhome_sliderhue, lvgl.SLIDER_PART_BG, style_copyhome_sliderhue_bg);

	--Write style lvgl.SLIDER_PART_KNOB for copyhome_sliderhue
	-- local style_copyhome_sliderhue_knob;
	-- lvgl.style_init(style_copyhome_sliderhue_knob);
	local style_copyhome_sliderhue_knob = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copyhome_sliderhue_knob
	lvgl.style_set_radius(style_copyhome_sliderhue_knob, lvgl.STATE_DEFAULT, 50);
	lvgl.style_set_bg_color(style_copyhome_sliderhue_knob, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_copyhome_sliderhue_knob, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_copyhome_sliderhue_knob, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copyhome_sliderhue_knob, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.copyhome_sliderhue, lvgl.SLIDER_PART_KNOB, style_copyhome_sliderhue_knob);
	lvgl.obj_set_pos(ui.copyhome_sliderhue, 420, 115);
	lvgl.obj_set_size(ui.copyhome_sliderhue, 8, 80);
	lvgl.slider_set_range(ui.copyhome_sliderhue,0, 100);
	lvgl.slider_set_value(ui.copyhome_sliderhue,50,false);

	--Write codes copyhome_sliderbright
	ui.copyhome_sliderbright = lvgl.slider_create(ui.copyhome, nil);

	--Write style lvgl.SLIDER_PART_INDIC for copyhome_sliderbright
	-- local style_copyhome_sliderbright_indic;
	-- lvgl.style_init(style_copyhome_sliderbright_indic);
	local style_copyhome_sliderbright_indic = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copyhome_sliderbright_indic
	lvgl.style_set_radius(style_copyhome_sliderbright_indic, lvgl.STATE_DEFAULT, 50);
	lvgl.style_set_bg_color(style_copyhome_sliderbright_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_bg_grad_color(style_copyhome_sliderbright_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0xdd, 0xd7, 0xd9));
	lvgl.style_set_bg_grad_dir(style_copyhome_sliderbright_indic, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copyhome_sliderbright_indic, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.copyhome_sliderbright, lvgl.SLIDER_PART_INDIC, style_copyhome_sliderbright_indic);

	--Write style lvgl.SLIDER_PART_BG for copyhome_sliderbright
	-- local style_copyhome_sliderbright_bg;
	-- lvgl.style_init(style_copyhome_sliderbright_bg);
	local style_copyhome_sliderbright_bg = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copyhome_sliderbright_bg
	lvgl.style_set_radius(style_copyhome_sliderbright_bg, lvgl.STATE_DEFAULT, 50);
	lvgl.style_set_bg_color(style_copyhome_sliderbright_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_bg_grad_color(style_copyhome_sliderbright_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_bg_grad_dir(style_copyhome_sliderbright_bg, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copyhome_sliderbright_bg, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_outline_color(style_copyhome_sliderbright_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_copyhome_sliderbright_bg, lvgl.STATE_DEFAULT, 0);

	--Write style state: lvgl.STATE_FOCUSED for style_copyhome_sliderbright_bg
	lvgl.style_set_outline_color(style_copyhome_sliderbright_bg, lvgl.STATE_FOCUSED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_copyhome_sliderbright_bg, lvgl.STATE_FOCUSED, 255);
	lvgl.obj_add_style(ui.copyhome_sliderbright, lvgl.SLIDER_PART_BG, style_copyhome_sliderbright_bg);

	--Write style lvgl.SLIDER_PART_KNOB for copyhome_sliderbright
	-- local style_copyhome_sliderbright_knob;
	-- lvgl.style_init(style_copyhome_sliderbright_knob);
	local style_copyhome_sliderbright_knob = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copyhome_sliderbright_knob
	lvgl.style_set_radius(style_copyhome_sliderbright_knob, lvgl.STATE_DEFAULT, 50);
	lvgl.style_set_bg_color(style_copyhome_sliderbright_knob, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_copyhome_sliderbright_knob, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_copyhome_sliderbright_knob, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copyhome_sliderbright_knob, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.copyhome_sliderbright, lvgl.SLIDER_PART_KNOB, style_copyhome_sliderbright_knob);
	lvgl.obj_set_pos(ui.copyhome_sliderbright, 380, 115);
	lvgl.obj_set_size(ui.copyhome_sliderbright, 8, 80);
	lvgl.slider_set_range(ui.copyhome_sliderbright,0, 100);
	lvgl.slider_set_value(ui.copyhome_sliderbright,50,false);

	--Write codes copyhome_bright
	ui.copyhome_bright = lvgl.img_create(ui.copyhome, nil);

	--Write style lvgl.IMG_PART_MAIN for copyhome_bright
	-- local style_copyhome_bright_main;
	-- lvgl.style_init(style_copyhome_bright_main);
	local style_copyhome_bright_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copyhome_bright_main
	lvgl.style_set_image_recolor(style_copyhome_bright_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_image_recolor_opa(style_copyhome_bright_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_image_opa(style_copyhome_bright_main, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.copyhome_bright, lvgl.IMG_PART_MAIN, style_copyhome_bright_main);
	lvgl.obj_set_pos(ui.copyhome_bright, 372, 82);
	lvgl.obj_set_size(ui.copyhome_bright, 24, 24);
	lvgl.obj_set_click(ui.copyhome_bright, true);
	lvgl.img_set_src(ui.copyhome_bright,"/images/bright_alpha_24x24.png");
	lvgl.img_set_pivot(ui.copyhome_bright, 0,0);
	lvgl.img_set_angle(ui.copyhome_bright, 0);

	--Write codes copyhome_hue
	ui.copyhome_hue = lvgl.img_create(ui.copyhome, nil);

	--Write style lvgl.IMG_PART_MAIN for copyhome_hue
	-- local style_copyhome_hue_main;
	-- lvgl.style_init(style_copyhome_hue_main);
	local style_copyhome_hue_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copyhome_hue_main
	lvgl.style_set_image_recolor(style_copyhome_hue_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_image_recolor_opa(style_copyhome_hue_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_image_opa(style_copyhome_hue_main, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.copyhome_hue, lvgl.IMG_PART_MAIN, style_copyhome_hue_main);
	lvgl.obj_set_pos(ui.copyhome_hue, 413, 83);
	lvgl.obj_set_size(ui.copyhome_hue, 21, 21);
	lvgl.obj_set_click(ui.copyhome_hue, true);
	lvgl.img_set_src(ui.copyhome_hue,"/images/hue_alpha_21x21.png");
	lvgl.img_set_pivot(ui.copyhome_hue, 0,0);
	lvgl.img_set_angle(ui.copyhome_hue, 0);

	--Write codes copyhome_btncopyback
	ui.copyhome_btncopyback = lvgl.btn_create(ui.copyhome, nil);

	--Write style lvgl.BTN_PART_MAIN for copyhome_btncopyback
	-- local style_copyhome_btncopyback_main;
	-- lvgl.style_init(style_copyhome_btncopyback_main);
	local style_copyhome_btncopyback_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_copyhome_btncopyback_main
	lvgl.style_set_radius(style_copyhome_btncopyback_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_copyhome_btncopyback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_copyhome_btncopyback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_copyhome_btncopyback_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copyhome_btncopyback_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_copyhome_btncopyback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_copyhome_btncopyback_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_border_opa(style_copyhome_btncopyback_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_outline_color(style_copyhome_btncopyback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_copyhome_btncopyback_main, lvgl.STATE_DEFAULT, 0);

	--Write style state: lvgl.STATE_FOCUSED for style_copyhome_btncopyback_main
	lvgl.style_set_radius(style_copyhome_btncopyback_main, lvgl.STATE_FOCUSED, 50);
	lvgl.style_set_bg_color(style_copyhome_btncopyback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_copyhome_btncopyback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_copyhome_btncopyback_main, lvgl.STATE_FOCUSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copyhome_btncopyback_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_border_color(style_copyhome_btncopyback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_copyhome_btncopyback_main, lvgl.STATE_FOCUSED, 2);
	lvgl.style_set_border_opa(style_copyhome_btncopyback_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_outline_color(style_copyhome_btncopyback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_copyhome_btncopyback_main, lvgl.STATE_FOCUSED, 255);

	--Write style state: lvgl.STATE_PRESSED for style_copyhome_btncopyback_main
	lvgl.style_set_radius(style_copyhome_btncopyback_main, lvgl.STATE_PRESSED, 0);
	lvgl.style_set_bg_color(style_copyhome_btncopyback_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_copyhome_btncopyback_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_copyhome_btncopyback_main, lvgl.STATE_PRESSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copyhome_btncopyback_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_border_color(style_copyhome_btncopyback_main, lvgl.STATE_PRESSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_copyhome_btncopyback_main, lvgl.STATE_PRESSED, 0);
	lvgl.style_set_border_opa(style_copyhome_btncopyback_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_outline_color(style_copyhome_btncopyback_main, lvgl.STATE_PRESSED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_copyhome_btncopyback_main, lvgl.STATE_PRESSED, 0);

	--Write style state: lvgl.STATE_CHECKED for style_copyhome_btncopyback_main
	lvgl.style_set_radius(style_copyhome_btncopyback_main, lvgl.STATE_CHECKED, 50);
	lvgl.style_set_bg_color(style_copyhome_btncopyback_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_copyhome_btncopyback_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_copyhome_btncopyback_main, lvgl.STATE_CHECKED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_copyhome_btncopyback_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_border_color(style_copyhome_btncopyback_main, lvgl.STATE_CHECKED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_copyhome_btncopyback_main, lvgl.STATE_CHECKED, 2);
	lvgl.style_set_border_opa(style_copyhome_btncopyback_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_outline_color(style_copyhome_btncopyback_main, lvgl.STATE_CHECKED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_copyhome_btncopyback_main, lvgl.STATE_CHECKED, 255);
	lvgl.obj_add_style(ui.copyhome_btncopyback, lvgl.BTN_PART_MAIN, style_copyhome_btncopyback_main);
	lvgl.obj_set_pos(ui.copyhome_btncopyback, 50, 25);
	lvgl.obj_set_size(ui.copyhome_btncopyback, 30, 30);
	ui.copyhome_btncopyback_label = lvgl.label_create(ui.copyhome_btncopyback, nil);
	lvgl.label_set_text(ui.copyhome_btncopyback_label, "");
	lvgl.obj_set_style_local_text_color(ui.copyhome_btncopyback_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
end

return copyhome
