

local sys = require "sys"

log.info("sys", "from win32")

sys.taskInit(function ()
    while true do
        log.info("hi", os.date())
        log.info("sys", rtos.meminfo("sys"))
        log.info("lua", rtos.meminfo("lua"))
        sys.wait(1000)
    end
end)

sys.run()
