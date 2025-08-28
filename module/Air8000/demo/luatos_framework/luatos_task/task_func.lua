--[[
@module  task_func
@summary “task任务处理函数”演示功能模块 
@version 1.0
@date    2025.08.12
@author  朱天华
@usage
本文件为task_func应用功能模块，用来演示“如何设置task任务处理函数”，核心业务逻辑为：
1、创建一个task时，需要设置task任务处理函数；
2、演示一种常见的错误设置方式；

本文件没有对外接口，直接在main.lua中require "task_func"就可以加载运行；
]]

-- 创建并启动一个led task
-- 运行这个task的任务处理函数led_task_func
-- 此处运行会报错，因为执行到这行代码时，找不到led_task_func函数的定义，犯了“先使用，后定义”的错误
sys.taskInit(led_task_func)


local function led_task_func()
    while true do
        log.info("led_task_func")
        sys.wait(1000)
    end
end

