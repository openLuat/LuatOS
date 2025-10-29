

local setup = {}

function setup.setup_scr_setup(ui)

	--Write codes setup
	ui.setup = lvgl.obj_create(nil, nil)

	--Write codes setup_cont0
	ui.setup_cont0 = lvgl.cont_create(ui.setup, nil)

	--Write style lvgl.CONT_PART_MAIN for setup_cont0
	-- local style_setup_cont0_main
	-- lvgl.style_init(style_setup_cont0_main)
	local style_setup_cont0_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_setup_cont0_main
	lvgl.style_set_radius(style_setup_cont0_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_bg_color(style_setup_cont0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xd2, 0x00, 0x00))
	lvgl.style_set_bg_grad_color(style_setup_cont0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xd2, 0x00, 0x00))
	lvgl.style_set_bg_grad_dir(style_setup_cont0_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_setup_cont0_main, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_border_color(style_setup_cont0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x99, 0x99, 0x99))
	lvgl.style_set_border_width(style_setup_cont0_main, lvgl.STATE_DEFAULT, 1)
	lvgl.style_set_border_opa(style_setup_cont0_main, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_pad_left(style_setup_cont0_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_right(style_setup_cont0_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_top(style_setup_cont0_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_bottom(style_setup_cont0_main, lvgl.STATE_DEFAULT, 0)
	lvgl.obj_add_style(ui.setup_cont0, lvgl.CONT_PART_MAIN, style_setup_cont0_main)
	lvgl.obj_set_pos(ui.setup_cont0, 0, 0)
	lvgl.obj_set_size(ui.setup_cont0, 480, 272)
	lvgl.obj_set_click(ui.setup_cont0, false)
	lvgl.cont_set_layout(ui.setup_cont0, lvgl.LAYOUT_OFF)
	lvgl.cont_set_fit(ui.setup_cont0, lvgl.FIT_NONE)

	--Write codes setup_btnsetback
	ui.setup_btnsetback = lvgl.btn_create(ui.setup, nil)

	--Write style lvgl.BTN_PART_MAIN for setup_btnsetback
	-- local style_setup_btnsetback_main
	-- lvgl.style_init(style_setup_btnsetback_main)
	local style_setup_btnsetback_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_setup_btnsetback_main
	lvgl.style_set_radius(style_setup_btnsetback_main, lvgl.STATE_DEFAULT, 50)
	lvgl.style_set_bg_color(style_setup_btnsetback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xd2, 0x00, 0x00))
	lvgl.style_set_bg_grad_color(style_setup_btnsetback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xd2, 0x00, 0x00))
	lvgl.style_set_bg_grad_dir(style_setup_btnsetback_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_setup_btnsetback_main, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_border_color(style_setup_btnsetback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_border_width(style_setup_btnsetback_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_border_opa(style_setup_btnsetback_main, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_outline_color(style_setup_btnsetback_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_outline_opa(style_setup_btnsetback_main, lvgl.STATE_DEFAULT, 255)

	--Write style state: lvgl.STATE_FOCUSED for style_setup_btnsetback_main
	lvgl.style_set_radius(style_setup_btnsetback_main, lvgl.STATE_FOCUSED, 50)
	lvgl.style_set_bg_color(style_setup_btnsetback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_setup_btnsetback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_setup_btnsetback_main, lvgl.STATE_FOCUSED, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_setup_btnsetback_main, lvgl.STATE_FOCUSED, 255)
	lvgl.style_set_border_color(style_setup_btnsetback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_border_width(style_setup_btnsetback_main, lvgl.STATE_FOCUSED, 2)
	lvgl.style_set_border_opa(style_setup_btnsetback_main, lvgl.STATE_FOCUSED, 255)
	lvgl.style_set_outline_color(style_setup_btnsetback_main, lvgl.STATE_FOCUSED, lvgl.color_make(0xd4, 0xd7, 0xd9))
	lvgl.style_set_outline_opa(style_setup_btnsetback_main, lvgl.STATE_FOCUSED, 255)

	--Write style state: lvgl.STATE_PRESSED for style_setup_btnsetback_main
	lvgl.style_set_radius(style_setup_btnsetback_main, lvgl.STATE_PRESSED, 50)
	lvgl.style_set_bg_color(style_setup_btnsetback_main, lvgl.STATE_PRESSED, lvgl.color_make(0xd2, 0x00, 0x00))
	lvgl.style_set_bg_grad_color(style_setup_btnsetback_main, lvgl.STATE_PRESSED, lvgl.color_make(0xd2, 0x00, 0x00))
	lvgl.style_set_bg_grad_dir(style_setup_btnsetback_main, lvgl.STATE_PRESSED, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_setup_btnsetback_main, lvgl.STATE_PRESSED, 255)
	lvgl.style_set_border_color(style_setup_btnsetback_main, lvgl.STATE_PRESSED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_border_width(style_setup_btnsetback_main, lvgl.STATE_PRESSED, 2)
	lvgl.style_set_border_opa(style_setup_btnsetback_main, lvgl.STATE_PRESSED, 255)
	lvgl.style_set_outline_color(style_setup_btnsetback_main, lvgl.STATE_PRESSED, lvgl.color_make(0xd4, 0xd7, 0xd9))
	lvgl.style_set_outline_opa(style_setup_btnsetback_main, lvgl.STATE_PRESSED, 100)

	--Write style state: lvgl.STATE_CHECKED for style_setup_btnsetback_main
	lvgl.style_set_radius(style_setup_btnsetback_main, lvgl.STATE_CHECKED, 50)
	lvgl.style_set_bg_color(style_setup_btnsetback_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_setup_btnsetback_main, lvgl.STATE_CHECKED, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_setup_btnsetback_main, lvgl.STATE_CHECKED, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_setup_btnsetback_main, lvgl.STATE_CHECKED, 255)
	lvgl.style_set_border_color(style_setup_btnsetback_main, lvgl.STATE_CHECKED, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_border_width(style_setup_btnsetback_main, lvgl.STATE_CHECKED, 2)
	lvgl.style_set_border_opa(style_setup_btnsetback_main, lvgl.STATE_CHECKED, 255)
	lvgl.style_set_outline_color(style_setup_btnsetback_main, lvgl.STATE_CHECKED, lvgl.color_make(0xd4, 0xd7, 0xd9))
	lvgl.style_set_outline_opa(style_setup_btnsetback_main, lvgl.STATE_CHECKED, 255)
	lvgl.obj_add_style(ui.setup_btnsetback, lvgl.BTN_PART_MAIN, style_setup_btnsetback_main)
	lvgl.obj_set_pos(ui.setup_btnsetback, 179, 205)
	lvgl.obj_set_size(ui.setup_btnsetback, 134, 39)
	ui.setup_btnsetback_label = lvgl.label_create(ui.setup_btnsetback, nil)
	lvgl.label_set_text(ui.setup_btnsetback_label, "返回")
	lvgl.obj_set_style_local_text_color(ui.setup_btnsetback_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.obj_set_style_local_text_font(ui.setup_btnsetback_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_14"))

	--Write codes setup_label2
	ui.setup_label2 = lvgl.label_create(ui.setup, nil)
	lvgl.label_set_text(ui.setup_label2, "您没有权限更改设置")
	lvgl.label_set_long_mode(ui.setup_label2, lvgl.LABEL_LONG_BREAK)
	lvgl.label_set_align(ui.setup_label2, lvgl.LABEL_ALIGN_CENTER)

	--Write style lvgl.LABEL_PART_MAIN for setup_label2
	-- local style_setup_label2_main
	-- lvgl.style_init(style_setup_label2_main)
	local style_setup_label2_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_setup_label2_main
	lvgl.style_set_radius(style_setup_label2_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_bg_color(style_setup_label2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xd2, 0x00, 0x00))
	lvgl.style_set_bg_grad_color(style_setup_label2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xd2, 0x00, 0x00))
	lvgl.style_set_bg_grad_dir(style_setup_label2_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_setup_label2_main, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_text_color(style_setup_label2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_text_font(style_setup_label2_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_18"))
	lvgl.style_set_text_letter_space(style_setup_label2_main, lvgl.STATE_DEFAULT, 2)
	lvgl.style_set_pad_left(style_setup_label2_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_right(style_setup_label2_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_top(style_setup_label2_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_bottom(style_setup_label2_main, lvgl.STATE_DEFAULT, 0)
	lvgl.obj_add_style(ui.setup_label2, lvgl.LABEL_PART_MAIN, style_setup_label2_main)
	lvgl.obj_set_pos(ui.setup_label2, 10, 146)
	lvgl.obj_set_size(ui.setup_label2, 460, 0)

	--Write codes setup_printer
	ui.setup_printer = lvgl.img_create(ui.setup, nil)

	--Write style lvgl.IMG_PART_MAIN for setup_printer
	-- local style_setup_printer_main
	-- lvgl.style_init(style_setup_printer_main)
	local style_setup_printer_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_setup_printer_main
	lvgl.style_set_image_recolor(style_setup_printer_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_image_recolor_opa(style_setup_printer_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_image_opa(style_setup_printer_main, lvgl.STATE_DEFAULT, 255)
	lvgl.obj_add_style(ui.setup_printer, lvgl.IMG_PART_MAIN, style_setup_printer_main)
	lvgl.obj_set_pos(ui.setup_printer, 154, 70)
	lvgl.obj_set_size(ui.setup_printer, 60, 55)
	lvgl.obj_set_click(ui.setup_printer, true)
	lvgl.img_set_src(ui.setup_printer,"/images/printer2_alpha_60x55.png")
	lvgl.img_set_pivot(ui.setup_printer, 0,0)
	lvgl.img_set_angle(ui.setup_printer, 0)

	--Write codes setup_img
	ui.setup_img = lvgl.img_create(ui.setup, nil)

	--Write style lvgl.IMG_PART_MAIN for setup_img
	-- local style_setup_img_main
	-- lvgl.style_init(style_setup_img_main)
	local style_setup_img_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_setup_img_main
	lvgl.style_set_image_recolor(style_setup_img_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_image_recolor_opa(style_setup_img_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_image_opa(style_setup_img_main, lvgl.STATE_DEFAULT, 255)
	lvgl.obj_add_style(ui.setup_img, lvgl.IMG_PART_MAIN, style_setup_img_main)
	lvgl.obj_set_pos(ui.setup_img, 217, 62)
	lvgl.obj_set_size(ui.setup_img, 25, 25)
	lvgl.obj_set_click(ui.setup_img, true)
	lvgl.img_set_src(ui.setup_img,"/images/no_internet_alpha_25x25.png")
	lvgl.img_set_pivot(ui.setup_img, 0,0)
	lvgl.img_set_angle(ui.setup_img, 0)

	--Write codes setup_cloud
	ui.setup_cloud = lvgl.img_create(ui.setup, nil)

	--Write style lvgl.IMG_PART_MAIN for setup_cloud
	-- local style_setup_cloud_main
	-- lvgl.style_init(style_setup_cloud_main)
	local style_setup_cloud_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_setup_cloud_main
	lvgl.style_set_image_recolor(style_setup_cloud_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_image_recolor_opa(style_setup_cloud_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_image_opa(style_setup_cloud_main, lvgl.STATE_DEFAULT, 255)
	lvgl.obj_add_style(ui.setup_cloud, lvgl.IMG_PART_MAIN, style_setup_cloud_main)
	lvgl.obj_set_pos(ui.setup_cloud, 258, 30)
	lvgl.obj_set_size(ui.setup_cloud, 55, 40)
	lvgl.obj_set_click(ui.setup_cloud, true)
	lvgl.img_set_src(ui.setup_cloud,"/images/cloud_alpha_55x40.png")
	lvgl.img_set_pivot(ui.setup_cloud, 0,0)
	lvgl.img_set_angle(ui.setup_cloud, 0)
end

return setup
