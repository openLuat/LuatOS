-- AI-MANAGED: true
-- 真实Lua/C/SDK/独立Router与peer的Get双向及生命周期回归。
local z = require("zenohpico")
local checks = 0
local function test(name, fn)
    fn(); checks = checks + 1; print("GET_PASS", name)
end
local function wait_for(predicate, ms)
    for _ = 1, math.ceil((ms or 10000)/5) do
        host_pump(5)
        if predicate() then return end
    end
    error("Get timeout waiting for actual peer/worker")
end
local events = {}
local function connect()
    events = {}
    local h = assert(z.open(ENDPOINT, 0, function(_, item) events[item.id] = item end))
    wait_for(function() return z.state(h) == z.ONLINE end)
    host_pump(50)
    return h
end
local function close(h)
    assert(z.close(h)); wait_for(function() return z.state(h) == z.CLOSED end)
    host_pump(100)
end
local h = connect()
test("exports and bounded parameters", function()
    for _, name in ipairs({"get", "cancel_get", "queryable", "unqueryable", "reply", "finish_reply"}) do
        assert(type(z[name]) == "function", name)
    end
    assert(z.GET_CANCEL_MODE == "local" and z.MAX_GET_REQUESTS == 4)
    assert(not pcall(z.get, h, "", {}, function() end, function() end))
    assert(not pcall(z.get, h, PREFIX, {parameters="a\0b"}, function() end, function() end))
    assert(not pcall(z.get, h, PREFIX, {timeout_ms=99}, function() end, function() end))
    assert(not pcall(z.get, h, PREFIX, {payload=string.rep("x",4097)}, function() end, function() end))
end)
test("outgoing Get binary two replies and final", function()
    for _, n in ipairs({0, 20, 4096}) do
        local payload = ("\0\255request"):rep(math.ceil(n/9)):sub(1,n)
        local replies, terminal = {}, nil
        local id = assert(z.get(h, PREFIX.."/peer", {payload=payload,parameters="source=lua",timeout_ms=5000},
            function(handle,item)
                assert(handle==h and item.kind=="get_reply" and item.code==0)
                assert(item.key==PREFIX.."/peer" and item.payload==payload)
                replies[#replies+1]=item.payload
            end,
            function(_,item) terminal=item end))
        wait_for(function() return terminal end)
        assert(terminal.request_id==id and terminal.reason=="completed" and terminal.code==0)
        assert(#replies==2)
    end
end)
test("error reply distinct from completion", function()
    local reply, done
    assert(z.get(h,PREFIX.."/error",{},function(_,e) reply=e end,function(_,e) done=e end))
    wait_for(function() return done end)
    assert(reply and reply.code==-11 and reply.operation=="error" and reply.payload=="peer-error")
    assert(done.kind=="get_done")
end)
test("finite timeout", function()
    local done
    assert(z.get(h,PREFIX.."/silent",{timeout_ms=300},function() error("unexpected reply") end,function(_,e) done=e end))
    wait_for(function() return done end)
    assert(done.reason=="timeout" and done.code==-12)
    host_pump(1700)
end)
test("cancel suppresses late reply and keeps finite context", function()
    local done, replies, terminals = nil,0,0
    local id = assert(z.get(h,PREFIX.."/silent",{timeout_ms=3000},function() replies=replies+1 end,
        function(_,e) done=e; terminals=terminals+1 end))
    wait_for(function() return events[id] and events[id].kind=="get_started" end)
    assert(z.cancel_get(h,id)==id)
    wait_for(function() return done end)
    assert(done.reason=="cancelled_local" and done.code==-13)
    host_pump(2200)
    assert(replies==0 and terminals==1)
    assert(z.cancel_get(h,id)==nil)
end)
test("allocation refusal does not consume command id", function()
    local before=assert(z.publish(h,PREFIX.."/unused","id"))
    wait_for(function() return events[before] end)
    host_fail_after(0)
    local id,err=z.get(h,PREFIX.."/peer",{},function() end,function() end)
    assert(id==nil and err==-3)
    local done
    id=assert(z.get(h,PREFIX.."/peer",{},function() end,function(_,e) done=e end))
    assert(id==before+1)
    wait_for(function() return done end)
end)
local status, incoming, saved_query, incoming_mode = {},0,nil,"reply"
local saved_query_id
local sub=assert(z.subscribe(h,PREFIX.."/status",function(_,e) status[#status+1]=e.payload end))
wait_for(function() return events[sub] and events[sub].kind=="subscribed" end)
local function on_query(handle,e)
    assert(handle==h and e.kind=="query" and e.parameters=="source=peer")
    assert(e.payload=="peer\0query\255" and type(e.query)=="userdata")
    incoming=incoming+1
    if incoming_mode=="reply" then
        saved_query=e.query
        assert(z.reply(h,e.query,PREFIX.."/device",e.payload))
        assert(z.reply(h,e.query,PREFIX.."/device",e.payload))
        assert(z.finish_reply(h,e.query))
    elseif incoming_mode=="hold" then saved_query=e.query;saved_query_id=e.query_id end
end
local qid=assert(z.queryable(h,PREFIX.."/device",on_query))
wait_for(function() return events[qid] and events[qid].kind=="queryable" end)
host_pump(150)
test("peer Get to device and owned-query double reply/final", function()
    assert(z.publish(h,PREFIX.."/control","ask"))
    wait_for(function() return #status==1 end)
    assert(incoming==1 and status[1]=="DEVICE_GET_DONE:2")
    assert(not pcall(z.reply,h,saved_query,PREFIX.."/device","late"))
end)
test("query userdata GC sends final without reply", function()
    incoming_mode="gc"
    assert(z.publish(h,PREFIX.."/control","ask"))
    wait_for(function() return incoming==2 end)
    collectgarbage("collect")
    wait_for(function() return #status==2 end)
    assert(status[2]=="DEVICE_GET_DONE:0")
end)
test("undeclare drops held query and rejects later reply execution", function()
    incoming_mode="hold"
    assert(z.publish(h,PREFIX.."/control","ask"))
    wait_for(function() return incoming==3 end)
    assert(z.unqueryable(h,qid)==qid)
    wait_for(function() return #status==3 end)
    assert(status[3]=="DEVICE_GET_DONE:0")
    local id=assert(z.reply(h,saved_query,PREFIX.."/device","late"))
    wait_for(function() return events[id] end)
    assert(events[id].kind=="error" and events[id].code==-4)
end)
test("owned incoming query expires before late reply",function()
    incoming_mode="hold"
    local id=assert(z.queryable(h,PREFIX.."/device",on_query))
    wait_for(function() return events[id] and events[id].kind=="queryable" end)
    host_pump(150)
    assert(z.publish(h,PREFIX.."/control","ask"))
    wait_for(function() return incoming==4 end)
    wait_for(function() return events[0] and events[0].kind=="query_expired" and events[0].query_id==saved_query_id end)
    wait_for(function() return #status==4 end)
    assert(status[4]=="DEVICE_GET_DONE:0")
    local late=assert(z.reply(h,saved_query,PREFIX.."/device","expired"))
    wait_for(function() return events[late] end)
    assert(events[late].kind=="error" and (events[late].code==-4 or events[late].code==-12))
    assert(z.unqueryable(h,id)==id);host_pump(100)
end)
test("queryable slot capacity and revoke", function()
    local ids={}
    for i=1,4 do ids[i]=assert(z.queryable(h,PREFIX.."/unused-query/"..i,function() end)) end
    local id,err=z.queryable(h,PREFIX.."/unused-query/5",function() end)
    assert(id==nil and err==-5)
    for _,id in ipairs(ids) do
        wait_for(function() return events[id] end)
        assert(z.unqueryable(h,id)==id)
    end
    host_pump(300)
end)
test("Get capacity and four local cancels", function()
    local ids,done={},{}
    for i=1,4 do ids[i]=assert(z.get(h,PREFIX.."/silent",{timeout_ms=3000},function() end,function(_,e) done[e.request_id]=e end)) end
    local id,err=z.get(h,PREFIX.."/silent",{},function() end,function() end)
    assert(id==nil and err==-5)
    for _,id in ipairs(ids) do wait_for(function() return events[id] and events[id].kind=="get_started" end) end
    for _,id in ipairs(ids) do
        local cancelled,err=z.cancel_get(h,id)
        assert(cancelled==id,"cancel id="..id.." rc="..tostring(err).." terminal="..tostring(done[id] and done[id].reason).." event="..tostring(events[id] and events[id].kind))
    end
    for _,id in ipairs(ids) do wait_for(function() return done[id] end); assert(done[id].reason=="cancelled_local") end
    host_pump(3500)
end)
test("throwing callbacks release request reference", function()
    local _,_,before=z.state(h)
    assert(z.get(h,PREFIX.."/peer",{},function() error("expected reply callback throw") end,
        function() error("expected terminal callback throw") end))
    host_pump(1000)
    local _,_,after=z.state(h);assert(after>=before+3)
end)
test("close completes pending request once", function()
    local terminal, count=nil,0
    local id=assert(z.get(h,PREFIX.."/silent",{timeout_ms=5000},function() end,
        function(_,e) terminal=e;count=count+1 end))
    wait_for(function() return events[id] and events[id].kind=="get_started" end)
    close(h)
    assert(terminal and terminal.reason=="closed" and count==1)
end)
h=nil;collectgarbage("collect");host_pump(200)
local baseline=host_allocations()
h=connect()
test("old generation query token cannot target reopened session",function()
    assert(not pcall(z.reply,h,saved_query,PREFIX.."/device","foreign"))
end)
test("actual TCP disconnect cleans pending Get",function()
    local terminal
    local id=assert(z.get(h,PREFIX.."/silent",{timeout_ms=5000},function() end,function(_,e) terminal=e end))
    wait_for(function() return events[id] and events[id].kind=="get_started" end)
    assert(host_disconnect())
    wait_for(function() return z.state(h)==z.CLOSED and terminal end)
    assert(terminal.reason=="closed")
end)
h=nil;collectgarbage("collect");host_pump(200)
test("module allocations return after request/disconnect cleanup",function()
    assert(host_allocations()==baseline,"Get module allocation leak")
end)
test("session GC cleans pending request",function()
    local s=connect()
    assert(z.get(s,PREFIX.."/silent",{timeout_ms=5000},function() end,function() end))
    host_pump(50);s=nil;collectgarbage("collect");host_pump(1500)
    assert(host_allocations()==baseline,"session GC leaked Get context")
end)
test("accepted Get immediately followed by close terminates",function()
    for _=1,3 do
        local s=connect();local terminal
        assert(z.get(s,PREFIX.."/silent",{timeout_ms=5000},function() end,function(_,e) terminal=e end))
        close(s)
        wait_for(function() return terminal end,1000)
        assert(terminal.reason=="closed")
    end
end)
local final=connect()
assert(z.publish(final,PREFIX.."/stop","done"));host_pump(200);close(final)
print("GET_HOST_PASS checks="..checks)
