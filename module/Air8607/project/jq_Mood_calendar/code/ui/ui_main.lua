--[[
@module  ui_main
@summary UI 主入口：聚合日历页 / 心情选择浮层 / 月度报告浮层
@author  蒋骞
@version 1.0
@date    2026.10.30

@usage
对外开放 2 个接口（app_main 启动编排中调用）：
1、ui_main.build(parent)  搭界面：三个层按顺序创建，再把回调互相接起来
2、ui_main.refresh()      每秒被调用（内部只在跨天时真正重画）

创建顺序 = 显示层级：
  ui_calendar（底层） -> ui_picker（浮层） -> ui_report（浮层）
后创建的在上层，所以两个浮层永远盖在日历上面（它们平时都是隐藏的）。
]]
local ui_calendar = require "ui_calendar"
local ui_picker = require "ui_picker"
local ui_report = require "ui_report"

local M = {}

function M.build(parent)
    ui_calendar.build(parent)
    ui_picker.build(parent)
    ui_report.build(parent)

    -- 点日历格子 -> 打开心情选择
    ui_calendar.on_pick = function(y, m, d, score)
        ui_picker.show(y, m, d, score)
    end

    -- 点「本月心情」-> 打开月度报告
    ui_calendar.on_report = function(y, m, sum, bless)
        ui_report.show(y, m, sum, bless)
    end

    -- 选完心情 -> 写盘并重画日历
    ui_picker.on_select = function(y, m, d, score)
        ui_calendar.set_score(y, m, d, score)
    end
end

function M.refresh()
    ui_calendar.refresh()
end

return M
