--[[
@module  udp_server_main
@summary udp server 主应用功能模块 
@version 1.0
@date    2025.11.15
@author  王世豪
@usage
本文件为udp server 主应用功能模块，核心业务逻辑为：
1、创建一个udp server，监听指定端口；
2、处理通信异常，出现异常后，重新初始化UDP服务以恢复正常数据接收；
3、调用udp_server_receiver和udp_server_sender中的外部接口，进行数据收发处理；

本文件没有对外接口，直接在main.lua中require "udp_server_main"就可以加载运行；
]]

local udpsrv = require "udpsrv"

-- 加载UDP服务器数据接收功能模块
local udp_server_receiver = require "udp_server_receiver"
-- 加载UDP服务器数据发送功能模块
local udp_server_sender = require "udp_server_sender"

-- 服务器监听端口
local SERVER_PORT = 50003
-- 服务器主题（用于接收消息）
SERVER_TOPIC = "udp_server"

-- udp server socket的任务处理函数
local function udp_server_main_task_func() 
    local udp_server
    local ret, data, remote_ip, remote_port

    while true do
        -- 如果当前时间点设置的网卡还没有连接成功，一直在这里循环等待
        while not socket.adapter(socket.dft()) do
            log.warn("udp_client_main_task_func", "wait IP_READY", socket.dft())
            -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
            -- 或者等待1秒超时退出阻塞等待状态;
            -- 注意：此处的1000毫秒超时不要修改的更长；
            -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
            -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
            -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
            sys.waitUntil("IP_READY", 1000)
        end

        -- 检测到了IP_READY消息
        log.info("udp_server_main_task_func", "recv IP_READY", socket.dft())

        -- 创建UDP服务器对象
        -- 注意：udpsrv.create有3个参数，最后一个参数是网络适配器编号
        udp_server = udpsrv.create(SERVER_PORT, SERVER_TOPIC, socket.dft())

        if not udp_server then
            log.error("udp_server_main_task_func", "udpsrv.create error")
            goto EXCEPTION_PROC
        end

        log.info("udp_server_main_task_func", "UDP server started on port", SERVER_PORT)

        -- 发送一条广播消息，通知端口号为50000的客户端，UDP服务器已启动
        udp_server:send("UDP Server is UP", "255.255.255.255", 50000)

        -- 数据收发以及网络连接异常事件总处理逻辑
        while true do
            -- 数据发送处理
            if not udp_server_sender.proc(udp_server) then
                log.error("udp_server_main_task_func", "udp_server_sender.proc error")
            end

            -- 等待接收数据事件
            ret, data, remote_ip, remote_port = sys.waitUntil(SERVER_TOPIC, 15000)

            if ret then
                -- 判断是否是发送就绪事件（通过 data 内容或 remote_ip 是否为 nil）
                if data == "SEND_READY" and remote_ip == nil then
                    -- 这是发送就绪事件，无需处理接收数据，直接继续循环以发送数据
                    log.info("udp_server_main_task_func", "send ready event received")
                -- 网络异常事件
                elseif data == "SOCKET_CLOSED" then
                    goto EXCEPTION_PROC
                else
                    -- 真实接收到的数据
                    if not udp_server_receiver.proc(data, remote_ip, remote_port) then
                        log.error("udp_server_main_task_func", "udp_server_receiver.proc error")
                    end
                end
            else
                -- 超时，发送一条心跳广播
                log.info("udp_server_main_task_func", "No data received, sending broadcast heartbeat")
                udp_server:send("UDP Server Heartbeat", "255.255.255.255", 50000)
            end
        end

        ::EXCEPTION_PROC::

        -- 数据发送应用模块对来不及发送的数据做清空和通知失败处理
        udp_server_sender.exception_proc()

        -- 关闭UDP服务器
        if udp_server then
            udp_server:close()
            udp_server = nil
        end
        
        -- 5秒后跳转到循环体开始位置，重建udp server
        sys.wait(5000)
    end
end

--创建并且启动一个task
--运行这个task的主函数udp_server_main_task_func
sys.taskInit(udp_server_main_task_func)