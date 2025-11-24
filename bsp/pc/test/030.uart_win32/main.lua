
_G.sys = require("sys")

sys.taskInit(function()
    local uartid = 24
    uart.setup(uartid, 115200)
    uart.on(uartid, "receive", function(id, len)
        log.info("uart接收", id, len)
        local s = ""
        repeat
            s = uart.read(id, 1024)
            if #s > 0 then
                log.info("uart输入", s)
            end
        until s == ""
    end)

end)

sys.run()
