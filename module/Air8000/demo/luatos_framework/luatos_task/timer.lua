


local function timer_test_task_func()
    sys.timerStart(log.info, 1000, "red")
    sys.timerStart(log.info, 2000, "red")
    sys.timerStart(log.info, 3000, "red")

    sys.wait(3000)

    sys.timerLoopStart(sys.publish, 1000, "loop_timer_cbfunc_msg")
    sys.timerStart(sys.timerStop, 5500, sys.publish, "loop_timer_cbfunc_msg")

    while true do
        local result = sys.waitUntil("loop_timer_cbfunc_msg", 2000)
        if result then
            log.info("receive loop_timer_cbfunc_msg")
        else
            log.info("no loop_timer_cbfunc_msg, 2000ms timeout")
            break
        end
    end

    local timer_id = sys.timerStart(log.info, 1000, "1")
    sys.timerStart(log.info, 2000, "2")
    sys.timerStart(log.info, 3000, "3")
    sys.timerStart(log.info, 4000, "4")
    sys.timerStart(log.info, 5000, "5")

    sys.timerStop(timer_id)
    
    sys.wait(2000)

    sys.timerStopAll(log.info)
end


sys.timerStart(sys.taskInit, 3000, timer_test_task_func)

