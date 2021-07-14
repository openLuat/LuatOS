
local setup = require "setup"
-- local home = require "home"

local custom = {}

_G.SCR_HOME = 0
_G.SCR_COPY_HOME = 1
_G.SCR_COPY_NEXT = 2
_G.SCR_SCAN_HOME = 3
_G.SCR_PRT_HOME = 4
_G.SCR_PRT_USB = 5
_G.SCR_PRT_MB = 6
_G.SCR_PRT_IT = 7
_G.SCR_SETUP = 8
_G.SCR_LOADER = 9
_G.SCR_SAVED = 10

local cur_scr;

local ani_en_btn_click;

local printusbcnt = 1;
local copynextcnt = 1;
local hue_act;
local lightness_act;
local img_style;

local save_src = 0;

-- local function cnt_event_cb(obj,event)
--     if (event == lvgl.EVENT_PRESSED) then
--         if(_G.guider_ui.copynext == lvgl.scr_act()) then
--             if (obj == _G.guider_ui.copynext_up) then
--                 if (copynextcnt < 200)then
--                     copynextcnt = copynextcnt+1;
-- 				end
--                 lvgl.label_set_text(_G.guider_ui.copynext_labelcnt, string.format("%d",copynextcnt));
--             else
--                 if (copynextcnt > 1)then
--                     copynextcnt = copynextcnt-1
-- 				end
--                 lvgl.label_set_text(_G.guider_ui.copynext_labelcnt, string.format("%d",copynextcnt));
--             end
--         elseif (_G.guider_ui.prtusb == lvgl.scr_act()) then
--             if (obj == _G.guider_ui.prtusb_up) then
--                 if (printusbcnt < 200)then
--                     printusbcnt = printusbcnt+1;
-- 				end
--                 lvgl.label_set_text(_G.guider_ui.prtusb_labelcnt, string.format("%d",printusbcnt));
--             else
--                 if (printusbcnt > 1)then
--                     printusbcnt = printusbcnt-1;
-- 				end
--                 lvgl.label_set_text(_G.guider_ui.prtusb_labelcnt, string.format("%d",printusbcnt));
--             end
--         end
--     end
-- end

function custom.demo_printer_anim_in_all(obj,delay)
    -- local child = lvgl.obj_get_child_back(obj, nil);
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

-- local function loader_anim_cb(arc, v)
--     if v > 100 then v = 100 end
--     lvgl.arc_set_angles(arc, 270, v * 360 / 100 + 270)
-- 	lvgl.label_set_text(_G.guider_ui.loader_loadlabel, string.format("%d %%",v))
-- end

-- function custom.add_loader(end_cb)
--     -- lvgl.anim_t a;
-- 	lvgl.arc_set_angles(_G.guider_ui.loader_loadarc, 270, 270);
--     -- lvgl.anim_init(a);
-- 	local a = lvgl.anim_create()
--     lvgl.anim_set_exec_cb(a, loader_anim_cb);
--     lvgl.anim_set_ready_cb(a, end_cb);
--     lvgl.anim_set_values(a, 0, 110);
--     lvgl.anim_set_time(a, 1000);
--     lvgl.anim_set_var(a, _G.guider_ui.loader_loadarc);
--     lvgl.anim_start(a);
-- end

local function get_scr_by_id(scr_id)
    if(scr_id == _G.SCR_HOME) then
    --     return ui.home;
    -- elseif(scr_id == _G.SCR_COPY_HOME) then
    --     return ui.copyhome;
    -- elseif(scr_id == _G.SCR_COPY_NEXT) then
    --     return ui.copynext;
    -- elseif(scr_id == _G.SCR_SCAN_HOME) then
    --     return ui.scanhome;
    -- elseif(scr_id == _G.SCR_PRT_HOME) then
    --     return ui.prthome;
    -- elseif(scr_id == _G.SCR_PRT_USB) then
    --     return ui.prtusb;
    -- elseif(scr_id == _G.SCR_PRT_MB) then
    --     return ui.prtmb;
    -- elseif(scr_id == _G.SCR_PRT_IT) then
    --     return ui.printit;
    elseif(scr_id == _G.SCR_SETUP) then
        return _G.guider_ui.setup;
    -- elseif(scr_id == _G.SCR_LOADER) then
    --     return ui.loader;
    -- elseif(scr_id == _G.SCR_SAVED) then
    --     return ui.saved;
	end
    return nil;
end

local function load_disbtn_home_cb(obj,event)
	if (event == lvgl.EVENT_PRESSED) then
	   custom.guider_load_screen(_G.SCR_HOME)
   end
end

local function prt_mb_event_init()
    lvgl.obj_set_event_cb(_G.guider_ui.prtmb_btnback, load_disbtn_home_cb);
end
local function prtit_event_init()
    lvgl.obj_set_event_cb(_G.guider_ui.printit_btnprtitback, load_disbtn_home_cb);
end
local function setup_event_init()
    lvgl.obj_set_event_cb(_G.guider_ui.setup_btnsetback, load_disbtn_home_cb);
end
-- local function loader_event_init()
--     lvgl.obj_add_style(_G.guider_ui.loader_loadarc, lvgl.STATE_DEFAULT, arc_style);
-- end
local function saved_event_init()
    lvgl.obj_set_event_cb(_G.guider_ui.saved_btnsavecontinue, load_disbtn_home_cb);
end

local function home_event_init()
    lvgl.obj_set_click(_G.guider_ui.home_imgbtnscan, false);
    lvgl.obj_set_click(_G.guider_ui.home_imgbtnprt, false);
    lvgl.obj_set_click(_G.guider_ui.home_imgbtnset, false);
    lvgl.obj_set_click(_G.guider_ui.home_imgbtncopy, false);
    custom.demo_printer_anim_in_all(_G.guider_ui.home, 200);
end

function custom.guider_load_screen(scr_id)
    local scr = nil;
    local old_scr = nil;
	if(scr_id == _G.SCR_HOME) then
		-- if( _G.guider_ui.home==nil) then
		-- 	scr = _G.guider_ui.home
		-- 	home.setup_scr_home()
		-- 	home_event_init()
		-- 	lvgl.anim_set_var(ani_en_btn_click, _G.guider_ui.home_imgbtncopy)
		-- 	lvgl.anim_start(ani_en_btn_click)
		-- 	print("load home\n")
		-- end
    elseif(scr_id == _G.SCR_COPY_HOME) then
	-- 	if(ui.copyhome~=nil) then
	-- 		scr = ui.copyhome;
	-- 		setup_scr_copyhome();
	-- 		copy_home_event_init();
	-- 		lvgl.anim_set_var(ani_en_btn_click, ui.copyhome_btncopyback);
	-- 		lvgl.anim_start(ani_en_btn_click);
	-- 	end
    -- elseif(scr_id == _G.SCR_COPY_NEXT) then
	-- 	if(ui.copynext~=nil) then
	-- 		scr = ui.copynext;
	-- 		setup_scr_copynext();
	-- 		copy_next_event_init();
	-- 	end
    -- elseif(scr_id == _G.SCR_SCAN_HOME) then
	-- 	if(ui.scanhome~=nil) then
	-- 		scr = ui.scanhome;
	-- 		setup_scr_scanhome();
	-- 		scan_home_event_init();
	-- 	end
    -- elseif(scr_id == _G.SCR_PRT_HOME) then
	-- 	if(ui.prthome~=nil) then
	-- 		scr = ui.prthome;
	-- 		setup_scr_prthome(ui);
	-- 		prt_home_event_init();
	-- 	end
    -- elseif(scr_id == _G.SCR_PRT_USB) then
	-- 	if(ui.prtusb~=nil) then
	-- 		scr = ui.prtusb;
	-- 		setup_scr_prtusb(ui);
	-- 		prt_usb_event_init();
	-- 	end
    -- elseif(scr_id == _G.SCR_PRT_MB) then
	-- 	if(ui.prtmb~=nil) then
	-- 		scr = ui.prtmb;
	-- 		setup_scr_prtmb(ui);
	-- 		prt_mb_event_init();
	-- 	end
    -- elseif(scr_id == _G.SCR_PRT_IT) then
	-- 	if(ui.printit~=nil) then
	-- 		scr = ui.printit;
	-- 		setup_scr_printit(ui);
	-- 		prtit_event_init();
	-- 	end
    elseif(scr_id == _G.SCR_SETUP) then
		if(_G.guider_ui.setup==nil) then
			setup.setup_scr_setup(_G.guider_ui);
			scr = _G.guider_ui.setup;
			setup_event_init();
			print("load setup\n");
		end
    -- elseif(scr_id == _G.SCR_LOADER) then
	-- 	if(ui.loader~=nil) then
	-- 		scr = ui.loader;
	-- 		setup_scr_loader(ui);
	-- 		loader_event_init();
	-- 	end
    -- elseif(scr_id == _G.SCR_SAVED) then
	-- 	if(ui.saved~=nil) then
	-- 		scr = ui.saved;
	-- 		setup_scr_saved(ui);
	-- 		saved_event_init();
	-- 	end
	end

    lvgl.scr_load(scr);
    -- old_scr = get_scr_by_id(cur_scr);
    -- lvgl.obj_clean(old_scr);
    -- lvgl.obj_del(old_scr);

    -- old_scr = nil;
    -- cur_scr = scr_id;
end

-- function custom.load_home(a)
--     guider_load_screen(SCR_HOME);
-- end
-- function custom.load_print(a)
--     guider_load_screen(SCR_PRT_HOME);
--     lvgl.demo_printer_anim_in_all(_G.guider_ui.prthome, 200);
-- end
-- function custom.load_copy(a)
--     guider_load_screen(SCR_COPY_HOME);
--     lvgl.demo_printer_anim_in_all(_G.guider_ui.copyhome, 200);
-- end
-- function custom.load_setup(a)
--     guider_load_screen(SCR_SETUP);
--     lvgl.demo_printer_anim_in_all(_G.guider_ui.setup, 200);
-- end
-- function custom.load_scan(a)
--     guider_load_screen(SCR_SCAN_HOME);
--     lvgl.demo_printer_anim_in_all(_G.guider_ui.scanhome, 200);
-- end

-- function custom.load_save(a)
--     guider_load_screen(SCR_SAVED);
--     if (save_src == 1) then
--         lvgl.obj_set_x(_G.guider_ui.saved_label2, 187);
--         lvgl.label_set_text(_G.guider_ui.saved_label2, "File saved");
--     elseif (save_src == 2) then
--         lvgl.obj_set_x(_G.guider_ui.saved_label2, 157);
--         lvgl.label_set_text(_G.guider_ui.saved_label2, "Printing finished");
--     else
--         lvgl.obj_set_x(_G.guider_ui.saved_label2, 187);
--         lvgl.label_set_text(_G.guider_ui.saved_label2, "File saved");
--     end
--     lvgl.demo_printer_anim_in_all(_G.guider_ui.saved, 200);
-- end

local function en_click_anim_cb(btn,v)
    if(v >= 150) then
		if cur_scr==_G.SCR_HOME then
			lvgl.obj_set_click(_G.guider_ui.home_imgbtncopy, true);
			lvgl.obj_set_click(_G.guider_ui.home_imgbtnprt, true);
			lvgl.obj_set_click(_G.guider_ui.home_imgbtnscan, true);
			lvgl.obj_set_click(_G.guider_ui.home_imgbtnset, true);
		elseif cur_scr==_G.SCR_COPY_HOME then
			lvgl.obj_set_click(_G.guider_ui.copyhome_btncopyback, true);
		elseif cur_scr==_G.SCR_COPY_NEXT then
			lvgl.obj_set_click(_G.guider_ui.copynext_print, true);
		elseif cur_scr==_G.SCR_SCAN_HOME then
		elseif cur_scr==_G.SCR_PRT_HOME then
		elseif cur_scr==_G.SCR_PRT_USB then
		elseif cur_scr==_G.SCR_PRT_MB then
		elseif cur_scr==_G.SCR_PRT_IT then
		elseif cur_scr==_G.SCR_SETUP then
		elseif cur_scr==_G.SCR_LOADER then
		elseif cur_scr==_G.SCR_SAVED then
		end
    end
end

-- function custom.load_home_cb(obj,event)
-- 	if (event == lvgl.EVENT_PRESSED) then
-- 		guider_load_screen(SCR_HOME);
-- 		lvgl.demo_printer_anim_in_all(_G.guider_ui.home, 200);
-- 	end
-- end

-- function custom.load_copy_next_cb(obj,event)
--     if (event == lvgl.EVENT_PRESSED) then
--         guider_load_screen(SCR_COPY_NEXT);
--         lvgl.demo_printer_anim_in_all(_G.guider_ui.copynext, 200);

--         lvgl.anim_set_var(ani_en_btn_click, _G.guider_ui.copynext_print);
--         lvgl.anim_start(ani_en_btn_click);
--     end
-- end

-- function custom.load_print_finish_cb(obj,event)
--  	if (event == lvgl.EVENT_PRESSED) then
--         save_src = 2;
--         guider_load_screen(SCR_LOADER);
--         add_loader(load_save);
--     end
-- end




-- function custom.load_save_cb(obj,event)
--     if (event == lvgl.EVENT_PRESSED) then
--         guider_load_screen(SCR_LOADER);
--         save_src = 1;
--         add_loader(load_save);
--     end
-- end

-- function custom.load_print_usb_cb(obj,event)
--  	if (event == lvgl.EVENT_PRESSED) then
--         guider_load_screen(SCR_PRT_USB);
--         lvgl.demo_printer_anim_in_all(_G.guider_ui.prtusb, 200);
--     end
-- end

-- function custom.load_print_mobile_cb(obj,event)
--  	if (event == lvgl.EVENT_PRESSED) then
--         guider_load_screen(SCR_PRT_MB);
--         lvgl.demo_printer_anim_in_all(_G.guider_ui.prtmb, 200);
--     end
-- end

-- function custom.load_print_it_cb(obj,event)
--  	if (event == lvgl.EVENT_PRESSED) then
--         guider_load_screen(SCR_PRT_IT);
--         lvgl.demo_printer_anim_in_all(_G.guider_ui.printit, 200);
--     end
-- end
-- lvgl.color_t c;
-- function custom.scan_img_color_refr()
--     int16_t light = lightness_act - 80;
--     printf("adjust image\n");
--     if(_G.guider_ui.scanhome == lvgl.scr_act()) then
--         printf("adjust scan home image\n");
--         uint8_t s = light > 0 ? 100 - light : 100;
--         uint8_t v = light < 0 ? 100 + light : 100;
--         lvgl.color_t c = lvgl.color_hsv_to_rgb(hue_act, s, v);

--         lvgl.obj_set_style_local_image_recolor(_G.guider_ui.scanhome_img3, lvgl.IMG_PART_MAIN, lvgl.STATE_DEFAULT, c);

--     end else if (_G.guider_ui.copyhome == lvgl.scr_act()) then
--         printf("adjust copy home image\n");
--         uint8_t s = light > 0 ? 100 - light : 100;
--         uint8_t v = light < 0 ? 100 + light : 100;
--         c = lvgl.color_hsv_to_rgb(hue_act, s, v);

--         lvgl.obj_set_style_local_image_recolor(_G.guider_ui.copyhome_img3, lvgl.IMG_PART_MAIN, lvgl.STATE_DEFAULT, c);
--         //

--     end
-- end

-- function custom.hue_slider_event_cb(obj,event)
--     if (event == lvgl.EVENT_VALUE_CHANGED)then
--         hue_act = lvgl.slider_get_value(obj);
--         scan_img_color_refr();
--     end
-- end

-- function custom.lightness_slider_event_cb(obj,event)
--     if (event == lvgl.EVENT_VALUE_CHANGED)then
--         lightness_act = lvgl.slider_get_value(obj);
--         scan_img_color_refr();
--     end
-- end

local style_backbtn;
local style_upbtn;
local style_downbtn;
local arc_style;



-- function custom.copy_home_event_init()
--     lvgl.obj_set_event_cb(_G.guider_ui.copyhome_btncopyback, load_disbtn_home_cb);
--     lvgl.obj_add_style(_G.guider_ui.copyhome_btncopyback, lvgl.BTN_PART_MAIN, style_backbtn);
--     lvgl.obj_set_event_cb(_G.guider_ui.copyhome_btncopynext, load_copy_next_cb);
--     lvgl.obj_set_event_cb(_G.guider_ui.copyhome_sliderhue, hue_slider_event_cb);
--     lvgl.obj_set_event_cb(_G.guider_ui.copyhome_sliderbright, lightness_slider_event_cb);
--     lvgl.obj_set_style_local_radius(_G.guider_ui.copyhome_img3, lvgl.IMG_PART_MAIN, lvgl.STATE_DEFAULT, 8);
--     lvgl.obj_set_style_local_clip_corner(_G.guider_ui.copyhome_img3, lvgl.IMG_PART_MAIN, lvgl.STATE_DEFAULT, true);
--     lvgl.obj_set_style_local_image_recolor_opa(_G.guider_ui.copyhome_img3, lvgl.IMG_PART_MAIN, lvgl.STATE_DEFAULT, 80);

-- end
-- function custom.copy_next_event_init()
--     lvgl.obj_add_style(_G.guider_ui.copynext_btncopyback, lvgl.BTN_PART_MAIN, style_backbtn);
--     lvgl.obj_set_click(_G.guider_ui.copynext_print, false);
--     lvgl.obj_set_event_cb(_G.guider_ui.copynext_up, cnt_event_cb);
--     lvgl.obj_add_style(_G.guider_ui.copynext_up, lvgl.BTN_PART_MAIN, style_upbtn);
--     lvgl.obj_set_event_cb(_G.guider_ui.copynext_down, cnt_event_cb);
--     lvgl.obj_add_style(_G.guider_ui.copynext_down, lvgl.BTN_PART_MAIN, style_downbtn);
--     lvgl.obj_set_event_cb(_G.guider_ui.copynext_print, load_print_finish_cb);
--     lvgl.obj_set_event_cb(_G.guider_ui.copynext_btncopyback, load_disbtn_home_cb);
--     lvgl.obj_set_style_local_radius(_G.guider_ui.copynext_img3, lvgl.IMG_PART_MAIN, lvgl.STATE_DEFAULT, 5);
--     lvgl.obj_set_style_local_clip_corner(_G.guider_ui.copynext_img3, lvgl.IMG_PART_MAIN, lvgl.STATE_DEFAULT, true);
--     lvgl.obj_set_style_local_image_recolor_opa(_G.guider_ui.copynext_img3, lvgl.IMG_PART_MAIN, lvgl.STATE_DEFAULT, 80);
--     lvgl.obj_set_style_local_image_recolor(_G.guider_ui.copynext_img3, lvgl.IMG_PART_MAIN, lvgl.STATE_DEFAULT, c);
-- end
-- function custom.scan_home_event_init()
--     lvgl.obj_set_event_cb(_G.guider_ui.scanhome_btnscanback, load_disbtn_home_cb);
--     lvgl.obj_add_style(_G.guider_ui.scanhome_btnscanback, lvgl.BTN_PART_MAIN, style_backbtn);
--     lvgl.obj_set_event_cb(_G.guider_ui.scanhome_btnscansave, load_save_cb);
--     lvgl.obj_set_event_cb(_G.guider_ui.scanhome_sliderhue, hue_slider_event_cb);
--     lvgl.obj_set_event_cb(_G.guider_ui.scanhome_sliderbright, lightness_slider_event_cb);
--     lvgl.obj_set_style_local_radius(_G.guider_ui.scanhome_img3, lvgl.IMG_PART_MAIN, lvgl.STATE_DEFAULT, 8);
--     lvgl.obj_set_style_local_clip_corner(_G.guider_ui.scanhome_img3, lvgl.IMG_PART_MAIN, lvgl.STATE_DEFAULT, true);
--     lvgl.obj_set_style_local_image_recolor_opa(_G.guider_ui.scanhome_img3, lvgl.IMG_PART_MAIN, lvgl.STATE_DEFAULT, 80);

-- end
-- function custom.prt_home_event_init()
--     lvgl.obj_set_event_cb(_G.guider_ui.prthome_imgbtnusb, load_print_usb_cb);
--     lvgl.obj_set_event_cb(_G.guider_ui.prthome_imgbtnmobile, load_print_mobile_cb);
--     lvgl.obj_set_event_cb(_G.guider_ui.prthome_imgbtnit, load_print_it_cb);
--     lvgl.obj_set_event_cb(_G.guider_ui.prthome_btnprintback, load_disbtn_home_cb);
--     lvgl.obj_add_style(_G.guider_ui.prthome_btnprintback, lvgl.BTN_PART_MAIN, style_backbtn);

-- end
-- function custom.prt_usb_event_init()
--     lvgl.obj_add_style(_G.guider_ui.prtusb_back, lvgl.BTN_PART_MAIN, style_backbtn);
--     lvgl.obj_set_event_cb(_G.guider_ui.prtusb_back, load_disbtn_home_cb);
--     lvgl.obj_set_event_cb(_G.guider_ui.prtusb_btnprint, load_print_finish_cb);
--     lvgl.obj_set_event_cb(_G.guider_ui.prtusb_up, cnt_event_cb);
--     lvgl.obj_add_style(_G.guider_ui.prtusb_up, lvgl.BTN_PART_MAIN, style_upbtn);
--     lvgl.obj_set_event_cb(_G.guider_ui.prtusb_down, cnt_event_cb);
--     lvgl.obj_add_style(_G.guider_ui.prtusb_down, lvgl.BTN_PART_MAIN, style_downbtn);
-- end

function custom.event_cb()
    -- lvgl.style_init(style_backbtn);
	style_backbtn = lvgl.style_create()
    lvgl.style_set_value_str(style_backbtn, lvgl.STATE_DEFAULT, lvgl.SYMBOL_LEFT);
    lvgl.style_set_value_color(style_backbtn, lvgl.STATE_DEFAULT, lvgl.color_hex(0xffffff));
    lvgl.style_set_value_color(style_backbtn, lvgl.STATE_PRESSED, lvgl.color_hex(0xc4c4c4));

    -- lvgl.style_init(style_upbtn);
	style_upbtn = lvgl.style_create()
    lvgl.style_set_value_str(style_upbtn, lvgl.STATE_DEFAULT, lvgl.SYMBOL_UP);
    lvgl.style_set_value_color(style_upbtn, lvgl.STATE_DEFAULT, lvgl.color_hex(0xffffff));
    lvgl.style_set_value_color(style_upbtn, lvgl.STATE_PRESSED, lvgl.color_hex(0xc4c4c4));

    -- lvgl.style_init(style_downbtn);
	style_downbtn = lvgl.style_create()
    lvgl.style_set_value_str(style_downbtn, lvgl.STATE_DEFAULT, lvgl.SYMBOL_DOWN);
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


function custom.custom_init(ui)
    -- home.setup_scr_home(ui);
	-- custom.event_cb();
	-- home_event_init();
	-- lvgl.anim_set_var(ani_en_btn_click, ui.home_imgbtncopy);
    -- lvgl.anim_start(ani_en_btn_click);
	cur_scr = _G.SCR_HOME;
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

return custom
