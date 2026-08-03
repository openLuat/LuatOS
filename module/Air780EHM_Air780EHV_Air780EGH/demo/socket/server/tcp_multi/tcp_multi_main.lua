--[[
@module  tcp_multi_main
@summary tcp server主应用功能模块(一对多)
@version 1.0
@date    2026.08.02
@author  王世豪
@usage
本文件为tcp server主应用功能模块(一对多版本)，核心业务逻辑为：
1、创建一个tcp server，通过libnet.listen(task, 0, netc, backlog)开启一对多监听；
2、循环调用libnet.listen阻塞等待客户端接入，再调用socket.accept派生独立client连接；
3、每个client通过独立的事件回调处理数据收发与断开事件，互不影响；
4、server socket只负责listen和accept，不再复用为client通信通道；

本文件没有对外接口，直接在main.lua中require "tcp_multi_main"就可以加载运行；

与tcp/目录下的一对一版本的区别：
1、libnet.listen增加backlog参数(默认8)，允许排队等待accept的客户端数量；
2、socket.accept传入回调函数，派生独立client socket，每个client独立处理收发；
3、clients表管理所有已连接client，支持广播和单播；
4、server socket只负责listen/accept，不复用为client通信通道；
]]

local libnet = require "libnet"

-- 加载TCP服务器数据接收功能模块
local tcp_multi_receiver = require "tcp_multi_receiver"
-- 加载TCP服务器数据发送功能模块
local tcp_multi_sender = require "tcp_multi_sender"

-- tcp_multi_main的任务名
local TASK_NAME = tcp_multi_sender.TASK_NAME

-- 已连接client的socket列表，结构为{ [1]=client_netc, [2]=client_netc, ... }
-- 由tcp_multi_sender引用，用于广播发送
local clients = {}
tcp_multi_sender.clients = clients

-- 处理未识别的消息
local function tcp_multi_main_cbfunc(msg)
	log.info("tcp_multi_main_cbfunc", msg[1], msg[2], msg[3], msg[4])
end

-- 从clients列表中移除指定client
local function remove_client(client)
    for i, c in ipairs(clients) do
        if tostring(c) == tostring(client) then
            table.remove(clients, i)
            log.info("tcp_multi_main.remove_client", "剩余连接数=", #clients)
            return
        end
    end
end

-- 关闭并清理单个client
local function close_client(client)
    if not client then return end
    -- 先清理receiver为该client缓存的接收缓冲区
    tcp_multi_receiver.cleanup(client)
    -- 强制关闭client连接
    socket.close(client)
    -- 释放client对象
    socket.release(client)
    -- 从clients列表中移除
    remove_client(client)
end

-- 单个client的事件回调函数，在socket.accept时注册
-- 每次该client有事件(数据到来/断开等)时，都会被回调
local function client_event_cb(client, event, param)
    if event == socket.EVENT then
        -- 有数据到来或连接异常，交给receiver处理
        if not tcp_multi_receiver.proc(client) then
            log.info("tcp_multi_main.client_event_cb", "client数据收发异常，关闭", client)
            close_client(client)
        end
    elseif event == socket.CLOSED then
        -- 客户端主动断开
        log.info("tcp_multi_main.client_event_cb", "客户端断开", client)
        close_client(client)
    else
        log.info("tcp_multi_main.client_event_cb", "其他事件", event)
    end
end

-- tcp server socket的任务处理函数
local function tcp_multi_main_task_func()
    local server_netc = nil
    local result, code, client, ip, port
    local listen_port = 50003 -- tcp server监听的端口号
    local backlog = 8         -- 允许排队等待accept的客户端数量，0~8

    while true do
        -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
        while not socket.adapter(socket.dft()) do
            log.warn("tcp_multi_main_task_func", "wait IP_READY", socket.dft())
            -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
            -- 或者等待1秒超时退出阻塞等待状态;
            -- 注意：此处的1000毫秒超时不要修改的更长；
            -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
            -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
            -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
            sys.waitUntil("IP_READY", 1000)
        end

        -- 检测到了IP_READY消息
        log.info("tcp_multi_main_task_func", "recv IP_READY", socket.dft())

        server_netc = socket.create(socket.dft(), TASK_NAME)
        if not server_netc then
            log.error("tcp_multi_main_task_func", "socket.create失败")
            goto EXCEPTION_PROC
        end

        socket.debug(server_netc, true)
        -- 配置socker server 对象为tcp server
        result = socket.config(server_netc, listen_port, nil, nil, 300, 10, 3)
        -- 如果配置失败
        if not result then
            log.error("tcp_multi_main_task_func", "socket.config失败")
            goto EXCEPTION_PROC
        end

        log.info("tcp_multi_main_task_func", "准备监听", socket.localIP(socket.dft()), listen_port)

        -- 主循环：不断监听并accept新的客户端
        while true do
            -- 阻塞等待客户端连接请求到来，libnet.listen内部开启一对多监听模式
            -- backlog表示最多允许排队等待accept的客户端数量
            result, code = libnet.listen(TASK_NAME, 0, server_netc, backlog)
            log.info("tcp_multi_main_task_func", "listen返回", result, code)

            -- 监听失败或超时，退出主循环，进入异常处理
            if not result then
                log.error("tcp_multi_main_task_func", "监听失败或超时")
                break
            end

            -- 有客户端连接请求到来，accept派生一个新的独立client连接
            -- 第二个参数传入事件回调函数，之后该client的数据/断开事件都会进入client_event_cb
            result, client, ip, port = socket.accept(server_netc, client_event_cb)
            log.info("tcp_multi_main_task_func", "accept结果", result, client, ip, port)

            if result and client then
                -- accept成功，记录client信息到clients列表
                socket.debug(client, true)
                table.insert(clients, client)
                log.info("tcp_multi_main_task_func", "新客户端接入", "IP=", ip, "port=", port, "当前连接数=", #clients)

                -- 客户端连上了, 发一条数据给客户端(非阻塞发送)
                socket.tx(client, "TCP server is UP! you are client-"..#clients)
            else
                log.warn("tcp_multi_main_task_func", "accept失败，稍后重新监听")
            end
        end

        -- 出现异常
        ::EXCEPTION_PROC::

        -- 数据发送应用模块对来不及发送的数据做清空和通知失败处理
        tcp_multi_sender.exception_proc()

        -- 关闭并清理所有已连接的client
        log.info("tcp_multi_main_task_func", "异常处理：关闭所有client，数量=", #clients)
        while #clients > 0 do
            close_client(clients[1])
        end

        -- 如果存在socket server对象
        if server_netc then
            -- 关闭socket server连接
            libnet.close(TASK_NAME, 5000, server_netc)
            -- 释放socket server对象
            socket.release(server_netc)
            server_netc = nil
        end

        -- 等待5秒后，再次尝试创建新的连接
        sys.wait(5000)
    end
end

--创建并且启动一个task
--运行这个task的主函数tcp_multi_main_task_func
sys.taskInitEx(tcp_multi_main_task_func, TASK_NAME, tcp_multi_main_cbfunc)
