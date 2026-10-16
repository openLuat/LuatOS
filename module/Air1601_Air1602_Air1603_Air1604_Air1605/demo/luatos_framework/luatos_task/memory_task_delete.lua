--[[
@module  memory_task_delete
@summary “高级task的sys.taskDel函数对内存资源释放”演示功能模块 
@version 1.0
@date    2025.12.02
@author  朱天华
@usage
本文件为memory_task_delete应用功能模块，用来演示“高级task的sys.taskDel函数对内存资源释放”，核心业务逻辑为：

1、打印下当前的ram信息；
2、创建并且启动一个高级task；在高级task的任务处理函数内，业务逻辑如下：
   (2.1) 循环发送1000次定向消息到高级task；
   (2.2) 不接收处理定向消息;
   (2.3) 有选择的调用sys.taskDel函数对高级task占用的内存资源进行释放；
   (2.4) 退出任务处理函数；
3、打印下当前的ram信息；

2.3步骤中调用或者不调用sys.taskDel函数，对比第1步和第3步的ram信息；
来理解“高级task的sys.taskDel函数对内存资源释放”的功能

本文件没有对外接口，直接在main.lua中require "memory_task_delete"就可以加载运行；
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
    -- log.info("mem.sys", rtos.meminfo("sys"))
end

-- led task的任务处理函数
local function led_task_func()
    for i=1, 1000 do
        sys.sendMsg("led_task", "targeted_msg_"..i)
    end

    -- 下一行代码会导致task运行异常
    -- 在此处task异常退出，不会执行后续的代码
    -- dhjsk = las + 2

    -- 有选择的打开或者关闭下一行代码
    -- 可以对比看出sys.taskDel对内存释放的作用
    sys.taskDel("led_task")
end

log.info("before led task")
-- 在创建一个task之前，打印下当前的ram信息
print_mem_info()

-- 创建并启动一个led task
-- 运行这个task的任务处理函数led_task_func
sys.taskInitEx(led_task_func, "led_task")

log.info("after led task")
-- task运行结束之后，每隔1秒钟打印一次当前的ram信息
sys.timerLoopStart(print_mem_info, 1000)

