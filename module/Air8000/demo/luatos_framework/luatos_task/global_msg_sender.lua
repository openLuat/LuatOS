


local function global_sender_msg_task_func()
    local count = 0

    while true do
        count = count+1

        -- 发布一条全局消息
        -- 消息名称为"SEND_DATA_REQ"
        -- 消息携带两个参数：
        -- 第一个参数是"from task"
        -- 第二个参数是number类型的count
        sys.publish("SEND_DATA_REQ", "from task", count)

        -- 延时等待1秒
        sys.wait(1000)
    end
end


local timer_count = 0

local function global_sender_msg_timer_cbfunc()
    timer_count = timer_count+1

    -- 发布一条全局消息
    -- 消息名称为"SEND_DATA_REQ"
    -- 消息携带两个参数：
    -- 第一个参数是"from timer"
    -- 第二个参数是number类型的timer_count
    sys.publish("SEND_DATA_REQ", "from timer", timer_count)
end


-- 创建并且启动一个基础task
-- 运行这个task的任务处理函数global_sender_msg_task_func
sys.taskInit(global_sender_msg_task_func)

global_sender_msg_timer_cbfunc()
sys.timerLoopStart(global_sender_msg_timer_cbfunc, 1000)

