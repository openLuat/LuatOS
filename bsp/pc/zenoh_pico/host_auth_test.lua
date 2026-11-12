-- AI-MANAGED: true
-- SPDX-License-Identifier: MIT
-- 合成测试账户只从临时环境读取，不输出凭据或认证报文。
local z = require('zenohpico')
local case = assert(os.getenv('ZENOH_AUTH_CASE'))
local user, password = os.getenv('ZENOH_TEST_USER'), os.getenv('ZENOH_TEST_PASSWORD')
local positive = case == 'correct' or case == 'maximum' or case == 'anonymous'
local function wait_until(predicate, ms)
    for _=1,math.ceil(ms/5) do host_pump(5); if predicate() then return end end
    error('auth test timed out')
end
local callback = function() end
for _, options in ipairs({{username='x'}, {password='x'}, {username='',password='x'},
    {username='x',password=''}, {username=1,password='x'}, {username='x',password=false},
    {username='x\0y',password='x'}, {username='x',password='x\ny'},
    {username=string.rep('x',129),password='x'}, {username='x',password=string.rep('x',129)},
    {user='x',password='x'}, {['username\0x']='x',['password\0x']='x'},
    {username='x',['password\0x']='x'}, {[1]='x'}}) do
    assert(not pcall(z.open, ENDPOINT, 0, callback, options), 'invalid options accepted')
end
assert(z.AUTH_USRPWD and z.AUTH_CREDENTIAL_MAX == 128)
local options
if case ~= 'anonymous' and case ~= 'missing_credentials' then
    options = {username=user, password=password}
end
local baseline_alloc, baseline_bytes
for round=1,(positive and 3 or 1) do
    local events, opened, closed, failed = {}, false, false, nil
    local h, rc = z.open(ENDPOINT, 0, function(_, e)
        events[e.id] = e
        if e.kind == 'opened' then opened = true end
        if e.kind == 'error' then failed = e end
        if e.kind == 'closed' then closed = true end
    end, options)
    assert(h, 'valid options refused before open: '..tostring(rc))
    wait_until(function() return opened or closed end, 6000)
    if positive then
        assert(opened and not failed and not closed, 'authentication did not open')
        if case=='anonymous' then assert(events[0].auth_stage==nil and events[0].remote_close_reason==nil)
        else assert(events[0].auth_stage=='confirmed','auth completion diagnostic') end
        local received
        local id=assert(z.subscribe(h, PREFIX..'/out', function(_,e) received=e.payload end))
        wait_until(function() return events[id] end,2000)
        assert(events[id].kind=='subscribed');host_pump(100)
        for _,n in ipairs({0,1,4096,65536,262144}) do
            local payload=string.rep('\0\255auth',math.ceil(n/6)):sub(1,n)
            received=nil
            local sent=assert(z.publish(h,PREFIX..'/in',payload))
            wait_until(function() return received~=nil and events[sent] end,8000)
            assert(received==payload and events[sent].code==0,'authenticated payload mismatch')
        end
        if round==3 then
            local stop=assert(z.publish(h,PREFIX..'/stop','stop'))
            wait_until(function() return events[stop] end,2000);assert(events[stop].code==0)
            host_pump(80)
        end
        assert(z.close(h));assert(z.close(h))
        wait_until(function() return closed end,2000)
        assert(z.state(h)==z.CLOSED)
    else
        assert(closed and not opened and failed,'invalid authentication was accepted')
        if case=='wrong_user' or case=='wrong_password' then
            assert(failed.code==-66 and failed.auth_stage=='open_wait' and type(failed.remote_close_reason)=='number','auth rejection diagnostic')
        elseif case=='missing_challenge' then assert(failed.code==-67 and failed.auth_stage=='init_wait') end
        print('AUTH_EXPECTED_REJECTION',case,failed.code,failed.reason or 'unclassified')
    end
    h=nil;events=nil;collectgarbage('collect');host_pump(30)
    local allocations, bytes=host_allocations(),host_heap_stats()
    if not baseline_alloc then baseline_alloc,baseline_bytes=allocations,bytes end
    assert(allocations==baseline_alloc and bytes==baseline_bytes,'closed native memory grew')
end
print('AUTH_CASE_PASS '..case)
