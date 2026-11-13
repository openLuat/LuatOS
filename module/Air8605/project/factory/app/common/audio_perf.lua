-- Fixed-size SIP performance counters. No timers or per-frame samples are stored.
-- Enabled only while the SIP PCM bridge owns audio; report windows are >= 10s.
local M = {}
local active, window_start = false, 0
local names = {"capture", "play", "pcm_up", "pcm_down", "uart_tx", "ui"}
local rows = {}
for _, name in ipairs(names) do
    rows[name] = {count=0, max_ms=0, ticks=0, last=nil, gap_max=0,
        le10=0, le20=0, le50=0, le100=0, gt100=0}
end
local counters = {underflow=0, queue_drop=0}
local function now()
    if mcu and mcu.ticks2 then
        local s, us = mcu.ticks2(0)
        return s * 1000 + (us or 0) / 1000
    end
    return os.time() * 1000
end
local function clear(reset_last)
    for _, name in ipairs(names) do
        local r=rows[name]
        r.count=0;r.max_ms=0;r.ticks=0;r.gap_max=0
        r.le10=0;r.le20=0;r.le50=0;r.le100=0;r.gt100=0
        if reset_last then r.last=nil end
    end
    counters.underflow=0;counters.queue_drop=0
end
-- Minimal downlink diagnostics: fixed counters, no timers, no forced GC.
local down_active=false
local d={}
local function down_clear(reset)
    d.pcm=0;d.silent=0;d.short=0;d.ticks=0;d.gap=0;d.exec=0;d.cap=0
    d.qmin=nil;d.qmax=nil
    if reset then d.last=nil;d.enter=nil end
end
function M.down_queue(bytes)
    if not down_active then return end
    d.qmin=d.qmin and math.min(d.qmin,bytes) or bytes
    d.qmax=d.qmax and math.max(d.qmax,bytes) or bytes
end
function M.down_tick(us,bytes)
    if not down_active then return end
    d.ticks=d.ticks+1
    if d.last then d.gap=math.max(d.gap,us-d.last) end
    d.last=us;d.enter=us
    M.down_queue(bytes)
end
function M.down_submit(silent,written,expected)
    if not down_active then return end
    if written==expected then
        if silent then d.silent=d.silent+1 else d.pcm=d.pcm+1 end
    else d.short=d.short+1 end
end
function M.down_end(us,capped,bytes)
    if not down_active then return end
    if d.enter then d.exec=math.max(d.exec,us-d.enter) end
    if capped then d.cap=d.cap+1 end
    M.down_queue(bytes)
end
local function down_report(session,t,force)
    if not down_active or (not force and t-window_start<10000) then return end
    log.info("sip_down_diag","R7-DOWN-DIAG","session",session,"window_ms",math.floor(t-window_start),
        "pcm_frames",d.pcm,"silence_frames",d.silent,"short_or_fail",d.short,
        "ticks",d.ticks,"gap_max_us",d.gap,"exec_max_us",d.exec,"catchup_capped",d.cap,
        "queue_min_bytes",d.qmin or "NA","queue_max_bytes",d.qmax or "NA")
    down_clear(false)
end
function M.start(enabled)
    clear(true);window_start=now();active=enabled~=false
    down_clear(true);down_active=_G.SIP_DOWN_DIAG==true
    if down_active then log.info("sip_down_diag","R7-DOWN-DIAG","ENABLED","UART full submissions, not chip ACK; queue at tick/write boundaries") end
    return window_start
end
-- Read cumulative downlink counts without resetting the whole-call report.
function M.down_counts()
    if not down_active then return nil,nil end
    return d.pcm,d.silent
end
function M.stop() active=false;down_active=false end
function M.begin(name)
    if active and rows[name] then return now() end
end
function M.finish(name, started)
    if not active or started==nil then return end
    local r=rows[name]
    if not r then return end
    r.count=r.count+1
    r.max_ms=math.max(r.max_ms,now()-started)
end
function M.tick(name)
    if not active or (name~="capture" and name~="play") then return end
    local r,t=rows[name],now()
    r.ticks=r.ticks+1
    if r.last then
        local gap=math.max(0,t-r.last)
        r.gap_max=math.max(r.gap_max,gap)
        if gap<=10 then r.le10=r.le10+1
        elseif gap<=20 then r.le20=r.le20+1
        elseif gap<=50 then r.le50=r.le50+1
        elseif gap<=100 then r.le100=r.le100+1
        else r.gt100=r.gt100+1 end
    end
    r.last=t
    return t
end
function M.count(name, n)
    if active and counters[name]~=nil then counters[name]=counters[name]+(n or 1) end
end
local function log_tick(name)
    local r=rows[name]
    -- Buckets are disjoint: (0,10], (10,20], (20,50], (50,100], >100 ms.
    log.info("sip_perf",name,"ticks",r.ticks,"exec_max_ms",r.max_ms,"gap_max_ms",r.gap_max,
        "le10",r.le10,"le20",r.le20,"le50",r.le50,"le100",r.le100,"gt100",r.gt100)
end
function M.report(session,force)
    if not active and not down_active then return false end
    local t=now()
    down_report(session,t,force)
    if not active then
        if down_active and t-window_start>=10000 then window_start=t end
        return false
    end
    if not force and t-window_start<10000 then return false end
    log.info("sip_perf","window","session",session,"window_ms",math.floor(t-window_start),
        "queue_drop",counters.queue_drop,"underflow_frames",counters.underflow)
    log_tick("capture");log_tick("play")
    local u,d,w,ui=rows.pcm_up,rows.pcm_down,rows.uart_tx,rows.ui
    log.info("sip_perf","PCM","up_calls",u.count,"up_max_ms",u.max_ms,
        "down_calls",d.count,"down_max_ms",d.max_ms)
    log.info("sip_perf","UART_UI","uart_calls",w.count,"uart_max_ms",w.max_ms,
        "ui_calls",ui.count,"ui_max_ms",ui.max_ms)
    clear(false);window_start=t
    return true
end
return M
