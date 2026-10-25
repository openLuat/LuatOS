--[[
@module  ui_main
@summary UI 主入口：加载 UI 聚合模块并对外提供构建与动画接口
@version 1.0
@date    2026.10.23
@author  江访
@usage
require 即执行，加载 UI 聚合模块 ui_shell（极光背景 / HUD / 玻璃卡片 / Dock / 页面过渡 / 主循环）；
对外接口 2 个（app_main 启动编排中调用）：
1、ui_main.build：搭整屏（极光背景 + HUD + 舞台 + 4 个页面 + Dock）
2、ui_main.run：启动逐帧动画任务（33ms / 约 30fps）
]]
local ui_shell = require "ui_shell"

local ui_main = {}

-- 搭整屏：极光背景 + HUD + 舞台 + 4 个页面 + Dock
function ui_main.build()
    ui_shell.build()
end

-- 启动逐帧动画任务（33ms / 约 30fps）
function ui_main.run()
    ui_shell.run()
end

return ui_main
