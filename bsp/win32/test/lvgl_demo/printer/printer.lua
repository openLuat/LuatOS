local setup = require "setup"
local loader = require "loader"
local printit = require "printit"
local prthome = require "prthome"
local prtmb = require "prtmb"
local scanhome = require "scanhome"
local symbol = require "symbol"
local printer = {}

local SCR_HOME = 0
local SCR_COPY_HOME = 1
local SCR_COPY_NEXT = 2
local SCR_SCAN_HOME = 3
local SCR_PRT_HOME = 4
local SCR_PRT_USB = 5
local SCR_PRT_MB = 6
local SCR_PRT_IT = 7
local SCR_SETUP = 8
local SCR_LOADER = 9
local SCR_SAVED = 10
local cur_scr;

local ani_en_btn_click;

local printusbcnt = 1;
local copynextcnt = 1;
local hue_act;
local lightness_act;
local img_style;

local save_src = 0;

local style_backbtn;
local style_upbtn;
local style_downbtn;
local arc_style;

function printer.demo_printer_anim_in_all(obj,delay)
    local child = lvgl.obj_get_child_back(obj, nil);
    -- while(child) do
    --     y = lvgl.obj_get_y(child);
    --     if (child ~= lvgl.scr_act() and child ~= _G.guider_ui.saved_img1) then
    --         -- lvgl.anim_t a;
    --         -- lvgl.anim_init(a);
	-- 		local a = lvgl.anim_create()
    --         lvgl.anim_set_var(a, child);
    --         lvgl.anim_set_time(a, 150);
    --         lvgl.anim_set_delay(a, delay);
    --         lvgl.anim_set_exec_cb(a, lvgl.obj_set_y);

    --         if(y > 150)then
    --             lvgl.anim_set_values(a, 270, y);
    --         else
    --             lvgl.anim_set_values(a, 0, y);
	-- 		end
    --         lvgl.anim_start(a);

    --         lvgl.obj_fade_in(child, 150 - 50, delay);
    --     end
    --     child = lvgl.obj_get_child_back(obj, child);
    -- end
end

local function get_scr_by_id(scr_id)
    if(scr_id == SCR_HOME) then
        return _G.guider_ui.home;
    elseif(scr_id == SCR_COPY_HOME) then
        return _G.guider_ui.copyhome;
    elseif(scr_id == SCR_COPY_NEXT) then
        return _G.guider_ui.copynext;
    elseif(scr_id == SCR_SCAN_HOME) then
        return _G.guider_ui.scanhome;
    elseif(scr_id == SCR_PRT_HOME) then
        return _G.guider_ui.prthome;
    elseif(scr_id == SCR_PRT_USB) then
        return _G.guider_ui.prtusb;
    elseif(scr_id == SCR_PRT_MB) then
        return _G.guider_ui.prtmb;
    elseif(scr_id == SCR_PRT_IT) then
        return _G.guider_ui.printit;
    elseif(scr_id == SCR_SETUP) then
        return _G.guider_ui.setup;
    elseif(scr_id == SCR_LOADER) then
        return _G.guider_ui.loader;
    elseif(scr_id == SCR_SAVED) then
        return _G.guider_ui.saved;
	end
    return nil;
end
local function load_disbtn_home_cb(obj,event)
	if (event == lvgl.EVENT_PRESSED) then
        printer.guider_load_screen(SCR_HOME)
   end
end

local function setup_event_init()
    lvgl.obj_set_event_cb(_G.guider_ui.setup_btnsetback, load_disbtn_home_cb);
end
local function home_event_init()
    lvgl.obj_set_click(_G.guider_ui.home_imgbtnscan, false);
    lvgl.obj_set_click(_G.guider_ui.home_imgbtnprt, false);
    lvgl.obj_set_click(_G.guider_ui.home_imgbtnset, false);
    lvgl.obj_set_click(_G.guider_ui.home_imgbtncopy, false);
    printer.demo_printer_anim_in_all(_G.guider_ui.home, 200);
end

function printer.guider_load_screen(scr_id)
    local scr = nil;
    local old_scr = nil;
	if(scr_id == SCR_HOME) then
		if( _G.guider_ui.home==nil) then
            printer.setup_scr_home(_G.guider_ui);
            scr = _G.guider_ui.home
			home_event_init()
			-- lvgl.anim_set_var(ani_en_btn_click, _G.guider_ui.home_imgbtncopy)
			-- lvgl.anim_start(ani_en_btn_click)
			print("load home\n")
		end
    elseif(scr_id == SCR_COPY_HOME) then
		if(_G.guider_ui.copyhome~=nil) then
			scr = _G.guider_ui.copyhome;
			-- setup_scr_copyhome();
			-- copy_home_event_init();
			-- lvgl.anim_set_var(ani_en_btn_click, ui.copyhome_btncopyback);
			-- lvgl.anim_start(ani_en_btn_click);
            print("load copy home\n");
		end
    elseif(scr_id == _G.SCR_COPY_NEXT) then
		if(_G.guider_ui.copynext~=nil) then
			scr = _G.guider_ui.copynext;
			-- setup_scr_copynext();
			-- copy_next_event_init();
            print("load copy next\n");
		end
    elseif(scr_id == _G.SCR_SCAN_HOME) then
		if(_G.guider_ui.scanhome==nil) then
			scanhome.setup_scr_scanhome(_G.guider_ui);
            scr = _G.guider_ui.scanhome;
			printer.scan_home_event_init();
            print("load scan home\n");
		end
    elseif(scr_id == SCR_PRT_HOME) then
		if(_G.guider_ui.prthome~=nil) then
			scr = _G.guider_ui.prthome;
			prthome.setup_scr_prthome(_G.guider_ui);
			-- prt_home_event_init();
            print("load prt home\n");
		end
    elseif(scr_id == SCR_PRT_USB) then
		if(_G.guider_ui.prtusb==nil) then
			scr = _G.guider_ui.prtusb;
			prtusb.setup_scr_prtusb(_G.guider_ui);
			-- prt_usb_event_init();
            print("load prt usb\n");
		end
    elseif(scr_id == SCR_PRT_MB) then
		if(_G.guider_ui.prtmb==nil) then
			prtmb.setup_scr_prtmb(_G.guider_ui);
            scr = _G.guider_ui.prtmb;
			-- prt_mb_event_init();
            print("load prt mb\n");
		end
    elseif(scr_id == SCR_PRT_IT) then
		if(_G.guider_ui.printit==nil) then
			printit.setup_scr_printit(_G.guider_ui);
            scr = _G.guider_ui.printit;
			-- prtit_event_init();
            print("load prt it\n");
		end
    elseif(scr_id == SCR_SETUP) then
		if(_G.guider_ui.setup==nil) then
			setup.setup_scr_setup(_G.guider_ui);
			scr = _G.guider_ui.setup;
			setup_event_init();
			print("load setup\n");
		end
    elseif(scr_id == SCR_LOADER) then
		if(_G.guider_ui.loader==nil) then
			loader.setup_scr_loader(_G.guider_ui);
            scr = _G.guider_ui.loader;
			-- loader_event_init();
		end
    elseif(scr_id == SCR_SAVED) then
		if(_G.guider_ui.saved==nil) then
			scr = _G.guider_ui.saved;
			-- setup_scr_saved(ui);
			-- saved_event_init();
		end
	end

    lvgl.scr_load(scr);
    old_scr = get_scr_by_id(cur_scr);
    lvgl.obj_clean(old_scr);
    lvgl.obj_del(old_scr);

    old_scr = nil;
    cur_scr = scr_id;
end

local function home_imgbtncopyevent_handler( obj, event)
	if event == lvgl.EVENT_PRESSED then
		guider_load_screen(SCR_LOADER)
		add_loader(load_copy)
	end
end
local function home_imgbtnsetevent_handler( obj, event)
	if event == lvgl.EVENT_PRESSED then
		printer.guider_load_screen(SCR_SETUP)
		printer.demo_printer_anim_in_all(_G.guider_ui.setup, 200)
	end
end
local function home_imgbtnscanevent_handler( obj,  event)
	if event == lvgl.EVENT_PRESSED then
		printer.guider_load_screen(SCR_LOADER)
		-- add_loader(load_scan)
	end
end
local function home_imgbtnprtevent_handler( obj, event)
	if event == lvgl.EVENT_PRESSED then
		custom.guider_load_screen(SCR_LOADER)
		custom.add_loader(custom.load_print)
	end
end

local function events_init_home(ui)
	-- lvgl.obj_set_event_cb(ui.home_imgbtncopy, home_imgbtncopyevent_handler)
	lvgl.obj_set_event_cb(ui.home_imgbtnset, home_imgbtnsetevent_handler)
	lvgl.obj_set_event_cb(ui.home_imgbtnscan, home_imgbtnscanevent_handler)
	-- lvgl.obj_set_event_cb(ui.home_imgbtnprt, home_imgbtnprtevent_handler)
end

function printer.setup_scr_home(ui)
	--Write codes home
	ui.home = lvgl.obj_create(nil, nil)

	--Write codes home_cont1
	ui.home_cont1 = lvgl.cont_create(ui.home, nil)

	--Write style lvgl.CONT_PART_MAIN for home_cont1
	-- local style_home_cont1_main
	-- lvgl.style_init(style_home_cont1_main)
	local style_home_cont1_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_cont1_main
	lvgl.style_set_radius(style_home_cont1_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_bg_color(style_home_cont1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43))
	lvgl.style_set_bg_grad_color(style_home_cont1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43))
	lvgl.style_set_bg_grad_dir(style_home_cont1_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_home_cont1_main, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_border_color(style_home_cont1_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x99, 0x99, 0x99))
	lvgl.style_set_border_width(style_home_cont1_main, lvgl.STATE_DEFAULT, 1)
	lvgl.style_set_border_opa(style_home_cont1_main, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_pad_left(style_home_cont1_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_right(style_home_cont1_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_top(style_home_cont1_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_bottom(style_home_cont1_main, lvgl.STATE_DEFAULT, 0)
	lvgl.obj_add_style(ui.home_cont1, lvgl.CONT_PART_MAIN, style_home_cont1_main)
	lvgl.obj_set_pos(ui.home_cont1, 0, 0)
	lvgl.obj_set_size(ui.home_cont1, 480, 100)
	lvgl.obj_set_click(ui.home_cont1, false)
	lvgl.cont_set_layout(ui.home_cont1, lvgl.LAYOUT_OFF)
	lvgl.cont_set_fit(ui.home_cont1, lvgl.FIT_NONE)

	--Write codes home_whitebg
	ui.home_whitebg = lvgl.cont_create(ui.home, nil)

	--Write style lvgl.CONT_PART_MAIN for home_whitebg
	-- local style_home_whitebg_main
	-- lvgl.style_init(style_home_whitebg_main)
	local style_home_whitebg_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_whitebg_main
	lvgl.style_set_radius(style_home_whitebg_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_bg_color(style_home_whitebg_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff))
	lvgl.style_set_bg_grad_color(style_home_whitebg_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff))
	lvgl.style_set_bg_grad_dir(style_home_whitebg_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_home_whitebg_main, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_border_color(style_home_whitebg_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x99, 0x99, 0x99))
	lvgl.style_set_border_width(style_home_whitebg_main, lvgl.STATE_DEFAULT, 1)
	lvgl.style_set_border_opa(style_home_whitebg_main, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_pad_left(style_home_whitebg_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_right(style_home_whitebg_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_top(style_home_whitebg_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_bottom(style_home_whitebg_main, lvgl.STATE_DEFAULT, 0)
	lvgl.obj_add_style(ui.home_whitebg, lvgl.CONT_PART_MAIN, style_home_whitebg_main)
	lvgl.obj_set_pos(ui.home_whitebg, 0, 100)
	lvgl.obj_set_size(ui.home_whitebg, 480, 172)
	lvgl.obj_set_click(ui.home_whitebg, false)
	lvgl.cont_set_layout(ui.home_whitebg, lvgl.LAYOUT_OFF)
	lvgl.cont_set_fit(ui.home_whitebg, lvgl.FIT_NONE)

	--Write codes home_cont2
	ui.home_cont2 = lvgl.cont_create(ui.home, nil)

	--Write style lvgl.CONT_PART_MAIN for home_cont2
	-- local style_home_cont2_main
	-- lvgl.style_init(style_home_cont2_main)
	local style_home_cont2_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_cont2_main
	lvgl.style_set_radius(style_home_cont2_main, lvgl.STATE_DEFAULT, 10)
	lvgl.style_set_bg_color(style_home_cont2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff))
	lvgl.style_set_bg_grad_color(style_home_cont2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff))
	lvgl.style_set_bg_grad_dir(style_home_cont2_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_home_cont2_main, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_border_color(style_home_cont2_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x99, 0x99, 0x99))
	lvgl.style_set_border_width(style_home_cont2_main, lvgl.STATE_DEFAULT, 1)
	lvgl.style_set_border_opa(style_home_cont2_main, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_pad_left(style_home_cont2_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_right(style_home_cont2_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_top(style_home_cont2_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_bottom(style_home_cont2_main, lvgl.STATE_DEFAULT, 0)
	lvgl.obj_add_style(ui.home_cont2, lvgl.CONT_PART_MAIN, style_home_cont2_main)
	lvgl.obj_set_pos(ui.home_cont2, 40, 80)
	lvgl.obj_set_size(ui.home_cont2, 380, 120)
	lvgl.obj_set_click(ui.home_cont2, false)
	lvgl.cont_set_layout(ui.home_cont2, lvgl.LAYOUT_OFF)
	lvgl.cont_set_fit(ui.home_cont2, lvgl.FIT_NONE)

	--Write codes home_labeldate
	ui.home_labeldate = lvgl.label_create(ui.home, nil)
	lvgl.label_set_text(ui.home_labeldate, "20 Nov 2020 08:08")
	lvgl.label_set_long_mode(ui.home_labeldate, lvgl.LABEL_LONG_BREAK)
	lvgl.label_set_align(ui.home_labeldate, lvgl.LABEL_ALIGN_CENTER)

	--Write style lvgl.LABEL_PART_MAIN for home_labeldate
	-- local style_home_labeldate_main
	-- lvgl.style_init(style_home_labeldate_main)
	local style_home_labeldate_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_labeldate_main
	lvgl.style_set_radius(style_home_labeldate_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_bg_color(style_home_labeldate_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43))
	lvgl.style_set_bg_grad_color(style_home_labeldate_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x2f, 0x32, 0x43))
	lvgl.style_set_bg_grad_dir(style_home_labeldate_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_home_labeldate_main, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_text_color(style_home_labeldate_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_text_font(style_home_labeldate_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_18"))
	lvgl.style_set_text_letter_space(style_home_labeldate_main, lvgl.STATE_DEFAULT, 2)
	lvgl.style_set_pad_left(style_home_labeldate_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_right(style_home_labeldate_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_top(style_home_labeldate_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_bottom(style_home_labeldate_main, lvgl.STATE_DEFAULT, 0)
	lvgl.obj_add_style(ui.home_labeldate, lvgl.LABEL_PART_MAIN, style_home_labeldate_main)
	lvgl.obj_set_pos(ui.home_labeldate, 240, 30)
	lvgl.obj_set_size(ui.home_labeldate, 225, 0)

	--Write codes home_imgbtncopy
	ui.home_imgbtncopy = lvgl.imgbtn_create(ui.home, nil)

	--Write style lvgl.IMGBTN_PART_MAIN for home_imgbtncopy
	-- local style_home_imgbtncopy_main
	-- lvgl.style_init(style_home_imgbtncopy_main)
	local style_home_imgbtncopy_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_imgbtncopy_main
	lvgl.style_set_text_color(style_home_imgbtncopy_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.style_set_image_recolor(style_home_imgbtncopy_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_image_recolor_opa(style_home_imgbtncopy_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_image_opa(style_home_imgbtncopy_main, lvgl.STATE_DEFAULT, 255)

	--Write style state: lvgl.STATE_PRESSED for style_home_imgbtncopy_main
	lvgl.style_set_text_color(style_home_imgbtncopy_main, lvgl.STATE_PRESSED, lvgl.color_make(0xFF, 0x33, 0xFF))
	lvgl.style_set_image_recolor(style_home_imgbtncopy_main, lvgl.STATE_PRESSED, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.style_set_image_recolor_opa(style_home_imgbtncopy_main, lvgl.STATE_PRESSED, 0)

	--Write style state: lvgl.STATE_CHECKED for style_home_imgbtncopy_main
	lvgl.style_set_text_color(style_home_imgbtncopy_main, lvgl.STATE_CHECKED, lvgl.color_make(0xFF, 0x33, 0xFF))
	lvgl.style_set_image_recolor(style_home_imgbtncopy_main, lvgl.STATE_CHECKED, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.style_set_image_recolor_opa(style_home_imgbtncopy_main, lvgl.STATE_CHECKED, 0)
	lvgl.obj_add_style(ui.home_imgbtncopy, lvgl.IMGBTN_PART_MAIN, style_home_imgbtncopy_main)
	lvgl.obj_set_pos(ui.home_imgbtncopy, 50, 90)
	lvgl.obj_set_size(ui.home_imgbtncopy, 85, 100)
	lvgl.imgbtn_set_src(ui.home_imgbtncopy,lvgl.BTN_STATE_RELEASED,"/images/btn_bg_1_alpha_85x100.png")
	lvgl.imgbtn_set_src(ui.home_imgbtncopy,lvgl.BTN_STATE_PRESSED,"/images/btn_bg_1_alpha_85x100.png")
	lvgl.imgbtn_set_src(ui.home_imgbtncopy,lvgl.BTN_STATE_CHECKED_RELEASED,"/images/btn_bg_1_alpha_85x100.png")
	lvgl.imgbtn_set_src(ui.home_imgbtncopy,lvgl.BTN_STATE_CHECKED_PRESSED,"/images/btn_bg_1_alpha_85x100.png")

	--Write codes home_labelcopy
	ui.home_labelcopy = lvgl.label_create(ui.home, nil)
	lvgl.label_set_text(ui.home_labelcopy, "COPY")
	lvgl.label_set_long_mode(ui.home_labelcopy, lvgl.LABEL_LONG_BREAK)
	lvgl.label_set_align(ui.home_labelcopy, lvgl.LABEL_ALIGN_CENTER)

	--Write style lvgl.LABEL_PART_MAIN for home_labelcopy
	-- local style_home_labelcopy_main
	-- lvgl.style_init(style_home_labelcopy_main)
	local style_home_labelcopy_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_labelcopy_main
	lvgl.style_set_radius(style_home_labelcopy_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_bg_color(style_home_labelcopy_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_home_labelcopy_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_home_labelcopy_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_home_labelcopy_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_text_color(style_home_labelcopy_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.style_set_text_font(style_home_labelcopy_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_16"))
	lvgl.style_set_text_letter_space(style_home_labelcopy_main, lvgl.STATE_DEFAULT, 2)
	lvgl.style_set_pad_left(style_home_labelcopy_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_right(style_home_labelcopy_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_top(style_home_labelcopy_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_bottom(style_home_labelcopy_main, lvgl.STATE_DEFAULT, 0)
	lvgl.obj_add_style(ui.home_labelcopy, lvgl.LABEL_PART_MAIN, style_home_labelcopy_main)
	lvgl.obj_set_pos(ui.home_labelcopy, 60, 155)
	lvgl.obj_set_size(ui.home_labelcopy, 62, 0)

	--Write codes home_imgbtnset
	ui.home_imgbtnset = lvgl.imgbtn_create(ui.home, nil)

	--Write style lvgl.IMGBTN_PART_MAIN for home_imgbtnset
	-- local style_home_imgbtnset_main
	-- lvgl.style_init(style_home_imgbtnset_main)
	local style_home_imgbtnset_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_imgbtnset_main
	lvgl.style_set_text_color(style_home_imgbtnset_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.style_set_image_recolor(style_home_imgbtnset_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_image_recolor_opa(style_home_imgbtnset_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_image_opa(style_home_imgbtnset_main, lvgl.STATE_DEFAULT, 255)

	--Write style state: lvgl.STATE_PRESSED for style_home_imgbtnset_main
	lvgl.style_set_text_color(style_home_imgbtnset_main, lvgl.STATE_PRESSED, lvgl.color_make(0xFF, 0x33, 0xFF))
	lvgl.style_set_image_recolor(style_home_imgbtnset_main, lvgl.STATE_PRESSED, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.style_set_image_recolor_opa(style_home_imgbtnset_main, lvgl.STATE_PRESSED, 0)

	--Write style state: lvgl.STATE_CHECKED for style_home_imgbtnset_main
	lvgl.style_set_text_color(style_home_imgbtnset_main, lvgl.STATE_CHECKED, lvgl.color_make(0xFF, 0x33, 0xFF))
	lvgl.style_set_image_recolor(style_home_imgbtnset_main, lvgl.STATE_CHECKED, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.style_set_image_recolor_opa(style_home_imgbtnset_main, lvgl.STATE_CHECKED, 0)
	lvgl.obj_add_style(ui.home_imgbtnset, lvgl.IMGBTN_PART_MAIN, style_home_imgbtnset_main)
	lvgl.obj_set_pos(ui.home_imgbtnset, 320, 90)
	lvgl.obj_set_size(ui.home_imgbtnset, 85, 100)
	lvgl.imgbtn_set_src(ui.home_imgbtnset,lvgl.BTN_STATE_RELEASED,"/images/btn4_alpha_85x100.png")
	lvgl.imgbtn_set_src(ui.home_imgbtnset,lvgl.BTN_STATE_PRESSED,"/images/btn4_alpha_85x100.png")
	lvgl.imgbtn_set_src(ui.home_imgbtnset,lvgl.BTN_STATE_CHECKED_RELEASED,"/images/btn4_alpha_85x100.png")
	lvgl.imgbtn_set_src(ui.home_imgbtnset,lvgl.BTN_STATE_CHECKED_PRESSED,"/images/btn4_alpha_85x100.png")

	--Write codes home_imgbtnscan
	ui.home_imgbtnscan = lvgl.imgbtn_create(ui.home, nil)

	--Write style lvgl.IMGBTN_PART_MAIN for home_imgbtnscan
	-- local style_home_imgbtnscan_main
	-- lvgl.style_init(style_home_imgbtnscan_main)
	local style_home_imgbtnscan_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_imgbtnscan_main
	lvgl.style_set_text_color(style_home_imgbtnscan_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.style_set_image_recolor(style_home_imgbtnscan_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_image_recolor_opa(style_home_imgbtnscan_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_image_opa(style_home_imgbtnscan_main, lvgl.STATE_DEFAULT, 255)

	--Write style state: lvgl.STATE_PRESSED for style_home_imgbtnscan_main
	lvgl.style_set_text_color(style_home_imgbtnscan_main, lvgl.STATE_PRESSED, lvgl.color_make(0xFF, 0x33, 0xFF))
	lvgl.style_set_image_recolor(style_home_imgbtnscan_main, lvgl.STATE_PRESSED, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.style_set_image_recolor_opa(style_home_imgbtnscan_main, lvgl.STATE_PRESSED, 0)

	--Write style state: lvgl.STATE_CHECKED for style_home_imgbtnscan_main
	lvgl.style_set_text_color(style_home_imgbtnscan_main, lvgl.STATE_CHECKED, lvgl.color_make(0xFF, 0x33, 0xFF))
	lvgl.style_set_image_recolor(style_home_imgbtnscan_main, lvgl.STATE_CHECKED, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.style_set_image_recolor_opa(style_home_imgbtnscan_main, lvgl.STATE_CHECKED, 0)
	lvgl.obj_add_style(ui.home_imgbtnscan, lvgl.IMGBTN_PART_MAIN, style_home_imgbtnscan_main)
	lvgl.obj_set_pos(ui.home_imgbtnscan, 140, 90)
	lvgl.obj_set_size(ui.home_imgbtnscan, 85, 100)
	lvgl.imgbtn_set_src(ui.home_imgbtnscan,lvgl.BTN_STATE_RELEASED,"/images/btn2_alpha_85x100.png")
	lvgl.imgbtn_set_src(ui.home_imgbtnscan,lvgl.BTN_STATE_PRESSED,"/images/btn2_alpha_85x100.png")
	lvgl.imgbtn_set_src(ui.home_imgbtnscan,lvgl.BTN_STATE_CHECKED_RELEASED,"/images/btn2_alpha_85x100.png")
	lvgl.imgbtn_set_src(ui.home_imgbtnscan,lvgl.BTN_STATE_CHECKED_PRESSED,"/images/btn2_alpha_85x100.png")

	--Write codes home_imgbtnprt
	ui.home_imgbtnprt = lvgl.imgbtn_create(ui.home, nil)

	--Write style lvgl.IMGBTN_PART_MAIN for home_imgbtnprt
	-- local style_home_imgbtnprt_main
	-- lvgl.style_init(style_home_imgbtnprt_main)
	local style_home_imgbtnprt_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_imgbtnprt_main
	lvgl.style_set_text_color(style_home_imgbtnprt_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.style_set_image_recolor(style_home_imgbtnprt_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_image_recolor_opa(style_home_imgbtnprt_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_image_opa(style_home_imgbtnprt_main, lvgl.STATE_DEFAULT, 255)

	--Write style state: lvgl.STATE_PRESSED for style_home_imgbtnprt_main
	lvgl.style_set_text_color(style_home_imgbtnprt_main, lvgl.STATE_PRESSED, lvgl.color_make(0xFF, 0x33, 0xFF))
	lvgl.style_set_image_recolor(style_home_imgbtnprt_main, lvgl.STATE_PRESSED, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.style_set_image_recolor_opa(style_home_imgbtnprt_main, lvgl.STATE_PRESSED, 0)

	--Write style state: lvgl.STATE_CHECKED for style_home_imgbtnprt_main
	lvgl.style_set_text_color(style_home_imgbtnprt_main, lvgl.STATE_CHECKED, lvgl.color_make(0xFF, 0x33, 0xFF))
	lvgl.style_set_image_recolor(style_home_imgbtnprt_main, lvgl.STATE_CHECKED, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.style_set_image_recolor_opa(style_home_imgbtnprt_main, lvgl.STATE_CHECKED, 0)
	lvgl.obj_add_style(ui.home_imgbtnprt, lvgl.IMGBTN_PART_MAIN, style_home_imgbtnprt_main)
	lvgl.obj_set_pos(ui.home_imgbtnprt, 230, 90)
	lvgl.obj_set_size(ui.home_imgbtnprt, 85, 100)
	lvgl.imgbtn_set_src(ui.home_imgbtnprt,lvgl.BTN_STATE_RELEASED,"/images//btn3_alpha_85x100.png")
	lvgl.imgbtn_set_src(ui.home_imgbtnprt,lvgl.BTN_STATE_PRESSED,"/images//btn3_alpha_85x100.png")
	lvgl.imgbtn_set_src(ui.home_imgbtnprt,lvgl.BTN_STATE_CHECKED_RELEASED,"/images//btn3_alpha_85x100.png")
	lvgl.imgbtn_set_src(ui.home_imgbtnprt,lvgl.BTN_STATE_CHECKED_PRESSED,"/images//btn3_alpha_85x100.png")

	--Write codes home_labelscan
	ui.home_labelscan = lvgl.label_create(ui.home, nil)
	lvgl.label_set_text(ui.home_labelscan, "SCAN")
	lvgl.label_set_long_mode(ui.home_labelscan, lvgl.LABEL_LONG_BREAK)
	lvgl.label_set_align(ui.home_labelscan, lvgl.LABEL_ALIGN_CENTER)

	--Write style lvgl.LABEL_PART_MAIN for home_labelscan
	-- local style_home_labelscan_main
	-- lvgl.style_init(style_home_labelscan_main)
	local style_home_labelscan_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_labelscan_main
	lvgl.style_set_radius(style_home_labelscan_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_bg_color(style_home_labelscan_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_home_labelscan_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_home_labelscan_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_home_labelscan_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_text_color(style_home_labelscan_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.style_set_text_font(style_home_labelscan_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_16"))
	lvgl.style_set_text_letter_space(style_home_labelscan_main, lvgl.STATE_DEFAULT, 2)
	lvgl.style_set_pad_left(style_home_labelscan_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_right(style_home_labelscan_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_top(style_home_labelscan_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_bottom(style_home_labelscan_main, lvgl.STATE_DEFAULT, 0)
	lvgl.obj_add_style(ui.home_labelscan, lvgl.LABEL_PART_MAIN, style_home_labelscan_main)
	lvgl.obj_set_pos(ui.home_labelscan, 150, 155)
	lvgl.obj_set_size(ui.home_labelscan, 60, 0)

	--Write codes home_labelprt
	ui.home_labelprt = lvgl.label_create(ui.home, nil)
	lvgl.label_set_text(ui.home_labelprt, "PRINT")
	lvgl.label_set_long_mode(ui.home_labelprt, lvgl.LABEL_LONG_BREAK)
	lvgl.label_set_align(ui.home_labelprt, lvgl.LABEL_ALIGN_CENTER)

	--Write style lvgl.LABEL_PART_MAIN for home_labelprt
	-- local style_home_labelprt_main
	-- lvgl.style_init(style_home_labelprt_main)
	local style_home_labelprt_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_labelprt_main
	lvgl.style_set_radius(style_home_labelprt_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_bg_color(style_home_labelprt_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_home_labelprt_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_home_labelprt_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_home_labelprt_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_text_color(style_home_labelprt_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.style_set_text_font(style_home_labelprt_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_16"))
	lvgl.style_set_text_letter_space(style_home_labelprt_main, lvgl.STATE_DEFAULT, 2)
	lvgl.style_set_pad_left(style_home_labelprt_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_right(style_home_labelprt_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_top(style_home_labelprt_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_bottom(style_home_labelprt_main, lvgl.STATE_DEFAULT, 0)
	lvgl.obj_add_style(ui.home_labelprt, lvgl.LABEL_PART_MAIN, style_home_labelprt_main)
	lvgl.obj_set_pos(ui.home_labelprt, 240, 155)
	lvgl.obj_set_size(ui.home_labelprt, 70, 0)

	--Write codes home_labelset
	ui.home_labelset = lvgl.label_create(ui.home, nil)
	lvgl.label_set_text(ui.home_labelset, "SETUP")
	lvgl.label_set_long_mode(ui.home_labelset, lvgl.LABEL_LONG_BREAK)
	lvgl.label_set_align(ui.home_labelset, lvgl.LABEL_ALIGN_CENTER)

	--Write style lvgl.LABEL_PART_MAIN for home_labelset
	-- local style_home_labelset_main
	-- lvgl.style_init(style_home_labelset_main)
	local style_home_labelset_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_labelset_main
	lvgl.style_set_radius(style_home_labelset_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_bg_color(style_home_labelset_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_home_labelset_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_home_labelset_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_home_labelset_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_text_color(style_home_labelset_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.style_set_text_font(style_home_labelset_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_16"))
	lvgl.style_set_text_letter_space(style_home_labelset_main, lvgl.STATE_DEFAULT, 2)
	lvgl.style_set_pad_left(style_home_labelset_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_right(style_home_labelset_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_top(style_home_labelset_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_bottom(style_home_labelset_main, lvgl.STATE_DEFAULT, 0)
	lvgl.obj_add_style(ui.home_labelset, lvgl.LABEL_PART_MAIN, style_home_labelset_main)
	lvgl.obj_set_pos(ui.home_labelset, 328, 155)
	lvgl.obj_set_size(ui.home_labelset, 75, 0)

	--Write codes home_labelnote
	ui.home_labelnote = lvgl.label_create(ui.home, nil)
	lvgl.label_set_text(ui.home_labelnote, "What do you want to do today?")
	lvgl.label_set_long_mode(ui.home_labelnote, lvgl.LABEL_LONG_BREAK)
	lvgl.label_set_align(ui.home_labelnote, lvgl.LABEL_ALIGN_CENTER)

	--Write style lvgl.LABEL_PART_MAIN for home_labelnote
	-- local style_home_labelnote_main
	-- lvgl.style_init(style_home_labelnote_main)
	local style_home_labelnote_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_labelnote_main
	lvgl.style_set_radius(style_home_labelnote_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_bg_color(style_home_labelnote_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff))
	lvgl.style_set_bg_grad_color(style_home_labelnote_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff))
	lvgl.style_set_bg_grad_dir(style_home_labelnote_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_home_labelnote_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_text_color(style_home_labelnote_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.style_set_text_font(style_home_labelnote_main, lvgl.STATE_DEFAULT, lvgl.font_get("opposans_m_14"))
	lvgl.style_set_text_letter_space(style_home_labelnote_main, lvgl.STATE_DEFAULT, 2)
	lvgl.style_set_pad_left(style_home_labelnote_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_right(style_home_labelnote_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_top(style_home_labelnote_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_bottom(style_home_labelnote_main, lvgl.STATE_DEFAULT, 0)
	lvgl.obj_add_style(ui.home_labelnote, lvgl.LABEL_PART_MAIN, style_home_labelnote_main)
	lvgl.obj_set_pos(ui.home_labelnote, 16, 225)
	lvgl.obj_set_size(ui.home_labelnote, 276, 0)

	--Write codes home_contbars
	ui.home_contbars = lvgl.cont_create(ui.home, nil)

	--Write style lvgl.CONT_PART_MAIN for home_contbars
	-- local style_home_contbars_main
	-- lvgl.style_init(style_home_contbars_main)
	local style_home_contbars_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_contbars_main
	lvgl.style_set_radius(style_home_contbars_main, lvgl.STATE_DEFAULT, 5)
	lvgl.style_set_bg_color(style_home_contbars_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff))
	lvgl.style_set_bg_grad_color(style_home_contbars_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xf6, 0xfa, 0xff))
	lvgl.style_set_bg_grad_dir(style_home_contbars_main, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_home_contbars_main, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_border_color(style_home_contbars_main, lvgl.STATE_DEFAULT, lvgl.color_make(0x99, 0x99, 0x99))
	lvgl.style_set_border_width(style_home_contbars_main, lvgl.STATE_DEFAULT, 1)
	lvgl.style_set_border_opa(style_home_contbars_main, lvgl.STATE_DEFAULT, 255)
	lvgl.style_set_pad_left(style_home_contbars_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_right(style_home_contbars_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_top(style_home_contbars_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_pad_bottom(style_home_contbars_main, lvgl.STATE_DEFAULT, 0)
	lvgl.obj_add_style(ui.home_contbars, lvgl.CONT_PART_MAIN, style_home_contbars_main)
	lvgl.obj_set_pos(ui.home_contbars, 300, 205)
	lvgl.obj_set_size(ui.home_contbars, 150, 50)
	lvgl.obj_set_click(ui.home_contbars, false)
	lvgl.cont_set_layout(ui.home_contbars, lvgl.LAYOUT_OFF)
	lvgl.cont_set_fit(ui.home_contbars, lvgl.FIT_NONE)

	--Write codes home_bar1
	ui.home_bar1 = lvgl.bar_create(ui.home, nil)

	--Write style lvgl.BAR_PART_BG for home_bar1
	-- local style_home_bar1_bg
	-- lvgl.style_init(style_home_bar1_bg)
	local style_home_bar1_bg = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_bar1_bg
	lvgl.style_set_radius(style_home_bar1_bg, lvgl.STATE_DEFAULT, 5)
	lvgl.style_set_bg_color(style_home_bar1_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_home_bar1_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_home_bar1_bg, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_home_bar1_bg, lvgl.STATE_DEFAULT, 255)
	lvgl.obj_add_style(ui.home_bar1, lvgl.BAR_PART_BG, style_home_bar1_bg)

	--Write style lvgl.BAR_PART_INDIC for home_bar1
	-- local style_home_bar1_indic
	-- lvgl.style_init(style_home_bar1_indic)
	local style_home_bar1_indic = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_bar1_indic
	lvgl.style_set_radius(style_home_bar1_indic, lvgl.STATE_DEFAULT, 10)
	lvgl.style_set_bg_color(style_home_bar1_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_bg_grad_color(style_home_bar1_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0x01, 0xa2, 0xb1))
	lvgl.style_set_bg_grad_dir(style_home_bar1_indic, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_home_bar1_indic, lvgl.STATE_DEFAULT, 255)
	lvgl.obj_add_style(ui.home_bar1, lvgl.BAR_PART_INDIC, style_home_bar1_indic)
	lvgl.obj_set_pos(ui.home_bar1, 315, 220)
	lvgl.obj_set_size(ui.home_bar1, 20, 30)
	lvgl.bar_set_anim_time(ui.home_bar1,1000)
	lvgl.bar_set_value(ui.home_bar1,60,lvgl.ANIM_OFF)
	lvgl.bar_set_range(ui.home_bar1,0,100)

	--Write codes home_bar2
	ui.home_bar2 = lvgl.bar_create(ui.home, nil)

	--Write style lvgl.BAR_PART_BG for home_bar2
	-- local style_home_bar2_bg
	-- lvgl.style_init(style_home_bar2_bg)
	local style_home_bar2_bg = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_bar2_bg
	lvgl.style_set_radius(style_home_bar2_bg, lvgl.STATE_DEFAULT, 5)
	lvgl.style_set_bg_color(style_home_bar2_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_home_bar2_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_home_bar2_bg, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_home_bar2_bg, lvgl.STATE_DEFAULT, 255)
	lvgl.obj_add_style(ui.home_bar2, lvgl.BAR_PART_BG, style_home_bar2_bg)

	--Write style lvgl.BAR_PART_INDIC for home_bar2
	-- local style_home_bar2_indic
	-- lvgl.style_init(style_home_bar2_indic)
	local style_home_bar2_indic = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_bar2_indic
	lvgl.style_set_radius(style_home_bar2_indic, lvgl.STATE_DEFAULT, 10)
	lvgl.style_set_bg_color(style_home_bar2_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0x00, 0xff))
	lvgl.style_set_bg_grad_color(style_home_bar2_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0x00, 0xff))
	lvgl.style_set_bg_grad_dir(style_home_bar2_indic, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_home_bar2_indic, lvgl.STATE_DEFAULT, 255)
	lvgl.obj_add_style(ui.home_bar2, lvgl.BAR_PART_INDIC, style_home_bar2_indic)
	lvgl.obj_set_pos(ui.home_bar2, 350, 220)
	lvgl.obj_set_size(ui.home_bar2, 20, 30)
	lvgl.bar_set_anim_time(ui.home_bar2,1000)
	lvgl.bar_set_value(ui.home_bar2,40,lvgl.ANIM_OFF)
	lvgl.bar_set_range(ui.home_bar2,0,100)

	--Write codes home_bar3
	ui.home_bar3 = lvgl.bar_create(ui.home, nil)

	--Write style lvgl.BAR_PART_BG for home_bar3
	-- local style_home_bar3_bg
	-- lvgl.style_init(style_home_bar3_bg)
	local style_home_bar3_bg = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_bar3_bg
	lvgl.style_set_radius(style_home_bar3_bg, lvgl.STATE_DEFAULT, 5)
	lvgl.style_set_bg_color(style_home_bar3_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_home_bar3_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_home_bar3_bg, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_home_bar3_bg, lvgl.STATE_DEFAULT, 255)
	lvgl.obj_add_style(ui.home_bar3, lvgl.BAR_PART_BG, style_home_bar3_bg)

	--Write style lvgl.BAR_PART_INDIC for home_bar3
	-- local style_home_bar3_indic
	-- lvgl.style_init(style_home_bar3_indic)
	local style_home_bar3_indic = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_bar3_indic
	lvgl.style_set_radius(style_home_bar3_indic, lvgl.STATE_DEFAULT, 10)
	lvgl.style_set_bg_color(style_home_bar3_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0x80))
	lvgl.style_set_bg_grad_color(style_home_bar3_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0x80))
	lvgl.style_set_bg_grad_dir(style_home_bar3_indic, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_home_bar3_indic, lvgl.STATE_DEFAULT, 255)
	lvgl.obj_add_style(ui.home_bar3, lvgl.BAR_PART_INDIC, style_home_bar3_indic)
	lvgl.obj_set_pos(ui.home_bar3, 385, 220)
	lvgl.obj_set_size(ui.home_bar3, 20, 30)
	lvgl.bar_set_anim_time(ui.home_bar3,1000)
	lvgl.bar_set_value(ui.home_bar3,80,lvgl.ANIM_OFF)
	lvgl.bar_set_range(ui.home_bar3,0,100)

	--Write codes home_bar4
	ui.home_bar4 = lvgl.bar_create(ui.home, nil)

	--Write style lvgl.BAR_PART_BG for home_bar4
	-- local style_home_bar4_bg
	-- lvgl.style_init(style_home_bar4_bg)
	local style_home_bar4_bg = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_bar4_bg
	lvgl.style_set_radius(style_home_bar4_bg, lvgl.STATE_DEFAULT, 5)
	lvgl.style_set_bg_color(style_home_bar4_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_color(style_home_bar4_bg, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_bg_grad_dir(style_home_bar4_bg, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_home_bar4_bg, lvgl.STATE_DEFAULT, 255)
	lvgl.obj_add_style(ui.home_bar4, lvgl.BAR_PART_BG, style_home_bar4_bg)

	--Write style lvgl.BAR_PART_INDIC for home_bar4
	-- local style_home_bar4_indic
	-- lvgl.style_init(style_home_bar4_indic)
	local style_home_bar4_indic = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_bar4_indic
	lvgl.style_set_radius(style_home_bar4_indic, lvgl.STATE_DEFAULT, 10)
	lvgl.style_set_bg_color(style_home_bar4_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.style_set_bg_grad_color(style_home_bar4_indic, lvgl.STATE_DEFAULT, lvgl.color_make(0x00, 0x00, 0x00))
	lvgl.style_set_bg_grad_dir(style_home_bar4_indic, lvgl.STATE_DEFAULT, lvgl.GRAD_DIR_VER)
	lvgl.style_set_bg_opa(style_home_bar4_indic, lvgl.STATE_DEFAULT, 255)
	lvgl.obj_add_style(ui.home_bar4, lvgl.BAR_PART_INDIC, style_home_bar4_indic)
	lvgl.obj_set_pos(ui.home_bar4, 425, 220)
	lvgl.obj_set_size(ui.home_bar4, 20, 30)
	lvgl.bar_set_anim_time(ui.home_bar4,1000)
	lvgl.bar_set_value(ui.home_bar4,30,lvgl.ANIM_OFF)
	lvgl.bar_set_range(ui.home_bar4,0,100)

	--Write codes home_wifi
	ui.home_wifi = lvgl.img_create(ui.home, nil)

	--Write style lvgl.IMG_PART_MAIN for home_wifi
	-- local style_home_wifi_main
	-- lvgl.style_init(style_home_wifi_main)
	local style_home_wifi_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_wifi_main
	lvgl.style_set_image_recolor(style_home_wifi_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_image_recolor_opa(style_home_wifi_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_image_opa(style_home_wifi_main, lvgl.STATE_DEFAULT, 255)
	lvgl.obj_add_style(ui.home_wifi, lvgl.IMG_PART_MAIN, style_home_wifi_main)
	lvgl.obj_set_pos(ui.home_wifi, 56, 31)
	lvgl.obj_set_size(ui.home_wifi, 29, 19)
	lvgl.obj_set_click(ui.home_wifi, true)
	lvgl.img_set_src(ui.home_wifi,"/images/wifi_alpha_29x19.png")
	lvgl.img_set_pivot(ui.home_wifi, 0,0)
	lvgl.img_set_angle(ui.home_wifi, 0)

	--Write codes home_tel
	ui.home_tel = lvgl.img_create(ui.home, nil)

	--Write style lvgl.IMG_PART_MAIN for home_tel
	-- local style_home_tel_main
	-- lvgl.style_init(style_home_tel_main)
	local style_home_tel_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_tel_main
	lvgl.style_set_image_recolor(style_home_tel_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_image_recolor_opa(style_home_tel_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_image_opa(style_home_tel_main, lvgl.STATE_DEFAULT, 255)
	lvgl.obj_add_style(ui.home_tel, lvgl.IMG_PART_MAIN, style_home_tel_main)
	lvgl.obj_set_pos(ui.home_tel, 105, 30)
	lvgl.obj_set_size(ui.home_tel, 21, 21)
	lvgl.obj_set_click(ui.home_tel, true)
	lvgl.img_set_src(ui.home_tel,"/images/tel_alpha_21x21.png")
	lvgl.img_set_pivot(ui.home_tel, 0,0)
	lvgl.img_set_angle(ui.home_tel, 0)

	--Write codes home_eco
	ui.home_eco = lvgl.img_create(ui.home, nil)

	--Write style lvgl.IMG_PART_MAIN for home_eco
	-- local style_home_eco_main
	-- lvgl.style_init(style_home_eco_main)
	local style_home_eco_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_eco_main
	lvgl.style_set_image_recolor(style_home_eco_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_image_recolor_opa(style_home_eco_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_image_opa(style_home_eco_main, lvgl.STATE_DEFAULT, 255)
	lvgl.obj_add_style(ui.home_eco, lvgl.IMG_PART_MAIN, style_home_eco_main)
	lvgl.obj_set_pos(ui.home_eco, 147, 30)
	lvgl.obj_set_size(ui.home_eco, 21, 21)
	lvgl.obj_set_click(ui.home_eco, true)
	lvgl.img_set_src(ui.home_eco,"/images/eco_alpha_21x21.png")
	lvgl.img_set_pivot(ui.home_eco, 0,0)
	lvgl.img_set_angle(ui.home_eco, 0)

	--Write codes home_pc
	ui.home_pc = lvgl.img_create(ui.home, nil)

	--Write style lvgl.IMG_PART_MAIN for home_pc
	-- local style_home_pc_main
	-- lvgl.style_init(style_home_pc_main)
	local style_home_pc_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_pc_main
	lvgl.style_set_image_recolor(style_home_pc_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_image_recolor_opa(style_home_pc_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_image_opa(style_home_pc_main, lvgl.STATE_DEFAULT, 255)
	lvgl.obj_add_style(ui.home_pc, lvgl.IMG_PART_MAIN, style_home_pc_main)
	lvgl.obj_set_pos(ui.home_pc, 198, 30)
	lvgl.obj_set_size(ui.home_pc, 21, 21)
	lvgl.obj_set_click(ui.home_pc, true)
	lvgl.img_set_src(ui.home_pc,"/images/pc_alpha_21x21.png")
	lvgl.img_set_pivot(ui.home_pc, 0,0)
	lvgl.img_set_angle(ui.home_pc, 0)

	--Write codes home_imgcopy
	ui.home_imgcopy = lvgl.img_create(ui.home, nil)

	--Write style lvgl.IMG_PART_MAIN for home_imgcopy
	-- local style_home_imgcopy_main
	-- lvgl.style_init(style_home_imgcopy_main)
	local style_home_imgcopy_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_imgcopy_main
	lvgl.style_set_image_recolor(style_home_imgcopy_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_image_recolor_opa(style_home_imgcopy_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_image_opa(style_home_imgcopy_main, lvgl.STATE_DEFAULT, 255)
	lvgl.obj_add_style(ui.home_imgcopy, lvgl.IMG_PART_MAIN, style_home_imgcopy_main)
	lvgl.obj_set_pos(ui.home_imgcopy, 90, 108)
	lvgl.obj_set_size(ui.home_imgcopy, 29, 29)
	lvgl.obj_set_click(ui.home_imgcopy, true)
	lvgl.img_set_src(ui.home_imgcopy,"/images/copy_alpha_29x29.png")
	lvgl.img_set_pivot(ui.home_imgcopy, 0,0)
	lvgl.img_set_angle(ui.home_imgcopy, 0)

	--Write codes home_imgscan
	ui.home_imgscan = lvgl.img_create(ui.home, nil)

	--Write style lvgl.IMG_PART_MAIN for home_imgscan
	-- local style_home_imgscan_main
	-- lvgl.style_init(style_home_imgscan_main)
	local style_home_imgscan_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_imgscan_main
	lvgl.style_set_image_recolor(style_home_imgscan_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_image_recolor_opa(style_home_imgscan_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_image_opa(style_home_imgscan_main, lvgl.STATE_DEFAULT, 255)
	lvgl.obj_add_style(ui.home_imgscan, lvgl.IMG_PART_MAIN, style_home_imgscan_main)
	lvgl.obj_set_pos(ui.home_imgscan, 180, 108)
	lvgl.obj_set_size(ui.home_imgscan, 29, 29)
	lvgl.obj_set_click(ui.home_imgscan, true)
	lvgl.img_set_src(ui.home_imgscan,"/images/scan_alpha_29x29.png")
	lvgl.img_set_pivot(ui.home_imgscan, 0,0)
	lvgl.img_set_angle(ui.home_imgscan, 0)

	--Write codes home_imgprt
	ui.home_imgprt = lvgl.img_create(ui.home, nil)

	--Write style lvgl.IMG_PART_MAIN for home_imgprt
	-- local style_home_imgprt_main
	-- lvgl.style_init(style_home_imgprt_main)
	local style_home_imgprt_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_imgprt_main
	lvgl.style_set_image_recolor(style_home_imgprt_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_image_recolor_opa(style_home_imgprt_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_image_opa(style_home_imgprt_main, lvgl.STATE_DEFAULT, 255)
	lvgl.obj_add_style(ui.home_imgprt, lvgl.IMG_PART_MAIN, style_home_imgprt_main)
	lvgl.obj_set_pos(ui.home_imgprt, 270, 108)
	lvgl.obj_set_size(ui.home_imgprt, 29, 29)
	lvgl.obj_set_click(ui.home_imgprt, true)
	lvgl.img_set_src(ui.home_imgprt,"/images/print_alpha_29x29.png")
	lvgl.img_set_pivot(ui.home_imgprt, 0,0)
	lvgl.img_set_angle(ui.home_imgprt, 0)

	--Write codes home_imgset
	ui.home_imgset = lvgl.img_create(ui.home, nil)

	--Write style lvgl.IMG_PART_MAIN for home_imgset
	-- local style_home_imgset_main
	-- lvgl.style_init(style_home_imgset_main)
	local style_home_imgset_main = lvgl.style_create()

	--Write style state: lvgl.STATE_DEFAULT for style_home_imgset_main
	lvgl.style_set_image_recolor(style_home_imgset_main, lvgl.STATE_DEFAULT, lvgl.color_make(0xff, 0xff, 0xff))
	lvgl.style_set_image_recolor_opa(style_home_imgset_main, lvgl.STATE_DEFAULT, 0)
	lvgl.style_set_image_opa(style_home_imgset_main, lvgl.STATE_DEFAULT, 255)
	lvgl.obj_add_style(ui.home_imgset, lvgl.IMG_PART_MAIN, style_home_imgset_main)
	lvgl.obj_set_pos(ui.home_imgset, 360, 108)
	lvgl.obj_set_size(ui.home_imgset, 29, 29)
	lvgl.obj_set_click(ui.home_imgset, true)
	lvgl.img_set_src(ui.home_imgset,"/images/setup_alpha_29x29.png")
	lvgl.img_set_pivot(ui.home_imgset, 0,0)
	lvgl.img_set_angle(ui.home_imgset, 0)

	--Init events for screen
	events_init_home(ui)
end
local function en_click_anim_cb(btn,v)
    if(v >= 150) then
		if cur_scr==SCR_HOME then
			lvgl.obj_set_click(_G.guider_ui.home_imgbtncopy, true);
			lvgl.obj_set_click(_G.guider_ui.home_imgbtnprt, true);
			lvgl.obj_set_click(_G.guider_ui.home_imgbtnscan, true);
			lvgl.obj_set_click(_G.guider_ui.home_imgbtnset, true);
		elseif cur_scr==SCR_COPY_HOME then
			lvgl.obj_set_click(_G.guider_ui.copyhome_btncopyback, true);
		elseif cur_scr==SCR_COPY_NEXT then
			lvgl.obj_set_click(_G.guider_ui.copynext_print, true);
		elseif cur_scr==SCR_SCAN_HOME then
		elseif cur_scr==SCR_PRT_HOME then
		elseif cur_scr==SCR_PRT_USB then
		elseif cur_scr==SCR_PRT_MB then
		elseif cur_scr==SCR_PRT_IT then
		elseif cur_scr==SCR_SETUP then
		elseif cur_scr==SCR_LOADER then
		elseif cur_scr==SCR_SAVED then
		end
    end
end
function printer.scan_home_event_init()
    lvgl.obj_set_event_cb(_G.guider_ui.scanhome_btnscanback, load_disbtn_home_cb);
    lvgl.obj_add_style(_G.guider_ui.scanhome_btnscanback, lvgl.BTN_PART_MAIN, style_backbtn);
    -- lvgl.obj_set_event_cb(_G.guider_ui.scanhome_btnscansave, load_save_cb);
    -- lvgl.obj_set_event_cb(_G.guider_ui.scanhome_sliderhue, hue_slider_event_cb);
    -- lvgl.obj_set_event_cb(_G.guider_ui.scanhome_sliderbright, lightness_slider_event_cb);
    lvgl.obj_set_style_local_radius(_G.guider_ui.scanhome_img3, lvgl.IMG_PART_MAIN, lvgl.STATE_DEFAULT, 8);
    lvgl.obj_set_style_local_clip_corner(_G.guider_ui.scanhome_img3, lvgl.IMG_PART_MAIN, lvgl.STATE_DEFAULT, true);
    lvgl.obj_set_style_local_image_recolor_opa(_G.guider_ui.scanhome_img3, lvgl.IMG_PART_MAIN, lvgl.STATE_DEFAULT, 80);
end

function printer.event_cb()
    -- lvgl.style_init(style_backbtn);
	style_backbtn = lvgl.style_create()
    lvgl.style_set_value_str(style_backbtn, lvgl.STATE_DEFAULT, _G.LV_SYMBOL_LEFT);
    lvgl.style_set_value_color(style_backbtn, lvgl.STATE_DEFAULT, lvgl.color_hex(0xffffff));
    lvgl.style_set_value_color(style_backbtn, lvgl.STATE_PRESSED, lvgl.color_hex(0xc4c4c4));

    -- lvgl.style_init(style_upbtn);
	style_upbtn = lvgl.style_create()
    lvgl.style_set_value_str(style_upbtn, lvgl.STATE_DEFAULT, _G.LV_SYMBOL_UP);
    lvgl.style_set_value_color(style_upbtn, lvgl.STATE_DEFAULT, lvgl.color_hex(0xffffff));
    lvgl.style_set_value_color(style_upbtn, lvgl.STATE_PRESSED, lvgl.color_hex(0xc4c4c4));

    -- lvgl.style_init(style_downbtn);
	style_downbtn = lvgl.style_create()
    lvgl.style_set_value_str(style_downbtn, lvgl.STATE_DEFAULT, _G.LV_SYMBOL_DOWN);
    lvgl.style_set_value_color(style_downbtn, lvgl.STATE_DEFAULT, lvgl.color_hex(0xffffff));
    lvgl.style_set_value_color(style_downbtn, lvgl.STATE_PRESSED, lvgl.color_hex(0xc4c4c4));

    -- lvgl.style_init(arc_style);
	arc_style = lvgl.style_create()
    -- lvgl.style_init(img_style);
	img_style = lvgl.style_create()
    lvgl.style_set_border_width(arc_style, lvgl.STATE_DEFAULT, 0);

    lightness_act = 0;
    hue_act = 180;

    -- lvgl.anim_init(ani_en_btn_click);
	ani_en_btn_click = lvgl.anim_create()
    lvgl.anim_set_exec_cb(ani_en_btn_click, en_click_anim_cb);
    lvgl.anim_set_values(ani_en_btn_click, 0, 150);
    lvgl.anim_set_time(ani_en_btn_click, 150);
end

function printer.setup_ui(ui)
	printer.setup_scr_home(ui)
	lvgl.scr_load(ui.home)
end

function printer.events_init(ui)

end

function printer.custom_init(ui)
    printer.setup_scr_home(ui);
	printer.event_cb();
	home_event_init();
	lvgl.anim_set_var(ani_en_btn_click, ui.home_imgbtncopy);
    lvgl.anim_start(ani_en_btn_click);
	cur_scr = SCR_HOME;
	ui.copyhome = nil;
	ui.copynext = nil;
	ui.scanhome = nil;
	ui.prthome = nil;
	ui.prtusb = nil;
	ui.prtmb = nil;
	ui.printit = nil;
	ui.setup = nil;
	ui.loader = nil;
	ui.saved = nil;

	lvgl.scr_load(ui.home);
end


return printer
