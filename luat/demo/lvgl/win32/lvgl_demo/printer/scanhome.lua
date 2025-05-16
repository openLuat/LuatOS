

local scanhome = {}

function scanhome.setup_scr_scanhome(ui)

	--Write codes scanhome
	ui.scanhome = lvgl.obj_create(nil, nil);

	--Write codes scanhome_cont0
	ui.scanhome_cont0 = lvgl.cont_create(ui.scanhome, nil);

	--Write style lvgl.CONT_PART_MAIN for scanhome_cont0
	-- local  style_scanhome_cont0_main;
	-- lvgl.style_init(style_scanhome_cont0_main);
	local style_scanhome_cont0_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_scanhome_cont0_main
	lvgl.style_set_radius(style_scanhome_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_scanhome_cont0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_scanhome_cont0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_scanhome_cont0_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_scanhome_cont0_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_scanhome_cont0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x99, 0x99, 0x99));
	lvgl.style_set_border_width(style_scanhome_cont0_main, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_border_opa(style_scanhome_cont0_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_pad_left(style_scanhome_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_scanhome_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_scanhome_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_scanhome_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.scanhome_cont0, lvgl.CONT_PART_MAIN, style_scanhome_cont0_main);
	lvgl.obj_set_pos(ui.scanhome_cont0, 0, 0);
	lvgl.obj_set_size(ui.scanhome_cont0, 480, 100);
	lvgl.obj_set_click(ui.scanhome_cont0, false);
	lvgl.cont_set_layout(ui.scanhome_cont0, lvgl.LAYOUT_OFF);
	lvgl.cont_set_fit(ui.scanhome_cont0, lvgl.FIT_NONE);

	--Write codes scanhome_label1
	ui.scanhome_label1 = lvgl.label_create(ui.scanhome, nil);
	lvgl.label_set_text(ui.scanhome_label1, "调整图像");
	lvgl.label_set_long_mode(ui.scanhome_label1, lvgl.LABEL_LONG_BREAK);
	lvgl.label_set_align(ui.scanhome_label1, lvgl.LABEL_ALIGN_CENTER);

	--Write style lvgl.LABEL_PART_MAIN for scanhome_label1
	-- local  style_scanhome_label1_main;
	-- lvgl.style_init(style_scanhome_label1_main);
	local style_scanhome_label1_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_scanhome_label1_main
	lvgl.style_set_radius(style_scanhome_label1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_scanhome_label1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_scanhome_label1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_scanhome_label1_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_scanhome_label1_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_text_color(style_scanhome_label1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_text_font(style_scanhome_label1_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_22"));
	lvgl.style_set_text_letter_space(style_scanhome_label1_main, lvgl.STATE_DEFAULT, 2);
	lvgl.style_set_pad_left(style_scanhome_label1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_scanhome_label1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_scanhome_label1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_scanhome_label1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.scanhome_label1, lvgl.LABEL_PART_MAIN, style_scanhome_label1_main);
	lvgl.obj_set_pos(ui.scanhome_label1, 136, 30);
	lvgl.obj_set_size(ui.scanhome_label1, 225, 0);

	--Write codes scanhome_cont2
	ui.scanhome_cont2 = lvgl.cont_create(ui.scanhome, nil);

	--Write style lvgl.CONT_PART_MAIN for scanhome_cont2
	-- local  style_scanhome_cont2_main;
	-- lvgl.style_init(style_scanhome_cont2_main);
	local style_scanhome_cont2_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_scanhome_cont2_main
	lvgl.style_set_radius(style_scanhome_cont2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_scanhome_cont2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff));
	lvgl.style_set_bg_grad_color(style_scanhome_cont2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff));
	lvgl.style_set_bg_grad_dir(style_scanhome_cont2_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_scanhome_cont2_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_scanhome_cont2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x99, 0x99, 0x99));
	lvgl.style_set_border_width(style_scanhome_cont2_main, lvgl.STATE_DEFAULT, 2);
	lvgl.style_set_border_opa(style_scanhome_cont2_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_pad_left(style_scanhome_cont2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_scanhome_cont2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_scanhome_cont2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_scanhome_cont2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.scanhome_cont2, lvgl.CONT_PART_MAIN, style_scanhome_cont2_main);
	lvgl.obj_set_pos(ui.scanhome_cont2, 0, 100);
	lvgl.obj_set_size(ui.scanhome_cont2, 480, 172);
	lvgl.obj_set_click(ui.scanhome_cont2, false);
	lvgl.cont_set_layout(ui.scanhome_cont2, lvgl.LAYOUT_OFF);
	lvgl.cont_set_fit(ui.scanhome_cont2, lvgl.FIT_NONE);

	--Write codes scanhome_img3
	ui.scanhome_img3 = lvgl.img_create(ui.scanhome, nil);

	--Write style lvgl.IMG_PART_MAIN for scanhome_img3
	-- local  style_scanhome_img3_main;
	-- lvgl.style_init(style_scanhome_img3_main);
	local style_scanhome_img3_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_scanhome_img3_main
	lvgl.style_set_image_recolor(style_scanhome_img3_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_image_recolor_opa(style_scanhome_img3_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_image_opa(style_scanhome_img3_main, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.scanhome_img3, lvgl.IMG_PART_MAIN, style_scanhome_img3_main);
	lvgl.obj_set_pos(ui.scanhome_img3, 27, 75);
	lvgl.obj_set_size(ui.scanhome_img3, 300, 172);
	lvgl.obj_set_click(ui.scanhome_img3, true);
	lvgl.img_set_src(ui.scanhome_img3,"/images/example_alpha_300x172.png");
	lvgl.img_set_pivot(ui.scanhome_img3, 0,0);
	lvgl.img_set_angle(ui.scanhome_img3, 0);

	--Write codes scanhome_cont4
	ui.scanhome_cont4 = lvgl.cont_create(ui.scanhome, nil);

	--Write style lvgl.CONT_PART_MAIN for scanhome_cont4
	-- local  style_scanhome_cont4_main;
	-- lvgl.style_init(style_scanhome_cont4_main);
	local style_scanhome_cont4_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_scanhome_cont4_main
	lvgl.style_set_radius(style_scanhome_cont4_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_scanhome_cont4_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff));
	lvgl.style_set_bg_grad_color(style_scanhome_cont4_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff));
	lvgl.style_set_bg_grad_dir(style_scanhome_cont4_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_scanhome_cont4_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_scanhome_cont4_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x99, 0x99, 0x99));
	lvgl.style_set_border_width(style_scanhome_cont4_main, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_border_opa(style_scanhome_cont4_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_pad_left(style_scanhome_cont4_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_scanhome_cont4_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_scanhome_cont4_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_scanhome_cont4_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.scanhome_cont4, lvgl.CONT_PART_MAIN, style_scanhome_cont4_main);
	lvgl.obj_set_pos(ui.scanhome_cont4, 368, 80);
	lvgl.obj_set_size(ui.scanhome_cont4, 80, 130);
	lvgl.obj_set_click(ui.scanhome_cont4, false);
	lvgl.cont_set_layout(ui.scanhome_cont4, lvgl.LAYOUT_OFF);
	lvgl.cont_set_fit(ui.scanhome_cont4, lvgl.FIT_NONE);

	--Write codes scanhome_btnscansave
	ui.scanhome_btnscansave = lvgl.btn_create(ui.scanhome, nil);

	--Write style lvgl.BTN_PART_MAIN for scanhome_btnscansave
	-- local  style_scanhome_btnscansave_main;
	-- lvgl.style_init(style_scanhome_btnscansave_main);
	local style_scanhome_btnscansave_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_scanhome_btnscansave_main
	lvgl.style_set_radius(style_scanhome_btnscansave_main, lvgl.STATE_DEFAULT, 50);
	lvgl.style_set_bg_color(style_scanhome_btnscansave_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x80, 0xff, 0x00));
	lvgl.style_set_bg_grad_color(style_scanhome_btnscansave_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x80, 0xff, 0x00));
	lvgl.style_set_bg_grad_dir(style_scanhome_btnscansave_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_scanhome_btnscansave_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_scanhome_btnscansave_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_scanhome_btnscansave_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_border_opa(style_scanhome_btnscansave_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_outline_color(style_scanhome_btnscansave_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_outline_opa(style_scanhome_btnscansave_main, lvgl.STATE_DEFAULT, 255);

	--Write style state: lvgl.STATE_FOCUSED for style_scanhome_btnscansave_main
	lvgl.style_set_radius(style_scanhome_btnscansave_main, lvgl.STATE_FOCUSED, 50);
	lvgl.style_set_bg_color(style_scanhome_btnscansave_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_scanhome_btnscansave_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_scanhome_btnscansave_main, lvgl.STATE_FOCUSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_scanhome_btnscansave_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_border_color(style_scanhome_btnscansave_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_scanhome_btnscansave_main, lvgl.STATE_FOCUSED, 2);
	lvgl.style_set_border_opa(style_scanhome_btnscansave_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_outline_color(style_scanhome_btnscansave_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_scanhome_btnscansave_main, lvgl.STATE_FOCUSED, 255);

	--Write style state: lvgl.STATE_PRESSED for style_scanhome_btnscansave_main
	lvgl.style_set_radius(style_scanhome_btnscansave_main, lvgl.STATE_PRESSED, 50);
	lvgl.style_set_bg_color(style_scanhome_btnscansave_main, lvgl.STATE_PRESSED, lvgl.color_make(0x00, 0xff, 0x40));
	lvgl.style_set_bg_grad_color(style_scanhome_btnscansave_main, lvgl.STATE_PRESSED, lvgl.color_make(0x00, 0xff, 0x40));
	lvgl.style_set_bg_grad_dir(style_scanhome_btnscansave_main, lvgl.STATE_PRESSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_scanhome_btnscansave_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_border_color(style_scanhome_btnscansave_main, lvgl.STATE_PRESSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_scanhome_btnscansave_main, lvgl.STATE_PRESSED, 2);
	lvgl.style_set_border_opa(style_scanhome_btnscansave_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_outline_color(style_scanhome_btnscansave_main, lvgl.STATE_PRESSED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_scanhome_btnscansave_main, lvgl.STATE_PRESSED, 100);

	--Write style state: lvgl.STATE_CHECKED for style_scanhome_btnscansave_main
	lvgl.style_set_radius(style_scanhome_btnscansave_main, lvgl.STATE_CHECKED, 50);
	lvgl.style_set_bg_color(style_scanhome_btnscansave_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_scanhome_btnscansave_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_scanhome_btnscansave_main, lvgl.STATE_CHECKED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_scanhome_btnscansave_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_border_color(style_scanhome_btnscansave_main, lvgl.STATE_CHECKED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_scanhome_btnscansave_main, lvgl.STATE_CHECKED, 2);
	lvgl.style_set_border_opa(style_scanhome_btnscansave_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_outline_color(style_scanhome_btnscansave_main, lvgl.STATE_CHECKED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_scanhome_btnscansave_main, lvgl.STATE_CHECKED, 255);
	lvgl.obj_add_style(ui.scanhome_btnscansave, lvgl.BTN_PART_MAIN, style_scanhome_btnscansave_main);
	lvgl.obj_set_pos(ui.scanhome_btnscansave, 368, 221);
	lvgl.obj_set_size(ui.scanhome_btnscansave, 80, 40);
	ui.scanhome_btnscansave_label = lvgl.label_create(ui.scanhome_btnscansave, nil);
	lvgl.label_set_text(ui.scanhome_btnscansave_label, "保存");
	lvgl.obj_set_style_local_text_color(ui.scanhome_btnscansave_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00));
	lvgl.obj_set_style_local_text_font(ui.scanhome_btnscansave_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_14"));

	--Write codes scanhome_sliderhue
	ui.scanhome_sliderhue = lvgl.slider_create(ui.scanhome, nil);

	--Write style lvgl.SLIDER_PART_INDIC for scanhome_sliderhue
	-- local  style_scanhome_sliderhue_indic;
	-- lvgl.style_init(style_scanhome_sliderhue_indic);
	local style_scanhome_sliderhue_indic = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_scanhome_sliderhue_indic
	lvgl.style_set_radius(style_scanhome_sliderhue_indic, lvgl.STATE_DEFAULT, 50);
	lvgl.style_set_bg_color(style_scanhome_sliderhue_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_bg_grad_color(style_scanhome_sliderhue_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0xdd, 0xd7, 0xd9));
	lvgl.style_set_bg_grad_dir(style_scanhome_sliderhue_indic, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_scanhome_sliderhue_indic, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.scanhome_sliderhue, lvgl.SLIDER_PART_INDIC, style_scanhome_sliderhue_indic);

	--Write style lvgl.SLIDER_PART_BG for scanhome_sliderhue
	-- local  style_scanhome_sliderhue_bg;
	-- lvgl.style_init(style_scanhome_sliderhue_bg);
	local style_scanhome_sliderhue_bg = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_scanhome_sliderhue_bg
	lvgl.style_set_radius(style_scanhome_sliderhue_bg, lvgl.STATE_DEFAULT, 50);
	lvgl.style_set_bg_color(style_scanhome_sliderhue_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_bg_grad_color(style_scanhome_sliderhue_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_bg_grad_dir(style_scanhome_sliderhue_bg, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_scanhome_sliderhue_bg, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_outline_color(style_scanhome_sliderhue_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_scanhome_sliderhue_bg, lvgl.STATE_DEFAULT, 0);

	--Write style state: lvgl.STATE_FOCUSED for style_scanhome_sliderhue_bg
	lvgl.style_set_outline_color(style_scanhome_sliderhue_bg, lvgl.STATE_FOCUSED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_scanhome_sliderhue_bg, lvgl.STATE_FOCUSED, 255);
	lvgl.obj_add_style(ui.scanhome_sliderhue, lvgl.SLIDER_PART_BG, style_scanhome_sliderhue_bg);

	--Write style lvgl.SLIDER_PART_KNOB for scanhome_sliderhue
	-- local  style_scanhome_sliderhue_knob;
	-- lvgl.style_init(style_scanhome_sliderhue_knob);
	local style_scanhome_sliderhue_knob = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_scanhome_sliderhue_knob
	lvgl.style_set_radius(style_scanhome_sliderhue_knob, lvgl.STATE_DEFAULT, 50);
	lvgl.style_set_bg_color(style_scanhome_sliderhue_knob, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_scanhome_sliderhue_knob, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_scanhome_sliderhue_knob, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_scanhome_sliderhue_knob, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.scanhome_sliderhue, lvgl.SLIDER_PART_KNOB, style_scanhome_sliderhue_knob);
	lvgl.obj_set_pos(ui.scanhome_sliderhue, 420, 115);
	lvgl.obj_set_size(ui.scanhome_sliderhue, 8, 80);
	lvgl.slider_set_range(ui.scanhome_sliderhue,0, 100);
	lvgl.slider_set_value(ui.scanhome_sliderhue,50,false);

	--Write codes scanhome_sliderbright
	ui.scanhome_sliderbright = lvgl.slider_create(ui.scanhome, nil);

	--Write style lvgl.SLIDER_PART_INDIC for scanhome_sliderbright
	-- local  style_scanhome_sliderbright_indic;
	-- lvgl.style_init(style_scanhome_sliderbright_indic);
	local style_scanhome_sliderbright_indic = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_scanhome_sliderbright_indic
	lvgl.style_set_radius(style_scanhome_sliderbright_indic, lvgl.STATE_DEFAULT, 50);
	lvgl.style_set_bg_color(style_scanhome_sliderbright_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_bg_grad_color(style_scanhome_sliderbright_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0xdd, 0xd7, 0xd9));
	lvgl.style_set_bg_grad_dir(style_scanhome_sliderbright_indic, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_scanhome_sliderbright_indic, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.scanhome_sliderbright, lvgl.SLIDER_PART_INDIC, style_scanhome_sliderbright_indic);

	--Write style lvgl.SLIDER_PART_BG for scanhome_sliderbright
	-- local  style_scanhome_sliderbright_bg;
	-- lvgl.style_init(style_scanhome_sliderbright_bg);
	local style_scanhome_sliderbright_bg = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_scanhome_sliderbright_bg
	lvgl.style_set_radius(style_scanhome_sliderbright_bg, lvgl.STATE_DEFAULT, 50);
	lvgl.style_set_bg_color(style_scanhome_sliderbright_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_bg_grad_color(style_scanhome_sliderbright_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_bg_grad_dir(style_scanhome_sliderbright_bg, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_scanhome_sliderbright_bg, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_outline_color(style_scanhome_sliderbright_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_scanhome_sliderbright_bg, lvgl.STATE_DEFAULT, 0);

	--Write style state: lvgl.STATE_FOCUSED for style_scanhome_sliderbright_bg
	lvgl.style_set_outline_color(style_scanhome_sliderbright_bg, lvgl.STATE_FOCUSED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_scanhome_sliderbright_bg, lvgl.STATE_FOCUSED, 255);
	lvgl.obj_add_style(ui.scanhome_sliderbright, lvgl.SLIDER_PART_BG, style_scanhome_sliderbright_bg);

	--Write style lvgl.SLIDER_PART_KNOB for scanhome_sliderbright
	-- local  style_scanhome_sliderbright_knob;
	-- lvgl.style_init(style_scanhome_sliderbright_knob);
	local style_scanhome_sliderbright_knob = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_scanhome_sliderbright_knob
	lvgl.style_set_radius(style_scanhome_sliderbright_knob, lvgl.STATE_DEFAULT, 50);
	lvgl.style_set_bg_color(style_scanhome_sliderbright_knob, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_scanhome_sliderbright_knob, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_scanhome_sliderbright_knob, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_scanhome_sliderbright_knob, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.scanhome_sliderbright, lvgl.SLIDER_PART_KNOB, style_scanhome_sliderbright_knob);
	lvgl.obj_set_pos(ui.scanhome_sliderbright, 380, 115);
	lvgl.obj_set_size(ui.scanhome_sliderbright, 8, 80);
	lvgl.slider_set_range(ui.scanhome_sliderbright,0, 100);
	lvgl.slider_set_value(ui.scanhome_sliderbright,50,false);

	--Write codes scanhome_bright
	ui.scanhome_bright = lvgl.img_create(ui.scanhome, nil);

	--Write style lvgl.IMG_PART_MAIN for scanhome_bright
	-- local  style_scanhome_bright_main;
	-- lvgl.style_init(style_scanhome_bright_main);
	local style_scanhome_bright_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_scanhome_bright_main
	lvgl.style_set_image_recolor(style_scanhome_bright_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_image_recolor_opa(style_scanhome_bright_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_image_opa(style_scanhome_bright_main, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.scanhome_bright, lvgl.IMG_PART_MAIN, style_scanhome_bright_main);
	lvgl.obj_set_pos(ui.scanhome_bright, 372, 82);
	lvgl.obj_set_size(ui.scanhome_bright, 24, 24);
	lvgl.obj_set_click(ui.scanhome_bright, true);
	lvgl.img_set_src(ui.scanhome_bright,"/images/bright_alpha_24x24.png");
	lvgl.img_set_pivot(ui.scanhome_bright, 0,0);
	lvgl.img_set_angle(ui.scanhome_bright, 0);

	--Write codes scanhome_hue
	ui.scanhome_hue = lvgl.img_create(ui.scanhome, nil);

	--Write style lvgl.IMG_PART_MAIN for scanhome_hue
	-- local  style_scanhome_hue_main;
	-- lvgl.style_init(style_scanhome_hue_main);
	local style_scanhome_hue_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_scanhome_hue_main
	lvgl.style_set_image_recolor(style_scanhome_hue_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_image_recolor_opa(style_scanhome_hue_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_image_opa(style_scanhome_hue_main, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.scanhome_hue, lvgl.IMG_PART_MAIN, style_scanhome_hue_main);
	lvgl.obj_set_pos(ui.scanhome_hue, 413, 83);
	lvgl.obj_set_size(ui.scanhome_hue, 21, 21);
	lvgl.obj_set_click(ui.scanhome_hue, true);
	lvgl.img_set_src(ui.scanhome_hue,"/images/hue_alpha_21x21.png");
	lvgl.img_set_pivot(ui.scanhome_hue, 0,0);
	lvgl.img_set_angle(ui.scanhome_hue, 0);

	--Write codes scanhome_btnscanback
	ui.scanhome_btnscanback = lvgl.btn_create(ui.scanhome, nil);

	--Write style lvgl.BTN_PART_MAIN for scanhome_btnscanback
	-- local  style_scanhome_btnscanback_main;
	-- lvgl.style_init(style_scanhome_btnscanback_main);
	local style_scanhome_btnscanback_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_scanhome_btnscanback_main
	lvgl.style_set_radius(style_scanhome_btnscanback_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_scanhome_btnscanback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_scanhome_btnscanback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_scanhome_btnscanback_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_scanhome_btnscanback_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_scanhome_btnscanback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_scanhome_btnscanback_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_border_opa(style_scanhome_btnscanback_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_outline_color(style_scanhome_btnscanback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_scanhome_btnscanback_main, lvgl.STATE_DEFAULT, 0);

	--Write style state: lvgl.STATE_FOCUSED for style_scanhome_btnscanback_main
	lvgl.style_set_radius(style_scanhome_btnscanback_main, lvgl.STATE_FOCUSED, 50);
	lvgl.style_set_bg_color(style_scanhome_btnscanback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_scanhome_btnscanback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_scanhome_btnscanback_main, lvgl.STATE_FOCUSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_scanhome_btnscanback_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_border_color(style_scanhome_btnscanback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_scanhome_btnscanback_main, lvgl.STATE_FOCUSED, 2);
	lvgl.style_set_border_opa(style_scanhome_btnscanback_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_outline_color(style_scanhome_btnscanback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_scanhome_btnscanback_main, lvgl.STATE_FOCUSED, 255);

	--Write style state: lvgl.STATE_PRESSED for style_scanhome_btnscanback_main
	lvgl.style_set_radius(style_scanhome_btnscanback_main, lvgl.STATE_PRESSED, 0);
	lvgl.style_set_bg_color(style_scanhome_btnscanback_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_scanhome_btnscanback_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_scanhome_btnscanback_main, lvgl.STATE_PRESSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_scanhome_btnscanback_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_border_color(style_scanhome_btnscanback_main, lvgl.STATE_PRESSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_scanhome_btnscanback_main, lvgl.STATE_PRESSED, 0);
	lvgl.style_set_border_opa(style_scanhome_btnscanback_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_outline_color(style_scanhome_btnscanback_main, lvgl.STATE_PRESSED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_scanhome_btnscanback_main, lvgl.STATE_PRESSED, 0);

	--Write style state: lvgl.STATE_CHECKED for style_scanhome_btnscanback_main
	lvgl.style_set_radius(style_scanhome_btnscanback_main, lvgl.STATE_CHECKED, 50);
	lvgl.style_set_bg_color(style_scanhome_btnscanback_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_scanhome_btnscanback_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_scanhome_btnscanback_main, lvgl.STATE_CHECKED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_scanhome_btnscanback_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_border_color(style_scanhome_btnscanback_main, lvgl.STATE_CHECKED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_scanhome_btnscanback_main, lvgl.STATE_CHECKED, 2);
	lvgl.style_set_border_opa(style_scanhome_btnscanback_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_outline_color(style_scanhome_btnscanback_main, lvgl.STATE_CHECKED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_scanhome_btnscanback_main, lvgl.STATE_CHECKED, 255);
	lvgl.obj_add_style(ui.scanhome_btnscanback, lvgl.BTN_PART_MAIN, style_scanhome_btnscanback_main);
	lvgl.obj_set_pos(ui.scanhome_btnscanback, 50, 25);
	lvgl.obj_set_size(ui.scanhome_btnscanback, 30, 30);
	ui.scanhome_btnscanback_label = lvgl.label_create(ui.scanhome_btnscanback, nil);
	lvgl.label_set_text(ui.scanhome_btnscanback_label, "");
	lvgl.obj_set_style_local_text_color(ui.scanhome_btnscanback_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
end

return scanhome
