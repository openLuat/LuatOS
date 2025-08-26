


local function targeted_msg_sender_task_func()
    local count = 0

    while true do
        count = count+1

        -- 发布一条定向消息到名称为"nromal_wait_msg_task"的高级task
        -- 消息名称为"SEND_DATA_REQ"
        -- 消息携带两个参数：
        -- 第一个参数是"from task"
        -- 第二个参数是number类型的count
        sysplus.sendMsg("nromal_wait_msg_task", "SEND_DATA_REQ", "from task", count)

        -- 发布一条定向消息到名称为"delay_wait_msg_task"的高级task
        -- 消息名称为"SEND_DATA_REQ"
        -- 消息携带两个参数：
        -- 第一个参数是"from task"
        -- 第二个参数是number类型的count
        sysplus.sendMsg("delay_wait_msg_task", "SEND_DATA_REQ", "from task", count)

        -- 延时等待1秒
        sys.wait(1000)
    end
end


-- 创建并且启动一个基础task
-- 运行这个task的任务处理函数targeted_msg_sender_task_func
sys.taskInit(targeted_msg_sender_task_func)

