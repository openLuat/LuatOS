--[[
@module  ui_main
@summary UI 主入口：加载界面模块并对外提供构建与运行接口
@version 1.0
@date    2026.10.23
@author  江访
@usage
require 即执行，加载仪表盘界面模块 cluster（速度弧 / 四张卡 / 顶栏 / 模式键，见 ui/cluster.lua）；
对外接口 2 个（app_main 启动编排中调用）：
1、ui_main.build：搭建仪表盘界面
2、ui_main.run：启动 30fps 主循环（先跑自检扫弧，再进入行驶态）
]]
local cluster = require "cluster"

local ui_main = {}

-- 搭建仪表盘界面
function ui_main.build()
    cluster.build()
end

-- 启动 30fps 主循环（先跑自检扫弧，再进入行驶态）
function ui_main.run()
    cluster.run()
end

return ui_main
