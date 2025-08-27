--[[
@module  scheduling
@summary task调度演示 
@version 1.0
@date    2025.08.12
@author  朱天华
@usage
本文件为task_scheduling应用功能模块，用来演示task调度，核心业务逻辑为：
1、创建两个task，task1和task2；
2、在task1的任务处理函数中，每隔500毫秒，task1的计数器加1，并且通过日志打印task1计数器的值；
3、在task2的任务处理函数中，每隔300毫秒，task2的计数器加1，并且通过日志打印task2计数器的值；

本文件没有对外接口，直接在main.lua中require "task_scheduling"就可以加载运行；
]]


-- 第一个task的任务处理函数
local function task1_func()
    local count = 0
    while true do
        count = count + 1
        log.info("task1_func", "运行中，计数:", count)
        -- 等待500ms
        sys.wait(500)  
    end
end


-- 第二个task的任务处理函数
local function task2_func()
    local count = 0
    while true do
        count = count + 1
        log.info("task2_func", "运行中，计数:", count)
        -- 等待300ms
        sys.wait(300)  
    end
end

-- 创建并启动第一个task
-- 运行这个task的任务处理函数task1_func
sys.taskInit(task1_func)

log.info("task_scheduling", "after task1 and before task2")

-- 创建并启动第二个task
-- 运行这个task的任务处理函数task2_func
sys.taskInit(task2_func)

