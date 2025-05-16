-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "pins"
VERSION = "1.0.0"

--[[
-- 请使用LuaTools的可视化工具进行配置,你通常不需要使用这个demo
-- 请使用LuaTools的可视化工具进行配置,你通常不需要使用这个demo
-- 请使用LuaTools的可视化工具进行配置,你通常不需要使用这个demo
-- 请使用LuaTools的可视化工具进行配置,你通常不需要使用这个demo
-- 请使用LuaTools的可视化工具进行配置,你通常不需要使用这个demo
-- 请使用LuaTools的可视化工具进行配置,你通常不需要使用这个demo
-- 请使用LuaTools的可视化工具进行配置,你通常不需要使用这个demo
-- 请使用LuaTools的可视化工具进行配置,你通常不需要使用这个demo
-- 请使用LuaTools的可视化工具进行配置,你通常不需要使用这个demo
-- 请使用LuaTools的可视化工具进行配置,你通常不需要使用这个demo
-- 请使用LuaTools的可视化工具进行配置,你通常不需要使用这个demo

-- 本库的API属于高级用法, 仅动态配置管脚时使用
-- 本库的API属于高级用法, 仅动态配置管脚时使用
-- 本库的API属于高级用法, 仅动态配置管脚时使用
]]

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

-- require "pinssetup"
require "pinsjson"


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!