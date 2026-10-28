-- UI 入口：构建配电房监测大屏（硬件初始化由 app_main 完成）
-- run() 由主循环节流调用，场景内部自己按时间控制刷新节奏
-- @author 江访
-- @time 2026-10-26 11:15

local M = {}

function M.build()
    M.scene = require "gridui"
    M.scene.build()
end

function M.run()
    M.scene.run()
end

return M
