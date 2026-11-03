--[[
@module  ui_main
@summary UI 主入口：对外只暴露 build / run 两个接口
@version 1.0
@date    2026.11.03
@usage
require 即执行，加载外壳模块 ui_shell（骨架与页面调度，见 ui/ui_shell.lua）；
app_main 的启动编排里调用：
1、ui_main.build：搭大厅骨架（HUD + 舞台 + 底部操作栏 + 通用弹窗）
2、ui_main.run：启动 30fps 主循环（页面绘制 + 触摸手势分发 + HUD 节流刷新）
]]

local T = require "theme"
local shell = require "ui_shell"

local M = {}

function M.build()
    shell.build(T.screen.w, T.screen.h)
end

function M.run()
    shell.run()
end

return M
