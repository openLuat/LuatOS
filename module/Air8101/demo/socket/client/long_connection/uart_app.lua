--[[
@module  uart_app
@summary 串口应用功能模块 
@version 1.0
@date    2025.07.01
@author  朱天华
@usage
本文件为串口应用功能模块，核心业务逻辑为：
1、打开uart1，波特率115200，数据位8，停止位1，无奇偶校验位；
2、uart1和pc端的串口工具相连；
3、从uart1接收到pc端串口工具发送的数据后，通知四个socket client进行处理；
4、收到四个socket client从socket server接收到的数据后，将数据通过uart1发送到pc端串口工具；

本文件的对外接口有两个：
1、sys.publish("SEND_DATA_REQ", "uart", read_buf)，通过publish通知其他应用功能模块处理read_buf数据；
2、sys.subscribe("RECV_DATA_FROM_SERVER", recv_data_from_server_proc)，订阅RECV_DATA_FROM_SERVER消息，处理消息携带的数据；；
]]


-- 使用UART1
local UART_ID = 1
-- 串口接收数据缓冲区
local read_buf = ""

-- 将前缀prefix和数据data拼接
-- 然后末尾增加回车换行两个字符，通过uart发送出去，方便在PC端换行显示查看
local function recv_data_from_server_proc(prefix, data)
    uart.write(UART_ID, prefix..data.."\r\n")
end


local function concat_timeout_func()
    -- 如果存在尚未处理的串口缓冲区数据；
    -- 将数据通过publish通知其他应用功能模块处理；
    -- 然后清空本文件的串口缓冲区数据
    if read_buf:len() > 0 then
        sys.publish("SEND_DATA_REQ", "uart", read_buf)
        read_buf = ""
    end
end


-- UART1的数据接收中断处理函数，UART1接收到数据时，会执行此函数
local function read()
    local s
    while true do
        -- 非阻塞读取UART1接收到的数据，最长读取1024字节
        s = uart.read(UART_ID, 1024)
        
        -- 如果从串口没有读到数据
        if not s or s:len() == 0 then
            -- 启动50毫秒的定时器，如果50毫秒内没收到新的数据，则处理当前收到的所有数据
            -- 这样处理是为了防止将一大包数据拆分成多个小包来处理
            -- 例如pc端串口工具下发1100字节的数据，可能会产生将近20次的中断进入到read函数，才能读取完整
            -- 此处的50毫秒可以根据自己项目的需求做适当修改，在满足整包拼接完整的前提下，时间越短，处理越及时
            sys.timerStart(concat_timeout_func, 50)
            -- 跳出循环，退出本函数
            break
        end

        log.info("uart_app.read len", s:len())
        -- log.info("uart_app.read", s)

        -- 将本次从串口读到的数据拼接到串口缓冲区read_buf中
        read_buf = read_buf..s
    end
end



-- 初始化UART1，波特率115200，数据位8，停止位1
uart.setup(UART_ID, 115200, 8, 1)

-- 注册UART1的数据接收中断处理函数，UART1接收到数据时，会执行read函数
uart.on(UART_ID, "receive", read)

-- 订阅"RECV_DATA_FROM_SERVER"消息的处理函数recv_data_from_server_proc
-- 收到"RECV_DATA_FROM_SERVER"消息后，会执行函数recv_data_from_server_proc
sys.subscribe("RECV_DATA_FROM_SERVER", recv_data_from_server_proc)
