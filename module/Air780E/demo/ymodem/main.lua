-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "uart_ymodem"
VERSION = "1.0.0"
log.style(1)
log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

local uartid = 1 -- 根据实际设备选取不同的uartid

--初始化
local result = uart.setup(
    uartid,--串口id
    115200,--波特率
    8,--数据位
    1--停止位
)
local ymodem_running = false

local rxbuff = zbuff.create(1024 + 32)
local ymodem_handler = ymodem.create("/","save.bin")
local function ymodem_to()
    if not ymodem_running then
        uart.write(uartid, "C")
        ymodem.reset(ymodem_handler)
    end
end


sys.timerLoopStart(ymodem_to,500)

local function ymodem_rx(id,len)
    uart.rx(id,rxbuff)
    log.info(rxbuff:used())
    local result,ack,flag,file_done,all_done = ymodem.receive(ymodem_handler,rxbuff)
    ymodem_running = result
    log.info(ymodem_running,ack,flag,file_done,all_done)
    rxbuff:del()
    if result then
        rxbuff:copy(0, ack,flag)
        uart.tx(id, rxbuff)
    end
    if all_done then
        ymodem_running = false  --再次开始接收
    end
    rxbuff:del()
end
uart.on(uartid, "receive", ymodem_rx)

uart.on(uartid, "sent", function(id)
    log.info("uart", "sent", id)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
