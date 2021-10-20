-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "uart_timeout"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
local sys = require "sys"

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(15000)--初始化watchdog设置为15s
    sys.timerLoopStart(wdt.feed, 10000)--10s喂一次狗
end

log.info("main", "uart timeout demo")

-- 串口ID,串口读缓冲区
local UART_ID, sendQueue = 1, {}
-- 串口超时，串口准备好后发布的消息
--例子是100ms，按需求改
local uartimeout, recvReady = 100, "UART_RECV_ID"
--初始化
local result = uart.setup(
    UART_ID,--串口id
    115200,--波特率
    8,--数据位
    1--停止位
)
uart.on(UART_ID, "receive", function(uid, length)
    local s
    while true do--保证读完不能丢包
        s = uart.read(uid, length)
        if #s == 0 then break end
        table.insert(sendQueue, s)
    end
    sys.timerStart(sys.publish, uartimeout, recvReady)
end)

-- 向串口发送收到的字符串
sys.subscribe(recvReady, function()
    --拼接所有收到的数据
    local str = table.concat(sendQueue)
    -- 串口的数据读完后清空缓冲区
    sendQueue = {}
    --注意打印会影响运行速度，调试完注释掉
    log.info("uartTask.read length", #str, str:sub(1,100))

    --在这里处理接收到的数据，这是例子
    if str:find("12345678901234567890") == 1 then --如果满足开头
        uart.write(UART_ID,"1234567890x2 lol") --回复
    else
        uart.write(UART_ID,"not match "..str) --回复
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
