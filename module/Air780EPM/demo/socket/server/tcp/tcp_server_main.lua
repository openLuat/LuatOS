--[[
@module  tcp_server_main
@summary tcp server主应用功能模块 
@version 1.0
@date    2025.11.15
@author  王世豪
@usage  
本文件为tcp server主应用功能模块，核心业务逻辑为：
1、创建一个tcp server ，等待client连接；
2、处理连接异常，出现异常后，关闭当前连接，等待下一个client连接；
3、调用tcp_server_receiver和tcp_server_sender中的外部接口，进行数据收发处理；

本文件没有对外接口，直接在main.lua中require "tcp_server_main"就可以加载运行；
]]

local libnet = require "libnet"

-- 加载TCP服务器数据接收功能模块
local tcp_server_receiver = require "tcp_server_receiver"
-- 加载TCP服务器数据发送功能模块
local tcp_server_sender = require "tcp_server_sender"

-- tcp_server_main的任务名
local TASK_NAME = tcp_server_sender.TASK_NAME

-- 处理未识别的消息
local function tcp_server_main_cbfunc(msg)
	log.info("tcp_server_main_cbfunc", msg[1], msg[2], msg[3], msg[4])
end

-- tcp server socket的任务处理函数
local function tcp_server_main_task_func()
    local netc = nil
    local result, param
    local listen_port = 50003 -- tcp server监听的端口号

    while true do
        -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
        while not socket.adapter(socket.dft()) do
            log.warn("tcp_server_main_task_func", "wait IP_READY", socket.dft())
            -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
            -- 或者等待1秒超时退出阻塞等待状态;
            -- 注意：此处的1000毫秒超时不要修改的更长；
            -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
            -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
            -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
            sys.waitUntil("IP_READY", 1000)
        end

        -- 检测到了IP_READY消息
        log.info("tcp_server_main_task_func", "recv IP_READY", socket.dft())

        netc = socket.create(socket.dft(), TASK_NAME)
        if not netc then
            log.error("tcp_server_task_func", "socket.create失败")
            goto EXCEPTION_PROC
        end

        socket.debug(netc, true)
        -- 配置socker server 对象为tcp server
        result = socket.config(netc, listen_port)
        -- 如果配置失败
        if not result then
            log.error("tcp_server_task_func", "socket.config失败")
            goto EXCEPTION_PROC
        end

        -- 监听tcp server端口
        result = libnet.listen(TASK_NAME, 0, netc)
        -- 如果监听失败
        if not result then
            log.error("tcp_server_task_func", "监听失败")
            goto EXCEPTION_PROC
        end

        -- 客户端连上了, 发一条数据给客户端
        libnet.tx(TASK_NAME, 0, netc, "TCP server is UP!")

        -- 数据收发以及网络连接异常事件总处理逻辑
        while true do
            -- 数据接收处理
            if not tcp_server_receiver.proc(netc) then
                log.info("tcp_server_task_func", "tcp_server_receiver.proc error")
                break
            end
            
            -- 数据发送处理
            if not tcp_server_sender.proc(TASK_NAME, netc) then
                log.info("tcp_server_task_func", "tcp_server_sender.proc error")
                break
            end

            -- 阻塞等待socket.EVENT事件或者15秒钟超时
            result, param = libnet.wait(TASK_NAME, 15000, netc)
            log.info("tcp_server_task_func", "wait result", result, param)

            -- 如果连接异常，则退出循环
            if not result then
                log.info("tcp_server_task_func", "客户端断开")
                break
            end
        end

        -- 出现异常    
        ::EXCEPTION_PROC::

        -- 数据发送应用模块对来不及发送的数据做清空和通知失败处理
        tcp_server_sender.exception_proc()

        -- 如果存在socket server对象
        if netc then
            -- 关闭socket server连接
            libnet.close(TASK_NAME, 5000, netc)

            -- 释放socket server对象
            socket.release(netc)
            netc = nil  
        end

        -- 等待5秒后，再次尝试创建新的连接
        sys.wait(5000)
    end
end

--创建并且启动一个task
--运行这个task的主函数tcp_server_main_task_func
sys.taskInitEx(tcp_server_main_task_func, TASK_NAME, tcp_server_main_cbfunc)
