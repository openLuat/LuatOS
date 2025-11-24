
_G.sys = require("sys")

sys.taskInit(function()
    while 1 do
        local num=0x7FFFFFC0
        data=string.format("%08X",num)
        log.info("data", data)
        num = bit.set(num, 5)
        data=string.format("%08X",num)
        log.info("data", data)
        sys.wait(1000)
    end

end)

sys.run()
