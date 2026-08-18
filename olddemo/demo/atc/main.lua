-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "atc"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
local out_buff = zbuff.create(8000)
local in_buff = zbuff.create(8000)
local uart_id = uart.VUART_0 -- USB虚拟串口的固定id
local atc_id = 0
--初始化
local result = uart.setup(
    uart_id,--串口id
    115200,--波特率,其实无所谓, 纯虚拟串口
    8,--数据位
    1--停止位
)

local function atc_out(id, event, param)
    uart.tx(uart_id, out_buff)
end
-- 收取数据会触发回调, 这里的"receive" 是固定值
uart.on(uart_id, "receive", function(id, len)
    uart.rx(id, in_buff)
    atc.input(atc_id, in_buff)
    in_buff:del()
end)

-- 并非所有设备都支持sent事件
uart.on(uart_id, "sent", function(id)
    log.info("uart", "sent", id)
end)

atc.debug(true)
atc.on(atc_id, atc_out, out_buff)



-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
