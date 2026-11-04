--[[
@module  ui_main
@summary 整屏装配与主循环（33ms 一拍，各层按自己的节流刷新）
@version 1.0
@date    2026.11.04

屏幕分区（1024x600）：
   0..56     顶栏：品牌 / 发射窗口 / 阶段 / 大倒计时 / 时钟
   64..520   主区：发射台 328x456 | 弹道 352x260 + 检查 170x188 + 余量 172x188 | 时序 306x456
   528..600  指令条：开始 / 中止 / 重置 / 自动演示 / 语音
]]
local conf    = require "conf"
local theme   = require "theme"
local mission = require "mission"
local board   = require "ui_board"
local panels  = require "ui_panels"
local pad     = require "ui_pad"

local C = theme.C
local M = {}

function M.build(root)
    local self = { t = 0, pad_acc = 0, chart_acc = 0, gauge_acc = 0 }

    -- 底色：上深下更深的控制室暗场
    theme.box(root, 0, 0, conf.W, conf.H, C.bg1, 0, 255)
    for i = 0, 5 do
        local col = theme.lerp_color(C.bg2, C.bg1, i / 5)
        theme.box(root, 0, 64 + i * 76, conf.W, 76, col, 0, 110)
    end

    -- 顶栏
    self.top = board.build_top(root)

    -- 发射台卡片
    local pad_card = theme.card(root, 12, 64, 328, 456, 0x03060C, 12, C.line2)
    self.pad = pad.build(pad_card)

    -- 弹道曲线 + 轴标
    self.chart = panels.build_chart(root)
    panels.build_chart_axis(root)

    -- 检查 / 余量 / 时序
    self.checks = panels.build_checks(root)
    self.gauges = panels.build_gauges(root)
    self.timeline = panels.build_timeline(root)

    -- 指令条（先建按钮，Toast 最后建以保证在最上层）
    local toast
    local function toast_fn(text)
        if toast then toast.show(text) end
    end
    self.bottom = board.build_bottom(root, toast_fn)
    toast = board.build_toast(root)
    self.toast = toast

    -- 首帧先画一遍，避免开局空白
    panels.tick_checks(self.checks)
    panels.tick_gauges(self.gauges)
    panels.tick_timeline(self.timeline)
    panels.draw_chart(self.chart)
    pad.tick(self.pad, 0)

    M.self = self
    return self
end

--- 启动主循环
function M.run(self)
    self = self or M.self
    if not self then return end

    sys.timerLoopStart(function()
        local dt = conf.tick.loop_ms / 1000
        self.t = self.t + dt

        local ok, err = pcall(mission.tick, dt)
        if not ok then log.error("ui", "mission.tick", tostring(err)) end

        -- 发射台动态层 ~15fps
        self.pad_acc = self.pad_acc + dt
        if self.pad_acc >= conf.tick.pad_ms / 1000 then
            pcall(pad.tick, self.pad, self.pad_acc)
            self.pad_acc = 0
        end

        -- 曲线 5Hz
        self.chart_acc = self.chart_acc + dt
        if self.chart_acc >= conf.tick.chart_ms / 1000 then
            pcall(panels.draw_chart, self.chart)
            self.chart_acc = 0
        end

        -- 余量条 4Hz
        self.gauge_acc = self.gauge_acc + dt
        if self.gauge_acc >= conf.tick.gauge_ms / 1000 then
            pcall(panels.tick_gauges, self.gauges)
            self.gauge_acc = 0
        end

        -- 只在数据变化时重绘的两块
        pcall(panels.tick_checks, self.checks)
        pcall(panels.tick_timeline, self.timeline)

        pcall(board.tick_top, self.top, dt)
        pcall(board.tick_bottom, self.bottom)
    end, conf.tick.loop_ms)
end

return M
