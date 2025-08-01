--[[
@module  tcp_ssl_main
@summary tcp_ssl client socket主应用功能模块 
@version 1.0
@date    2025.07.01
@author  朱天华
@usage
本文件为tcp_ssl client socket主应用功能模块，核心业务逻辑为：
1、创建一个tcp_ssl client socket，连接server；
2、处理连接异常，出现异常后执行重连动作；
3、调用tcp_ssl_receiver和tcp_ssl_sender中的外部接口，进行数据收发处理；

本文件没有对外接口，直接在main.lua中require "tcp_ssl_main"就可以加载运行；
]]

local libnet = require "libnet"

-- 加载tcp_ssl client socket数据接收功能模块
local tcp_ssl_receiver = require "tcp_ssl_receiver"
-- 加载tcp_ssl client socket数据发送功能模块
local tcp_ssl_sender = require "tcp_ssl_sender"

-- 电脑访问：https://netlab.luatos.com/
-- 点击 打开TCP SSL 按钮，会创建一个TCP SSL server
-- 将server的地址和端口赋值给下面这两个变量
local SERVER_ADDR = "112.125.89.8"
local SERVER_PORT = 43312

-- tcp_ssl_main的任务名
local TASK_NAME = tcp_ssl_sender.TASK_NAME


-- 处理未识别的消息
local function tcp_ssl_main_cbfunc(msg)
	log.info("tcp_ssl_main_cbfunc", msg[1], msg[2], msg[3], msg[4])
end

-- tcp_ssl client socket的任务处理函数
local function tcp_ssl_main_task_func() 

    local socket_client
    local result, para1, para2

    while true do
        -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
        while not socket.adapter(socket.dft()) do
            log.warn("tcp_ssl_main_task_func", "wait IP_READY", socket.dft())
            -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
            -- 或者等待1秒超时退出阻塞等待状态;
            -- 注意：此处的1000毫秒超时不要修改的更长；
            -- 因为当使用libnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
            -- 当libnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
            -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
            sys.waitUntil("IP_READY", 1000)
        end

        -- 检测到了IP_READY消息
        log.info("tcp_ssl_main_task_func", "recv IP_READY", socket.dft())

        -- 创建socket client对象
        socket_client = socket.create(nil, TASK_NAME)
        -- 如果创建socket client对象失败
        if not socket_client then
            log.error("tcp_ssl_main_task_func", "socket.create error")
            goto EXCEPTION_PROC
        end

        -- 配置socket client对象为tcp_ssl client
        -- 不做证书校验
        result = socket.config(socket_client, nil, nil, true)
        -- 如果配置失败
        if not result then
            log.error("tcp_ssl_main_task_func", "socket.config error")
            goto EXCEPTION_PROC
        end

        -- 连接server
        result = libnet.connect(TASK_NAME, 15000, socket_client, SERVER_ADDR, SERVER_PORT)
        -- 如果连接server失败
        if not result then
            log.error("tcp_ssl_main_task_func", "libnet.connect error")
            goto EXCEPTION_PROC
        end

        log.info("tcp_ssl_main_task_func", "libnet.connect success")

        -- 数据收发以及网络连接异常事件总处理逻辑
        while true do
            -- 数据接收处理（接收处理必须写在libnet.wait之前，因为老版本的内核固件要求必须这样，新版本的内核固件没这个要求，为了不出问题，写在libnet.wait之前就行了）
            -- 如果处理失败，则退出循环
            if not tcp_ssl_receiver.proc(socket_client) then
                log.error("tcp_ssl_main_task_func", "tcp_ssl_receiver.proc error")
                break
            end

            -- 数据发送处理
            -- 如果处理失败，则退出循环
            if not tcp_ssl_sender.proc(TASK_NAME, socket_client) then
                log.error("tcp_ssl_main_task_func", "tcp_ssl_sender.proc error")
                break
            end

            -- 阻塞等待socket.EVENT事件或者15秒钟超时
            -- 以下三种业务逻辑会发布事件：
            -- 1、socket client和server之间的连接出现异常（例如server主动断开，网络环境出现异常等），此时在内核固件中会发布事件socket.EVENT
            -- 2、socket client接收到server发送过来的数据，此时在内核固件中会发布事件socket.EVENT
            -- 3、socket client需要发送数据到server, 在tcp_ssl_sender.lua中会发布事件socket.EVENT
			result, para1, para2 = libnet.wait(TASK_NAME, 15000, socket_client)
            log.info("tcp_ssl_main_task_func", "libnet.wait", result, para1, para2)
			
			-- 如果连接异常，则退出循环
			if not result then
				log.warn("tcp_ssl_main_task_func", "connection exception")
				break
            end
        end


        -- 出现异常    
        ::EXCEPTION_PROC::

        -- 数据发送应用模块对来不及发送的数据做清空和通知失败处理
        tcp_ssl_sender.exception_proc()

        -- 如果存在socket client对象
        if socket_client then
            -- 关闭socket client连接
            libnet.close(TASK_NAME, 5000, socket_client)

            -- 释放socket client对象
            socket.release(socket_client)
            socket_client = nil
        end
        
        -- 5秒后跳转到循环体开始位置，自动发起重连
        sys.wait(5000)
    end
end

--创建并且启动一个task
--运行这个task的主函数tcp_ssl_main_task_func
sysplus.taskInitEx(tcp_ssl_main_task_func, TASK_NAME, tcp_ssl_main_cbfunc)

