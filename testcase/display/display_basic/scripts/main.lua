PROJECT = "display_pc_test"
VERSION = "1.0.0"
local sys = require("sys")

sys.taskInit(function()
    log.info("display", "start init")
    local ret, err = display.init("custom", {w = 240, h = 320, interface = "rgb"})
    log.info("display", "init ret", ret, err)

    display.fill(0, 0, 240, 320, 0xF800)
    log.info("display", "fill red done")

    display.flush()
    log.info("display", "flush done")

    sys.wait(1000)
    os.exit(0)
end)

sys.run()
