--[[
@module  websocket_main
@summary WebSocket client 主应用功能模块
@version 1.2
@date    2025.08.24
@author  陈媛媛
@usage
本文件为WebSocket client 主应用功能模块，核心业务逻辑为：
1、创建一个WebSocket client，连接server；
2、处理连接/异常逻辑，出现异常后执行重连动作；
3、调用websocket_receiver的外部接口websocket_receiver.proc，对接收到的数据进行处理；
4、调用sysplus.sendMsg接口，发送"CONNECT OK"和"DISCONNECTED"两种类型的"WEBSOCKET_EVENT"消息到websocket_sender的task，控制数据发送逻辑；
5、收到WebSocket数据后，执行sys.publish("FEED_NETWORK_WATCHDOG") 对网络环境检测看门狗功能模块进行喂狗；

本文件没有对外接口，直接在main.lua中require "websocket_main"就可以加载运行；
]]

-- 加载WebSocket client数据接收功能模块
local websocket_receiver = require "websocket_receiver"
-- 加载WebSocket client数据发送功能模块
local websocket_sender = require "websocket_sender"

-- WebSocket服务器地址和端口
-- 这里使用的地址和端口，会不定期重启或维护，仅能用作测试用途，不可商用，说不定哪一天就关闭了
-- 用户开发项目时，替换为自己的商用服务器地址和端口
-- 加密TCP链接 wss 表示加密
local SERVER_URL = "wss://echo.airtun.air32.cn/ws/echo"
-- 这是另外一个测试服务, 能响应websocket的二进制帧
--local SERVER_URL = "ws://echo.airtun.air32.cn/ws/echo2"

-- websocket_main的任务名
local TASK_NAME = websocket_sender.TASK_NAME_PREFIX.."main"

-- WebSocket client的事件回调函数
local function websocket_client_event_cbfunc(ws_client, event, data, fin, opcode)
    log.info("WebSocket事件回调", ws_client, event, data, fin, opcode)

    -- WebSocket连接成功
    if event == "conack" then
        sysplus.sendMsg(TASK_NAME, "WEBSOCKET_EVENT", "CONNECT", true)
        -- 连接成功，通知网络环境检测看门狗功能模块进行喂狗
        sys.publish("FEED_NETWORK_WATCHDOG")

    -- 接收到服务器下发的数据
    -- data：string类型，表示接收到的数据
    -- fin：number类型，1表示是最后一个数据包，0表示还有后续数据包
    -- opcode：number类型，表示数据包类型（1-文本，2-二进制）
    elseif event == "recv" then
        -- 对接收到的数据处理
        websocket_receiver.proc(data, fin, opcode)

    -- 发送成功数据
    -- data：number类型，表示发送状态（通常为nil或0）
    elseif event == "sent" then
        log.info("WebSocket事件回调", "数据发送成功，发送确认")
        -- 发送消息通知 websocket sender task
        sysplus.sendMsg(websocket_sender.TASK_NAME, "WEBSOCKET_EVENT", "SEND_OK", data)

    -- 服务器断开WebSocket连接
    elseif event == "disconnect" then
        -- 发送消息通知 websocket main task
        sysplus.sendMsg(TASK_NAME, "WEBSOCKET_EVENT", "DISCONNECTED", false)

    -- 严重异常，本地会主动断开连接
    -- data：string类型，表示具体的异常，有以下几种：
    --       "connect"：tcp连接失败
    --       "tx"：数据发送失败
    --       "rx"：数据接收失败（解析错误等）
    --       "other"：其他异常
    elseif event == "error" then
        log.error("WebSocket错误", "错误类型:", data)
        if data == "connect" then
            -- 发送消息通知 websocket main task，连接失败
            sysplus.sendMsg(TASK_NAME, "WEBSOCKET_EVENT", "CONNECT", false)
        elseif data == "tx" or data == "rx" or data == "other" then
            -- 发送消息通知 websocket main task，出现异常
            sysplus.sendMsg(TASK_NAME, "WEBSOCKET_EVENT", "ERROR")
        else
            -- 处理未知错误类型
            log.error("WebSocket错误", "未知错误类型:", data)
            sysplus.sendMsg(TASK_NAME, "WEBSOCKET_EVENT", "ERROR")
        end
    end
end

-- websocket main task 的任务处理函数
local function websocket_client_main_task_func()
    local ws_client
    local result, msg

    while true do
        -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
        while not socket.adapter(socket.dft()) do
            log.warn("WebSocket主任务", "等待网络就绪", socket.dft())
            -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
            -- 或者等待1秒超时退出阻塞等待状态;
            -- 注意：此处的1000毫秒超时不要修改的更长；
            -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
            -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
            -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
            sys.waitUntil("IP_READY", 1000)
        end

        -- 检测到了IP_READY消息
        log.info("WebSocket主任务", "收到网络就绪消息", socket.dft())

        -- 清空此task绑定的消息队列中的未处理的消息
        sysplus.cleanMsg(TASK_NAME)

        -- 创建WebSocket client对象
        ws_client = websocket.create(nil, SERVER_URL)
        -- 如果创建WebSocket client对象失败
        if not ws_client then
            log.error("WebSocket主任务", "WebSocket创建失败")
            goto EXCEPTION_PROC
        end

        -- 设置自定义请求头
        --如果有需要，根据自己的实际需求，在此处配置请求头并打开注释。
        --if ws_client.headers then
           --ws_client:headers({Auth="Basic ABCDEGG"})
        --end

        -- 注册WebSocket client对象的事件回调函数
        ws_client:on(websocket_client_event_cbfunc)

        -- 连接server
        result = ws_client:connect()
        -- 如果连接server失败
        if not result then
            log.error("WebSocket主任务", "WebSocket连接失败")
            goto EXCEPTION_PROC
        end

        -- 连接、断开连接、异常等各种事件的处理调度逻辑
        while true do
            -- 等待"WEBSOCKET_EVENT"消息
            msg = sysplus.waitMsg(TASK_NAME, "WEBSOCKET_EVENT")
            log.info("WebSocket主任务等待消息", msg[2], msg[3], msg[4])

            -- connect连接结果
            -- msg[3]表示连接结果，true为连接成功，false为连接失败
            if msg[2] == "CONNECT" then
                -- WebSocket连接成功
                if msg[3] then
                    log.info("WebSocket主任务", "连接成功")
                    -- 通知websocket sender数据发送应用模块的task，WebSocket连接成功
                    sysplus.sendMsg(websocket_sender.TASK_NAME, "WEBSOCKET_EVENT", "CONNECT_OK", ws_client)
                -- WebSocket连接失败
                else
                    log.info("WebSocket主任务", "连接失败")
                    -- 退出循环，发起重连
                    break
                end

            -- 需要主动关闭WebSocket连接
            -- 用户需要主动关闭WebSocket连接时，可以调用sysplus.sendMsg(TASK_NAME, "WEBSOCKET_EVENT", "CLOSE")
            elseif msg[2] == "CLOSE" then
                -- 主动断开WebSocket client连接
                ws_client:disconnect()
                -- 发送disconnect之后，此处延时1秒，给数据发送预留一点儿时间
                sys.wait(1000)
                break

            -- 被动关闭了WebSocket连接
            -- 被网络或者服务器断开了连接
            elseif msg[2] == "DISCONNECTED" then
                break

            -- 出现了其他异常
            elseif msg[2] == "ERROR" then
                break
            end
        end

        -- 出现异常
        ::EXCEPTION_PROC::

        -- 清空此task绑定的消息队列中的未处理的消息
        sysplus.cleanMsg(TASK_NAME)

        -- 通知websocket sender数据发送应用模块的task，WebSocket连接已经断开
        sysplus.sendMsg(websocket_sender.TASK_NAME, "WEBSOCKET_EVENT", "DISCONNECTED")

        -- 如果存在WebSocket client对象
        if ws_client then
            -- 关闭WebSocket client，并且释放WebSocket client对象
            ws_client:close()
            ws_client = nil
        end

        -- 5秒后跳转到循环体开始位置，自动发起重连（与MQTT保持一致）
        sys.wait(5000)
    end
end

--创建并且启动一个task
sysplus.taskInitEx(websocket_client_main_task_func, TASK_NAME)