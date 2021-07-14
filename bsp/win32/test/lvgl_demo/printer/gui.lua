
local home = require "home"
local custom = require "custom"
local gui = {}
_G.guider_ui = {}
function gui.setup_ui()
	home.setup_scr_home(_G.guider_ui)
    lvgl.scr_load(_G.guider_ui.home)
	custom.custom_init(_G.guider_ui)
end

return gui
