
_G.sys = require("sys")


sys.taskInit(function()
    sys.wait(100)
    local zbuff = zbuff.create(1024)
    zbuff:resize(0)
end)

sys.run()
