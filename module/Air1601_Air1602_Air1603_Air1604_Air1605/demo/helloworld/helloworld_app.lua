--[[
@module  helloworld_app
@summary helloworld应用功能模块 
@version 1.0
@date    2026.04.15
@author  沈园园
@usage
本文件为helloworld应用功能模块，核心业务逻辑为：
1、每隔三秒钟通过日志输出一次hello world；

本文件没有对外接口，直接在main.lua中require "helloworld_app"就可以加载运行；
]]


local function helloworld_task_func()
    while true do
        -- 每隔三秒钟通过日志输出一次hello world
        log.info("hello world")
        sys.wait(3000)
    end
end

--创建一个task，并且运行task的主函数helloworld_task_func
sys.taskInit(helloworld_task_func)
