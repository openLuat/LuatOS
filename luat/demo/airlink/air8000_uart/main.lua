-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air8000_gpio_ext"
VERSION = "1.0.5"

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用http库需要下列语句]]

PWR8000S = function(level)
    gpio.set(23, level)
end

gpio.debounce(0, 1000)
gpio.setup(0, function()
    sys.taskInit(function()
        log.info("复位Air8000S")
        PWR8000S(0)
        sys.wait(20)
        PWR8000S(1)
    end)
end, gpio.PULLDOWN)

local uartid = 11
local buff = zbuff.create(1024)
function uart_on()
    local result = uart.on(uartid, "receive", function(id, len)
        local s = ""
        log.info("uart", "recv", id, len)
        repeat
            -- s = uart.read(id, 128)
            uart.rx(id, buff)
            s = buff:query()
            if s and #s > 0 then -- #s 是取字符串的长度
                -- 如果传输二进制/十六进制数据, 部分字符不可见, 不代表没收到
                -- 关于收发hex值,请查阅 https://doc.openluat.com/article/583
                log.info("uart", "receive", id, #s, s)
                -- log.info("uart", "receive", id, #s, s:toHex())
                buff:del()
            else
                break
            end
        until s == ""
    end)
    log.info("uart.on", result)
end

sys.taskInit(function()
    sys.wait(1000)
    airlink.debug(1)
    local ret = uart.setup(uartid, 115200)
    log.info("执行初始化", ret);
    uart_on()
    while 1 do
        uart.write(uartid, "1234123412341234")
        -- gpio.setup(164, 0, gpio.PULLDOWN)
        sys.wait(1000)
        -- break
        -- airlink.statistics()
    end
    -- while 1 do
    --     uart.write(11, "ABC\r\n")
    --     sys.wait(1000)
    -- end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
