-- LuaTools需要PROJECT和VERSION这两个信息

PROJECT = "rf_test"

VERSION = "1.0.0"

PRODUCT_KEY = "1111"

-- 引入必要的库文件(lua编写), 内部库不需要require

_G.sys = require("sys")

local uartid = uart.VUART_0 -- USB虚拟串口的固定id

--初始化
local result = uart.setup(
    uartid,--串口id
    115200,--波特率,其实无所谓, 纯虚拟串口
    8,--数据位
    1--停止位
)


-- 收取数据会触发回调, 这里的"receive" 是固定值
uart.on(uartid, "receive", function(id, len)
    local s = ""
    repeat
        s = uart.read(id, len)
        if s and #s > 0 then -- #s 是取字符串的长度
           log.info("uart", "receive", id, #s, s:toHex())
		   mobile.nstInput(s)
        end
    until s == ""
	mobile.nstInput(nil)
end)


mobile.nstOnOff(true,uart.VUART_0)
-- 结尾总是这一句

sys.run()

-- sys.run()之后后面不要加任何语句!!!!!