--[[
@module  main
@summary ymodem 接收文件应用功能模块 
@version 1.0
@date    2025.07.01
@author  杨鹏
@usage
本文件为Air780EHM核心板演示ymodem功能的代码示例，核心业务逻辑为：
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

-- 根据实际设备选取不同的uartid
local uartid = 1 

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

--  定义一个局部变量，用于表示Ymodem协议是否正在运行
local ymodem_running = false 

--  创建一个缓冲区，大小为1024 + 32
local rxbuff = zbuff.create(1024 + 32) 

--  创建一个ymodem处理程序，保存路径为"/"，文件名为"save.bin"
local ymodem_handler = ymodem.create("/","save.bin")

--  定义一个ymodem_to函数，用于发送C字符，并重置ymodem处理程序
local function ymodem_to() 
    while true do
        --  如果ymodem协议没有在运行，则发送请求；并重置ymodem处理程序
        if not ymodem_running then 
            uart.write(uartid, "C")
            ymodem.reset(ymodem_handler) 
        end
        sys.wait(500)
    end
end

--  定义一个ymodem_rx函数，用于接收数据
local function ymodem_rx(id,len) 
    --  从uart接收数据到缓冲区
    uart.rx(id,rxbuff) 
    --  打印缓冲区已使用的大小
    log.info(rxbuff:used()) 
    --  调用ymodem.receive函数，接收数据
    local result,ack,flag,file_done,all_done = ymodem.receive(ymodem_handler,rxbuff) 
    ymodem_running = result
    log.info("result:",ymodem_running,ack,flag,file_done,all_done)
    rxbuff:del()
    if result then
        rxbuff:copy(0, ack,flag)
        uart.tx(id, rxbuff)
    end

    --  所有数据都接收完毕
    if all_done then 
        -- 判断/save.bin文件是否存在
        local exists=io.exists("/save.bin") 

        -- 判断/save.bin文件是否存在，存在则打印日志，显示/save.bin文件大小；不存在则打印日志，显示/save.bin文件不存在
        if exists then
            log.info("io", "save.bin file exists:", exists) 
            log.info("io", "save.bin file size:", io.fileSize("/save.bin")) 
        else
            log.info("io", "save.bin file not exists") 
        end
        
        --ymodem_running置为false，再次开始接收
        ymodem_running = false 
    end
    rxbuff:del()
end

--  监听串口接收事件
uart.on(uartid, "receive", ymodem_rx) 

--  监听串口发送事件
uart.on(uartid, "sent", function(id) 
    log.info("uart", "sent", id) 
end)

--创建并且启动一个task
--运行这个task的主函数ymodem_to
sysplus.taskInitEx(ymodem_to, taskName,ymodem_to_cb)
