

local sys = require "sys"
-- local gui = require "gui"
local printer = require "printer"

log.info("sys", "from win32")

_G.guider_ui = {}

sys.taskInit(function ()
    log.info("lvgl", lvgl.init(480,320))
	-- gui.setup_ui()
    printer.setup_ui(_G.guider_ui)
    printer.events_init(_G.guider_ui)
    printer.custom_init(_G.guider_ui)
    while true do
        sys.wait(500)
    end
end)

sys.run()
