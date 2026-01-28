local task = {}

local dtulib = require "dtulib"
local config = require "irtu_config"
local driver = require "irtu_driver"

local function sendCommand(uid, value)
    if value:match("function(.+)end") then
        local res, msg = pcall(loadstring(value:match("function(.+)end")))
        if res and msg then
            driver.publishNet(uid, msg)
        end
    elseif value ~= "" then
        driver.publishNet(uid, dtulib.fromHexnew(value))
    end
end

local function autoSampl(uid)
    while true do
        sys.waitUntil("AUTO_SAMPL_" .. uid)
        local dtu = config.get()
        local cmd = dtu.cmds and dtu.cmds[uid]
        if cmd and #cmd > 1 then
            local interval = tonumber(cmd[1]) or 0
            for i = 2, #cmd do
                sendCommand(uid, cmd[i])
                if interval > 0 then
                    sys.wait(interval)
                end
            end
        end
    end
end

local function startAutoSampling()
    for uid = 1, 3 do
        sys.taskInit(autoSampl, uid)
    end
end

local function startUserTasks()
    local dtu = config.get()
    if dtu.task and #dtu.task ~= 0 then
        for _, script in ipairs(dtu.task) do
            if script and script:match("function(.+)end") then
                sys.taskInit(function()
                    pcall(loadstring(script:match("function(.+)end")))
                end)
            end
        end
    end
end

function task.init()
    startAutoSampling()
    startUserTasks()
end

return task

