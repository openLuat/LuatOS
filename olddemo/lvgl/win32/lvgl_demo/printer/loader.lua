

local loader = {}

function loader.setup_scr_loader(ui)

	--Write codes loader
	ui.loader = lvgl.obj_create(nil, nil);

	--Write codes loader_cont0
	ui.loader_cont0 = lvgl.cont_create(ui.loader, nil);

	--Write style lvgl.CONT_PART_MAIN for loader_cont0
	-- local style_loader_cont0_main;
	-- lvgl.style_init(style_loader_cont0_main);
	local style_loader_cont0_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_loader_cont0_main
	lvgl.style_set_radius(style_loader_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_loader_cont0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_loader_cont0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_loader_cont0_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_loader_cont0_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_border_color(style_loader_cont0_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x99, 0x99, 0x99));
	lvgl.style_set_border_width(style_loader_cont0_main, lvgl.STATE_DEFAULT, 1);
	lvgl.style_set_border_opa(style_loader_cont0_main, lvgl.STATE_DEFAULT, 255);
	lvgl.style_set_pad_left(style_loader_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_loader_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_loader_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_loader_cont0_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.loader_cont0, lvgl.CONT_PART_MAIN, style_loader_cont0_main);
	lvgl.obj_set_pos(ui.loader_cont0, 0, 0);
	lvgl.obj_set_size(ui.loader_cont0, 480, 272);
	lvgl.obj_set_click(ui.loader_cont0, false);
	lvgl.cont_set_layout(ui.loader_cont0, lvgl.LAYOUT_OFF);
	lvgl.cont_set_fit(ui.loader_cont0, lvgl.FIT_NONE);

	--Write codes loader_loadarc
	ui.loader_loadarc = lvgl.arc_create(ui.loader, nil);

	--Write style lvgl.ARC_PART_BG for loader_loadarc
	-- local style_loader_loadarc_bg;
	-- lvgl.style_init(style_loader_loadarc_bg);
	local style_loader_loadarc_bg = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_loader_loadarc_bg
	lvgl.style_set_bg_color(style_loader_loadarc_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x23, 0x46));
	lvgl.style_set_bg_grad_color(style_loader_loadarc_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x23, 0x46));
	lvgl.style_set_bg_grad_dir(style_loader_loadarc_bg, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_loader_loadarc_bg, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_border_width(style_loader_loadarc_bg, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_left(style_loader_loadarc_bg, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_loader_loadarc_bg, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_loader_loadarc_bg, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_loader_loadarc_bg, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_line_color(style_loader_loadarc_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x23, 0x46));
	lvgl.style_set_line_width(style_loader_loadarc_bg, lvgl.STATE_DEFAULT, 5);
	lvgl.obj_add_style(ui.loader_loadarc, lvgl.ARC_PART_BG, style_loader_loadarc_bg);

	--Write style lvgl.ARC_PART_INDIC for loader_loadarc
	-- local style_loader_loadarc_indic;
	-- lvgl.style_init(style_loader_loadarc_indic);
	local style_loader_loadarc_indic = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_loader_loadarc_indic
	lvgl.style_set_line_color(style_loader_loadarc_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_line_width(style_loader_loadarc_indic, lvgl.STATE_DEFAULT, 5);
	lvgl.obj_add_style(ui.loader_loadarc, lvgl.ARC_PART_INDIC, style_loader_loadarc_indic);
	lvgl.obj_set_pos(ui.loader_loadarc, 180, 80);
	lvgl.obj_set_size(ui.loader_loadarc, 110, 110);
	lvgl.arc_set_angles(ui.loader_loadarc, 271, 271);
	lvgl.arc_set_bg_angles(ui.loader_loadarc, 0, 360);
	lvgl.arc_set_rotation(ui.loader_loadarc, 0);
	lvgl.obj_set_style_local_line_rounded(ui.loader_loadarc, lvgl.ARC_PART_INDIC, lvgl.STATE_DEFAULT, 0);

	--Write codes loader_loadlabel
	ui.loader_loadlabel = lvgl.label_create(ui.loader, nil);
	lvgl.label_set_text(ui.loader_loadlabel, "0 %");
	lvgl.label_set_long_mode(ui.loader_loadlabel, lvgl.LABEL_LONG_BREAK);
	lvgl.label_set_align(ui.loader_loadlabel, lvgl.LABEL_ALIGN_CENTER);

	--Write style lvgl.LABEL_PART_MAIN for loader_loadlabel
	-- local style_loader_loadlabel_main;
	-- lvgl.style_init(style_loader_loadlabel_main);
	local style_loader_loadlabel_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_loader_loadlabel_main
	lvgl.style_set_radius(style_loader_loadlabel_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_bg_color(style_loader_loadlabel_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_color(style_loader_loadlabel_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43));
	lvgl.style_set_bg_grad_dir(style_loader_loadlabel_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER);
	lvgl.style_set_bg_opa(style_loader_loadlabel_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_text_color(style_loader_loadlabel_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff));
	lvgl.style_set_text_font(style_loader_loadlabel_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_16"));
	lvgl.style_set_text_letter_space(style_loader_loadlabel_main, lvgl.STATE_DEFAULT, 2);
	lvgl.style_set_pad_left(style_loader_loadlabel_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_right(style_loader_loadlabel_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_top(style_loader_loadlabel_main, lvgl.STATE_DEFAULT, 0);
	lvgl.style_set_pad_bottom(style_loader_loadlabel_main, lvgl.STATE_DEFAULT, 0);
	lvgl.obj_add_style(ui.loader_loadlabel, lvgl.LABEL_PART_MAIN, style_loader_loadlabel_main);
	lvgl.obj_set_pos(ui.loader_loadlabel, 201, 125);
	lvgl.obj_set_size(ui.loader_loadlabel, 80, 0);
end

return loader
