local sys = require "sys"
log.info("main", "uart demo")
local uartid = 1
local recvBuff = {{}, {}}
--初始化
local result = uart.setup(
    uartid,--串口id
    115200,--波特率
    8,--数据位
    1--停止位
)
local function read(uid)
    log.info("uart", "buff table", #recvBuff[uid])
    local s = table.concat(recvBuff[uid])
    log.info("uart", "buff string", #s)
    recvBuff[uid] = {}
    uart.write(uartid,s)
end
sys.timerLoopStart(function()
    log.info("RAM:", _G.collectgarbage("count"))-- 打印占用的RAM
end, 1000)
local function taskRead()
    uart.on(
        1,
        'receive',
        function(uid, length)
            --table.insert(recvBuff[uid], uart.read(uid, length or 1024))
            --sys.timerStart(sys.publish, 50, 'UART_RECV_WAIT_', uid)
            uart.write(uid, uart.read(uid, length or 1024))
        end
    )
end
sys.subscribe('UART_RECV_WAIT_', read)
sys.taskInit(taskRead)
sys.run()
