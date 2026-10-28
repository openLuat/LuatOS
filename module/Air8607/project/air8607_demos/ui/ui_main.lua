--[[
@module  ui_main
@summary UI 主入口：加载演示外壳并对外提供构建与动画接口
@version 1.0
@date    2026.10.26
@usage
require 即执行，加载 ui_demos（外壳：HUD + 舞台 + 场景切换栏 + 自动轮播）。
每个应用场景是独立 demo 文档（ui/demo_*.lua），本文件只是薄封装：
1、ui_main.build：搭建界面骨架并载入第一个场景
2、ui_main.run：启动逐帧动画任务（约 30fps，shape:set_items 重绘舞台）
]]
local ui_demos = require "ui_demos"

local ui_main = {}

function ui_main.build(SW, SH)
    ui_demos.build(SW, SH)
end

function ui_main.run()
    ui_demos.run()
end

return ui_main
