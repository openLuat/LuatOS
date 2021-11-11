

local printit = {}

function printit.setup_scr_printit(ui)

	--Write codes printit
	ui.printit = lvgl.obj_create(nil, nil);

	--Write codes printit_cont0
	ui.printit_cont0 = lvgl.cont_create(ui.printit, nil);

	--Write style lvgl.CONT_PART_MAIN for printit_cont0
	-- local style_printit_cont0_main;
	-- lvgl.style_init(style_printit_cont0_main);
	local style_printit_cont0_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_printit_cont0_main
	lvgl.style_set_radius(style_printit_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_printit_cont0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xd2, 0x00, 0x00));
	lvgl.style_set_bg_grad_color(style_printit_cont0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xd2, 0x00, 0x00));
	lvgl.style_set_bg_grad_dir(style_printit_cont0_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_printit_cont0_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_printit_cont0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x99, 0x99, 0x99));
	lvgl.style_set_border_width(style_printit_cont0_main, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_border_opa(style_printit_cont0_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_pad_left(style_printit_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_printit_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_printit_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_printit_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.printit_cont0, lvgl.CONT_PART_MAIN, style_printit_cont0_main);
	lvgl.obj_set_pos(ui.printit_cont0, 0, 0);
	lvgl.obj_set_size(ui.printit_cont0, 480, 272);
	lvgl.obj_set_click(ui.printit_cont0, false);
	lvgl.cont_set_layout(ui.printit_cont0, lvgl.LAYOUT_OFF);
	lvgl.cont_set_fit(ui.printit_cont0, lvgl.FIT_NONE);

	--Write codes printit_btnprtitback
	ui.printit_btnprtitback = lvgl.btn_create(ui.printit, nil);

	--Write style lvgl.BTN_PART_MAIN for printit_btnprtitback
	-- local style_printit_btnprtitback_main;
	-- lvgl.style_init(style_printit_btnprtitback_main);
	local style_printit_btnprtitback_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_printit_btnprtitback_main
	lvgl.style_set_radius(style_printit_btnprtitback_main, lvgl.STATE_DEFAULT, 50);
	lvgl.style_set_bg_color(style_printit_btnprtitback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xd2, 0x00, 0x00));
	lvgl.style_set_bg_grad_color(style_printit_btnprtitback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xd2, 0x00, 0x00));
	lvgl.style_set_bg_grad_dir(style_printit_btnprtitback_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_printit_btnprtitback_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_printit_btnprtitback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_border_width(style_printit_btnprtitback_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_border_opa(style_printit_btnprtitback_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_outline_color(style_printit_btnprtitback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_outline_opa(style_printit_btnprtitback_main, lvgl.STATE_DEFAULT, 255);

	--Write style state: lvgl.STATE_FOCUSED for style_printit_btnprtitback_main
	lvgl.style_set_radius(style_printit_btnprtitback_main, lvgl.STATE_FOCUSED, 50);
	lvgl.style_set_bg_color(style_printit_btnprtitback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_printit_btnprtitback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_printit_btnprtitback_main, lvgl.STATE_FOCUSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_printit_btnprtitback_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_border_color(style_printit_btnprtitback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_printit_btnprtitback_main, lvgl.STATE_FOCUSED, 2);
	lvgl.style_set_border_opa(style_printit_btnprtitback_main, lvgl.STATE_FOCUSED, 255);
	lvgl.style_set_outline_color(style_printit_btnprtitback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_printit_btnprtitback_main, lvgl.STATE_FOCUSED, 255);

	--Write style state: lvgl.STATE_PRESSED for style_printit_btnprtitback_main
	lvgl.style_set_radius(style_printit_btnprtitback_main, lvgl.STATE_PRESSED, 50);
	lvgl.style_set_bg_color(style_printit_btnprtitback_main, lvgl.STATE_PRESSED, lvgl.color_make(0xd2, 0x00, 0x00));
	lvgl.style_set_bg_grad_color(style_printit_btnprtitback_main, lvgl.STATE_PRESSED, lvgl.color_make(0xd2, 0x00, 0x00));
	lvgl.style_set_bg_grad_dir(style_printit_btnprtitback_main, lvgl.STATE_PRESSED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_printit_btnprtitback_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_border_color(style_printit_btnprtitback_main, lvgl.STATE_PRESSED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_border_width(style_printit_btnprtitback_main, lvgl.STATE_PRESSED, 2);
	lvgl.style_set_border_opa(style_printit_btnprtitback_main, lvgl.STATE_PRESSED, 255);
	lvgl.style_set_outline_color(style_printit_btnprtitback_main, lvgl.STATE_PRESSED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_printit_btnprtitback_main, lvgl.STATE_PRESSED, 100);

	--Write style state: lvgl.STATE_CHECKED for style_printit_btnprtitback_main
	lvgl.style_set_radius(style_printit_btnprtitback_main, lvgl.STATE_CHECKED, 50);
	lvgl.style_set_bg_color(style_printit_btnprtitback_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_color(style_printit_btnprtitback_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_bg_grad_dir(style_printit_btnprtitback_main, lvgl.STATE_CHECKED, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_printit_btnprtitback_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_border_color(style_printit_btnprtitback_main, lvgl.STATE_CHECKED, lvgl.color_make(0x01, 0xa2, 0xb1));
	lvgl.style_set_border_width(style_printit_btnprtitback_main, lvgl.STATE_CHECKED, 2);
	lvgl.style_set_border_opa(style_printit_btnprtitback_main, lvgl.STATE_CHECKED, 255);
	lvgl.style_set_outline_color(style_printit_btnprtitback_main, lvgl.STATE_CHECKED, lvgl.color_make(0xd4, 0xd7, 0xd9));
	lvgl.style_set_outline_opa(style_printit_btnprtitback_main, lvgl.STATE_CHECKED, 255);
	lvgl.obj_add_style(ui.printit_btnprtitback, lvgl.BTN_PART_MAIN, style_printit_btnprtitback_main);
	lvgl.obj_set_pos(ui.printit_btnprtitback, 179, 205);
	lvgl.obj_set_size(ui.printit_btnprtitback, 134, 39);
	ui.printit_btnprtitback_label = lvgl.label_create(ui.printit_btnprtitback, nil);
	lvgl.label_set_text(ui.printit_btnprtitback_label, "返回");
	lvgl.obj_set_style_local_text_color(ui.printit_btnprtitback_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.obj_set_style_local_text_font(ui.printit_btnprtitback_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_14"));

	--Write codes printit_label2
	ui.printit_label2 = lvgl.label_create(ui.printit, nil);
	lvgl.label_set_text(ui.printit_label2, "无互联网连接");
	lvgl.label_set_long_mode(ui.printit_label2, lvgl.LABEL_LONG_BREAK);
	lvgl.label_set_align(ui.printit_label2, lvgl.LABEL_ALIGN_CENTER);

	--Write style lvgl.LABEL_PART_MAIN for printit_label2
	-- local style_printit_label2_main;
	-- lvgl.style_init(style_printit_label2_main);
	local style_printit_label2_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_printit_label2_main
	lvgl.style_set_radius(style_printit_label2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_printit_label2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xd2, 0x00, 0x00));
	lvgl.style_set_bg_grad_color(style_printit_label2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xd2, 0x00, 0x00));
	lvgl.style_set_bg_grad_dir(style_printit_label2_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_printit_label2_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_text_color(style_printit_label2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_text_font(style_printit_label2_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_18"));
	lvgl.style_set_text_letter_space(style_printit_label2_main, lvgl.STATE_DEFAULT, 2);
	lvgl.style_set_pad_left(style_printit_label2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_printit_label2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_printit_label2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_printit_label2_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.printit_label2, lvgl.LABEL_PART_MAIN, style_printit_label2_main);
	lvgl.obj_set_pos(ui.printit_label2, 10, 146);
	lvgl.obj_set_size(ui.printit_label2, 460, 0);

	--Write codes printit_printer
	ui.printit_printer = lvgl.img_create(ui.printit, nil);

	--Write style lvgl.IMG_PART_MAIN for printit_printer
	-- local style_printit_printer_main;
	-- lvgl.style_init(style_printit_printer_main);
	local style_printit_printer_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_printit_printer_main
	lvgl.style_set_image_recolor(style_printit_printer_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_image_recolor_opa(style_printit_printer_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_image_opa(style_printit_printer_main, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.printit_printer, lvgl.IMG_PART_MAIN, style_printit_printer_main);
	lvgl.obj_set_pos(ui.printit_printer, 154, 70);
	lvgl.obj_set_size(ui.printit_printer, 60, 55);
	lvgl.obj_set_click(ui.printit_printer, true);
	lvgl.img_set_src(ui.printit_printer,"/images/printer2_alpha_60x55.png");
	lvgl.img_set_pivot(ui.printit_printer, 0,0);
	lvgl.img_set_angle(ui.printit_printer, 0);

	--Write codes printit_imgnotit
	ui.printit_imgnotit = lvgl.img_create(ui.printit, nil);

	--Write style lvgl.IMG_PART_MAIN for printit_imgnotit
	-- local style_printit_imgnotit_main;
	-- lvgl.style_init(style_printit_imgnotit_main);
	local style_printit_imgnotit_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_printit_imgnotit_main
	lvgl.style_set_image_recolor(style_printit_imgnotit_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_image_recolor_opa(style_printit_imgnotit_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_image_opa(style_printit_imgnotit_main, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.printit_imgnotit, lvgl.IMG_PART_MAIN, style_printit_imgnotit_main);
	lvgl.obj_set_pos(ui.printit_imgnotit, 217, 62);
	lvgl.obj_set_size(ui.printit_imgnotit, 25, 25);
	lvgl.obj_set_click(ui.printit_imgnotit, true);
	lvgl.img_set_src(ui.printit_imgnotit,"/images/no_internet_alpha_25x25.png");
	lvgl.img_set_pivot(ui.printit_imgnotit, 0,0);
	lvgl.img_set_angle(ui.printit_imgnotit, 0);

	--Write codes printit_cloud
	ui.printit_cloud = lvgl.img_create(ui.printit, nil);

	--Write style lvgl.IMG_PART_MAIN for printit_cloud
	-- local style_printit_cloud_main;
	-- lvgl.style_init(style_printit_cloud_main);
	local style_printit_cloud_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_printit_cloud_main
	lvgl.style_set_image_recolor(style_printit_cloud_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_image_recolor_opa(style_printit_cloud_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_image_opa(style_printit_cloud_main, lvgl.STATE_DEFAULT, 255);
	lvgl.obj_add_style(ui.printit_cloud, lvgl.IMG_PART_MAIN, style_printit_cloud_main);
	lvgl.obj_set_pos(ui.printit_cloud, 258, 30);
	lvgl.obj_set_size(ui.printit_cloud, 55, 40);
	lvgl.obj_set_click(ui.printit_cloud, true);
	lvgl.img_set_src(ui.printit_cloud,"/images/cloud_alpha_55x40.png");
	lvgl.img_set_pivot(ui.printit_cloud, 0,0);
	lvgl.img_set_angle(ui.printit_cloud, 0);
end

return printit
