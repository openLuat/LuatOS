local irtu_main = {}

local default = require "default"
local gnss = require "gnss"
local driver = require "driver"
local create = require "create"
local audio_config= require "audio_config"

sys.taskInit(function()
    -- 初始化配置
    default.init()
    -- 初始化驱动
    driver.init()
    -- 启动服务器
    create.start()
    -- 启动GNSS
    -- gnss.init()
    -- 启动音频配置
    -- audio_config.init()
end)

return irtu_main

