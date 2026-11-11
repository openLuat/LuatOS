-- AI-MANAGED: true
-- SPDX-License-Identifier: MIT
-- 真实共享query和Final写失败，钩子只在对应worker FINISH命令生效。
local z=require('zenohpico')
local events,queries,status={}, {}, {}
local function wait_for(fn,ms)
    local until_us=host_monotonic_us()+(ms or 6000)*1000
    repeat host_pump(5);if fn()then return end until host_monotonic_us()>=until_us
    error('Final case timeout')
end
local function open()
    events,queries,status={},{},{}
    local h=assert(z.open(ENDPOINT,0,function(_,e)events[e.id]=e end))
    wait_for(function()return z.state(h)==z.ONLINE end)
    local sub=assert(z.subscribe(h,PREFIX..'/status',function(_,e)status[#status+1]=e.payload end))
    wait_for(function()return events[sub]end);host_pump(100);return h
end
local function declare(h,key)
    local id=assert(z.queryable(h,key,function(_,e)queries[#queries+1]=e.query end))
    wait_for(function()return events[id]end);host_pump(100);return id
end
local h=open();local done
assert(z.get(h,PREFIX..'/peer',{},function()end,function(_,e)done=e end));wait_for(function()return done end);assert(done.code==0)
declare(h,PREFIX..'/device');declare(h,PREFIX..'/**')
assert(z.publish(h,PREFIX..'/control','ask'));wait_for(function()return #queries==2 end)
for i=1,2 do local id=assert(z.reply(h,queries[i],PREFIX..'/device','peer\0query\255'));wait_for(function()return events[id]end);assert(events[id].code==0)end
local first=assert(z.finish_reply(h,queries[1]));wait_for(function()return events[first]end)
assert(events[first].kind=='query_owner_released' and events[first].code==0);host_pump(100);assert(#status==0)
local last=assert(z.finish_reply(h,queries[2]));wait_for(function()return events[last] and #status==1 end)
assert(events[last].kind=='query_finished' and events[last].code==0 and status[1]=='DEVICE_GET_DONE:2')
print('FINAL_SHARED_PASS')
assert(z.close(h));wait_for(function()return z.state(h)==z.CLOSED end);host_pump(80)
for _,budget in ipairs({0,5})do
    h=open();declare(h,PREFIX..'/device');assert(z.publish(h,PREFIX..'/control','ask'))
    wait_for(function()return #queries==1 end)
    for _=1,2 do local id=assert(z.reply(h,queries[1],PREFIX..'/device','peer\0query\255'));wait_for(function()return events[id]end);assert(events[id].code==0)end
    host_fail_final_write(budget)
    local id=assert(z.finish_reply(h,queries[1]));wait_for(function()return events[id] and z.state(h)==z.CLOSED end);host_pump(60)
    assert(events[id].kind=='error' and events[id].code<0,'Final was falsely successful')
    local bytes,later=host_write_failure_stats();assert(bytes==budget and later==0)
    assert(events[id].io_failure and events[id].io_failure.command_id==id)
    print('FINAL_FAULT_PASS '..budget..' '..id..' '..events[id].code..' '..bytes..' '..later)
    queries={};h=nil;collectgarbage('collect');host_pump(1700)
    host_write_failure_after(-1)
    assert(z.payload_stats().tx_bytes==0 and z.payload_stats().rx_bytes==0)
end
h=open();declare(h,PREFIX..'/device');assert(z.publish(h,PREFIX..'/control','ask'))
wait_for(function()return #queries==1 end)
for _=1,2 do local id=assert(z.reply(h,queries[1],PREFIX..'/device','peer\0query\255'));wait_for(function()return events[id]end);assert(events[id].code==0)end
host_cancel_write_after(5)
local cancelled=assert(z.publish(h,PREFIX..'/in','partial cancellation frame'));host_write_release()
wait_for(function()return z.state(h)==z.CLOSED and events[0] and events[0].kind=='closed'end);host_pump(80)
local bytes,later=host_write_failure_stats();assert(bytes==5 and later==0,'cleanup wrote after partial cancellation')
assert(events[0].code<0 and events[0].io_failure.stage=='tx_cancelled' and events[0].io_failure.transferred==5)
assert(events[0].cleanup_code<0 and z.payload_stats().tx_bytes==0 and z.payload_stats().rx_bytes==0)
print('CANCEL_PARTIAL_PASS '..bytes..' '..later..' '..events[0].cleanup_code)
queries={};h=nil;collectgarbage('collect');host_pump(1700);host_write_failure_after(-1)
h=open();local stop=assert(z.publish(h,PREFIX..'/stop','done'));wait_for(function()return events[stop]end);host_pump(100)
assert(z.close(h));wait_for(function()return z.state(h)==z.CLOSED end)
print('FINAL_TESTS_PASS')
