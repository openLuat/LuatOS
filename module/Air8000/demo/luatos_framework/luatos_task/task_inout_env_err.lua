

local function mqtt_event_cbfunc()
    log.info("mqtt_event_cbfunc")
    sys.wait(1000)
end

-- sys.subscribe("MQTT_EVENT", mqtt_event_cbfunc)
-- sys.timerStart(sys.publish, 1000, "MQTT_EVENT")


local function timer_cbfunc()
    log.info("timer_cbfunc")
    sys.waitUntil("UNKNOWN_MSG", 1000)
end

-- sys.timerStart(timer_cbfunc, 1000)


local function loop_timer_cbfunc()
    log.info("loop_timer_cbfunc")
    sysplus.waitMsg("SEND_MSG_TASK", "UNKNOWN_MSG", 1000)
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
sysplus.taskInitEx(send_targeted_msg_task_func, "SEND_MSG_TASK")
sys.timerLoopStart(loop_timer_cbfunc, 1000)