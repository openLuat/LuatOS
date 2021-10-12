
PROJECT = "uartdemo"
VERSION = "1.0.0"

local sys = require "sys"

pmd.ldoset(1800, pmd.LDO_VLCD)

sys.taskInit(function()
    netled = gpio.setup(1, 0)
    while 1 do
        netled(1)
        sys.wait(300)
        netled(0)
        sys.wait(300)
        log.info("luatos", "hi", os.date())
    end
end)

sys.subscribe("UART_WRITE", function (id, data)
    if #data > 0 then
        uart.write(id, data)
    end
end)

uart.setup(2, 115200)
uart.on(2, "recv", function (id, len)
    local data = uart.read(id, 1024)
    log.info("uart", id, len, #data)
    sys.publish("UART_WRITE", id, data)
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
