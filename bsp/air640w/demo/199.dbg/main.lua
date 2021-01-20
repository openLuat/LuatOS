
dbg.wait()

local sys = require("sys")

local function call_abc(tag, val, date, time)
    log.info(tag, val, date)
    log.info(tag, val + time, date)
end

local function call_def(t)
    call_abc("QQ", 123, os.date(), t)
end

sys.taskInit(function()
    while true do
        call_def(os.time())
        sys.wait(3000)
    end
end)

sys.run()
