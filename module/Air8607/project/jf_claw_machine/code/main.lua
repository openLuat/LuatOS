--[[
@module main
@summary 欢乐抓娃娃 · Air8607 大屏触摸抓娃娃机 demo 入口
@ver 1.0.0
@author cqd
@note 模式沿用 cqd_LuckyWheel：固定周期帧 + 卡顿钳制（Pacer:due 跳帧不补偿）。
      main 每帧只做四件事：取帧 dt、model:step(dt)、view:render(快照)、
      性能日志。触摸回调走 airui.touch_subscribe。
]]
PROJECT = "ClawMachine"
VERSION = "1.0.0"

_G.sys = require("sys")
local config = require("config")
local board = require("board")
local Clock = require("clock_ms")
local Pacer = require("frame_pacer")
local rng = require("rng")
local Claw = require("claw_model")
local UI = require("ui")
local sfx = require("sfx")

sys.taskInit(function()
    local ok, reason = board.init(config)
    if not ok then
        log.error(PROJECT, reason)
        return
    end
    sfx.init(config)

    local model = Claw.new(config, rng.float)
    local view = UI.new(config, model, sfx)
    view:init()

    local previous = Clock.now()
    local pacer = Pacer.new(config.frame_ms, previous)
    local stats = { at = previous, frames = 0, skipped = 0, late = 0, submit = 0 }
    view:render(model:snapshot())

    local function frame()
        local now = Clock.now()
        local due, skipped, late = pacer:due(now)
        if not due then return end
        model:step(Clock.elapsed(now, previous))
        previous = now
        view:render(model:snapshot())
        local submit = Clock.elapsed(Clock.now(), now)
        stats.frames = stats.frames + 1
        stats.skipped = stats.skipped + skipped
        stats.late = math.max(stats.late, late)
        stats.submit = math.max(stats.submit, submit)
        local elapsed = Clock.elapsed(now, stats.at)
        if elapsed >= (config.performance_log_ms or 2000) then
            log.info("claw.perf", string.format(
                "fps=%.1f skipped=%d late=%dms submit=%dms phase=%s score=%d",
                stats.frames * 1000 / elapsed, stats.skipped,
                stats.late, stats.submit, model.phase, model.score))
            stats = { at = now, frames = 0, skipped = 0, late = 0, submit = 0 }
        end
    end

    -- 固定周期定时器：渲染耗时不叠加进下一帧期限
    if not sys.timerLoopStart(frame, config.frame_ms) then
        log.warn("claw.perf", "timer unavailable; using deadline task")
        while true do
            sys.wait(math.max(1, math.ceil(pacer.next_ms - Clock.now())))
            frame()
        end
    end
end)

sys.run()
