-- AI-MANAGED: true
-- 真实SDK/Router/独立peer验证大载荷、字节预算和异常回收；不操作设备。
local z = require('zenohpico')
-- 仍强制短读/短写；大包套件用257/511避免把系统调用吞吐当作载荷超时。
host_network_chunks(257,511)
local checks, events, samples, status, query = 0, {}, {}, {}, nil
local query_mode, expected_query = 'reply', ''
local unit = {}; for i=0,255 do unit[#unit+1]=string.char(i) end; unit=table.concat(unit)
local function payload(n) return unit:rep(math.ceil(n/#unit)):sub(1,n) end
local function wait_for(fn, ms)
    for _=1,math.ceil((ms or 15000)/5) do host_pump(5); if fn() then return end end
    error('payload test deadline')
end
local function test(name, fn)
    print('PAYLOAD_START',name,os.date('%H:%M:%S'))
    local ok,err=xpcall(fn,debug.traceback); assert(ok,err)
    checks=checks+1; print('PAYLOAD_PASS',name)
end
local function zero_bytes()
    local s=z.payload_stats(); return s.tx_bytes==0 and s.rx_bytes==0
end
local function close(h)
    assert(z.close(h)); wait_for(function() return z.state(h)==z.CLOSED end)
    host_pump(100); assert(zero_bytes(),'close leaked payload budget')
end
local function connect()
    events={}; samples={}; status={}; query=nil
    local h=assert(z.open(ENDPOINT,0,function(_,e) events[e.id]=e end))
    wait_for(function() return z.state(h)==z.ONLINE end)
    host_pump(50); return h
end
local function subscribe(h)
    local id=assert(z.subscribe(h,PREFIX..'/out',function(_,e) samples[#samples+1]=e.payload end))
    wait_for(function() return events[id] end)
    local sid=assert(z.subscribe(h,PREFIX..'/status',function(_,e) status[#status+1]=e.payload end))
    wait_for(function() return events[sid] end); host_pump(150)
end
local function drained()
    collectgarbage('collect'); host_pump(200); wait_for(zero_bytes)
end
local function hold_publish(h,body)
    drained(); assert(host_race_arm(6))
    local id=assert(z.publish(h,PREFIX..'/unused',body)); wait_for(host_race_arrived)
    local seen,op=host_race_command(); assert(seen==id and op==1,'wrong barrier command')
    return id
end
local function wait_unpumped(fn)
    for _=1,3000 do host_sleep(5); if fn() then return end end
    error('unpolled worker deadline')
end
local h=connect(); close(h)
local base_allocations, base_bytes=host_allocations(),host_heap_stats()
h=connect(); subscribe(h)
test('exports and 256KiB+1 refusal',function()
    assert(z.MAX_PAYLOAD==262144)
    local s=z.payload_stats(); assert(s.tx_limit==524288 and s.rx_limit==524288)
    assert(not pcall(z.publish,h,PREFIX..'/in',payload(262145)))
    assert(not pcall(z.get,h,PREFIX..'/peer',{payload=payload(262145)},function()end,function()end))
end)
test('PubSub exact binary boundaries',function()
    for _,n in ipairs({0,1,4095,4096,4097,65535,65536,65537,131072,262143,262144}) do
        local body=payload(n); local before=#samples
        local id=assert(z.publish(h,PREFIX..'/in',body))
        wait_for(function() return #samples>before and events[id] end)
        assert(#samples==before+1 and samples[#samples]==body,'PubSub bytes '..n)
        assert(events[id].kind=='published' and events[id].code==0)
        wait_for(zero_bytes)
    end
end)
test('Get request and two replies 64/128/256KiB',function()
    for _,n in ipairs({65536,131072,262144}) do
        local body=payload(n); local count,done=0,nil
        assert(z.get(h,PREFIX..'/peer',{payload=body,timeout_ms=10000},function(_,e)
            assert(e.payload==body and e.code==0); count=count+1
        end,function(_,e) done=e end))
        wait_for(function() return done end)
        assert(done.reason=='completed' and done.code==0 and count==2,'Get size '..n)
        wait_for(zero_bytes)
    end
end)
test('256KiB error reply',function()
    local body=payload(262144); local response,done
    assert(z.get(h,PREFIX..'/error',{payload=body,timeout_ms=10000},function(_,e) response=e end,function(_,e) done=e end))
    wait_for(function() return done end)
    assert(response and response.operation=='error' and response.code==-11 and response.payload==body)
    assert(done.code==0); wait_for(zero_bytes)
end)
local qid=assert(z.queryable(h,PREFIX..'/device',function(handle,e)
    assert(handle==h and e.payload==expected_query)
    query=e.query
    if query_mode=='hold' then return end
    assert(not pcall(z.reply,h,e.query,e.key,payload(262145)))
    assert(z.reply(h,e.query,e.key,e.payload)); assert(z.reply(h,e.query,e.key,e.payload))
    assert(z.finish_reply(h,e.query))
end))
wait_for(function() return events[qid] end); host_pump(150)
test('incoming queries and two replies 64/128/256KiB',function()
    for _,n in ipairs({65536,131072,262144}) do
        expected_query=payload(n); query=nil; local before=#status
        assert(z.publish(h,PREFIX..'/control',expected_query))
        wait_for(function() return #status>before end)
        assert(query and status[#status]=='DEVICE_GET_DONE:2','incoming size '..n)
        wait_for(zero_bytes)
    end
end)
test('owned query stays charged until expiry',function()
    expected_query=payload(262144); query=nil; query_mode='hold'; local before=#status
    assert(z.publish(h,PREFIX..'/control',expected_query))
    wait_for(function() return query~=nil end)
    assert(z.payload_stats().rx_bytes==262144,'retained SDK query uncharged')
    wait_for(function() return #status>before end,8000)
    assert(status[#status]=='DEVICE_GET_DONE:0'); wait_for(zero_bytes)
    query=nil; query_mode='reply'
end)
test('command allocation failures roll back bytes and id',function()
    for _,allocation in ipairs({0,1}) do
        local before=assert(z.publish(h,PREFIX..'/unused','id')); wait_for(function() return events[before] end)
        host_fail_after(allocation)
        local id,err=z.publish(h,PREFIX..'/unused',payload(65536))
        assert(id==nil and err==-3 and z.payload_stats().tx_bytes==0)
        local nextid=assert(z.publish(h,PREFIX..'/unused','ok')); assert(nextid==before+1)
        wait_for(function() return events[nextid] end)
    end
end)
test('worker payload allocation failure gives failed Get terminal',function()
    local done, replies=nil,0; host_fail_rx_payload(65536)
    assert(z.get(h,PREFIX..'/peer',{payload=payload(65536),timeout_ms=10000},function() replies=replies+1 end,function(_,e) done=e end))
    wait_for(function() return done end)
    assert(done.reason=='resource_limit' and done.code==-3 and replies==0)
    host_pump(100); wait_for(zero_bytes)
end)
test('Lua payload allocation failure cannot report completed',function()
    local body=payload(262144); local done,replies,terminals=nil,0,0
    drained(); local _,_,before=z.state(h); host_fail_lua_payload(#body)
    assert(z.get(h,PREFIX..'/peer',{payload=body,timeout_ms=10000},function() replies=replies+1 end,function(_,e) done=e; terminals=terminals+1 end))
    wait_for(function() return done end)
    assert(host_lua_failures()==2 and replies==0 and terminals==1)
    assert(done.reason=='resource_limit' and done.code==-3); wait_for(zero_bytes)
    local _,_,after=z.state(h); assert(after==before+1)
    -- 失败后的四槽都可重用，真实对端每个请求仍给两次回复。
    local ends,counts=0,0
    for _=1,z.MAX_GET_REQUESTS do
        assert(z.get(h,PREFIX..'/peer',{payload='recovered',timeout_ms=10000},function(_,e)
            assert(e.payload=='recovered'); counts=counts+1
        end,function(_,e) assert(e.code==0); ends=ends+1 end))
    end
    wait_for(function() return ends==z.MAX_GET_REQUESTS end)
    assert(counts==2*z.MAX_GET_REQUESTS); wait_for(zero_bytes)
end)
test('terminal table OOM releases Get capacity',function()
    drained(); local _,_,before=z.state(h); local replies,done=0,0
    host_fail_lua_terminal()
    assert(z.get(h,PREFIX..'/peer',{payload='terminal',timeout_ms=10000},function(_,e)
        assert(e.payload=='terminal'); replies=replies+1
    end,function() done=done+1 end))
    wait_for(function() local _,_,n=z.state(h); return n>before end)
    assert(host_lua_failures()==2 and replies==2 and done==0); wait_for(zero_bytes)
    local ends,counts=0,0
    for _=1,z.MAX_GET_REQUESTS do
        assert(z.get(h,PREFIX..'/peer',{payload='again',timeout_ms=10000},function(_,e)
            assert(e.payload=='again'); counts=counts+1
        end,function(_,e) assert(e.code==0); ends=ends+1 end))
    end
    wait_for(function() return ends==z.MAX_GET_REQUESTS end)
    assert(counts==2*z.MAX_GET_REQUESTS); wait_for(zero_bytes)
end)
test('TX budget includes dequeued maximum command',function()
    local body=payload(262144); hold_publish(h,body)
    assert(z.publish(h,PREFIX..'/unused',body))
    assert(z.payload_stats().tx_bytes==524288)
    local id,err=z.publish(h,PREFIX..'/unused','x'); assert(id==nil and err==-10)
    host_race_release(); wait_for(zero_bytes); host_pump(100)
end)
test('full command queue releases newly allocated large payload',function()
    local body=payload(262144); local last=hold_publish(h,'x')
    for _=1,8 do last=assert(z.publish(h,PREFIX..'/unused','x')) end
    assert(z.payload_stats().tx_bytes==9)
    local allocations,bytes=host_allocations(),host_heap_stats()
    local id,err=z.publish(h,PREFIX..'/unused',body)
    assert(id==nil and err==-10 and z.payload_stats().tx_bytes==9)
    assert(host_allocations()==allocations and host_heap_stats()==bytes,'rejected large payload leaked')
    host_race_release(); wait_for(zero_bytes); host_pump(100)
    id=assert(z.publish(h,PREFIX..'/unused','ok')); assert(id==last+1)
    wait_for(function() return events[id] end)
end)
-- 逐包确认已进入绑定，不poll Lua，独立验证累计RX预算。
-- 另测连续三包；只有绑定明确拒绝才成功，不能把缺末片超时当预算拒绝。
local function fill_rx()
    for i=1,2 do
        assert(z.publish(h,PREFIX..'/control','__max__'))
        wait_unpumped(function() return z.payload_stats().rx_bytes==i*262144 end)
    end
end
test('RX budget refuses third maximum sample without polling',function()
    drained(); local _,before=z.state(h); local count=#samples
    assert(z.publish(h,PREFIX..'/control','__burst__'))
    wait_unpumped(function() local _,d=z.state(h); return d>before end)
    assert(z.payload_stats().rx_bytes==524288)
    wait_for(zero_bytes)
    assert(#samples==count+2 and #samples[#samples]==262144)
end)
test('RX byte budget rejection fails Get exactly once',function()
    drained(); local _,before=z.state(h); local done,replies,terminals=nil,0,0
    fill_rx()
    assert(z.payload_stats().rx_bytes==524288)
    local rejected=z.payload_stats().rx_rejected
    assert(z.get(h,PREFIX..'/peer',{payload='budget',timeout_ms=10000},function() replies=replies+1 end,function(_,e) done=e; terminals=terminals+1 end))
    wait_unpumped(function() return z.payload_stats().rx_rejected>rejected end)
    wait_for(function() return done end); host_pump(100)
    assert(done.reason=='resource_limit' and done.code==-10 and replies==0 and terminals==1)
    wait_for(zero_bytes)
end)
test('full event queue fails Get exactly once',function()
    drained()
    for _=1,8 do
        assert(z.publish(h,PREFIX..'/unused','x'))
        wait_unpumped(function() return z.payload_stats().tx_bytes==0 end)
    end
    local _,before=z.state(h); local done,replies,terminals=nil,0,0
    assert(z.get(h,PREFIX..'/peer',{payload='queue',timeout_ms=10000},function() replies=replies+1 end,function(_,e) done=e; terminals=terminals+1 end))
    wait_unpumped(function() local _,d=z.state(h); return d>=before+2 end)
    wait_for(function() return done end); host_pump(100)
    assert(done.reason=='resource_limit' and done.code==-10 and replies==0 and terminals==1)
    wait_for(zero_bytes)
end)
test('remote maximum+1 is rejected before Lua',function()
    local _,before=z.state(h); local count=#samples
    assert(z.publish(h,PREFIX..'/control','__oversize__'))
    wait_for(function() local _,d=z.state(h); return d>before end)
    assert(#samples==count); wait_for(zero_bytes)
end)
test('callback failure releases large event payload',function()
    local _,_,before=z.state(h)
    local sid=assert(z.subscribe(h,PREFIX..'/out',function() error('intentional payload callback failure') end))
    wait_for(function() return events[sid] end); host_pump(150)
    assert(z.publish(h,PREFIX..'/in',payload(65536)))
    wait_for(function() local _,_,n=z.state(h); return n>before end)
    local _,_,after=z.state(h); assert(after==before+1); wait_for(zero_bytes)
    local id=assert(z.unsubscribe(h,sid)); wait_for(function() return events[id] and events[id].kind=='unsubscribed' end)
end)
test('unqueryable releases retained payload and attachment',function()
    drained(); query_mode='hold'; expected_query=string.rep('A',131072); query=nil; local before=#status
    assert(z.publish(h,PREFIX..'/control','__attachment__'))
    wait_for(function() return query~=nil end)
    assert(z.payload_stats().rx_bytes==262144,'SDK payload+attachment accounting')
    assert(z.unqueryable(h,qid))
    wait_for(function() return events[qid] and events[qid].kind=='unqueryable' end)
    wait_for(zero_bytes); wait_for(function() return #status>before end)
    assert(status[#status]=='DEVICE_GET_DONE:0'); query=nil; drained()
end)
test('close drains in-flight maximum commands',function()
    local body=payload(262144); hold_publish(h,body)
    assert(z.publish(h,PREFIX..'/unused',body))
    assert(z.close(h)); host_race_release(); close(h)
    collectgarbage('collect'); host_pump(100)
    assert(host_allocations()==base_allocations and host_heap_stats()==base_bytes,'C allocations not restored')
end)
test('close releases held query payload and attachment',function()
    h=connect(); subscribe(h); query=nil; local before=#status
    local held=assert(z.queryable(h,PREFIX..'/device',function(_,e)
        assert(e.payload==string.rep('A',131072)); query=e.query
    end))
    wait_for(function() return events[held] end); host_pump(150)
    assert(z.publish(h,PREFIX..'/control','__attachment__'))
    wait_for(function() return query~=nil end)
    assert(z.payload_stats().rx_bytes==262144)
    close(h); query=nil; drained()
    assert(host_allocations()==base_allocations and host_heap_stats()==base_bytes)
    -- 先让peer完整处理关闭终态，再开始下个会话；不用旧代消息作成功证据。
    host_pump(100)
end)
test('reopen and maximum payload still works',function()
    h=connect(); subscribe(h)
    local body=payload(262144); assert(z.publish(h,PREFIX..'/in',body))
    wait_for(function() return #samples==1 end); assert(samples[1]==body)
    local id=assert(z.publish(h,PREFIX..'/stop','done')); wait_for(function() return events[id] end)
    close(h); collectgarbage('collect'); host_pump(100)
    assert(host_allocations()==base_allocations and host_heap_stats()==base_bytes)
end)
local stats=z.payload_stats()
assert(stats.tx_bytes==0 and stats.rx_bytes==0 and stats.tx_peak<=stats.tx_limit and stats.rx_peak<=stats.rx_limit)
local _,_,callback_errors=z.state(h); assert(callback_errors==3,'unexpected protected callback error')
local bytes,peak=host_heap_stats()
print('PAYLOAD_MEMORY',bytes,peak,stats.tx_peak,stats.rx_peak,stats.tx_rejected,stats.rx_rejected)
print('PAYLOAD_TESTS_PASS',checks)
