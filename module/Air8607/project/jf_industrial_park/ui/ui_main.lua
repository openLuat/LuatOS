--[[
@module  ui_main
@summary UI 主入口：加载界面模块并对外提供构建与运行接口
@version 1.0
@date    2026.10.25
@author  江访
@usage
require 即执行，加载园区大屏界面模块 parkui（见 ui/parkui.lua）；
对外接口 2 个（app_main 启动编排中调用）：
1、ui_main.build：搭建整个界面
2、ui_main.run：启动主循环（约 16fps，卡片与文本按各自的节拍刷新）
@note
模块名不能叫 "park"：模拟器的脚本区里有同名内置模块，require "park" 会拿到
一个布尔值 true（内置模块没有返回值），表现为 build() 里 "attempt to index a boolean"。
]]
local parkui = require "parkui"

local ui_main = {}

function ui_main.build()
    parkui.build()
end

function ui_main.run()
    parkui.run()
end

return ui_main
