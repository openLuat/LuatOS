-- AI-MANAGED: true
-- 用真实pthread屏障、worker/SDK/socket复现关闭交错，不模拟终态。
local z=require('zenohpico')
local mode=os.getenv('ZENOH_TEST_RACE_CASE') or 'both'
local function wait(fn,ms)
    for _=1,math.ceil((ms or 5000)/5) do host_pump(5);if fn() then return end end
    error('actual worker barrier/terminal deadline')
end
local function open()
    local h=assert(z.open(ENDPOINT,0,function() end))
    wait(function() return z.state(h)==z.ONLINE end);host_pump(50);return h
end
local checks=0
if mode=='dequeue' or mode=='both' then
    local h=open();local terminal,count=nil,0
    local _,before=z.state(h)
    assert(host_race_arm(1))
    local id=assert(z.get(h,PREFIX..'/no-queryable',{timeout_ms=1000},function() error('stale reply') end,
        function(_,e) terminal=e;count=count+1 end))
    wait(host_race_arrived);print("RACE_TRACE dequeue_barrier_arrived")
    assert(z.close(h));host_race_release()
    wait(function() return z.state(h)==z.CLOSED end);print("RACE_TRACE actual_closed_before_done_check")
    wait(function() return terminal end,1000)
    local _,after=z.state(h)
    assert(terminal.request_id==id and terminal.reason=='closed' and count==1 and after==before)
    print('RACE_PASS dequeue_close accepted_done_once_no_drop');checks=checks+1
end
if mode=='enqueue' or mode=='both' then
    local h=open();local terminal
    assert(host_race_arm(2))
    local id,err=z.get(h,PREFIX..'/no-queryable',{timeout_ms=1000},function() error('stale reply') end,
        function(_,e) terminal=e end)
    assert(host_race_closed(),'actual disconnect did not close worker before resume')
    assert(id==nil and err==-8,'late command accepted after real disconnect drain')
    host_pump(100);assert(terminal==nil)
    print('RACE_PASS admission_disconnect rejected_no_stale_queue');checks=checks+1
end
local h=open();assert(z.publish(h,PREFIX..'/in','race-control'));host_pump(200)
assert(z.publish(h,PREFIX..'/stop','done'));host_pump(200)
assert(z.close(h));wait(function() return z.state(h)==z.CLOSED end)
print('RACE_HOST_PASS checks='..checks)
