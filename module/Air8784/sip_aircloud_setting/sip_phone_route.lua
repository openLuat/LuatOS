--[[
@module sip_phone_route
@summary 从已保存的AirCloud任务读取SIP来电转拨号码
@version 2.1
@date    2026.09.29
@usage
sip_runtime 已初始化 fskv。每次来电读取最新任务，修改号码无需重启。
SIP呼入使用targets()获取本次轮拨号码快照；按键由任务引擎轮拨。
无phone任务、任务已删除或号码无效时不回退到配置文件占位号码。
]]
local M = {}
function M.valid(number)
    return type(number) == "string" and #number == 11 and number:match("^1%d+$") ~= nil
end
function M.targets()
    local saved = fskv.get("sip_task_v1")
    if type(saved) ~= "table" or type(saved.task) ~= "table" then return nil end
    local task = saved.task
    if task.mode ~= "phone" or type(task.targets) ~= "table" then return nil end
    if #task.targets < 1 or #task.targets > 3 then return nil end
    local numbers, seen = {}, {}
    for i, number in ipairs(task.targets) do
        if not M.valid(number) or seen[number] then return nil end
        numbers[i] = number; seen[number] = true
    end
    return numbers
end
function M.current()
    local numbers = M.targets()
    return numbers and numbers[1] or nil
end
return M
