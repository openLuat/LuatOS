local testmem = {}

local sys = require "sys"

sys.taskInit(function()
    local count = 1
    while 1 do
        sys.wait(1000)
        log.info("luatos", "hi", count, os.date())
        log.info("luatos", rtos.meminfo())
        log.info("luatos", rtos.meminfo("sys"))
        count = count + 1
    end
end)

return testmem