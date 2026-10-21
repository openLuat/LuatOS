-- 单一协作任务驱动全部8只动物。logic_fps表示Lua更新率，不是实测屏显FPS。
local C=require "config"
local M={}
local started=false
local read_clock,epoch,last_elapsed

function M.elapsed()
    if not started then return 0 end
    -- 点击与动画共用时间轴；时钟短暂回退时也不让行为时间倒退。
    local elapsed=read_clock()-epoch
    if elapsed>last_elapsed then last_elapsed=elapsed end
    return last_elapsed
end

function M.clock()
    assert(mcu,"requires official mcu clock")
    if type(mcu.ticks2)=="function" then
        return function()
            local high,low=mcu.ticks2(1)
            return high*1000000+low -- 官方按1000000毫秒拆分，并非高低32位
        end
    end
    assert(type(mcu.ticks)=="function" and type(mcu.hz)=="function",
        "requires mcu.ticks2 or mcu.ticks/hz")
    local hz=mcu.hz()
    assert(hz and hz>0,"invalid mcu tick frequency")
    local previous,total=mcu.ticks()%4294967296,0
    return function()
        local tick=mcu.ticks()%4294967296
        total=total+(tick-previous)%4294967296
        previous=tick
        return math.floor(total*1000/hz)
    end
end

function M.start(step,now_ms)
    if started then return false end
    assert(type(step)=="function","animation callback required")
    now_ms=now_ms or M.clock()
    read_clock=now_ms
    epoch=read_clock() -- 在start调用时固定，不能等任务首次被调度才开始计时
    last_elapsed=0
    started=true
    sys.taskInit(function()
        local next_frame=1
        local report,last_update=epoch,epoch
        local updates,skipped,max_gap=0,0,0
        while true do
            local elapsed=M.elapsed()
            local now=epoch+elapsed
            local frame=math.floor(elapsed*C.ANIM_FPS/1000)
            if frame>=next_frame then
                skipped=skipped+frame-next_frame
                step(elapsed)
                updates=updates+1
                max_gap=math.max(max_gap,now-last_update)
                last_update=now
                next_frame=frame+1
            end
            if now-report>=C.REPORT_MS then
                local counts=require("scene").summary()
                log.info("petpark",string.format(
                    "target=%d logic_fps=%.1f skipped=%d max_gap_ms=%d active=%d quality=%s run=%d idle=%d",
                    C.ANIM_FPS,updates*1000/(now-report),skipped,max_gap,
                    counts.active,counts.quality,counts.run,counts.idle))
                report=now
                updates,skipped,max_gap=0,0,0
            end
            local deadline=epoch+math.ceil(next_frame*1000/C.ANIM_FPS)
            sys.wait(math.max(1,deadline-(epoch+M.elapsed())))
        end
    end)
    return true
end
return M
