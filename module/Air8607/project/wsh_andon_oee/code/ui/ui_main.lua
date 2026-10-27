--[[
@module  ui_main
@summary UI 主入口：聚合看板，并提供刷新接口
@author  王世豪
@version 1.0
@date    2026.10.26
@usage
对外接口：
1、ui_main.build(parent)  构建看板
2、ui_main.refresh()      每秒推进产线数据并刷新界面
]]
local ui_board = require "ui_board"
local line_sim = require "line_sim"

local M = {}

function M.build(parent)
    ui_board.build(parent)
end

function M.refresh()
    line_sim.tick(1)
    ui_board.refresh()
end

return M
