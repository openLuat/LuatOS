PROJECT="LuckyWheel_Air8601"
VERSION="001.000.002"
_G.sys=require("sys")
local config=require("config")
local board=require("board")
local Clock=require("clock_ms")
local Random=require("random_source")
local Lottery=require("lottery_model")
local UI=require("ui")
local Pacer=require("frame_pacer")
log.info(PROJECT,"scripts",VERSION,"embedded roster",#config.participants)

sys.taskInit(function()
    local ok,reason=board.init(config)
    if not ok then log.error(PROJECT,reason);return end
    local model=Lottery.new(config,Random.index)
    local view=UI.new(model,config)
    local previous=Clock.now()
    local pacer=Pacer.new(config.frame_ms,previous)
    local stats={phase=model.phase,at=previous,frames=0,skipped=0,late=0,submit=0}
    log.info(PROJECT,"participants",#config.participants,"clock",type(mcu),previous)
    view:render(model:snapshot(true))
    local function frame()
        local now=Clock.now()
        local due,skipped,late=pacer:due(now)
        if not due then return end
        model:step(Clock.elapsed(now,previous))
        previous=now
        if model.phase~="IDLE" or view.phase~="IDLE" then view:render(model:snapshot(true)) end
        local submit=Clock.elapsed(Clock.now(),now)
        if stats.phase~=model.phase then
            stats={phase=model.phase,at=now,frames=0,skipped=0,late=0,submit=0}
        else stats.frames=stats.frames+1 end
        stats.skipped=stats.skipped+skipped
        stats.late=math.max(stats.late,late);stats.submit=math.max(stats.submit,submit)
        local elapsed=Clock.elapsed(now,stats.at)
        if elapsed>=(config.performance_log_ms or 1000) then
            if model.phase~="IDLE" then
                log.info("lottery.perf",model.phase,"ui_fps",string.format("%.1f",stats.frames*1000/elapsed),
                    "skipped",stats.skipped,"late_ms_max",stats.late,"submit_ms_max",stats.submit)
            end
            stats={phase=model.phase,at=now,frames=0,skipped=0,late=0,submit=0}
        end
    end
    -- Fixed-period timer does not add render time to the next 40ms deadline.
    if not sys.timerLoopStart(frame,config.frame_ms) then
        log.warn("lottery.perf","timer unavailable; using deadline task")
        while true do
            sys.wait(math.max(1,math.ceil(pacer.next_ms-Clock.now())))
            frame()
        end
    end
end)
sys.run()
