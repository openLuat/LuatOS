--[[
@module  ui_main
@summary UI 主入口：加载界面模块并对外提供构建与刷新接口
@version 1.0
@date    2026.10.23
@author  江访
@usage
require 即执行，加载大屏界面模块 ui_dashboard（三列布局，见 ui/ui_dashboard.lua）；
对外接口 3 个（app_main 启动编排与定时刷新中调用）：
1、ui_main.build：构建大屏 UI 界面
2、ui_main.tick_clock：顶栏时钟每秒刷新
3、ui_main.refresh_all：传感器/设备/告警数据刷新
]]
local ui_dashboard = require "ui_dashboard"

local ui_main = {}

-- 构建大屏 UI 界面
function ui_main.build()
    ui_dashboard.build()
end

-- 顶栏时钟每秒刷新
function ui_main.tick_clock()
    ui_dashboard.tick_clock()
end

-- 传感器/设备/告警数据刷新
function ui_main.refresh_all()
    ui_dashboard.refresh_all()
end

return ui_main
