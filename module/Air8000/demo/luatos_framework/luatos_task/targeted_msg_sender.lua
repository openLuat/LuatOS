--[[
@module  targeted_msg_sender
@summary “用户定向消息发送”演示功能模块
@version 1.0
@date    2025.08.12
@author  朱天华
@usage
本文件为targeted_msg_sender应用功能模块，用来演示“用户定向消息发送”功能，核心业务逻辑为：
1、创建并且启动一个基础task，每隔一秒钟向两个高级task发布各发送一条定向消息；

本文件没有对外接口，直接在main.lua中require "targeted_msg_sender"就可以加载运行；
]]


local function targeted_msg_sender_task_func()
    local count = 0

    while true do
        count = count+1

        -- 发布一条定向消息到名称为"nromal_wait_msg_task"的高级task
        -- 消息名称为"SEND_DATA_REQ"
        -- 消息携带两个参数：
        -- 第一个参数是"from task"
        -- 第二个参数是number类型的count
        sys.sendMsg("nromal_wait_msg_task", "SEND_DATA_REQ", "from task", count)

        -- 发布一条定向消息到名称为"delay_wait_msg_task"的高级task
        -- 消息名称为"SEND_DATA_REQ"
        -- 消息携带两个参数：
        -- 第一个参数是"from task"
        -- 第二个参数是number类型的count
        sys.sendMsg("delay_wait_msg_task", "SEND_DATA_REQ", "from task", count)

        -- 延时等待1秒
        sys.wait(1000)
    end
end


-- 创建并且启动一个基础task
-- 运行这个task的任务处理函数targeted_msg_sender_task_func
sys.taskInit(targeted_msg_sender_task_func)

