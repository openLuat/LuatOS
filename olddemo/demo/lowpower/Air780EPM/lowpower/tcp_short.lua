--[[
@module  tcp_short
@summary 短连接TCP客户端功能模块
@version 1.0
@date    2025.07.17
@author  陈取德
@usage
本文件实现了一个短连接TCP客户端，核心功能：
1. 等待特定消息触发TCP连接
2. 建立连接后发送队列中的数据
3. 完成发送后阻塞3秒，等待平台下发的返回信息
4. 3秒后如果没收到则默认平台无返回信息，随机释放客户端，避免造成过多功耗浪费
5. 适用于低功耗场景下的周期性数据上报
本模块功能具备以下对外接口
1. 可以通过推送消息给"tcp_short"，触发消息自动发送。
2. 通过订阅"tcp_short_close"主题，可以知道tcp_short功能模块任务完成并释放了tcp客户端，并且消息还携带了信息发送状态和平台返回信息
]] -- 
-- 服务器地址配置
local SERVER_ADDR = "112.125.89.8"
-- 服务器端口配置
local SERVER_PORT = 44706
-- 任务名称，用于标识当前TCP客户端任务
local tcp_short = "tcp_short"

-- 引入网络库，提供TCP通信功能
local libnet = require "libnet"

local tcp_rec = true
local recv_buff = nil -- 接收消息缓存区
local socket_client -- 声明socket客户端对象
local result, rec_result -- 声明TCP连接任务结果，接收消息结果
local send_data, rec_data , _  -- 声明发送数据的变量和收到的数据变量

--[[
@function tcp_short_main_cbfunc
@summary TCP客户端主任务回调函数
@param msg 消息内容数组
@usage 用于处理来自系统的消息通知
]]
local function tcp_short_main_cbfunc(msg)
    log.info("tcp_client_main_cbfunc", msg[1], msg[2], msg[3], msg[4])
end
--[[
函数名称: tcp_rec_short
功能描述: 短连接TCP数据接收处理函数
          接收TCP下发的数据，接收成功后取出数据给rec_data
--]]
local function tcp_rec_short()
    -- 检查接收缓冲区是否存在，如果不存在则创建1024字节的缓冲区
    if recv_buff == nil then
        recv_buff = zbuff.create(1024)
    end
    -- 从socket客户端接收数据到缓冲区
    rec_result = socket.rx(socket_client, recv_buff)
    if rec_result then
        -- 取出缓冲区中的数据
        rec_data = recv_buff:query()
        -- 如果接收到数据不为空
        if rec_data ~= nil then
            -- 记录接收到的数据
            log.info("收到数据", rec_data)
        else
            -- 如果没有接收到数据
            log.info("无数据返回")
        end
    else
        log.info("数据读取失败")
    end

end
--[[
@function tcp_short_main
@summary TCP客户端主任务函数
@usage 实现TCP连接建立、数据发送和连接关闭的完整流程
]]
local function tcp_short_main()
    while not socket.adapter(socket.dft()) do
        -- 在此处阻塞等待4G连接成功的消息"IP_READY"，避免联网过快，丢失了"IP_READY"信息而导致一直被卡住。
        -- 或者等待30秒超时退出阻塞等待状态
        log.warn("tcp_client_main_task_func", "wait IP_READY")
        local mobile_result = sys.waitUntil("IP_READY", 30000)
        if mobile_result then
            log.info("4G已经连接成功。")
        else
            log.info("SIM卡异常,当前状态：", mobile.status(), "。请检查SIM卡!")
            -- 30S后网络还没连接成功，开关一下飞行模式，让SIM卡软重启，重新尝试驻网。
            mobile.flymode(0, true)
            mobile.flymode(0, false)
        end
    end
    -- 阻塞等待接收指定taskname为"tcp_short"的任务信息
    send_data = sys.waitMsg(tcp_short)
    -- 等待网络适配器就绪
    log.info("tcp_client_create", "recv IP_READY", socket.dft())
    -- 创建socket客户端对象
    socket_client = socket.create(nil, tcp_short)
    -- 检查socket客户端是否创建成功
    if socket_client then
        -- 配置socket客户端
        if socket.config(socket_client, nil, nil, nil, 300, 10, 3) then
            -- 连接服务器，超时时间15000ms
            if libnet.connect(tcp_short, 15000, socket_client, SERVER_ADDR, SERVER_PORT) then
                -- 发送数据，超时时间15000ms
                result = libnet.tx(tcp_short, 15000, socket_client, send_data[2])
                -- 阻塞等待socket.EVENT事件或者3秒钟超时
                -- 以下三种业务逻辑会发布事件：
                -- 1、socket client和server之间的连接出现异常（例如server主动断开，网络环境出现异常等），此时在内核固件中会发布事件socket.EVENT
                -- 2、socket client接收到server发送过来的数据，此时在内核固件中会发布事件socket.EVENT
                -- 3、socket client需要发送数据到server, 在tcp_client_sender.lua中会发布事件socket.EVENT
                if tcp_rec then
                    _ , rec_result = libnet.wait(tcp_short, 3000, socket_client)
                    -- 有事件触发就执行接收信息动作，超时打印结果
                    if rec_result then
                        tcp_rec_short()
                    else
                        log.info("tcp_rec_short", "获取信息超时,平台无下发信息。")
                    end
                end
            else
                result = "connect false" -- tcp客户端连接失败
            end
        else
            result = "config false" -- tcp客户端配置失败
        end
    else
        result = "create false" -- tcp客户端创建失败
    end

    -- 打印TCP处理结果
    if result == true then
        log.info("tcp_short 发送完成")
    else
        log.error("tcp_short 发送异常，原因为：", "libnet." .. result .. " error")
    end
    -- 关闭连接，超时时间5000ms
    libnet.close(tcp_short, 5000, socket_client)
    -- 释放socket客户端资源
    socket.release(socket_client)
    socket_client = nil
    log.info("tcp_short", "close")
    -- 推送"tcp_short_result"消息，告知外部代码块tco_short模块任务已完成，并携带着发送信息结果和接收到平台的信息。
    sys.publish("tcp_short_result", result, rec_data)
end

sys.taskInitEx(tcp_short_main, tcp_short, tcp_short_main_cbfunc)
