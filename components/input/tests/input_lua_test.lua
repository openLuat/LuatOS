local function flush()
    for i=1,8 do test_tick(); test_pump() end
end
-- Exercise source filtering through the public USB entry point.
local function test_usb_hid_subscription()
    assert(input == nil and type(usb.hid_subscribe) == "function")
    local events = {}
    local usb_id = test_add(0)
    local touch_id = test_add(1, 0x18) -- I2C; otherwise identical caps to USB.
    local sub = assert(usb.hid_subscribe({queue_bytes=512, types={usb.HID_EV_REL}}, function(k, id, data)
        events[#events+1] = {k, id, data}
    end))
    local missing, why = usb.hid_subscribe({device=touch_id}, function() end)
    assert(missing == nil and why == "not_found")
    flush()
    assert(#events == 1 and events[1][1] == "attach" and events[1][2] == usb_id)
    local function move(id) test_emit(id, {{usb.HID_EV_REL,0,1}}) end
    for i=1,100 do move(touch_id) end
    flush()
    assert(#events == 1 and sub:stats().overflows == 0)
    move(usb_id); flush()
    assert(#events == 2 and events[2][1] == "frame" and events[2][2] == usb_id)
    assert(events[2][3]:get(1) == usb.HID_EV_REL)

    events = {}
    for i=1,100 do move(usb_id) end
    flush()
    assert(#events == 2 and events[1][1] == "overflow" and events[1][3].reason == "queue_full")
    assert(events[2][1] == "attach" and events[2][2] == usb_id and events[2][3].resync)
    test_remove(touch_id); test_remove(usb_id); flush()
    assert(#events == 3 and events[3][1] == "remove" and events[3][2] == usb_id)

    local new_touch = test_add(1, 0x18)
    local new_usb = test_add(0)
    flush()
    assert(#events == 4 and events[4][1] == "attach" and events[4][2] == new_usb)
    sub:close()
    test_remove(new_touch); test_remove(new_usb); flush()
    assert(#events == 4 and input == nil)
end

test_usb_hid_subscription()

-- Event codes from luat_input.h; the fixture exposes these capabilities.
local KEY_A = 30
local ABS_MT_SLOT, ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_MT_TRACKING_ID = 0x2f, 0x35, 0x36, 0x39
local function key(id, value)
    test_emit(id, {{usb.HID_EV_KEY, KEY_A, value}})
end
assert(input == nil)
local records = {}
local s = assert(usb.hid_subscribe({}, function(kind, id, data)
    records[#records+1] = {kind, id, data}
end))
local id = test_add(0)
test_pump()
assert(records[1][1] == "attach" and records[1][3].vendor == 0x1234)
assert(records[1][3].id == id and records[1][3].caps.abs[0].max == 1023)
assert(records[1][3].caps.mt_slots == 1)
key(id, 1); key(id, 0); test_pump()
local held = records[2][3]
assert(held.count == 1 and #held == 1 and held.device_id == id)
local t,c,v = held:get(1)
assert(t == usb.HID_EV_KEY and c == KEY_A and v == 1)
assert(not pcall(function() held.count=99 end))
assert(not pcall(function() held:get(2) end))
collectgarbage("collect")
assert(select(3,held:get(1)) == 1)

local filtered = {}
local only = assert(usb.hid_subscribe({device=id,types={usb.HID_EV_KEY}}, function(k,_,data)
    if k == "frame" then filtered[#filtered+1] = data end
end))
test_pump()
test_emit(id, {{usb.HID_EV_REL,0,9},{usb.HID_EV_KEY,KEY_A,1},{usb.HID_EV_REL,1,8}})
test_pump()
assert(#filtered == 1 and filtered[1].count == 1)
test_emit(id, {{usb.HID_EV_REL,0,3}}); test_pump()
assert(#filtered == 1)
local snap
local late = assert(usb.hid_subscribe({device=id}, function(k,_,data)
    if k == "attach" then snap = data.state end
end))
test_pump(); assert(snap.keys[KEY_A]); late:close()
only:close(); only:close(); assert(only:stats().closed)
test_emit(id, {{usb.HID_EV_ABS,ABS_MT_SLOT,0},{usb.HID_EV_ABS,ABS_MT_TRACKING_ID,7},
    {usb.HID_EV_ABS,ABS_MT_POSITION_X,100},{usb.HID_EV_ABS,ABS_MT_POSITION_Y,200}})
local mt_state
local mt_sub = assert(usb.hid_subscribe({device=id}, function(k, _, data)
    if k == "attach" then mt_state = data.state end
end))
flush(); assert(mt_state.slots[0][ABS_MT_TRACKING_ID] == 7); mt_sub:close()

-- An entire lifecycle can finish before Lua handles its first ATTACH.
local transient = test_add(1); test_remove(transient); flush()
local attach, remove
for _,r in ipairs(records) do
    if r[2] == transient and r[1] == "attach" then attach=r[3] end
    if r[2] == transient and r[1] == "remove" then remove=true end
end
assert(attach.name == "fixture" and remove)
local absent,err = usb.hid_subscribe({device=transient}, function() end); assert(absent == nil and err == "not_found")
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
assert(overflow == "queue_full" and not baseline.keys[KEY_A])
assert(s:stats().overflows == 1)
test_remove(recovery_device); flush()
local n=#records;key(id,1);test_pump();assert(#records == n+1)

-- Closing from a callback is safe and suppresses already queued later frames.
local closed_hits = 0
local selfclosing
selfclosing = assert(usb.hid_subscribe({device=id}, function(k, device_id)
    if k == "frame" then
        closed_hits=closed_hits+1
        assert(device_id == id); selfclosing:close()
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
local disposable = assert(usb.hid_subscribe({},function(k) if k == "frame" then gc_hits=gc_hits+1 end end))
flush();key(id,0);disposable=nil;collectgarbage("collect");flush();assert(gc_hits == 0)
local bad = assert(usb.hid_subscribe({}, function(k) if k == "frame" then error("expected test error") end end))
flush();key(id,1);flush();assert(bad:stats().closed and not s:stats().closed)

-- A single frame bigger than the queue closes only that consumer, with reason.
local reason
local small = assert(usb.hid_subscribe({queue_bytes=512},function(k,_,data)
    if k == "overflow" then reason=data.reason end
end))
flush()
local big={};for i=1,100 do big[i]={usb.HID_EV_REL,0,1} end
test_emit(id,big);flush()
assert(reason == "frame_too_large" and small:stats().closed)
assert(s:stats().closed == false)
assert(small:stats().required_bytes == 816)
s:close();test_remove(id);flush()
assert(input == nil)
assert(usb.hid_subscribe({device=id},function() end) == nil)
collectgarbage("collect")
