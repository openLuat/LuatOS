--[[
@module  ui_main
@summary UI 主入口：加载界面模块并对外提供构建与主循环接口
@version 1.0
@date    2026.10.23
@author  江访
@usage
require 即执行，加载界面模块 ui_gallery（橱窗骨架 + 分组调度）；
对外接口 2 个（app_main 启动编排中调用）：
1、ui_main.build：搭建整屏界面（顶栏 HUD + 组件舞台 + 分组切换栏）
2、ui_main.run：30fps 主循环（数据模拟 + 分组绘制 + HUD 刷新）
]]
local ui = require "ui_gallery"

local ui_main = {}

-- 搭建整屏界面（顶栏 HUD + 组件舞台 + 分组切换栏）
function ui_main.build()
    ui.build(1024, 600)
end

-- 30fps 主循环（数据模拟 + 分组绘制 + HUD 刷新）
function ui_main.run()
    ui.run()
end

return ui_main
