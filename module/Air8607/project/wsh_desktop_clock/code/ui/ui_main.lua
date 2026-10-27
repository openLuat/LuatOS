--[[
@module  ui_main
@summary UI 主入口：聚合时钟页 / 设置页，并提供页面切换与刷新接口
@author  王世豪
@version 1.0
@date    2026.10.26
@usage
对外开放 2 个接口（app_main 启动编排中调用）：
1、ui_main.build(parent)  搭界面：时钟页 + 设置页 + 页面切换回调，最后显示时钟页
2、ui_main.refresh()      每秒刷新时钟（app_main 的定时器调用）
]]
local ui_clock = require "ui_clock"
local ui_settings = require "ui_settings"

local M = {}

-- 搭界面：两个页面 + 互相切换的回调
function M.build(parent)
    ui_clock.build(parent)
    ui_settings.build(parent)

    ui_clock.on_settings = function()
        ui_clock.hide()
        ui_settings.show()
    end
    ui_settings.on_back = function()
        ui_settings.hide()
        ui_clock.show()
    end

    ui_clock.show()
end

-- 每秒刷新时钟
function M.refresh()
    ui_clock.refresh()
end

return M
