

local custom = require "custom"

local events = {}

local function home_imgbtncopyevent_handler( obj, event)
	if event == lvgl.EVENT_PRESSED then
		guider_load_screen(_G.SCR_LOADER)
		add_loader(load_copy)
	end
end

local function home_imgbtnsetevent_handler( obj, event)
	if event == lvgl.EVENT_PRESSED then
		custom.guider_load_screen(_G.SCR_SETUP)
		--custom.demo_printer_anim_in_all(_G.guider_ui.setup, 200)
	end
end

local function home_imgbtnscanevent_handler( obj,  event)
	if event == lvgl.EVENT_PRESSED then
		guider_load_screen(_G.SCR_LOADER)
		add_loader(load_scan)
	end
end
local function home_imgbtnprtevent_handler( obj, event)
	if event == lvgl.EVENT_PRESSED then
		custom.guider_load_screen(_G.SCR_LOADER)
		custom.add_loader(custom.load_print)
	end
end

function events.events_init_home(ui)
	-- lvgl.obj_set_event_cb(ui.home_imgbtncopy, home_imgbtncopyevent_handler)
	lvgl.obj_set_event_cb(ui.home_imgbtnset, home_imgbtnsetevent_handler)
	-- lvgl.obj_set_event_cb(ui.home_imgbtnscan, home_imgbtnscanevent_handler)
	-- lvgl.obj_set_event_cb(ui.home_imgbtnprt, home_imgbtnprtevent_handler)
end

return events
