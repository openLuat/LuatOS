--[[
@module  global_msg_sender
@summary “用户全局消息发送”演示功能模块
@version 1.0
@date    2025.08.12
@author  朱天华
@usage
本文件为global_msg_sender应用功能模块，用来演示“用户全局消息发送”功能，核心业务逻辑为：
1、创建并且启动一个基础task，每隔一秒钟发布一条全局消息；
2、创建并且启动一个循环定时器，每隔一秒钟发布一条全局消息；

本文件没有对外接口，直接在main.lua中require "global_msg_sender"就可以加载运行；
]]


local function global_sender_msg_task_func()
    local count = 0

    while true do
        count = count+1

        -- 发布一条全局消息
        -- 消息名称为"SEND_DATA_REQ"
        -- 消息携带两个参数：
        -- 第一个参数是"from task"
        -- 第二个参数是number类型的count
        sys.publish("SEND_DATA_REQ", "from task", count)

        -- 延时等待1秒
        sys.wait(1000)
    end
end


local timer_count = 0

local function global_sender_msg_timer_cbfunc()
    timer_count = timer_count+1

    -- 发布一条全局消息
    -- 消息名称为"SEND_DATA_REQ"
    -- 消息携带两个参数：
    -- 第一个参数是"from timer"
    -- 第二个参数是number类型的timer_count
    sys.publish("SEND_DATA_REQ", "from timer", timer_count)
end


-- 创建并且启动一个基础task
-- 运行这个task的任务处理函数global_sender_msg_task_func
sys.taskInit(global_sender_msg_task_func)

-- 首先执行定时器的处理函数发布一条全局消息
global_sender_msg_timer_cbfunc()
-- 创建并且启动一个超时时长为1秒钟的循环定时器
sys.timerLoopStart(global_sender_msg_timer_cbfunc, 1000)

