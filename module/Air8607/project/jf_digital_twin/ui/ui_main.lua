--[[
@module  ui_main
@summary DIGITAL TWIN - UI 主入口（只暴露 build / run 两个接口）
@version 1.0
@date    2026.10.23
@author  江访
]]

local board = require "ui_board"

local M = {}

-- 搭界面（在 airui.init + font_load 之后调用）
function M.build()
    board.build(1024, 600)
end

-- 主循环（在独立 task 里跑）
function M.run()
    board.run()
end

-- 切视图（调试用；正常走底栏按钮）
function M.select(i)
    board.select(i)
end

return M
