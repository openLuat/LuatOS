--[[
@module  create
@summary task调度演示 
@version 1.0
@date    2025.08.12
@author  朱天华
@usage
本文件为task_scheduling应用功能模块，用来演示task调度，核心业务逻辑为：
1、创建两个task，task1和task2；
2、在task1的任务处理函数中，每隔500毫秒，task1的计数器加1，并且通过日志打印task1计数器的值；
3、在task2的任务处理函数中，每隔300毫秒，task2的计数器加1，并且通过日志打印task2计数器的值；

本文件没有对外接口，直接在main.lua中require "create"就可以加载运行；
]]


-- tcp_client_main的任务名
local TASK_NAME = "TCP_CLINET_MAIN"


-- 非目标消息回调函数
local function mqtt_client_main_cbfunc(msg)
	log.info("mqtt_client_main_cbfunc", msg[1], msg[2], msg[3], msg[4])
end

-- mqtt main task 的任务处理函数
local function mqtt_client_main_task_func()
    -- 连接、断开连接、订阅、取消订阅、异常等各种事件的处理调度逻辑
    while true do
        -- 等待"MQTT_EVENT"消息
        msg = sys.waitMsg(TASK_NAME, "MQTT_EVENT")
        log.info("mqtt_client_main_task_func waitMsg", msg[2], msg[3], msg[4])

        -- connect连接结果
        -- msg[3]表示连接结果，true为连接成功，false为连接失败
        if msg[2] == "CONNECT" then
            -- mqtt连接成功
            if msg[3] then
                log.info("mqtt_client_main_task_func", "connect success")
            -- mqtt连接失败
            else
                log.info("mqtt_client_main_task_func", "connect error")
            end

        -- subscribe订阅结果
        -- msg[3]表示订阅结果，true为订阅成功，false为订阅失败
        elseif msg[2] == "SUBSCRIBE" then
            -- 订阅成功
            if msg[3] then
                log.info("mqtt_client_main_task_func", "subscribe success", "qos: "..(msg[4] or "nil"))
            -- 订阅失败
            else
                log.error("mqtt_client_main_task_func", "subscribe error", "code", msg[4])
            end

        -- 被动关闭了mqtt连接
        -- 被网络或者服务器断开了连接
        elseif msg[2] == "DISCONNECTED" then
            log.info("mqtt_client_main_task_func", "disconnected")
        end
    end
end

local function send_non_targeted_msg_task_func()
    local count = 0

    while true do
        count = count+1

        -- 向TASK_NAME这个任务发送一条消息
        -- 消息名称为"UNKNOWN_EVENT"
        -- 消息携带一个number类型的参数count
        sys.sendMsg(TASK_NAME, "UNKNOWN_EVENT", count)

        -- 延时等待1秒
        sys.wait(1000)
    end
end

local function send_non_targeted_msg_task_func()
    local count = 0

    while true do
        count = count+1

        -- 向TASK_NAME这个任务发送一条消息
        -- 消息名称为"UNKNOWN_EVENT"
        -- 消息携带一个number类型的参数count
        sys.sendMsg(TASK_NAME, "UNKNOWN_EVENT", count)

        -- 延时等待1秒
        sys.wait(1000)
    end
end


local function send_targeted_msg_task_func()
    while true do
        -- 向TASK_NAME这个任务发送一条消息
        -- 消息名称为"MQTT_EVENT"
        -- 消息携带两个参数
        -- 第一个参数为"CONNECT"
        -- 第二个参数为true
        -- 这条消息的意思是MQTT连接成功
        sys.sendMsg(TASK_NAME, "MQTT_EVENT", "CONNECT", true)

        -- 延时等待1秒
        sys.wait(1000)

        -- 向TASK_NAME这个任务发送一条消息
        -- 消息名称为"MQTT_EVENT"
        -- 消息携带三个参数
        -- 第一个参数为"SUBSCRIBE"
        -- 第二个参数为true
        -- 第三个参数为0
        -- 这条消息的意思是MQTT订阅成功，qos为0
        sys.sendMsg(TASK_NAME, "MQTT_EVENT", "SUBSCRIBE", true, 0)

        -- 延时等待1秒
        sys.wait(1000)

        -- 向TASK_NAME这个任务发送一条消息
        -- 消息名称为"MQTT_EVENT"
        -- 消息携带一个参数"DISCONNECTED"
        -- 这条消息的意思是MQTT连接被动断开
        sys.sendMsg(TASK_NAME, "MQTT_EVENT", "DISCONNECTED")

        -- 延时等待1秒
        sys.wait(1000)
    end
end

-- 创建并且启动一个高级task
-- task的任务处理函数为mqtt_client_main_task_func
-- task的名称为TASK_NAME变量的值"MQTT_CLINET_MAIN"
-- task的非目标消息回调函数为mqtt_client_main_cbfunc
-- 运行这个task的任务处理函数mqtt_client_main_task_func
sys.taskInitEx(mqtt_client_main_task_func, TASK_NAME, mqtt_client_main_cbfunc)


-- 创建并且启动一个基础task
-- 运行这个task的任务处理函数send_targeted_msg_task_func
sys.taskInit(send_non_targeted_msg_task_func)

-- 创建并且启动一个高级task
-- task的任务处理函数为send_targeted_msg_task_func
-- task的名称为SEND_TASK_NAME
-- 运行这个task的任务处理函数send_targeted_msg_task_func
sys.taskInitEx(send_targeted_msg_task_func, "SEND_MSG_TASK")
