

local saved = {}

function saved.setup_scr_saved(ui)

	--Write codes saved
	ui.saved = lvgl.obj_create(nil, nil);

	--Write codes saved_cont0
	ui.saved_cont0 = lvgl.cont_create(ui.saved, nil);

	--Write style lvgl.CONT_PART_MAIN for saved_cont0
	-- local style_saved_cont0_main;
	-- lvgl.style_init(style_saved_cont0_main);
	local style_saved_cont0_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_saved_cont0_main
	lvgl.style_set_radius(style_saved_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_saved_cont0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x4a, 0xb2, 0x41));
	lvgl.style_set_bg_grad_color(style_saved_cont0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x4a, 0xb2, 0x41));
	lvgl.style_set_bg_grad_dir(style_saved_cont0_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_saved_cont0_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_saved_cont0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x99, 0x99, 0x99));
	lvgl.style_set_border_width(style_saved_cont0_main, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_border_opa(style_saved_cont0_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_pad_left(style_saved_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_saved_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_saved_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_saved_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.saved_cont0, lvgl.CONT_PART_MAIN, style_saved_cont0_main);
	lvgl.obj_set_pos(ui.saved_cont0, 0, 0);
	lvgl.obj_set_size(ui.saved_cont0, 480, 272);
	lvgl.obj_set_click(ui.saved_cont0, false);
	lvgl.cont_set_layout(ui.saved_cont0, lvgl.LAYOUT_OFF);
	lvgl.cont_set_fit(ui.saved_cont0, lvgl.FIT_NONE);

	--Write codes saved_btnsavecontinue
	ui.saved_btnsavecontinue = lvgl.btn_create(ui.saved, nil);

	--Write style lvgl.BTN_PART_MAIN for saved_btnsavecontinue
	-- local style_saved_btnsavecontinue_main;
	-- lvgl.style_init(style_saved_btnsavecontinue_main);
	local style_saved_btnsavecontinue_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_saved_btnsavecontinue_main
	lvgl.style_set_radius(style_saved_btnsavecontinue_main, lvgl.STATE_DEFAULT, 50);
	lvgl.style_set_bg_color(style_saved_btnsavecontinue_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x4a, 0xb2, 0x41));
	lvgl.style_set_bg_grad_color(style_saved_btnsavecontinue_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x4a, 0xb2, 0x41));
	lvgl.style_set_bg_grad_dir(style_saved_btnsavecontinue_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_saved_btnsavecontinue_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_saved_btnsavecontinue_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_border_width(style_saved_btnsavecontinue_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_border_opa(style_saved_btnsavecontinue_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_outline_color(style_saved_btnsavecontinue_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_outline_opa(style_saved_btnsavecontinue_main, lvgl.STATE_DEFAULT, 255);

	--Write style state: lvgl.STATE_FOCUSED for style_saved_btnsavecontinue_main
	lvgl.style_set_radius(style_saved_btnsavecontinue_main, lvgl.STATE_FOCUSED, 50);
	lvgl.style_set_bg_color(style_saved_btnsavecontinue_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_saved_btnsavecontinue_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_saved_btnsavecontinue_main, lvgl.STATE_FOCUSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_saved_btnsavecontinue_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_border_color(style_saved_btnsavecontinue_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_saved_btnsavecontinue_main, lvgl.STATE_FOCUSED, 2);
	lvgl.style_set_border_opa(style_saved_btnsavecontinue_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_outline_color(style_saved_btnsavecontinue_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_saved_btnsavecontinue_main, lvgl.STATE_FOCUSED, 255);

	--Write style state: lvgl.STATE_PRESSED for style_saved_btnsavecontinue_main
	lvgl.style_set_radius(style_saved_btnsavecontinue_main, lvgl.STATE_PRESSED, 50);
	lvgl.style_set_bg_color(style_saved_btnsavecontinue_main, lvgl.STATE_PRESSED, lvgl.color_make(0x4a, 0xb2, 0x41));
	lvgl.style_set_bg_grad_color(style_saved_btnsavecontinue_main, lvgl.STATE_PRESSED, lvgl.color_make(0x4a, 0xb2, 0x41));
	lvgl.style_set_bg_grad_dir(style_saved_btnsavecontinue_main, lvgl.STATE_PRESSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_saved_btnsavecontinue_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_border_color(style_saved_btnsavecontinue_main, lvgl.STATE_PRESSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_border_width(style_saved_btnsavecontinue_main, lvgl.STATE_PRESSED, 0);
	lvgl.style_set_border_opa(style_saved_btnsavecontinue_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_outline_color(style_saved_btnsavecontinue_main, lvgl.STATE_PRESSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_outline_opa(style_saved_btnsavecontinue_main, lvgl.STATE_PRESSED, 100);

	--Write style state: lvgl.STATE_CHECKED for style_saved_btnsavecontinue_main
	lvgl.style_set_radius(style_saved_btnsavecontinue_main, lvgl.STATE_CHECKED, 50);
	lvgl.style_set_bg_color(style_saved_btnsavecontinue_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_saved_btnsavecontinue_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_saved_btnsavecontinue_main, lvgl.STATE_CHECKED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_saved_btnsavecontinue_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_border_color(style_saved_btnsavecontinue_main, lvgl.STATE_CHECKED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_saved_btnsavecontinue_main, lvgl.STATE_CHECKED, 2);
	lvgl.style_set_border_opa(style_saved_btnsavecontinue_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_outline_color(style_saved_btnsavecontinue_main, lvgl.STATE_CHECKED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_saved_btnsavecontinue_main, lvgl.STATE_CHECKED, 255);
	lvgl.obj_add_style(ui.saved_btnsavecontinue, lvgl.BTN_PART_MAIN, style_saved_btnsavecontinue_main);
	lvgl.obj_set_pos(ui.saved_btnsavecontinue, 168, 195);
	lvgl.obj_set_size(ui.saved_btnsavecontinue, 140, 40);
	ui.saved_btnsavecontinue_label = lvgl.label_create(ui.saved_btnsavecontinue, nil);
	lvgl.label_set_text(ui.saved_btnsavecontinue_label, "继续");
	lvgl.obj_set_style_local_text_color(ui.saved_btnsavecontinue_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.obj_set_style_local_text_font(ui.saved_btnsavecontinue_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_20"));

	--Write codes saved_label2
	ui.saved_label2 = lvgl.label_create(ui.saved, nil);
	lvgl.label_set_text(ui.saved_label2, "文件已保存");
	lvgl.label_set_long_mode(ui.saved_label2, lvgl.LABEL_LONG_BREAK);
	lvgl.label_set_align(ui.saved_label2, lvgl.LABEL_ALIGN_LEFT);

	--Write style lvgl.LABEL_PART_MAIN for saved_label2
	-- local style_saved_label2_main;
	-- lvgl.style_init(style_saved_label2_main);
	local style_saved_label2_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_saved_label2_main
	lvgl.style_set_radius(style_saved_label2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_saved_label2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x4a, 0xb2, 0x41));
	lvgl.style_set_bg_grad_color(style_saved_label2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x4a, 0xb2, 0x41));
	lvgl.style_set_bg_grad_dir(style_saved_label2_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_saved_label2_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_text_color(style_saved_label2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_text_font(style_saved_label2_main, lvgl.STATE_DEFAULT,  lvgl.font_get("opposans_m_18"));
	lvgl.style_set_text_letter_space(style_saved_label2_main, lvgl.STATE_DEFAULT, 2);
	lvgl.style_set_pad_left(style_saved_label2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_saved_label2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_saved_label2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_saved_label2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.saved_label2, lvgl.LABEL_PART_MAIN, style_saved_label2_main);
	lvgl.obj_set_pos(ui.saved_label2, 187, 160);
	lvgl.obj_set_size(ui.saved_label2, 180, 0);

	--Write codes saved_img1
	ui.saved_img1 = lvgl.img_create(ui.saved, nil);

	--Write style lvgl.IMG_PART_MAIN for saved_img1
	-- local style_saved_img1_main;
	-- lvgl.style_init(style_saved_img1_main);
	local style_saved_img1_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_saved_img1_main
	lvgl.style_set_image_recolor(style_saved_img1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_image_recolor_opa(style_saved_img1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_image_opa(style_saved_img1_main, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.saved_img1, lvgl.IMG_PART_MAIN, style_saved_img1_main);
	lvgl.obj_set_pos(ui.saved_img1, 185, 40);
	lvgl.obj_set_size(ui.saved_img1, 100, 100);
	lvgl.obj_set_click(ui.saved_img1, true);
	lvgl.img_set_src(ui.saved_img1,"/images/ready_alpha_100x100.png");
	lvgl.img_set_pivot(ui.saved_img1, 0,0);
	lvgl.img_set_angle(ui.saved_img1, 0);
end

return saved
