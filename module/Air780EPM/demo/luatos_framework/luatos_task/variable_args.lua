--[[
@module  variable_args
@summary “task创建时的可变参数”演示功能模块 
@version 1.0
@date    2025.08.12
@author  朱天华
@usage
本文件为variable_args应用功能模块，用来演示“task创建时的可变参数”如何使用，核心业务逻辑为：
1、创建一个task，可变参数部分携带5个参数；
2、在task的任务处理函数中打印传入的5个参数的值；

本文件没有对外接口，直接在main.lua中require "variable_args"就可以加载运行；
]]


local function led_task_func(arg1, arg2, arg3, arg4, arg5)
    while true do
        log.info("led_task_func", arg1, arg2, arg3, arg4, arg5)
        sys.wait(1000)
    end
end

-- 创建并启动一个task
-- 这个task的任务处理函数为led_task_func
-- 携带5个参数，分别为"arg1", 3, nil, true, led_task_func
-- 运行这个task的任务处理函数led_task_func时，会将这5个参数传递给任务处理函数使用
sys.taskInit(led_task_func, "arg1", 3, nil, true, led_task_func)
