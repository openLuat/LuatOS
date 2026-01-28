local irtu_main = {}

local config = require "irtu_config"
local driver = require "irtu_driver"
local task = require "irtu_task"
local network = require "irtu_network"

sys.taskInit(function()
    -- 初始化配置
    config.init()
    -- 初始化驱动
    driver.init()
    -- 初始化任务
    task.init()
    -- 启动网络
    network.start()
end)

return irtu_main

