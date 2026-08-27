--[[
@module  socket_ipv6
@summary tcp client使用IPv6连接服务器示例
@version 1.0
@date    2026.08.24
@author  拓毅恒
@usage

注意：
服务器地址使用合宙Netlab分配的测试服务器 https://iot.luatos.com/#/page6/netlab ，实际项目中时需要使用自己的服务器

本文件为tcp client使用IPv6连接服务器的应用功能模块，核心业务逻辑为：
1、等待ipv6_info发布 IPV6_READY 消息后创建并配置tcp client
2、连接服务器，每分钟发送一条 "hello world" 到服务器
3、连接异常后自动关闭并重新连接

本文件没有对外接口，直接在main.lua中require "socket_ipv6"就可以加载运行；
]]

local TAG = "socket_ipv6"
local libnet = require "libnet"

-- 电脑访问：https://iot.luatos.com/#/p8000/netlab ，创建一个 TCP server
-- 将 server 的地址和端口赋值给下面这两个变量
local SERVER_ADDR = "115.120.239.161"
local SERVER_PORT = 21979

-- 本任务的名字，socket.create / libnet 系列接口都要用
local TASK_NAME = "socket_ipv6"

local function socket_ipv6_task()
    local socket_client
    local result, para1, para2

    while true do
        -- 等待 ipv6_info 广播的 IPV6_READY 消息
        sys.waitUntil("IPV6_READY")
        log.info(TAG, "网络已就绪，准备进行 IPv6 TCP 连接:", SERVER_ADDR, SERVER_PORT)

        -- 创建 socket client 对象
        socket_client = socket.create(nil, TASK_NAME)
        if not socket_client then
            log.error(TAG, "socket.create 失败，5 秒后重连")
            sys.wait(5000)
            goto EXCEPTION_PROC
        end

        -- 配置为 tcp client
        result = socket.config(socket_client, nil, nil, nil, 300, 10, 3)
        if not result then
            log.error(TAG, "socket.config 失败，5 秒后重连")
            sys.wait(5000)
            goto EXCEPTION_PROC
        end

        -- 连接服务器，最后一个参数 true 表示开启 IPv6
        result = libnet.connect(TASK_NAME, 15000, socket_client, SERVER_ADDR, SERVER_PORT, true)
        if not result then
            log.error(TAG, "IPv6 TCP 连接失败，请确认服务器支持 IPv6 且地址/端口正确，5 秒后重连")
            sys.wait(5000)
            goto EXCEPTION_PROC
        end
        log.info(TAG, "IPv6 TCP 连接成功")

        -- 收发主循环
        while true do
            -- 阻塞等待收发事件或 60 秒超时
            result, para1, para2 = libnet.wait(TASK_NAME, 60000, socket_client)
            log.info(TAG, "libnet.wait", result, para1, para2)

            -- 连接异常（断开/超时）则退出循环，进入重连
            if not result then
                log.warn(TAG, "连接异常断开，5 秒后重连")
                sys.wait(5000)
                break
            end

            -- 每分钟发送一条 hello world
            result = libnet.tx(TASK_NAME, 15000, socket_client, "hello world")
            if not result then
                log.error(TAG, "发送失败，准备重连")
                break
            end
            log.info(TAG, "已发送: hello world")
        end

        ::EXCEPTION_PROC::
        if socket_client then
            libnet.close(TASK_NAME, 5000, socket_client)
            socket.release(socket_client)
            socket_client = nil
        end
        sys.wait(5000)
    end
end

sys.taskInitEx(socket_ipv6_task, TASK_NAME)
