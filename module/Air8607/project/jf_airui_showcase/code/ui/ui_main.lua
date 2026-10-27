--[[
@module  ui_main
@summary UI 主入口：加载界面模块并对外提供构建与动画接口
@version 1.0
@date    2026.10.23
@author  江访
@usage
require 即执行，加载 UI 聚合模块 ui_showcase（界面骨架与场景调度，见 ui/ui_showcase.lua）；
对外接口 2 个（app_main 启动编排中调用）：
1、ui_main.build：搭建演示界面（顶栏 HUD + 特效舞台 + 场景切换栏）
2、ui_main.run：启动逐帧动画任务（约 30fps，shape:set_items 重绘舞台）
]]
local ui_showcase = require "ui_showcase"

local ui_main = {}

-- 搭建演示界面（顶栏 HUD + 特效舞台 + 场景切换栏）
function ui_main.build(SW, SH)
    ui_showcase.build(SW, SH)
end

-- 启动逐帧动画任务（约 30fps，shape:set_items 重绘舞台）
function ui_main.run()
    ui_showcase.run()
end

return ui_main
