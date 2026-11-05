-- AI-MANAGED: true
-- 真实SDK开会话结果与close交错；双阶段屏障防止短暂错误状态被轮询漏采。
local z = require('zenohpico')
-- luat_zenoh_pico.h的C状态；Lua公开常量目前只有ONLINE/CLOSED。
local OPENING, CLOSING = 1, 3
local function wait(fn)
    for _ = 1, 1000 do host_pump(5); if fn() then return end end
    error('open race deadline')
end
local function ordinary()
    local h = assert(z.open(ENDPOINT, 0, function() end))
    wait(function() return z.state(h) == z.ONLINE end)
    return h
end
local function finish(h)
    assert(z.close(h))
    wait(function() return z.state(h) == z.CLOSED end)
    host_pump(100)
end
-- 先建立长期保留的worker/队列，之后只比较可回收模块分配。
finish(ordinary())
local baseline = host_allocations()
local old
local mode = os.getenv('ZENOH_OPEN_RACE_CASE') or 'both'
assert(mode == 'both' or mode == 'success' or mode == 'sdk_failure')
local checks = 1
for _, case in ipairs({{'success', ENDPOINT}, {'sdk_failure', 'tcp/127.0.0.1:0'}}) do
    if mode == 'both' or mode == case[1] then
    local opened, errors, closed, terminal = 0, 0, 0, nil
    assert(host_race_arm(3))
    local h = assert(z.open(case[2], 0, function(_, e)
        if e.kind == 'opened' then opened = opened + 1 end
        if e.kind == 'error' then errors = errors + 1 end
        if e.kind == 'closed' then closed = closed + 1; terminal = e end
    end))
    wait(host_race_arrived)
    assert(z.state(h) == OPENING)
    assert(z.close(h))
    assert(z.state(h) == CLOSING)
    host_race_release()
    wait(host_race_arrived)
    assert(z.state(h) == CLOSING, 'late open result overwrote CLOSING: '..case[1])
    assert(z.publish(h, PREFIX..'/in', 'rejected') == nil)
    host_race_release()
    wait(function() return z.state(h) == z.CLOSED and closed == 1 end)
    host_pump(100)
    assert(opened == 0 and errors == 0 and closed == 1)
    assert(terminal.code == 0 or case[1] == 'sdk_failure')
    if case[1] == 'sdk_failure' then assert(terminal.code ~= 0) end
    assert(host_allocations() == baseline, 'SDK/module resource leak')
    old = h
    print('OPEN_RACE_PASS '..case[1]..' closing_preserved closed_once resources_released')
    checks = checks + 1
    end
end
-- 下一代通过真实peer完成回显；旧句柄不能影响它。
local h = ordinary()
assert(z.close(old))
assert(z.state(h) == z.ONLINE)
local echoed
assert(z.subscribe(h, PREFIX..'/out', function(_, e) echoed = e.payload end))
host_pump(200)
assert(z.publish(h, PREFIX..'/in', 'open-race-control'))
wait(function() return echoed == 'open-race-control' end)
assert(z.publish(h, PREFIX..'/stop', 'done')); host_pump(200)
finish(h)
assert(host_allocations() == baseline)
print('OPEN_RACE_HOST_PASS checks='..checks)
