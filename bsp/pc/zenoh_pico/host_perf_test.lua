-- AI-MANAGED: true
-- SPDX-License-Identifier: MIT
-- 相同C版本/相同SDK，仅切换第二份复制；计时不含载荷生成，仍逐字节验收。
local z=require('zenohpico')
local samples=tonumber(os.getenv('ZENOH_PERF_SAMPLES') or '64')
assert(samples>=16 and samples<=1024)
host_network_chunks(257,511)
local events,received={},nil
local rx_count=0
local function wait_for(fn,timeout)
    local deadline=host_monotonic_us()+(timeout or 8000)*1000
    repeat host_pump(1);if fn() then return end until host_monotonic_us()>=deadline
    error('performance case timeout')
end
local h=assert(z.open(ENDPOINT,0,function(_,e) events[e.id]=e end))
wait_for(function()return z.state(h)==z.ONLINE end)
local sub=assert(z.subscribe(h,PREFIX..'/out',function(_,e)rx_count=rx_count+1;received={time=host_monotonic_us(),payload=e.payload}end))
wait_for(function()return events[sub]end);host_pump(150)
for _,n in ipairs({0,1,256,4096,65536,262144}) do
    local payload=string.rep('\0\255perf',math.ceil(n/6)):sub(1,n)
    collectgarbage('collect');host_pump(20);local idle=host_heap_stats();host_reset_peak()
    for i=1,samples+8 do
        local expected=n>=8 and (string.pack("<I8",i)..payload:sub(9)) or n==1 and string.char(i%256) or payload
        local before=rx_count;received=nil;local start=host_monotonic_us()
        local id=assert(z.publish(h,PREFIX..'/in',expected));local admitted=host_monotonic_us()
        wait_for(function()return received and events[id]end)
        assert(received.payload==expected and rx_count==before+1 and events[id].code==0)
        if i>8 then print('PERF '..n..' '..i..' '..(admitted-start)..' '..(received.time-start)) end
        events[id]=nil
    end
    host_pump(20);local current,peak=host_heap_stats()
    print('PERF_MEMORY '..n..' '..idle..' '..current..' '..peak)
end
local stop=assert(z.publish(h,PREFIX..'/stop','done'));wait_for(function()return events[stop]end)
host_pump(100);assert(z.close(h));wait_for(function()return z.state(h)==z.CLOSED end);host_pump(80)
assert(z.payload_stats().tx_bytes==0 and z.payload_stats().rx_bytes==0)
print('PERF_PASS '..samples)
