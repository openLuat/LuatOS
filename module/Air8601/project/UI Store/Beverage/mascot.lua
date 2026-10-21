-- 一张96x96透明PNG + 原生容器位移。24fps为逻辑采样目标，不代表实测屏显FPS。
-- 时间轴按绝对deadline推进，迟到时跳过过期帧，不循环补绘积压帧。
local A = require("config").MASCOT
local M = {}
local group, started, last_slot, last_x, last_y
local cycle_frames = math.floor(A.fps*A.cycle_ms/1000+0.5)
assert(A.fps>0 and cycle_frames>0, "invalid mascot cadence")
local poses = {}
for frame=0,cycle_frames-1 do
    local phase=frame*2*math.pi/cycle_frames
    poses[frame+1]={A.x+math.floor(A.move_x*math.sin(phase)+0.5),
        A.y+math.floor(-A.move_y*math.sin(2*phase)+0.5)}
end

local function clock_ms()
    assert(mcu, "mascot requires the official mcu clock")
    if type(mcu.ticks2)=="function" then
        -- 官方ticks2(1)按1000000毫秒拆分，不是高低32位。
        return function()
            local high,low=mcu.ticks2(1)
            return high*1000000+low
        end
    end
    assert(type(mcu.ticks)=="function" and type(mcu.hz)=="function",
        "mascot requires mcu.ticks2 or mcu.ticks/hz")
    local hz=mcu.hz()
    assert(hz and hz>0, "invalid mcu tick frequency")
    local previous=mcu.ticks()%4294967296
    local total=0
    return function()
        local tick=mcu.ticks()%4294967296
        total=total+(tick-previous)%4294967296
        previous=tick
        return math.floor(total*1000/hz)
    end
end

function M.pose(elapsed_ms)
    local slot=math.floor(math.max(0,elapsed_ms)*A.fps/1000)
    local p=poses[slot%cycle_frames+1]
    return p[1],p[2]
end

function M.step(elapsed_ms)
    if not group then return false end
    local slot=math.floor(math.max(0,elapsed_ms)*A.fps/1000)
    if slot==last_slot then return false end
    local x,y=M.pose(elapsed_ms)
    if x~=last_x or y~=last_y then group:set_pos(x,y) end
    last_slot,last_x,last_y=slot,x,y
    return true
end

function M.create(parent)
    if group or not A.enabled then return false end
    local shadow=airui.container({parent=parent,x=A.x+26,y=A.y+A.h-1,
        w=44,h=5,color=0x66816E,radius=3,border_width=0})
    shadow:set_color(0x66816E,30)
    group=airui.container({parent=parent,x=A.x,y=A.y,w=A.w,h=A.h,
        radius=0,border_width=0})
    airui.image({parent=group,x=0,y=0,w=A.w,h=A.h,src="/luadb/mascot.png"})
    M.step(0)
    return true
end

function M.start()
    if started or not group or not A.enabled then return false end
    local now_ms=clock_ms()
    started=true
    sys.taskInit(function()
        local epoch=now_ms()
        local next_frame=1
        local report_start,last_update=epoch,epoch
        local updates,skipped,max_gap=0,0,0
        while true do
            local now=now_ms()
            local elapsed=now-epoch
            local frame=math.floor(elapsed*A.fps/1000)
            if frame>=next_frame then
                skipped=skipped+frame-next_frame
                M.step(elapsed)
                updates=updates+1
                max_gap=math.max(max_gap,now-last_update)
                last_update=now
                next_frame=frame+1
            end
            if now-report_start>=A.report_ms then
                log.info("mascot24",string.format(
                    "target=%d logic_fps=%.1f skipped=%d max_gap_ms=%d",
                    A.fps,updates*1000/(now-report_start),skipped,max_gap))
                report_start=now
                updates,skipped,max_gap=0,0,0
            end
            -- 例如前3个等待42/42/41ms，长期平均1000/24；不使用固定42ms累积漂移。
            local deadline=epoch+math.ceil(next_frame*1000/A.fps)
            sys.wait(math.max(1,deadline-now_ms()))
        end
    end)
    log.info("mascot24", "start", A.fps, "fps target; logic_fps is not panel FPS")
    return true
end

return M
