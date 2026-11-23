-- CALL-QUERY-DIAG1: fixed counters, no polling, no per-query logging.
-- Scope: factory status probes and AirCloud safe_call probes, not all native RPC.
local M = {}
local names = {"status.csq", "status.wifi", "mobile.csq", "mobile.status",
    "mobile.iccid", "mobile.imei", "wlan.getInfo", "wlan.getMac", "socket.adapter"}
local rows = {}
for _, name in ipairs(names) do rows[name]={count=0,total=0,max=0,unknown=0} end
local active, epoch = false, 0
local function now()
    if mcu and mcu.ticks2 then
        local s, us = mcu.ticks2(0)
        if type(s)=="number" and type(us)=="number" then return s*1000+us/1000 end
    end
end
function M.begin(name)
    if not active or not rows[name] then return end
    return epoch, now()
end
function M.finish(name, token, started)
    if not token or not active or token~=epoch then return end
    local r=rows[name]
    r.count=r.count+1
    local ended=now()
    if not started or not ended or ended<started then r.unknown=r.unknown+1; return end
    local elapsed=ended-started
    r.total=r.total+elapsed; r.max=math.max(r.max,elapsed)
end
local function state(s)
    local v=s and s.state
    local busy=v=="dialing" or v=="incoming" or v=="answering" or v=="talking" or v=="ending"
    if busy and not active then
        epoch=epoch+1; active=true
        for _,r in pairs(rows) do r.count=0;r.total=0;r.max=0;r.unknown=0 end
    elseif not busy and active then
        active=false
        local parts={}
        for _,name in ipairs(names) do
            local r=rows[name]
            parts[#parts+1]=string.format("%s=%d/%.3f/%.3f/%d",name,r.count,r.total,r.max,r.unknown)
        end
        log.info("sip_query_diag", "CALL-QUERY-DIAG1 FINAL", epoch,
            "scope=dialing-to-end count/known_total_ms/known_max_ms/time_unavailable", table.concat(parts," "))
    end
end
-- The active SIP phone publishes SIP_STATE. Do not mix legacy engine state streams.
sys.subscribe("SIP_STATE",state)
return M
