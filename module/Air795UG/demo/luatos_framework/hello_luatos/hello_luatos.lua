--[[
@module  hello_luatos
@summary hello_luatos应用功能模块 
@version 1.0
@date    2025.07.19
@author  朱天华
@usage
本文件为hello_luatos应用功能模块，核心业务逻辑为：
1、创建一个task；
2、在task的任务处理函数中，每隔一秒钟通过日志输出一次Hello, LuatOS；

本文件没有对外接口，直接在main.lua中require "hello_luatos"就可以加载运行；
]]


-- hello_luatos的任务处理函数
local function hello_luatos_task_func()
    while true do
        -- 输出日志 Hello, LuatOS
        log.info("Hello, LuatOS")
               
        -- 延时1000毫秒
        sys.wait(1000)
    end
end


-- 创建并且启动一个task
-- 运行这个task的处理函数hello_luatos_task_func
sys.taskInit(hello_luatos_task_func)
