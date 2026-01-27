--[[
@module  irtu_main
@summary irtu功能初始化模块
@version 5.0.0
@date    2026.01.27
@author  李源龙
@usage
本文件为irtu的功能初始化模块，核心业务逻辑为：
    加载default,gnss,driver,create,audio_config模块，然后开启task，在task中初始化各个模块
    其中基础功能模块为default,driver,create，如需GNSS定位/音频，可以选择加载gnss,audio_config模块
    GNSS定位功能目前仅支持Air780EGG,Air780EGP,Air780EGH等内置GNSS的模块，如需外挂GNSS模块，请自行修改gnss模块的配置
    音频功能目前仅支持Air780EHV内置音频解码芯片的模块，如需外挂音频解码芯片，请自行修改audio_config模块的配置
]]
local irtu_main = {}

local default = require "default"
local gnss = require "gnss"
local driver = require "driver"
local create = require "create"
local audio_config= require "audio_config"

local function irtu_init()
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
end
sys.taskInit(irtu_init)

return irtu_main

