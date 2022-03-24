local testir = {}

local sys = require "sys"

sys.taskInit(function()
    while true do
        ir.sendNEC(0, 0x11, 0x22)
        sys.wait(1000)
    end

end)

return testir