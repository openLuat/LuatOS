_G.sys = require("sys")

-- print('Go')

-- sys.timerStart(function()
--     log.info("timer", "timeout once")
-- end, 1000)

-- sys.timerLoopStart(function()
--     log.info("timer", "3s repeat")
-- end, 3000)

sys.taskInit(function()
    while 1 do
        sys.wait(1000)
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
    end
end)

sys.run()
