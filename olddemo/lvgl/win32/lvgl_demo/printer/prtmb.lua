

local prtmb = {}

function prtmb.setup_scr_prtmb(ui)

	--Write codes prtmb
	ui.prtmb = lvgl.obj_create(nil, nil);

	--Write codes prtmb_cont0
	ui.prtmb_cont0 = lvgl.cont_create(ui.prtmb, nil);

	--Write style lvgl.CONT_PART_MAIN for prtmb_cont0
	-- local style_prtmb_cont0_main;
	-- lvgl.style_init(style_prtmb_cont0_main);
	local style_prtmb_cont0_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtmb_cont0_main
	lvgl.style_set_radius(style_prtmb_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_prtmb_cont0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_prtmb_cont0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_prtmb_cont0_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtmb_cont0_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_prtmb_cont0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x99, 0x99, 0x99));
	lvgl.style_set_border_width(style_prtmb_cont0_main, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_border_opa(style_prtmb_cont0_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_pad_left(style_prtmb_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_prtmb_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_prtmb_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_prtmb_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.prtmb_cont0, lvgl.CONT_PART_MAIN, style_prtmb_cont0_main);
	lvgl.obj_set_pos(ui.prtmb_cont0, 0, 0);
	lvgl.obj_set_size(ui.prtmb_cont0, 480, 272);
	lvgl.obj_set_click(ui.prtmb_cont0, false);
	lvgl.cont_set_layout(ui.prtmb_cont0, lvgl.LAYOUT_OFF);
	lvgl.cont_set_fit(ui.prtmb_cont0, lvgl.FIT_NONE);

	--Write codes prtmb_btnback
	ui.prtmb_btnback = lvgl.btn_create(ui.prtmb, nil);

	--Write style lvgl.BTN_PART_MAIN for prtmb_btnback
	-- local style_prtmb_btnback_main;
	-- lvgl.style_init(style_prtmb_btnback_main);
	local style_prtmb_btnback_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtmb_btnback_main
	lvgl.style_set_radius(style_prtmb_btnback_main, lvgl.STATE_DEFAULT, 50);
	lvgl.style_set_bg_color(style_prtmb_btnback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x29, 0x30, 0x41));
	lvgl.style_set_bg_grad_color(style_prtmb_btnback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x29, 0x30, 0x41));
	lvgl.style_set_bg_grad_dir(style_prtmb_btnback_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtmb_btnback_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_prtmb_btnback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_border_width(style_prtmb_btnback_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_border_opa(style_prtmb_btnback_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_outline_color(style_prtmb_btnback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_outline_opa(style_prtmb_btnback_main, lvgl.STATE_DEFAULT, 255);

	--Write style state: lvgl.STATE_FOCUSED for style_prtmb_btnback_main
	lvgl.style_set_radius(style_prtmb_btnback_main, lvgl.STATE_FOCUSED, 50);
	lvgl.style_set_bg_color(style_prtmb_btnback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_prtmb_btnback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_prtmb_btnback_main, lvgl.STATE_FOCUSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtmb_btnback_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_border_color(style_prtmb_btnback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_prtmb_btnback_main, lvgl.STATE_FOCUSED, 2);
	lvgl.style_set_border_opa(style_prtmb_btnback_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_outline_color(style_prtmb_btnback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_prtmb_btnback_main, lvgl.STATE_FOCUSED, 255);

	--Write style state: lvgl.STATE_PRESSED for style_prtmb_btnback_main
	lvgl.style_set_radius(style_prtmb_btnback_main, lvgl.STATE_PRESSED, 50);
	lvgl.style_set_bg_color(style_prtmb_btnback_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_prtmb_btnback_main, lvgl.STATE_PRESSED, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_prtmb_btnback_main, lvgl.STATE_PRESSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtmb_btnback_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_border_color(style_prtmb_btnback_main, lvgl.STATE_PRESSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_border_width(style_prtmb_btnback_main, lvgl.STATE_PRESSED, 2);
	lvgl.style_set_border_opa(style_prtmb_btnback_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_outline_color(style_prtmb_btnback_main, lvgl.STATE_PRESSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_outline_opa(style_prtmb_btnback_main, lvgl.STATE_PRESSED, 100);

	--Write style state: lvgl.STATE_CHECKED for style_prtmb_btnback_main
	lvgl.style_set_radius(style_prtmb_btnback_main, lvgl.STATE_CHECKED, 50);
	lvgl.style_set_bg_color(style_prtmb_btnback_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_prtmb_btnback_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_prtmb_btnback_main, lvgl.STATE_CHECKED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtmb_btnback_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_border_color(style_prtmb_btnback_main, lvgl.STATE_CHECKED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_prtmb_btnback_main, lvgl.STATE_CHECKED, 2);
	lvgl.style_set_border_opa(style_prtmb_btnback_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_outline_color(style_prtmb_btnback_main, lvgl.STATE_CHECKED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_prtmb_btnback_main, lvgl.STATE_CHECKED, 255);
	lvgl.obj_add_style(ui.prtmb_btnback, lvgl.BTN_PART_MAIN, style_prtmb_btnback_main);
	lvgl.obj_set_pos(ui.prtmb_btnback, 179, 205);
	lvgl.obj_set_size(ui.prtmb_btnback, 134, 39);
	ui.prtmb_btnback_label = lvgl.label_create(ui.prtmb_btnback, nil);
	lvgl.label_set_text(ui.prtmb_btnback_label, "返回");
	lvgl.obj_set_style_local_text_color(ui.prtmb_btnback_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.obj_set_style_local_text_font(ui.prtmb_btnback_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_14"));

	--Write codes prtmb_label2
	ui.prtmb_label2 = lvgl.label_create(ui.prtmb, nil);
	lvgl.label_set_text(ui.prtmb_label2, "请将您的电话靠近打印机");
	lvgl.label_set_long_mode(ui.prtmb_label2, lvgl.LABEL_LONG_BREAK);
	lvgl.label_set_align(ui.prtmb_label2, lvgl.LABEL_ALIGN_CENTER);

	--Write style lvgl.LABEL_PART_MAIN for prtmb_label2
	-- local style_prtmb_label2_main;
	-- lvgl.style_init(style_prtmb_label2_main);
	local style_prtmb_label2_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtmb_label2_main
	lvgl.style_set_radius(style_prtmb_label2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_prtmb_label2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_prtmb_label2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_prtmb_label2_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_prtmb_label2_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_text_color(style_prtmb_label2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_text_font(style_prtmb_label2_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_18"));
	lvgl.style_set_text_letter_space(style_prtmb_label2_main, lvgl.STATE_DEFAULT, 2);
	lvgl.style_set_pad_left(style_prtmb_label2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_prtmb_label2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_prtmb_label2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_prtmb_label2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.prtmb_label2, lvgl.LABEL_PART_MAIN, style_prtmb_label2_main);
	lvgl.obj_set_pos(ui.prtmb_label2, 10, 146);
	lvgl.obj_set_size(ui.prtmb_label2, 460, 0);

	--Write codes prtmb_printer
	ui.prtmb_printer = lvgl.img_create(ui.prtmb, nil);

	--Write style lvgl.IMG_PART_MAIN for prtmb_printer
	-- local style_prtmb_printer_main;
	-- lvgl.style_init(style_prtmb_printer_main);
	local style_prtmb_printer_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtmb_printer_main
	lvgl.style_set_image_recolor(style_prtmb_printer_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_image_recolor_opa(style_prtmb_printer_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_image_opa(style_prtmb_printer_main, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.prtmb_printer, lvgl.IMG_PART_MAIN, style_prtmb_printer_main);
	lvgl.obj_set_pos(ui.prtmb_printer, 154, 70);
	lvgl.obj_set_size(ui.prtmb_printer, 60, 55);
	lvgl.obj_set_click(ui.prtmb_printer, true);
	lvgl.img_set_src(ui.prtmb_printer,"/images/printer2_alpha_60x55.png");
	lvgl.img_set_pivot(ui.prtmb_printer, 0,0);
	lvgl.img_set_angle(ui.prtmb_printer, 0);

	--Write codes prtmb_img
	ui.prtmb_img = lvgl.img_create(ui.prtmb, nil);

	--Write style lvgl.IMG_PART_MAIN for prtmb_img
	-- local style_prtmb_img_main;
	-- lvgl.style_init(style_prtmb_img_main);
	local style_prtmb_img_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtmb_img_main
	lvgl.style_set_image_recolor(style_prtmb_img_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_image_recolor_opa(style_prtmb_img_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_image_opa(style_prtmb_img_main, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.prtmb_img, lvgl.IMG_PART_MAIN, style_prtmb_img_main);
	lvgl.obj_set_pos(ui.prtmb_img, 235, 83);
	lvgl.obj_set_size(ui.prtmb_img, 25, 25);
	lvgl.obj_set_click(ui.prtmb_img, true);
	lvgl.img_set_src(ui.prtmb_img,"/images/wave_alpha_25x25.png");
	lvgl.img_set_pivot(ui.prtmb_img, 0,0);
	lvgl.img_set_angle(ui.prtmb_img, 0);

	--Write codes prtmb_cloud
	ui.prtmb_cloud = lvgl.img_create(ui.prtmb, nil);

	--Write style lvgl.IMG_PART_MAIN for prtmb_cloud
	-- local style_prtmb_cloud_main;
	-- lvgl.style_init(style_prtmb_cloud_main);
	local style_prtmb_cloud_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_prtmb_cloud_main
	lvgl.style_set_image_recolor(style_prtmb_cloud_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_image_recolor_opa(style_prtmb_cloud_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_image_opa(style_prtmb_cloud_main, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.prtmb_cloud, lvgl.IMG_PART_MAIN, style_prtmb_cloud_main);
	lvgl.obj_set_pos(ui.prtmb_cloud, 280, 72);
	lvgl.obj_set_size(ui.prtmb_cloud, 45, 55);
	lvgl.obj_set_click(ui.prtmb_cloud, true);
	lvgl.img_set_src(ui.prtmb_cloud,"/images/phone_alpha_45x55.png");
	lvgl.img_set_pivot(ui.prtmb_cloud, 0,0);
	lvgl.img_set_angle(ui.prtmb_cloud, 0);
end

return prtmb
