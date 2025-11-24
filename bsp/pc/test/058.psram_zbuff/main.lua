
local sys = require "sys"

function zbuff_abc()
    while true do
        local buff = zbuff.create(1024, 0, zbuff.HEAP_PSRAM)
        log.info("psram", rtos.meminfo("psram"))
        sys.wait(1000)
        -- collectgarbage("collect")
        collectgarbage("collect")
    end
end

sys.taskInit(zbuff_abc)

sys.run()
