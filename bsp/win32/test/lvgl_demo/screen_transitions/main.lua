

local sys = require "sys"
local setup = require "setup_scr_screen"

log.info("sys", "from win32")

sys.taskInit(function ()
    sys.wait(1000)
    log.info("lvgl", lvgl.init(480,320))
	setup.setup_ui()
    while true do
        sys.wait(500)
    end
end)

sys.run()
