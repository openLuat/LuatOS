--[[
@module  main
@summary ymodem 接收文件应用功能模块 
@version 1.0
@date    2025.10.27
@author  李源龙
@usage
本文件为Air780EHM核心板演示ymodem功能的代码示例，核心业务逻辑为：
1. 创建协程，调用ymodem_open函数打开ymodem接收功能，初始化zbuff，
初始化串口，创建一个ymodem对象，然后开始往串口发送'C'字符，启动ymodem接收功能。
2. 接收串口数据，并且保存到指定路径，接收完成后，自动关闭ymodem接收功能。
]]

-- 根据实际设备选取不同的uartid
local uartid = 1 

local taskName = "ymodem_open"

-- 处理未识别的消息
local function ymodem_open_cb(msg)
    log.info("ymodem_open_cb", msg[1], msg[2], msg[3], msg[4])
end

--  定义一个局部变量，用于表示Ymodem协议是否正在运行
local ymodem_running = false 

local rxbuff 

local ymodem_handler

local ymodem_result=false

--定义一个ymodem_close函数，用于关闭ymodem接收功能，包括释放zbuff，关闭串口，释放ymodem对象等操作
local function ymodem_close()
    --释放rxbuff
    rxbuff:free()
    --关闭串口
    uart.close(uartid)
    --释放ymodem处理程序
    ymodem.release(ymodem_handler)
end



--  定义一个ymodem_rx函数，用于接收数据
local function ymodem_rx(id,len) 
    --  从uart接收数据到缓冲区
    while 1 do
        log.info("uart", "缓冲区", uart.rxSize(id)) -- 缓冲区中的数据数量
        local len = uart.rx(id, rxbuff)
        if len <= 0 then
            break
        end
        log.info("uart", "receive", id, rxbuff:used(), rxbuff:toStr())
    end
    --  打印缓冲区已使用的大小
    log.info(rxbuff:used()) 
    --  调用ymodem.receive函数，接收数据
    local result,ack,flag,file_done,all_done = ymodem.receive(ymodem_handler,rxbuff) 
    ymodem_running = result
    log.info("result:",ymodem_running,ack,flag,file_done,all_done)
    rxbuff:del()
    --成功就发送ack和flag
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
            --打印文件大小
            log.info("io", "save.bin file size:", io.fileSize("/save.bin")) 
        else
            log.info("io", "save.bin file not exists") 
        end

        --ymodem_running置为false，再次开始接收
        ymodem_running = false
        --ymodem_result置为true，表示接收完成
        ymodem_result=true
        --关闭ymodem，释放资源
        ymodem_close()
        
    end
    rxbuff:del()
end

local function uart_sent_cb(id)
    log.info("uart", "sent", id) 
end

--开启ymodem接收，主要包括串口初始化，zbuff初始化，ymodem初始化等，初始化完毕之后开始发送'C'，等待发送端发送数据
local function ymodem_open()

    --  创建一个缓冲区，大小为1024 + 32，接收数据为1k，32为剩下的协议数据，可能不到32，保险起见，留足够的大小
    rxbuff = zbuff.create(1024 + 32) 

    --  创建一个ymodem处理程序，保存路径为"/"，文件名为"save.bin"
    ymodem_handler = ymodem.create("/","save.bin")
    
    --初始化
    uart.setup(
    uartid,--串口id
    115200,--波特率
    8,--数据位
    1--停止位
    )
    --  监听串口接收事件
    uart.on(uartid, "receive", ymodem_rx) 

    --  监听串口发送事件
    uart.on(uartid, "sent", uart_sent_cb)
    
    while not ymodem_result do
        --  如果ymodem协议没有在运行，则发送请求；并重置ymodem处理程序
        if not ymodem_running then 
            --YMODEM 传输文件时，接收方会先发送一个字符 'C'来启动传输过程
            uart.write(uartid, "C")
            --发送完之后重置恢复到初始状态
            ymodem.reset(ymodem_handler) 
        end
        sys.wait(500)
    end
    
end

--创建并且启动一个task
--运行这个task的主函数ymodem_run
sys.taskInit(ymodem_open, taskName,ymodem_open_cb)
