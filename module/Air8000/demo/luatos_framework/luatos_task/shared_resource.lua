--[[
@module  shared_resource
@summary 共享资源访问演示 
@version 1.0
@date    2025.08.15
@author  朱天华
@usage
本文件为shared_resource应用功能模块，用来演示多个task访问共享资源，核心业务逻辑为：
1、创建一个全局共享变量global_shared_variable，变量值初始化为0；
2、创建两个task，task1和task2；
2、在task1的任务处理函数中：
   (1) 每隔1秒，执行一次for循环
   (2) 循环体内循环100次，每次将全局共享变量global_shared_variable的值加1
3、在task2的任务处理函数中，每隔300毫秒，task2的计数器加1，并且通过日志打印task2计数器的值；

本文件没有对外接口，直接在main.lua中require "task_scheduling"就可以加载运行；
]]

-- 全局共享变量，初始值为0
local global_shared_variable = 0

-- 第一个task的任务处理函数
local function task1_func()
    while true do
        log.info("task1_func", "for循环前，全局共享变量的值:", global_shared_variable)

        for i=1,100 do
            global_shared_variable = global_shared_variable + 1
            -- sys.wait(5)
        end

        log.info("task1_func", "for循环后，全局共享变量的值:", global_shared_variable)

        sys.wait(1000)
    end
end


-- 第二个task的任务处理函数
local function task2_func()
    while true do
        log.info("task2_func", "for循环前，全局共享变量的值:", global_shared_variable)

        for i=1,100 do
            global_shared_variable = global_shared_variable + 1
            -- sys.wait(5)
        end

        log.info("task2_func", "for循环后，全局共享变量的值:", global_shared_variable)

        sys.wait(1000)
    end
end


-- 创建并启动第一个task
-- 运行这个task的任务处理函数为task1_func
sys.taskInit(task1_func)

-- 创建并启动第二个task
-- 运行这个task的任务处理函数为task2_func
sys.taskInit(task2_func)

