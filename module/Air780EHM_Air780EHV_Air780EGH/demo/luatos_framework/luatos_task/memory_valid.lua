--[[
@module  memory_valid
@summary “查看用户可用ram信息”演示功能模块
@version 1.0
@date    2025.08.12
@author  朱天华
@usage
本文件为memory_valid应用功能模块，用来演示：如何查看用户可用ram信息，核心业务逻辑为：
1、创建一个task；
2、在task的任务处理函数中，每隔1秒查询一次当前的ram信息；

本文件没有对外接口，直接在main.lua中require "memory_valid"就可以加载运行；
]]


local function print_mem_info()
    -- 这个接口可以强制执行一次垃圾内存回收，方便我们分析内存信息
    -- 在实际项目开发中中，用户不需要主动使用这个接口，LuatOS内部的Lua虚拟机会自动进行垃圾回收
    collectgarbage()

    -- rtos.meminfo()有三个返回值：
    -- 1、总ram大小（单位字节）
    -- 2、运行过程中实时使用的ram大小（单位字节）
    -- 3、运行过程中历史使用的最高ram大小（单位字节）

    -- rtos.meminfo()是Lua虚拟机中的用户可用ram信息，用户开发的大部分LuatOS脚本程序都是自动从这里分配ram
    log.info("mem.lua", rtos.meminfo())
    -- rtos.meminfo("sys")是内核系统中的用户可用ram信息，用户使用zbuff核心库时，会用到这部分ram
    -- 在这里我们就不展开讲这一部分了，等讲到zbuff的时候再做讨论
    log.info("mem.sys", rtos.meminfo("sys"))
end


local function mem_task_func()
    while true do
        -- 打印当前的ram信息
        print_mem_info()

        -- 延时1秒
        sys.wait(1000)
    end
end

-- 创建并启动一个task
-- 运行这个task的任务处理函数mem_task_func
sys.taskInit(mem_task_func)

