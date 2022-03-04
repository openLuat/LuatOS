--加载sys库
_G.sys = require("sys")

log.info("start","cwait test")
sys.taskInit(function()
    for i=1,5 do
        log.info("testCwaitDelay.start",os.time())
        local r = win32.testCwaitDelay(100).wait()
        log.info("testCwaitDelay",type(r),r)
        if r ~= true then os.exit(1) end
        log.info("testCwaitDelay.end",os.time())
    end

    log.info("testCwaitError",win32.testCwaitError().wait())

    os.exit(0)
end)

sys.run()
