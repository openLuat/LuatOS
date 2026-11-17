--[[
@module  ui_main
@summary UI 入口：build 搭建界面，run 启动主循环
@version 1.0
@date    2026.11.17
]]

local M = {}

function M.build()
    M.scene = require "ui_home"
    M.scene.build()
end

function M.run()
    M.scene.run()
end

return M
