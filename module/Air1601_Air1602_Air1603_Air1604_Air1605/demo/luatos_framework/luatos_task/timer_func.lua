--[[
@module  timer
@summary “定时器”演示功能模块
@version 1.0
@date    2025.08.12
@author  朱天华
@usage
本文件为timer应用功能模块，用来演示“定时器”如何使用，核心业务逻辑为：
1、演示单次定时器，循环定时器，task内的延时定时器的创建，启动，停止和删除功能；

本文件没有对外接口，直接在main.lua中require "timer"就可以加载运行；
]]


local function timer_test_task_func()
    -- 以下三行代码执行后，只有最后一个定时器存在
    sys.timerStart(log.info, 1000, "red")
    sys.timerStart(log.info, 2000, "red")
    sys.timerStart(log.info, 3000, "red")

    -- 阻塞等待3秒钟，实际上创建了一个3秒钟超时时长的单次定时器
    -- 超时时长到达后，会控制本task退出阻塞状态，继续运行
    sys.wait(3000)

    -- 创建并且启动一个循环定时器，每隔1秒钟执行一次sys.publish("loop_timer_cbfunc_msg")
    -- 相当于每隔1秒钟发布一条用户全局消息"loop_timer_cbfunc_msg"
    sys.timerLoopStart(sys.publish, 1000, "loop_timer_cbfunc_msg")

    -- 创建并且启动一个单次定时器，5.5秒后执行sys.timerStop(sys.publish, "loop_timer_cbfunc_msg")
    -- 相当于5.5秒后主动停止并且删除了上一行代码创建的循环定时器
    sys.timerStart(sys.timerStop, 5500, sys.publish, "loop_timer_cbfunc_msg")

    while true do
        -- 阻塞等待用户全局消息"loop_timer_cbfunc_msg"，超时时长为2秒钟
        -- 5秒内，每秒都会收到一次消息；
        -- 5秒后，不再收到消息，超时2秒退出阻塞状态；
        local result = sys.waitUntil("loop_timer_cbfunc_msg", 2000)
        
        if result then
            log.info("receive loop_timer_cbfunc_msg")
        else
            log.info("no loop_timer_cbfunc_msg, 2000ms timeout")
            break
        end
    end

    -- 以下五行代码执行后，创建并且启动了5个不同的定时器
    local timer_id = sys.timerStart(log.info, 1000, "1")
    sys.timerStart(log.info, 2000, "2")
    sys.timerStart(log.info, 3000, "3")
    sys.timerStart(log.info, 4000, "4")
    sys.timerStart(log.info, 5000, "5")

    -- 根据定时器id停止并且删除刚才创建的5个定时器中的第一个定时器
    sys.timerStop(timer_id)
    
    -- 阻塞等待2秒钟
    sys.wait(2000)

    -- 运行到这里
    -- 刚才创建的5个定时器中的后4个定时器：
    -- sys.timerStart(log.info, 2000, "2")，这个定时器已经超时，并且自动停止和删除
    -- 还剩下另外3个定时器处于运行状态，超时时长未到达
    -- 执行下面这行代码后，可以将这3个定时器全部停止并且删除
    sys.timerStopAll(log.info)
end

-- 创建并且启动一个单次定时器，超时时长为3秒
-- 3秒后执行sys.taskInit(timer_test_task_func)
-- 相当于3秒后，创建并且启动一个基础task，然后执行这个task的任务处理函数timer_test_task_func
sys.timerStart(sys.taskInit, 3000, timer_test_task_func)

