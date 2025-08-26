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

local count = 0

-- led task的任务处理函数
local function led_task_func()
    while true do
        log.info("led_task_func")
        sys.waitUntil("INVALID_MESSAGE")
    end
end

-- 创建并启动第一个led task
-- 运行这个task的任务处理函数led_task_func
while true do
    sys.taskInit(led_task_func)
    count = count+1
    log.info("create task count", count)
end

