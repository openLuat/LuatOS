
_G.sys = require("sys")

sys.taskInit(function()
    while 1 do
        sys.wait(1000)
        log.info("bsp", rtos.bsp())
    end
end)

sys.run()
