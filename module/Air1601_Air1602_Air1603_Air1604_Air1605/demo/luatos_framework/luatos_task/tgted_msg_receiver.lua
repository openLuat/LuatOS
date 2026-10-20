--[[
@module  tgted_msg_receiver
@summary “使用sys.waitMsg接口实现task内用户定向消息接收”功能演示模块
@version 1.0
@date    2025.08.12
@author  朱天华
@usage
本文件为tgted_msg_receiver应用功能模块；
用来演示“使用sys.waitMsg接口实现task内用户定向消息接收”的功能，核心业务逻辑为：
1、创建并且启动一个高级task，task名称为"nromal_wait_msg_task"，在task的任务处理函数内及时接收发送给自己的定向消息；
2、创建并且启动另一个高级task，task名称为"delay_wait_msg_task"，在task的任务处理函数内延时接收发送给自己的定向消息；

本文件没有对外接口，直接在main.lua中require "tgted_msg_receiver"就可以加载运行；
]]

local function normal_wait_msg_task_func()
    local msg
    while true do
        msg = sys.waitMsg("nromal_wait_msg_task", "SEND_DATA_REQ")
        if msg then
            log.info("normal_wait_msg_task_func", msg[1], msg[2], msg[3], msg[4])
        end
    end
end

local function delay_wait_msg_task_func()
    local msg
    while true do
        -- 阻塞等待3秒钟
        -- 在这段时间内，本task无法及时处理定向消息发送模块发布的"SEND_DATA_REQ"消息
        -- 但是不会造成消息丢失，消息会存储到本task绑定的定向消息队列中
        -- 虽然不会造成消息丢失，但是业务逻辑中这样写明显也存在问题，因为消息处理的及时性很差
        sys.wait(3000)
        
        msg = sys.waitMsg("delay_wait_msg_task", "SEND_DATA_REQ")
        if msg then
            log.info("delay_wait_msg_task_func", msg[1], msg[2], msg[3], msg[4])
        end
    end
end

-- 创建并且启动一个高级task，task名称为"nromal_wait_msg_task"
-- 运行这个task的任务处理函数normal_wait_msg_task_func
sys.taskInitEx(normal_wait_msg_task_func, "nromal_wait_msg_task")

-- 创建并且启动一个高级task，task名称为"delay_wait_msg_task"
-- 运行这个task的任务处理函数delay_wait_msg_task_func
sys.taskInitEx(delay_wait_msg_task_func, "delay_wait_msg_task")
