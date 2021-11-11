

local prthome = {}

function prthome.setup_scr_prthome(ui)

	--Write codes prthome
	ui.prthome = lvgl.obj_create(nil, nil);

	--Write codes prthome_cont0
	ui.prthome_cont0 = lvgl.cont_create(ui.prthome, nil);

	--Write style lvgl.CONT_PART_MAIN for prthome_cont0
	-- local style_prthome_cont0_main;
	-- lvgl.style_init(style_prthome_cont0_main);
	local style_prthome_cont0_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prthome_cont0_main
	lvgl.style_set_radius(style_prthome_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_prthome_cont0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_prthome_cont0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_prthome_cont0_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prthome_cont0_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_prthome_cont0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x99, 0x99, 0x99));
	lvgl.style_set_border_width(style_prthome_cont0_main, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_border_opa(style_prthome_cont0_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_pad_left(style_prthome_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_prthome_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_prthome_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_prthome_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.prthome_cont0, lvgl.CONT_PART_MAIN, style_prthome_cont0_main);
	lvgl.obj_set_pos(ui.prthome_cont0, 0, 0);
	lvgl.obj_set_size(ui.prthome_cont0, 480, 100);
	lvgl.obj_set_click(ui.prthome_cont0, false);
	lvgl.cont_set_layout(ui.prthome_cont0, lvgl.LAYOUT_OFF);
	lvgl.cont_set_fit(ui.prthome_cont0, lvgl.FIT_NONE);

	--Write codes prthome_cont3
	ui.prthome_cont3 = lvgl.cont_create(ui.prthome, nil);

	--Write style lvgl.CONT_PART_MAIN for prthome_cont3
	-- local style_prthome_cont3_main;
	-- lvgl.style_init(style_prthome_cont3_main);
	local style_prthome_cont3_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prthome_cont3_main
	lvgl.style_set_radius(style_prthome_cont3_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_prthome_cont3_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff));
	lvgl.style_set_bg_grad_color(style_prthome_cont3_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff));
	lvgl.style_set_bg_grad_dir(style_prthome_cont3_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prthome_cont3_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_prthome_cont3_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x99, 0x99, 0x99));
	lvgl.style_set_border_width(style_prthome_cont3_main, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_border_opa(style_prthome_cont3_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_pad_left(style_prthome_cont3_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_prthome_cont3_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_prthome_cont3_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_prthome_cont3_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.prthome_cont3, lvgl.CONT_PART_MAIN, style_prthome_cont3_main);
	lvgl.obj_set_pos(ui.prthome_cont3, 0, 100);
	lvgl.obj_set_size(ui.prthome_cont3, 480, 172);
	lvgl.obj_set_click(ui.prthome_cont3, false);
	lvgl.cont_set_layout(ui.prthome_cont3, lvgl.LAYOUT_OFF);
	lvgl.cont_set_fit(ui.prthome_cont3, lvgl.FIT_NONE);

	--Write codes prthome_cont1
	ui.prthome_cont1 = lvgl.cont_create(ui.prthome, nil);

	--Write style lvgl.CONT_PART_MAIN for prthome_cont1
	-- local style_prthome_cont1_main;
	-- lvgl.style_init(style_prthome_cont1_main);
	local style_prthome_cont1_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prthome_cont1_main
	lvgl.style_set_radius(style_prthome_cont1_main, lvgl.STATE_DEFAULT, 10);
	lvgl.style_set_bg_color(style_prthome_cont1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff));
	lvgl.style_set_bg_grad_color(style_prthome_cont1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff));
	lvgl.style_set_bg_grad_dir(style_prthome_cont1_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prthome_cont1_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_prthome_cont1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x99, 0x99, 0x99));
	lvgl.style_set_border_width(style_prthome_cont1_main, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_border_opa(style_prthome_cont1_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_pad_left(style_prthome_cont1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_prthome_cont1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_prthome_cont1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_prthome_cont1_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.prthome_cont1, lvgl.CONT_PART_MAIN, style_prthome_cont1_main);
	lvgl.obj_set_pos(ui.prthome_cont1, 40, 60);
	lvgl.obj_set_size(ui.prthome_cont1, 400, 140);
	lvgl.obj_set_click(ui.prthome_cont1, false);
	lvgl.cont_set_layout(ui.prthome_cont1, lvgl.LAYOUT_OFF);
	lvgl.cont_set_fit(ui.prthome_cont1, lvgl.FIT_NONE);

	--Write codes prthome_label4
	ui.prthome_label4 = lvgl.label_create(ui.prthome, nil);
	lvgl.label_set_text(ui.prthome_label4, "打印菜单");
	lvgl.label_set_long_mode(ui.prthome_label4, lvgl.LABEL_LONG_BREAK);
	lvgl.label_set_align(ui.prthome_label4, lvgl.LABEL_ALIGN_CENTER);

	--Write style lvgl.LABEL_PART_MAIN for prthome_label4
	-- local style_prthome_label4_main;
	-- lvgl.style_init(style_prthome_label4_main);
	local style_prthome_label4_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prthome_label4_main
	lvgl.style_set_radius(style_prthome_label4_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_prthome_label4_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_prthome_label4_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_prthome_label4_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prthome_label4_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_text_color(style_prthome_label4_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_text_font(style_prthome_label4_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_20"));
	lvgl.style_set_text_letter_space(style_prthome_label4_main, lvgl.STATE_DEFAULT, 2);
	lvgl.style_set_pad_left(style_prthome_label4_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_prthome_label4_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_prthome_label4_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_prthome_label4_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.prthome_label4, lvgl.LABEL_PART_MAIN, style_prthome_label4_main);
	lvgl.obj_set_pos(ui.prthome_label4, 169, 16);
	lvgl.obj_set_size(ui.prthome_label4, 137, 0);

	--Write codes prthome_imgbtnit
	ui.prthome_imgbtnit = lvgl.imgbtn_create(ui.prthome, nil);

	--Write style lvgl.IMGBTN_PART_MAIN for prthome_imgbtnit
	-- local style_prthome_imgbtnit_main;
	-- lvgl.style_init(style_prthome_imgbtnit_main);
	local style_prthome_imgbtnit_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prthome_imgbtnit_main
	lvgl.style_set_text_color(style_prthome_imgbtnit_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00));
	lvgl.style_set_image_recolor(style_prthome_imgbtnit_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_image_recolor_opa(style_prthome_imgbtnit_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_image_opa(style_prthome_imgbtnit_main, lvgl.STATE_DEFAULT, 255);

	--Write style state: lvgl.STATE_PRESSED for style_prthome_imgbtnit_main
	lvgl.style_set_text_color(style_prthome_imgbtnit_main, lvgl.STATE_PRESSED, lvgl.color_make(0xFF, 0x33, 0xFF));
	lvgl.style_set_image_recolor(style_prthome_imgbtnit_main, lvgl.STATE_PRESSED, lvgl.color_make(0x00, 0x00, 0x00));
	lvgl.style_set_image_recolor_opa(style_prthome_imgbtnit_main, lvgl.STATE_PRESSED, 0);

	--Write style state: lvgl.STATE_CHECKED for style_prthome_imgbtnit_main
	lvgl.style_set_text_color(style_prthome_imgbtnit_main, lvgl.STATE_CHECKED, lvgl.color_make(0xFF, 0x33, 0xFF));
	lvgl.style_set_image_recolor(style_prthome_imgbtnit_main, lvgl.STATE_CHECKED, lvgl.color_make(0x00, 0x00, 0x00));
	lvgl.style_set_image_recolor_opa(style_prthome_imgbtnit_main, lvgl.STATE_CHECKED, 0);
	lvgl.obj_add_style(ui.prthome_imgbtnit, lvgl.IMGBTN_PART_MAIN, style_prthome_imgbtnit_main);
	lvgl.obj_set_pos(ui.prthome_imgbtnit, 325, 60);
	lvgl.obj_set_size(ui.prthome_imgbtnit, 115, 140);
	lvgl.imgbtn_set_src(ui.prthome_imgbtnit,lvgl.BTN_STATE_RELEASED,"/images/btn4_alpha_115x140.png");
	lvgl.imgbtn_set_src(ui.prthome_imgbtnit,lvgl.BTN_STATE_PRESSED,"/images/btn4_alpha_115x140.png");
	lvgl.imgbtn_set_src(ui.prthome_imgbtnit,lvgl.BTN_STATE_CHECKED_RELEASED,"/images/btn4_alpha_115x140.png");
	lvgl.imgbtn_set_src(ui.prthome_imgbtnit,lvgl.BTN_STATE_CHECKED_PRESSED,"/images/btn4_alpha_115x140.png");

	--Write codes prthome_imgbtnusb
	ui.prthome_imgbtnusb = lvgl.imgbtn_create(ui.prthome, nil);

	--Write style lvgl.IMGBTN_PART_MAIN for prthome_imgbtnusb
	-- local style_prthome_imgbtnusb_main;
	-- lvgl.style_init(style_prthome_imgbtnusb_main);
	local style_prthome_imgbtnusb_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prthome_imgbtnusb_main
	lvgl.style_set_text_color(style_prthome_imgbtnusb_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00));
	lvgl.style_set_image_recolor(style_prthome_imgbtnusb_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_image_recolor_opa(style_prthome_imgbtnusb_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_image_opa(style_prthome_imgbtnusb_main, lvgl.STATE_DEFAULT, 255);

	--Write style state: lvgl.STATE_PRESSED for style_prthome_imgbtnusb_main
	lvgl.style_set_text_color(style_prthome_imgbtnusb_main, lvgl.STATE_PRESSED, lvgl.color_make(0xFF, 0x33, 0xFF));
	lvgl.style_set_image_recolor(style_prthome_imgbtnusb_main, lvgl.STATE_PRESSED, lvgl.color_make(0x00, 0x00, 0x00));
	lvgl.style_set_image_recolor_opa(style_prthome_imgbtnusb_main, lvgl.STATE_PRESSED, 0);

	--Write style state: lvgl.STATE_CHECKED for style_prthome_imgbtnusb_main
	lvgl.style_set_text_color(style_prthome_imgbtnusb_main, lvgl.STATE_CHECKED, lvgl.color_make(0xFF, 0x33, 0xFF));
	lvgl.style_set_image_recolor(style_prthome_imgbtnusb_main, lvgl.STATE_CHECKED, lvgl.color_make(0x00, 0x00, 0x00));
	lvgl.style_set_image_recolor_opa(style_prthome_imgbtnusb_main, lvgl.STATE_CHECKED, 0);
	lvgl.obj_add_style(ui.prthome_imgbtnusb, lvgl.IMGBTN_PART_MAIN, style_prthome_imgbtnusb_main);
	lvgl.obj_set_pos(ui.prthome_imgbtnusb, 40, 60);
	lvgl.obj_set_size(ui.prthome_imgbtnusb, 115, 140);
	lvgl.imgbtn_set_src(ui.prthome_imgbtnusb,lvgl.BTN_STATE_RELEASED,"/images/btn2_alpha_115x140.png");
	lvgl.imgbtn_set_src(ui.prthome_imgbtnusb,lvgl.BTN_STATE_PRESSED,"/images/btn2_alpha_115x140.png");
	lvgl.imgbtn_set_src(ui.prthome_imgbtnusb,lvgl.BTN_STATE_CHECKED_RELEASED,"/images/btn2_alpha_115x140.png");
	lvgl.imgbtn_set_src(ui.prthome_imgbtnusb,lvgl.BTN_STATE_CHECKED_PRESSED,"/images/btn2_alpha_115x140.png");

	--Write codes prthome_imgbtnmobile
	ui.prthome_imgbtnmobile = lvgl.imgbtn_create(ui.prthome, nil);

	--Write style lvgl.IMGBTN_PART_MAIN for prthome_imgbtnmobile
	-- local style_prthome_imgbtnmobile_main;
	-- lvgl.style_init(style_prthome_imgbtnmobile_main);
	local style_prthome_imgbtnmobile_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prthome_imgbtnmobile_main
	lvgl.style_set_text_color(style_prthome_imgbtnmobile_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00));
	lvgl.style_set_image_recolor(style_prthome_imgbtnmobile_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_image_recolor_opa(style_prthome_imgbtnmobile_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_image_opa(style_prthome_imgbtnmobile_main, lvgl.STATE_DEFAULT, 255);

	--Write style state: lvgl.STATE_PRESSED for style_prthome_imgbtnmobile_main
	lvgl.style_set_text_color(style_prthome_imgbtnmobile_main, lvgl.STATE_PRESSED, lvgl.color_make(0xFF, 0x33, 0xFF));
	lvgl.style_set_image_recolor(style_prthome_imgbtnmobile_main, lvgl.STATE_PRESSED, lvgl.color_make(0x00, 0x00, 0x00));
	lvgl.style_set_image_recolor_opa(style_prthome_imgbtnmobile_main, lvgl.STATE_PRESSED, 0);

	--Write style state: lvgl.STATE_CHECKED for style_prthome_imgbtnmobile_main
	lvgl.style_set_text_color(style_prthome_imgbtnmobile_main, lvgl.STATE_CHECKED, lvgl.color_make(0xFF, 0x33, 0xFF));
	lvgl.style_set_image_recolor(style_prthome_imgbtnmobile_main, lvgl.STATE_CHECKED, lvgl.color_make(0x00, 0x00, 0x00));
	lvgl.style_set_image_recolor_opa(style_prthome_imgbtnmobile_main, lvgl.STATE_CHECKED, 0);
	lvgl.obj_add_style(ui.prthome_imgbtnmobile, lvgl.IMGBTN_PART_MAIN, style_prthome_imgbtnmobile_main);
	lvgl.obj_set_pos(ui.prthome_imgbtnmobile, 183, 60);
	lvgl.obj_set_size(ui.prthome_imgbtnmobile, 115, 140);
	lvgl.imgbtn_set_src(ui.prthome_imgbtnmobile,lvgl.BTN_STATE_RELEASED,"/images/btn3_alpha_115x140.png");
	lvgl.imgbtn_set_src(ui.prthome_imgbtnmobile,lvgl.BTN_STATE_PRESSED,"/images/btn3_alpha_115x140.png");
	lvgl.imgbtn_set_src(ui.prthome_imgbtnmobile,lvgl.BTN_STATE_CHECKED_RELEASED,"/images/btn3_alpha_115x140.png");
	lvgl.imgbtn_set_src(ui.prthome_imgbtnmobile,lvgl.BTN_STATE_CHECKED_PRESSED,"/images/btn3_alpha_115x140.png");

	--Write codes prthome_labelusb
	ui.prthome_labelusb = lvgl.label_create(ui.prthome, nil);
	lvgl.label_set_text(ui.prthome_labelusb, "USB");
	lvgl.label_set_long_mode(ui.prthome_labelusb, lvgl.LABEL_LONG_BREAK);
	lvgl.label_set_align(ui.prthome_labelusb, lvgl.LABEL_ALIGN_LEFT);

	--Write style lvgl.LABEL_PART_MAIN for prthome_labelusb
	-- local style_prthome_labelusb_main;
	-- lvgl.style_init(style_prthome_labelusb_main);
	local style_prthome_labelusb_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prthome_labelusb_main
	lvgl.style_set_radius(style_prthome_labelusb_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_prthome_labelusb_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_prthome_labelusb_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_prthome_labelusb_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prthome_labelusb_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_text_color(style_prthome_labelusb_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_text_font(style_prthome_labelusb_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_14"));
	lvgl.style_set_text_letter_space(style_prthome_labelusb_main, lvgl.STATE_DEFAULT, 2);
	lvgl.style_set_pad_left(style_prthome_labelusb_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_prthome_labelusb_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_prthome_labelusb_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_prthome_labelusb_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.prthome_labelusb, lvgl.LABEL_PART_MAIN, style_prthome_labelusb_main);
	lvgl.obj_set_pos(ui.prthome_labelusb, 58, 160);
	lvgl.obj_set_size(ui.prthome_labelusb, 74, 0);

	--Write codes prthome_labelmobile
	ui.prthome_labelmobile = lvgl.label_create(ui.prthome, nil);
	lvgl.label_set_text(ui.prthome_labelmobile, "手机");
	lvgl.label_set_long_mode(ui.prthome_labelmobile, lvgl.LABEL_LONG_BREAK);
	lvgl.label_set_align(ui.prthome_labelmobile, lvgl.LABEL_ALIGN_LEFT);

	--Write style lvgl.LABEL_PART_MAIN for prthome_labelmobile
	-- local style_prthome_labelmobile_main;
	-- lvgl.style_init(style_prthome_labelmobile_main);
	local style_prthome_labelmobile_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prthome_labelmobile_main
	lvgl.style_set_radius(style_prthome_labelmobile_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_prthome_labelmobile_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_prthome_labelmobile_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_prthome_labelmobile_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prthome_labelmobile_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_text_color(style_prthome_labelmobile_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_text_font(style_prthome_labelmobile_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_16"));
	lvgl.style_set_text_letter_space(style_prthome_labelmobile_main, lvgl.STATE_DEFAULT, 2);
	lvgl.style_set_pad_left(style_prthome_labelmobile_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_prthome_labelmobile_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_prthome_labelmobile_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_prthome_labelmobile_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.prthome_labelmobile, lvgl.LABEL_PART_MAIN, style_prthome_labelmobile_main);
	lvgl.obj_set_pos(ui.prthome_labelmobile, 198, 160);
	lvgl.obj_set_size(ui.prthome_labelmobile, 74, 0);

	--Write codes prthome_labelit
	ui.prthome_labelit = lvgl.label_create(ui.prthome, nil);
	lvgl.label_set_text(ui.prthome_labelit, "网络");
	lvgl.label_set_long_mode(ui.prthome_labelit, lvgl.LABEL_LONG_BREAK);
	lvgl.label_set_align(ui.prthome_labelit, lvgl.LABEL_ALIGN_LEFT);

	--Write style lvgl.LABEL_PART_MAIN for prthome_labelit
	-- local style_prthome_labelit_main;
	-- lvgl.style_init(style_prthome_labelit_main);
	local style_prthome_labelit_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prthome_labelit_main
	lvgl.style_set_radius(style_prthome_labelit_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_prthome_labelit_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_prthome_labelit_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_prthome_labelit_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prthome_labelit_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_text_color(style_prthome_labelit_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_text_font(style_prthome_labelit_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_16"));
	lvgl.style_set_text_letter_space(style_prthome_labelit_main, lvgl.STATE_DEFAULT, 2);
	lvgl.style_set_pad_left(style_prthome_labelit_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_prthome_labelit_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_prthome_labelit_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_prthome_labelit_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.prthome_labelit, lvgl.LABEL_PART_MAIN, style_prthome_labelit_main);
	lvgl.obj_set_pos(ui.prthome_labelit, 340, 160);
	lvgl.obj_set_size(ui.prthome_labelit, 85, 0);

	--Write codes prthome_label2
	ui.prthome_label2 = lvgl.label_create(ui.prthome, nil);
	lvgl.label_set_text(ui.prthome_label2, "您想从哪里打印?");
	lvgl.label_set_long_mode(ui.prthome_label2, lvgl.LABEL_LONG_BREAK);
	lvgl.label_set_align(ui.prthome_label2, lvgl.LABEL_ALIGN_CENTER);

	--Write style lvgl.LABEL_PART_MAIN for prthome_label2
	-- local style_prthome_label2_main;
	-- lvgl.style_init(style_prthome_label2_main);
	local style_prthome_label2_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prthome_label2_main
	lvgl.style_set_radius(style_prthome_label2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_prthome_label2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff));
	lvgl.style_set_bg_grad_color(style_prthome_label2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff));
	lvgl.style_set_bg_grad_dir(style_prthome_label2_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prthome_label2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_text_color(style_prthome_label2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00));
	lvgl.style_set_text_font(style_prthome_label2_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_22"));
	lvgl.style_set_text_letter_space(style_prthome_label2_main, lvgl.STATE_DEFAULT, 2);
	lvgl.style_set_pad_left(style_prthome_label2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_prthome_label2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_prthome_label2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_prthome_label2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.prthome_label2, lvgl.LABEL_PART_MAIN, style_prthome_label2_main);
	lvgl.obj_set_pos(ui.prthome_label2, 16, 218);
	lvgl.obj_set_size(ui.prthome_label2, 440, 0);

	--Write codes prthome_usb
	ui.prthome_usb = lvgl.img_create(ui.prthome, nil);

	--Write style lvgl.IMG_PART_MAIN for prthome_usb
	-- local style_prthome_usb_main;
	-- lvgl.style_init(style_prthome_usb_main);
	local style_prthome_usb_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prthome_usb_main
	lvgl.style_set_image_recolor(style_prthome_usb_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_image_recolor_opa(style_prthome_usb_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_image_opa(style_prthome_usb_main, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.prthome_usb, lvgl.IMG_PART_MAIN, style_prthome_usb_main);
	lvgl.obj_set_pos(ui.prthome_usb, 100, 85);
	lvgl.obj_set_size(ui.prthome_usb, 30, 30);
	lvgl.obj_set_click(ui.prthome_usb, true);
	lvgl.img_set_src(ui.prthome_usb,"/images/usb_alpha_30x30.png");
	lvgl.img_set_pivot(ui.prthome_usb, 0,0);
	lvgl.img_set_angle(ui.prthome_usb, 0);

	--Write codes prthome_mobile
	ui.prthome_mobile = lvgl.img_create(ui.prthome, nil);

	--Write style lvgl.IMG_PART_MAIN for prthome_mobile
	-- local style_prthome_mobile_main;
	-- lvgl.style_init(style_prthome_mobile_main);
	local style_prthome_mobile_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prthome_mobile_main
	lvgl.style_set_image_recolor(style_prthome_mobile_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_image_recolor_opa(style_prthome_mobile_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_image_opa(style_prthome_mobile_main, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.prthome_mobile, lvgl.IMG_PART_MAIN, style_prthome_mobile_main);
	lvgl.obj_set_pos(ui.prthome_mobile, 242, 85);
	lvgl.obj_set_size(ui.prthome_mobile, 30, 30);
	lvgl.obj_set_click(ui.prthome_mobile, true);
	lvgl.img_set_src(ui.prthome_mobile,"/images/mobile_alpha_30x30.png");
	lvgl.img_set_pivot(ui.prthome_mobile, 0,0);
	lvgl.img_set_angle(ui.prthome_mobile, 0);

	--Write codes prthome_internet
	ui.prthome_internet = lvgl.img_create(ui.prthome, nil);

	--Write style lvgl.IMG_PART_MAIN for prthome_internet
	-- local style_prthome_internet_main;
	-- lvgl.style_init(style_prthome_internet_main);
	local style_prthome_internet_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prthome_internet_main
	lvgl.style_set_image_recolor(style_prthome_internet_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_image_recolor_opa(style_prthome_internet_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_image_opa(style_prthome_internet_main, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.prthome_internet, lvgl.IMG_PART_MAIN, style_prthome_internet_main);
	lvgl.obj_set_pos(ui.prthome_internet, 383, 85);
	lvgl.obj_set_size(ui.prthome_internet, 30, 30);
	lvgl.obj_set_click(ui.prthome_internet, true);
	lvgl.img_set_src(ui.prthome_internet,"/images/internet_alpha_30x30.png");
	lvgl.img_set_pivot(ui.prthome_internet, 0,0);
	lvgl.img_set_angle(ui.prthome_internet, 0);

	--Write codes prthome_btnprintback
	ui.prthome_btnprintback = lvgl.btn_create(ui.prthome, nil);

	--Write style lvgl.BTN_PART_MAIN for prthome_btnprintback
	-- local style_prthome_btnprintback_main;
	-- lvgl.style_init(style_prthome_btnprintback_main);
	local style_prthome_btnprintback_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prthome_btnprintback_main
	lvgl.style_set_radius(style_prthome_btnprintback_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_prthome_btnprintback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_prthome_btnprintback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_prthome_btnprintback_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prthome_btnprintback_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_prthome_btnprintback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_prthome_btnprintback_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_border_opa(style_prthome_btnprintback_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_outline_color(style_prthome_btnprintback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_outline_opa(style_prthome_btnprintback_main, lvgl.STATE_DEFAULT, 255);

	--Write style state: lvgl.STATE_FOCUSED for style_prthome_btnprintback_main
	lvgl.style_set_radius(style_prthome_btnprintback_main, lvgl.STATE_FOCUSED, 50);
	lvgl.style_set_bg_color(style_prthome_btnprintback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_prthome_btnprintback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_prthome_btnprintback_main, lvgl.STATE_FOCUSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prthome_btnprintback_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_border_color(style_prthome_btnprintback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_prthome_btnprintback_main, lvgl.STATE_FOCUSED, 2);
	lvgl.style_set_border_opa(style_prthome_btnprintback_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_outline_color(style_prthome_btnprintback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_prthome_btnprintback_main, lvgl.STATE_FOCUSED, 255);

	--Write style state: lvgl.STATE_PRESSED for style_prthome_btnprintback_main
	lvgl.style_set_radius(style_prthome_btnprintback_main, lvgl.STATE_PRESSED, 0);
	lvgl.style_set_bg_color(style_prthome_btnprintback_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_prthome_btnprintback_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_prthome_btnprintback_main, lvgl.STATE_PRESSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prthome_btnprintback_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_border_color(style_prthome_btnprintback_main, lvgl.STATE_PRESSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_prthome_btnprintback_main, lvgl.STATE_PRESSED, 0);
	lvgl.style_set_border_opa(style_prthome_btnprintback_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_outline_color(style_prthome_btnprintback_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_outline_opa(style_prthome_btnprintback_main, lvgl.STATE_PRESSED, 100);

	--Write style state: lvgl.STATE_CHECKED for style_prthome_btnprintback_main
	lvgl.style_set_radius(style_prthome_btnprintback_main, lvgl.STATE_CHECKED, 50);
	lvgl.style_set_bg_color(style_prthome_btnprintback_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_prthome_btnprintback_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_prthome_btnprintback_main, lvgl.STATE_CHECKED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prthome_btnprintback_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_border_color(style_prthome_btnprintback_main, lvgl.STATE_CHECKED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_prthome_btnprintback_main, lvgl.STATE_CHECKED, 2);
	lvgl.style_set_border_opa(style_prthome_btnprintback_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_outline_color(style_prthome_btnprintback_main, lvgl.STATE_CHECKED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_prthome_btnprintback_main, lvgl.STATE_CHECKED, 255);
	lvgl.obj_add_style(ui.prthome_btnprintback, lvgl.BTN_PART_MAIN, style_prthome_btnprintback_main);
	lvgl.obj_set_pos(ui.prthome_btnprintback, 50, 13);
	lvgl.obj_set_size(ui.prthome_btnprintback, 30, 30);
	ui.prthome_btnprintback_label = lvgl.label_create(ui.prthome_btnprintback, nil);
	lvgl.label_set_text(ui.prthome_btnprintback_label, "");
	lvgl.obj_set_style_local_text_color(ui.prthome_btnprintback_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00));
end

return prthome
