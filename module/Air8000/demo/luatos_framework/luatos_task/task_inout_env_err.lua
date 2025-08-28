--[[
@module  targeted_msg_sender
@summary “task内和task外运行环境典型错误”演示功能模块
@version 1.0
@date    2025.08.12
@author  朱天华
@usage
本文件为task_inout_env_err应用功能模块，用来演示“task内和task外运行环境典型错误”，核心业务逻辑为：
演示“task内外运行环境使用不当”而出现的典型错误
1、在用户全局消息订阅的回调函数中执行sys.wait接口；
2、在单次定时器的回调函数中执行sys.waitUntil接口；
3、在循环定时器的回调函数中执行sys.waitMsg接口；
4、以上三种都是在task外的运行环境中执行“必须在task内运行”的接口，还有其他类似的使用错误，不再一一列举；

本文件没有对外接口，直接在main.lua中require "task_inout_env_err"就可以加载运行；
]]


local function mqtt_event_cbfunc()
    log.info("mqtt_event_cbfunc")
    -- 在用户全局消息订阅的回调函数中执行sys.wait接口，会报错
    sys.wait(1000)
end

-- sys.subscribe("MQTT_EVENT", mqtt_event_cbfunc)
-- sys.timerStart(sys.publish, 1000, "MQTT_EVENT")





local function timer_cbfunc()
    log.info("timer_cbfunc")
    -- 在单次定时器的回调函数中执行sys.waitUntil接口，会报错
    sys.waitUntil("UNKNOWN_MSG", 1000)
end

-- sys.timerStart(timer_cbfunc, 1000)





local function loop_timer_cbfunc()
    log.info("loop_timer_cbfunc")
    -- 在循环定时器的回调函数中执行sys.waitMsg接口，会报错
    sys.waitMsg("SEND_MSG_TASK", "UNKNOWN_MSG", 1000)
end

local function send_targeted_msg_task_func()
    while true do
        -- 延时等待1秒
        sys.wait(1000)
    end
end

-- 创建并且启动一个高级task
-- task的任务处理函数为send_targeted_msg_task_func
-- task的名称为SEND_TASK_NAME
-- 运行这个task的任务处理函数send_targeted_msg_task_func
sys.taskInitEx(send_targeted_msg_task_func, "SEND_MSG_TASK")
sys.timerLoopStart(loop_timer_cbfunc, 1000)