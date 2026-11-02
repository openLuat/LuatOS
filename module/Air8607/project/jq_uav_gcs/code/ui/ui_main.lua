--[[
@module  ui_main
@summary UI 主入口：把外壳的构建与运行暴露给启动编排
@version 1.0
@date    2026.11.02
@usage
require 即执行，加载外壳 shell（顶栏 / 标签栏 / 五个页面 / 主循环，见 ui/shell.lua）。
对外只暴露两个接口，供 app_main 的启动流程调用：
1、ui_main.build：搭整屏
2、ui_main.run：起 30fps 主循环
]]
local shell = require "shell"

local ui_main = {}

function ui_main.build()
    shell.build()
end

function ui_main.run()
    shell.run()
end

return ui_main
