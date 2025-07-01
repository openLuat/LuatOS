--[[
本文件为Air780EHM核心板演示ymodem功能的代码示例，核心业务逻辑为：
从机模式(peripheral)的基本流程(概要描述)
1. 初始化串口通信
2. 创建Ymodem处理对象
    local ymodem_handler = ymodem.create("/","save.bin")
3. 启动请求发送任务
    uart.write(uartid, "C")
4. 监听串口数据接收
    uart.on(uartid, "receive", ymodem_rx)
5. 处理Ymodem数据包
    local function ymodem_rx(id,len)
]]

local uartid = 1 -- 根据实际设备选取不同的uartid

--初始化
local result = uart.setup(
    uartid,--串口id
    115200,--波特率
    8,--数据位
    1--停止位
)
local taskName = "ymodem_to"

-- 处理未识别的消息
local function ymodem_to_cb(msg)
	log.info("ymodem_to_cb", msg[1], msg[2], msg[3], msg[4])
end

local ymodem_running = false --  定义一个局部变量，用于表示Ymodem协议是否正在运行
local rxbuff = zbuff.create(1024 + 32) --  创建一个缓冲区，大小为1024 + 32
local ymodem_handler = ymodem.create("/","save.bin") --  创建一个ymodem处理程序，保存路径为"/"，文件名为"save.bin"

local function ymodem_to() --  定义一个ymodem_to函数，用于发送C字符，并重置ymodem处理程序
    while true do
        if not ymodem_running then --  如果ymodem协议没有在运行，则发送请求
            uart.write(uartid, "C")
            ymodem.reset(ymodem_handler) --  重置ymodem处理程序
        end
        sys.wait(500)
    end
end


local function ymodem_rx(id,len) --  定义一个ymodem_rx函数，用于接收数据
    uart.rx(id,rxbuff) --  从uart接收数据到缓冲区
    log.info(rxbuff:used()) --  打印缓冲区已使用的大小
    local result,ack,flag,file_done,all_done = ymodem.receive(ymodem_handler,rxbuff) --  调用ymodem.receive函数，接收数据
    ymodem_running = result
    log.info("result:",ymodem_running,ack,flag,file_done,all_done)
    rxbuff:del()
    if result then
        rxbuff:copy(0, ack,flag)
        uart.tx(id, rxbuff)
    end
    if all_done then --  所有数据都接收完毕
        local exists=io.exists("/save.bin") -- 判断/save.bin文件是否存在
        if exists then
            log.info("io", "save.bin file exists:", exists) --  打印日志，判断/save.bin文件是否存在
            log.info("io", "save.bin file size:", io.fileSize("/save.bin")) --  打印日志，显示/save.bin文件大小
        else
            log.info("io", "save.bin file not exists") --  打印日志，/save.bin文件不存在
        end
            
        ymodem_running = false  --再次开始接收
    end
    rxbuff:del()
end

uart.on(uartid, "receive", ymodem_rx) --  监听串口接收事件

uart.on(uartid, "sent", function(id) --  监听串口发送事件
    log.info("uart", "sent", id) --  打印发送事件
end)

--创建并且启动一个task
--运行这个task的主函数ymodem_to
sysplus.taskInitEx(ymodem_to, taskName,ymodem_to_cb)
