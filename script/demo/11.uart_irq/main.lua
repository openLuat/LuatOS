local sys = require "sys"

local uartid = 1
local maxBuffer = 4*100

--初始化
local result = uart.setup(
    uartid,--串口id
    115200,--波特率
    8,--数据位
    1,--停止位
    uart.None,--校验位
    uart.LSB,--高低位顺序
    maxBuffer--缓冲区大小
)

--返回值为0，表示打开成功
if result ~= 0 then
    print("uart open error",result)
    error("uart open fail")
end

--循环发数据
sys.timerLoopStart(uart.write,1000,uartid,"test")

--方式1:轮询
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


-- --方式2:收数据回调
sys.subscribe("IRQ_UART"..uartid, function(uartid)
    local str = uart.read(uartid,maxBuffer)
    print("uart","receive:"..str)
    uart.write(uartid,str)
end)

sys.run()
