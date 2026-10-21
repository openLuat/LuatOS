-- Fixed deadlines: late callbacks skip missed slots instead of adding another
-- full frame delay or replaying stale queued timer messages.
local Pacer={};Pacer.__index=Pacer
local function finite(n) return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge end
function Pacer.new(period_ms,now_ms)
    assert(finite(period_ms) and period_ms>=1,"positive frame period required")
    assert(finite(now_ms) and now_ms>=0,"valid initial time required")
    return setmetatable({period_ms=period_ms,next_ms=now_ms+period_ms},Pacer)
end
function Pacer:due(now_ms)
    if not finite(now_ms) or now_ms<self.next_ms then return false,0,0 end
    local late=now_ms-self.next_ms
    local skipped=math.floor(late/self.period_ms)
    self.next_ms=self.next_ms+(skipped+1)*self.period_ms
    return true,skipped,late
end
return Pacer
