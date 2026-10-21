-- SPDX-License-Identifier: MIT
local z = require("zenohpico")
assert(z.version == "1.9.0")
local checks = 0
local function test(name, fn)
    fn(); checks = checks + 1; print("PASS " .. name)
end
local function wait_for(predicate, limit)
    for _ = 1, math.ceil((limit or 7000) / 5) do
        host_pump(5)
        if predicate() then return end
    end
    error("timeout")
end
local events, samples, operations, errors_seen = {}, {}, {}, 0
local function control(_, event)
    events[event.id] = event
    if event.kind == "error" then errors_seen = errors_seen + 1 end
end
local function connect()
    events = {}; errors_seen = 0
    local handle, err = z.open(ENDPOINT, 0, control)
    assert(handle, err)
    wait_for(function() return z.state(handle) == z.ONLINE end)
    host_pump(50)
    return handle
end
local function close(handle)
    assert(z.close(handle)); assert(z.close(handle))
    wait_for(function() return z.state(handle) == z.CLOSED end)
    host_pump(100)
end
local function subscribe(handle)
    samples = {}; operations = {}
    local id = assert(z.subscribe(handle, PREFIX .. "/out", function(_, event)
        assert(event.kind == "sample"); samples[#samples + 1] = event.payload
        operations[#samples] = event.operation
    end))
    wait_for(function() return events[id] and events[id].kind == "subscribed" end)
    host_pump(150)
    return id
end
test("parameters", function()
    assert(not pcall(z.open, ENDPOINT .. "\0bad", 0, control))
    assert(not pcall(z.open, ENDPOINT, -1, control))
    assert(z.open("udp/127.0.0.1:17447", 0, control) == nil)
end)
local s = connect()
test("single session", function() local h, err = z.open(ENDPOINT, 0, control); assert(h == nil and err == -8) end)
local sub = subscribe(s)
test("binary and payload boundaries", function()
    for _, n in ipairs({0, 1, 255, 1024, 4096}) do
        local payload = ("\0\255\1zenoh-"):rep(math.ceil(n / 9)):sub(1, n)
        assert(#payload == n)
        local before = #samples
        local id = assert(z.publish(s, PREFIX .. "/in", payload))
        wait_for(function() return #samples > before end)
        assert(#samples == before + 1 and samples[#samples] == payload)
        assert(operations[#samples] == "put")
        wait_for(function() return events[id] ~= nil end)
        assert(events[id].kind == "published" and events[id].code == 0)
    end
    assert(not pcall(z.publish, s, PREFIX .. "/in", string.rep("x", 4097)))
    assert(not pcall(z.publish, s, "a\0b", "x"))
end)
test("remote delete differs from empty put", function()
    local before = #samples
    assert(z.publish(s, PREFIX .. "/in", "__delete__"))
    wait_for(function() return #samples == before + 1 end)
    assert(samples[#samples] == "" and operations[#samples] == "delete")
end)
test("allocation refusal", function()
    host_fail_after(0)
    local id, err = z.publish(s, PREFIX .. "/in", "not accepted")
    assert(id == nil and err == -3)
end)
test("unsubscribe and old sample filtering", function()
    assert(z.unsubscribe(s, sub))
    wait_for(function() return events[sub] and events[sub].kind == "unsubscribed" end)
    local before = #samples
    local id = assert(z.publish(s, PREFIX .. "/in", "unsubscribed"))
    wait_for(function() return events[id] ~= nil end); host_pump(300)
    assert(#samples == before)
    local no, err = z.unsubscribe(s, sub); assert(no == nil and err == -4)
end)
test("bounded subscriber callbacks", function()
    local ids = {}
    for i = 1, 4 do
        ids[i] = assert(z.subscribe(s, PREFIX .. "/unused/" .. i, function() end))
        wait_for(function() return events[ids[i]] ~= nil end)
    end
    local no, err = z.subscribe(s, PREFIX .. "/unused/5", function() end)
    assert(no == nil and err == -5)
    for _, id in ipairs(ids) do assert(z.unsubscribe(s, id)) end
    host_pump(700)
end)
test("queue backpressure and dropped result observation", function()
    sub = subscribe(s)
    local _, before = z.state(s)
    local refused = 0
    for i = 1, 100 do
        local id, err = z.publish(s, PREFIX .. "/in", "burst:" .. i)
        if not id then assert(err == -10); refused = refused + 1 end
    end
    assert(refused > 0)
    host_sleep(1500)
    local _, after = z.state(s)
    assert(after > before)
    z.poll(); host_pump(700)
end)
test("close suppresses queued samples", function()
    local before = #samples
    assert(z.publish(s, PREFIX .. "/in", "late\0sample"))
    host_sleep(500)
    close(s)
    assert(#samples == before)
end)
collectgarbage("collect"); host_pump(100)
local baseline = host_allocations()
test("close reopen and resource cleanup", function()
    for i = 1, 10 do
        local h = connect(); subscribe(h)
        local payload = "reopen:" .. i .. "\0\255"
        assert(z.publish(h, PREFIX .. "/in", payload))
        wait_for(function() return #samples == 1 end)
        assert(samples[1] == payload)
        close(h)
        assert(z.publish(h, PREFIX .. "/in", "closed") == nil)
        h = nil; collectgarbage("collect"); host_pump(30)
        assert(host_allocations() == baseline, "module allocation leak")
    end
end)
test("GC closes unreferenced handle", function()
    local h = connect(); h = nil; collectgarbage("collect"); host_pump(1200)
    assert(host_allocations() == baseline, "GC leaked module allocations")
    local check = connect(); close(check)
end)
test("real TCP disconnect and explicit recovery", function()
    local h = connect(); subscribe(h)
    assert(host_disconnect())
    wait_for(function() return z.state(h) == z.CLOSED and errors_seen > 0 end)
    host_pump(50)
    local recovered = connect(); subscribe(recovered)
    assert(z.publish(recovered, PREFIX .. "/in", "after disconnect\0\255"))
    wait_for(function() return #samples == 1 end)
    assert(samples[1] == "after disconnect\0\255")
    close(recovered)
    assert(host_allocations() == baseline)
end)
test("partial frame failure stops all later writes", function()
    local h = connect()
    host_write_failure_after(5)
    assert(z.publish(h, PREFIX .. "/in", "incomplete first frame"))
    local second = assert(z.publish(h, PREFIX .. "/in", "must never send"))
    host_write_release()
    wait_for(function() return z.state(h) == z.CLOSED and errors_seen > 0 end)
    host_pump(100)
    local bytes, later = host_write_failure_stats()
    assert(bytes == 5 and later == 0, "continued writing after incomplete frame")
    assert(not events[second] or events[second].kind ~= "published")
    host_write_failure_after(-1)
    local recovered = connect(); subscribe(recovered)
    assert(z.publish(recovered, PREFIX .. "/in", "after write fault"))
    wait_for(function() return #samples == 1 end)
    assert(samples[1] == "after write fault"); close(recovered)
    assert(host_allocations() == baseline)
end)
test("closed callback can immediately reopen", function()
    for _ = 1, 5 do
        local next_handle, failure
        local h = assert(z.open(ENDPOINT, 0, function(_, event)
            if event.kind == "closed" then next_handle, failure = z.open(ENDPOINT, 0, control) end
        end))
        wait_for(function() return z.state(h) == z.ONLINE end)
        assert(z.close(h))
        wait_for(function() return next_handle ~= nil or failure ~= nil end)
        assert(next_handle, failure)
        wait_for(function() return z.state(next_handle) == z.ONLINE end)
        close(next_handle)
    end
    collectgarbage("collect"); host_pump(100)
    assert(host_allocations() == baseline)
end)
test("actual partial reads and writes", function()
    local reads, writes = host_network_stats()
    assert(reads > 0 and writes > 0)
    print("PARTIAL_IO reads=" .. reads .. " writes=" .. writes)
end)
test("peer confirms stop request", function()
    local h = connect()
    local id = assert(z.publish(h, PREFIX .. "/stop", "stop"))
    wait_for(function() return events[id] ~= nil end); close(h)
end)
print("HOST_PASS checks=" .. checks .. " lua=" .. _VERSION)
