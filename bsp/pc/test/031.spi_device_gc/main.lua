
_G.sys = require("sys")

sys.taskInit(function()
    local abc = spi.deviceSetup(1,90)
    log.info("生成了,等gc", abc)
end)

sys.taskInit(function()
    sys.wait(100)
    collectgarbage("collect")
    collectgarbage("collect")
    collectgarbage("collect")
    collectgarbage("collect")
end)

sys.run()
