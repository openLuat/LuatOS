--[[
@module  dtls_client_main
@summary dtls client socket主应用功能模块
@version 1.0
@date    2026.06.04
@usage
本文件为dtls client socket主应用功能模块，核心业务逻辑为：
1、创建一个dtls client socket（UDP + TLS/DTLS-PSK），连接server；
2、处理连接异常，出现异常后执行重连动作；
3、调用dtls_client_receiver和dtls_client_sender中的外部接口，进行数据收发处理；

本文件没有对外接口，直接在main.lua中require "dtls_client_main"就可以加载运行；
]]

local libnet = require "libnet"

-- 加载dtls client socket数据接收功能模块
local dtls_client_receiver = require "dtls_client_receiver"
-- 加载dtls client socket数据发送功能模块
local dtls_client_sender = require "dtls_client_sender"

-- DTLS server地址和端口，请根据实际情况修改
local SERVER_ADDR = "10.93.192.3"
local SERVER_PORT = 5684

-- DTLS-PSK 配置，请根据实际情况修改
local DTLS_PSK = "luatos-dtls-psk"
local DTLS_PSK_IDENTITY = "luatos-dtls-id"

-- dtls_client_main的任务名
local TASK_NAME = dtls_client_sender.TASK_NAME


-- 处理未识别的消息
local function dtls_client_main_cbfunc(msg)
	log.info("dtls_client_main_cbfunc", msg[1], msg[2], msg[3], msg[4])
end

-- dtls client socket的任务处理函数
local function dtls_client_main_task_func()
    -- socket.sslLog(3) -- 设置ssl日志级别，0-关闭，1-错误，2-警告，3-信息，4-调试
    local socket_client
    local result, para1, para2

    while true do
        sys.wait(5000)
        -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
        -- while not socket.adapter(socket.dft()) do
        --     log.warn("dtls_client_main_task_func", "wait IP_READY", socket.dft())
        --     -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        --     -- 或者等待1秒超时退出阻塞等待状态;
        --     sys.waitUntil("IP_READY", 1000)
        -- end
        -- 获取网卡IP地址
        local ip = netdrv.ipv4(socket.LWIP_STA)
        log.info("dtls_client_main_task_func", "netdrv.ipv4", ip)
        -- 检测到了IP_READY消息
        log.info("dtls_client_main_task_func", "recv IP_READY", socket.dft())

        -- 创建socket client对象
        socket_client = socket.create(nil, TASK_NAME)
        -- 如果创建socket client对象失败
        if not socket_client then
            log.error("dtls_client_main_task_func", "socket.create error")
            goto EXCEPTION_PROC
        end

        -- 配置socket client对象为dtls client (UDP + TLS)
        -- 参数：local_port, is_udp, is_tls, keep_idle, keep_interval, keep_cnt, server_cert(psk), client_cert(psk_identity)
        result = socket.config(socket_client, nil, true, true, nil, nil, nil, DTLS_PSK, DTLS_PSK_IDENTITY)
        -- 如果配置失败
        if not result then
            log.error("dtls_client_main_task_func", "socket.config error")
            goto EXCEPTION_PROC
        end

        -- 连接server
        result = libnet.connect(TASK_NAME, 30000, socket_client, SERVER_ADDR, SERVER_PORT)
        -- 如果连接server失败
        if not result then
            log.error("dtls_client_main_task_func", "libnet.connect error")
            goto EXCEPTION_PROC
        end

        log.info("dtls_client_main_task_func", "libnet.connect success")

        -- 连接成功后，发布一个事件给aircloud_data文件，通知连接成功了
        sys.publish("CONNECTION_SUCCESS")

        -- 数据收发以及网络连接异常事件总处理逻辑
        while true do
            -- 数据接收处理
            if not dtls_client_receiver.proc(socket_client) then
                log.error("dtls_client_main_task_func", "dtls_client_receiver.proc error")
                break
            end

            -- 数据发送处理
            if not dtls_client_sender.proc(TASK_NAME, socket_client) then
                log.error("dtls_client_main_task_func", "dtls_client_sender.proc error")
                break
            end

            -- 阻塞等待socket.EVENT事件或者15秒钟超时
			result, para1, para2 = libnet.wait(TASK_NAME, 15000, socket_client)
            log.info("dtls_client_main_task_func", "libnet.wait", result, para1, para2)
			
			-- 如果连接异常，则退出循环
			if not result then
				log.warn("dtls_client_main_task_func", "connection exception")
				break
            end
        end


        -- 出现异常    
        ::EXCEPTION_PROC::

        -- 数据发送应用模块对来不及发送的数据做清空和通知失败处理
        dtls_client_sender.exception_proc()

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
--运行这个task的主函数dtls_client_main_task_func
sys.taskInitEx(dtls_client_main_task_func, TASK_NAME, dtls_client_main_cbfunc)
