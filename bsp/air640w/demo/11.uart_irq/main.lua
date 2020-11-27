-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "uart_irq"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
local sys = require "sys"

log.info("main", "uart demo")

local uartid = 1

--初始化
local result = uart.setup(
    uartid,--串口id
    115200,--波特率
    8,--数据位
    1--停止位
)


--循环发数据
sys.timerLoopStart(uart.write,1000,uartid,"test")
uart.on(uartid, "receive", function(id, len)
    log.info("uart", "receive", id, len, uart.read(uartid, len))
end)
uart.on(uartid, "sent", function(id)
    log.info("uart", "sent", id)
end)

--轮询例子
-- sys.taskInit(function ()
--     while true do
--         local data = uart.read(uartid,maxBuffer)
--         if data:len() > 0 then
--             print(data)
--             uart.write(uartid,"receive:"..data)
--         end
--         sys.wait(100)--不阻塞的延时函数
--     end
-- end)
--[[

    uart.None,--校验位
    uart.LSB,--高低位顺序
    maxBuffer,--缓冲区大小
    function ()--接收回调
        local str = uart.read(uartid,maxBuffer)
        print("uart","receive:"..str)
    end,
    function ()--发送完成回调
        print("uart","send ok")
    end


]]

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
