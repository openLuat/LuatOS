-- AI-MANAGED: true
-- 直接运行真实C/SDK/原PC peer；保留4096B和1800ms原场景，不依赖业务适配。
local z=require('zenohpico')
io.stdout:setvbuf('no')
local events,samples,status={},{},{}
local function wait_for(predicate)
    for _=1,1600 do
        host_pump(5)
        if predicate() then return end
    end
    error('actual peer/worker timeout')
end
local h=assert(z.open(ENDPOINT,0,function(_,e) events[e.id]=e end))
wait_for(function() return z.state(h)==z.ONLINE end)
local sub=assert(z.subscribe(h,PREFIX..'/out',function(_,e) samples[#samples+1]=e.payload end))
local status_sub=assert(z.subscribe(h,PREFIX..'/status',function(_,e) status[#status+1]=e.payload end))
local incoming=0
local q=assert(z.queryable(h,PREFIX..'/device',function(handle,e)
    assert(e.parameters=='source=peer' and e.payload=='peer\0query\255')
    incoming=incoming+1
    assert(z.reply(handle,e.query,e.key,e.payload))
    assert(z.reply(handle,e.query,e.key,e.payload))
    assert(z.finish_reply(handle,e.query))
end))
wait_for(function() return events[sub] and events[status_sub] and events[q] end)
host_pump(100)
for round=1,2 do
    local payload=('\0\255'..PREFIX..':'..round):rep(1000):sub(1,4096)
    local before=#samples
    assert(z.publish(h,PREFIX..'/in',payload))
    wait_for(function() return #samples>before end)
    assert(samples[#samples]==payload)
    local replies,done={},nil
    local terminals=0
    local id=assert(z.get(h,PREFIX..'/peer',
        {payload=payload,parameters='source=lua',timeout_ms=1800},
        function(_,e)
            assert(e.key==PREFIX..'/peer' and e.payload==payload and e.code==0)
            replies[#replies+1]=e.payload
        end,
        function(_,e) done=e;terminals=terminals+1 end))
    wait_for(function() return done end)
    print('G08_OBSERVED',round,#replies,done.reason,done.code,terminals)
    assert(done.request_id==id and done.reason=='completed' and done.code==0)
    assert(terminals==1 and #replies==2)
    before=#samples
    assert(z.publish(h,PREFIX..'/in','alive:'..round))
    wait_for(function() return #samples>before end)
    assert(samples[#samples]=='alive:'..round)
end
assert(z.publish(h,PREFIX..'/control','ask'))
wait_for(function() return incoming==1 and status[1]=='DEVICE_GET_DONE:2' end)
assert(z.unsubscribe(h,sub));assert(z.unsubscribe(h,status_sub));assert(z.unqueryable(h,q))
host_pump(100)
assert(z.publish(h,PREFIX..'/stop','stop'));host_pump(100)
assert(z.close(h));wait_for(function() return z.state(h)==z.CLOSED end)
host_pump(100)
print('G08_HOST_PASS rounds=2 payload=4096 timeout_ms=1800 scope=host_not_target')
