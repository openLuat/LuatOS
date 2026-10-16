--[[
@module  task_count
@summary “创建task的数量”演示功能模块 
@version 1.0
@date    2025.08.12
@author  朱天华
@usage
本文件为task_count应用功能模块，用来演示“可以创建多少个task”，核心业务逻辑为：
执行一个while true循环，每次执行到循环体内，执行以下两项动作：
1、创建并且启动一个task，启动后，task处于阻塞状态，永远不会死亡
2、task数量的计数器加一，并且打印当前已经创建的task总数量

本文件没有对外接口，直接在main.lua中require "task_count"就可以加载运行；
]]

local count = 0

-- task的任务处理函数
local function led_task_func()
    while true do
        log.info("led_task_func")
        sys.waitUntil("INVALID_MESSAGE")
    end
end

-- 不断地创建task，直到ram资源耗尽
while true do
    sys.taskInit(led_task_func)
    count = count+1
    log.info("create task count", count)
end

