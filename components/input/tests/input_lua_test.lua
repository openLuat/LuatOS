local function flush()
    for i=1,8 do test_tick(); test_pump() end
end
local function key(id, value)
    test_emit(id, {{input.EV_KEY, input.KEY_A, value}})
end
assert(#input.list() == 0)
local records = {}
local s = assert(input.subscribe({}, function(kind, id, data)
    records[#records+1] = {kind, id, data}
end))
local id = test_add(0)
test_pump()
assert(records[1][1] == "attach" and records[1][3].vendor == 0x1234)
assert(input.list()[1].id == id)
assert(input.info(id).caps.abs[0].max == 1023)
assert(input.info(id).caps.mt_slots == 1)
key(id, 1); key(id, 0); test_pump()
local held = records[2][3]
assert(held.count == 1 and #held == 1 and held.device_id == id)
local t,c,v = held:get(1)
assert(t == input.EV_KEY and c == input.KEY_A and v == 1)
assert(not pcall(function() held.count=99 end))
assert(not pcall(function() held:get(2) end))
collectgarbage("collect")
assert(select(3,held:get(1)) == 1)

local filtered = {}
local only = assert(input.subscribe({device=id,types={input.EV_KEY}}, function(k,_,data)
    if k == "frame" then filtered[#filtered+1] = data end
end))
test_pump()
test_emit(id, {{input.EV_REL,0,9},{input.EV_KEY,input.KEY_A,1},{input.EV_REL,1,8}})
test_pump()
assert(#filtered == 1 and filtered[1].count == 1)
test_emit(id, {{input.EV_REL,0,3}}); test_pump()
assert(#filtered == 1)
assert(input.state(id).keys[input.KEY_A])
local snap
local late = assert(input.subscribe({device=id}, function(k,_,data)
    if k == "attach" then snap = data.state end
end))
test_pump(); assert(snap.keys[input.KEY_A]); late:close()
only:close(); only:close(); assert(only:stats().closed)
test_emit(id, {{input.EV_ABS,input.ABS_MT_SLOT,0},{input.EV_ABS,input.ABS_MT_TRACKING_ID,7},
    {input.EV_ABS,input.ABS_MT_POSITION_X,100},{input.EV_ABS,input.ABS_MT_POSITION_Y,200}})
assert(input.state(id).slots[0][input.ABS_MT_TRACKING_ID] == 7)
flush()

-- An entire lifecycle can finish before Lua handles its first ATTACH.
local transient = test_add(1); test_remove(transient); flush()
local attach, remove
for _,r in ipairs(records) do
    if r[2] == transient and r[1] == "attach" then attach=r[3] end
    if r[2] == transient and r[1] == "remove" then remove=true end
end
assert(attach.name == "fixture" and remove)
local absent,err = input.info(transient); assert(absent == nil and err == "not_found")
local replacement = test_add(1); assert(replacement ~= transient); flush()
test_remove(replacement); flush()

-- One overloaded subscription recovers; subsequent release is in its snapshot.
local recovery_device = test_add(1); flush()
records = {}
for i=1,300 do key(id,i%2) end
key(id,0)
test_fail_alloc(1); test_pump(); collectgarbage("collect")
assert(#records == 0) -- Partial recovery allocation is cleaned up and retried.
test_fail_alloc(-1)
flush()
local overflow, baseline
for _,r in ipairs(records) do
    if r[1] == "overflow" then overflow=r[3].reason end
    if r[1] == "attach" and r[2] == id and r[3].resync then baseline=r[3].state end
end
assert(overflow == "queue_full" and not baseline.keys[input.KEY_A])
assert(s:stats().overflows == 1)
test_remove(recovery_device); flush()
local n=#records;key(id,1);test_pump();assert(#records == n+1)

-- Closing from a callback is safe and suppresses already queued later frames.
local closed_hits = 0
local selfclosing
selfclosing = assert(input.subscribe({device=id}, function(k)
    if k == "frame" then
        closed_hits=closed_hits+1
        assert(input.state(id)); selfclosing:close()
    end
end))
flush();key(id,0);key(id,1);test_pump();assert(closed_hits == 1)
flush()

-- Failed wake is retried even if no new input arrives.
records={};test_reject();key(id,0);test_pump();assert(#records == 0)
test_tick();test_pump();assert(#records == 1)

-- At most eight frames per subscription per message.
records={};for i=1,20 do key(id,i%2) end
test_pump();assert(#records == 8 and s:stats().queued_bytes > 0)
test_pump();assert(#records == 16) -- Backlog schedules itself without waiting for the retry timer.
flush();assert(#records == 20)

-- GC and stale wakeups never touch a destroyed subscription.
local gc_hits = 0
local disposable = assert(input.subscribe({},function(k) if k == "frame" then gc_hits=gc_hits+1 end end))
flush();key(id,0);disposable=nil;collectgarbage("collect");flush();assert(gc_hits == 0)
local bad = assert(input.subscribe({}, function(k) if k == "frame" then error("expected test error") end end))
flush();key(id,1);flush();assert(bad:stats().closed and not s:stats().closed)

-- A single frame bigger than the queue closes only that consumer, with reason.
local reason
local small = assert(input.subscribe({queue_bytes=512},function(k,_,data)
    if k == "overflow" then reason=data.reason end
end))
flush()
local big={};for i=1,100 do big[i]={input.EV_REL,0,1} end
test_emit(id,big);flush()
assert(reason == "frame_too_large" and small:stats().closed)
assert(s:stats().closed == false)
assert(small:stats().required_bytes == 816)
s:close();test_remove(id);flush()
assert(#input.list() == 0)
assert(input.subscribe({device=id},function() end) == nil)
collectgarbage("collect")
