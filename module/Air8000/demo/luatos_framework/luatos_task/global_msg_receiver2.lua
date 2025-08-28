--[[
@module  global_msg_receiver2
@summary “使用sys.waitUntil接口实现task内用户全局消息接收”功能模块
@version 1.0
@date    2025.08.12
@author  朱天华
@usage
本文件为global_msg_receiver2应用功能模块；
用来演示“使用sys.waitUntil接口实现task内用户全局消息接收”的功能，核心业务逻辑为：
1、创建一个基础task，演示“使用sys.waitUntil接口实现task内用户全局消息接收”的正确方法；
2、创建另一个基础task，演示“使用sys.waitUntil接口实现task内用户全局消息接收”的错误方法；

本文件没有对外接口，直接在main.lua中require "global_msg_receiver2"就可以加载运行；
]]


local function success_wait_until_base_task_func()
    local result, tag, count
    while true do
        result, tag, count = sys.waitUntil("SEND_DATA_REQ")
        if result then
            log.info("success_wait_until_base_task_func", tag, count)
        end
    end
end


local function lost_wait_until_base_task_func()
    local result, tag, count
    while true do
        -- 阻塞等待3秒钟
        -- 在这段时间内，本task无法及时处理全局消息发送模块发布的"SEND_DATA_REQ"消息，会造成消息丢失
        sys.wait(3000)
        
        result, tag, count = sys.waitUntil("SEND_DATA_REQ")
        if result then
            log.info("lost_wait_until_base_task_func", tag, count)
        end
    end
end

-- 创建并且启动一个基础task
-- 运行这个task的任务处理函数success_wait_until_base_task_func
sys.taskInit(success_wait_until_base_task_func)

-- 创建并且启动一个基础task
-- 运行这个task的任务处理函数lost_wait_until_base_task_func
sys.taskInit(lost_wait_until_base_task_func)

