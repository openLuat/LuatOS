
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "uart2demo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

sys.subscribe("uart_write", function(data)
    uart.write(2, data)
end)

uart.on(2, "receive", function(id, len)
    local data = uart.read(id, 1024)
    log.info("uart", "receive", data)
    sys.publish("uart_write", data) -- 或者调用uart.write(2, data)也可以的
end)
uart.setup(2, 115200)
uart.write(2, "hi from uart2\r\n")


gpio.setup(1, function()
    -- 按一下boot按键试试
    log.info("gpio", "BOOT button release")
    uart.write(2, "boot button release")
end, gpio.PULLUP)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
