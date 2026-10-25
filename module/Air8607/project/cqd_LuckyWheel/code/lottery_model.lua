-- Pure Lua 5.3 lottery state machine. No clock, timer, graphics or RNG seeding.
-- new({participants={"name",{id="stable-id",name="name"}}, ...}, rng)
-- rng(n) must return a uniformly chosen integer 1..n. It is called once for
-- each successful draw attempt, before the animation starts, never at its end.
-- Sector i has unrotated center (i-0.5)*360/n degrees; zero points right,
-- positive angles rotate clockwise, and the default pointer points up (-90).
local Lottery={}
Lottery.__index=Lottery

local function finite(value)
    return type(value)=="number" and value==value and value~=math.huge and value~=-math.huge
end

local function copy(value)
    if type(value)~="table" then return value end
    local result={}
    for key,item in pairs(value) do result[key]=copy(item) end
    return result
end

function Lottery.new(config,rng)
    config=config or {}
    assert(type(config)=="table","lottery configuration must be a table")
    local participants=config.participants or {}
    assert(type(participants)=="table","participants must be an array")
    rng=rng or config.rng
    assert(type(rng)=="function","an injected rng(n) function is required")
    local duration=config.spin_duration_ms
    if not finite(duration) or duration<=0 then duration=3200 end
    local pointer=config.pointer_angle_deg
    if not finite(pointer) then pointer=-90 end
    local self=setmetatable({phase="IDLE",elapsed_ms=0,round=0,draw_count=0,
        angle_deg=0,spin_elapsed_ms=0,spin_duration_ms=duration,
        pointer_angle_deg=pointer,rng=rng,participants={}},Lottery)
    for i,person in ipairs(participants) do
        local id,name
        if type(person)=="string" then id,name=i,person
        elseif type(person)=="table" then id,name=person.id or i,person.name
        else error("participant "..i.." must be a name or {id,name}") end
        assert(type(name)=="string" and name~="","participant "..i.." needs a nonempty name")
        assert((type(id)=="string" and id~="") or finite(id),"participant "..i.." needs a valid id")
        self.participants[i]={id=id,name=name,index=i}
    end
    return self
end

function Lottery:start()
    if self.phase~="IDLE" then return false,"not_idle" end
    local count=#self.participants
    if count==0 then return false,"no_participants" end
    local ok,index,reason=pcall(self.rng,count)
    if not ok then return false,"rng_error" end
    if not finite(index) or index%1~=0 or index<1 or index>count then
        return false,type(reason)=="string" and reason~="" and reason or "invalid_rng_result"
    end
    self.round=self.round+1
    self.draw_count=self.draw_count+1
    self.selected_index=index
    self.started_ms=self.elapsed_ms
    self.start_angle_deg=self.angle_deg
    local sector_center=(index-0.5)*360/count
    local desired=(self.pointer_angle_deg-sector_center)%360
    local alignment=(desired-self.start_angle_deg%360)%360
    -- Five or six full circles plus less than one circle of alignment keeps
    -- the actual travel in [5,7) circles, without spending extra random draws.
    local full_turns=5+(self.round-1)%2
    self.target_angle_deg=self.start_angle_deg+full_turns*360+alignment
    self.spin_elapsed_ms=0
    self.winner=nil
    self.phase="SPINNING"
    return true
end

function Lottery:step(dt_ms)
    if not finite(dt_ms) or dt_ms<0 then return false,"invalid_dt" end
    self.elapsed_ms=self.elapsed_ms+dt_ms
    if self.phase~="SPINNING" then return true end
    self.spin_elapsed_ms=math.min(self.spin_duration_ms,self.spin_elapsed_ms+dt_ms)
    local progress=self.spin_elapsed_ms/self.spin_duration_ms
    local eased=1-(1-progress)^3
    self.angle_deg=self.start_angle_deg+(self.target_angle_deg-self.start_angle_deg)*eased
    if progress>=1 then
        self.angle_deg=self.target_angle_deg
        local person=self.participants[self.selected_index]
        self.winner={id=person.id,name=person.name,index=self.selected_index,round=self.round,
            started_ms=self.started_ms,completed_ms=self.started_ms+self.spin_duration_ms}
        self.last_winner=copy(self.winner)
        self.phase="WINNER"
    end
    return true
end

function Lottery:dismiss()
    if self.phase~="WINNER" then return false,"not_winner" end
    self.phase="IDLE"
    self.winner=nil
    self.selected_index=nil
    self.spin_elapsed_ms=0
    return true
end

-- Per-frame snapshots omit the static roster when compact==true. The UI keeps
-- its configuration roster; no internal participant reference is exposed.
-- The default API still returns a complete, detached participant list.
function Lottery:snapshot(compact)
    return {phase=self.phase,elapsed_ms=self.elapsed_ms,round=self.round,draw_count=self.draw_count,
        angle_deg=self.angle_deg,angle_normalized_deg=self.angle_deg%360,
        spin_elapsed_ms=self.spin_elapsed_ms,spin_duration_ms=self.spin_duration_ms,
        progress=self.spin_elapsed_ms/self.spin_duration_ms,
        pointer_angle_deg=self.pointer_angle_deg,
        sector_angle_deg=#self.participants>0 and 360/#self.participants or 0,
        participant_count=#self.participants,participants=compact~=true and copy(self.participants) or nil,
        can_start=self.phase=="IDLE" and #self.participants>0,can_dismiss=self.phase=="WINNER",
        winner=copy(self.winner),last_winner=copy(self.last_winner)}
end

return Lottery
