


local function success_wait_until_base_task_func()
    local result, tag, count
    while true do
        result, tag, count = sys.waitUntil("SEND_DATA_REQ")
        if result then
            log.info("success_wait_until_base_task_func", tag, count)
        end
    end
end


local function lost_wait_until_base_task_func()
    local result, tag, count
    while true do
        sys.wait(3000)
        
        result, tag, count = sys.waitUntil("SEND_DATA_REQ")
        if result then
            log.info("lost_wait_until_base_task_func", tag, count)
        end
    end
end


sys.taskInit(success_wait_until_base_task_func)
sys.taskInit(lost_wait_until_base_task_func)

