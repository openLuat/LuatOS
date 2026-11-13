-- Low-frequency allocation/lifecycle diagnostics; no timer, retained samples or GC.
local M = {}
local serial = 0
local function emit(stage, phase, id, detail)
    local kb = collectgarbage("count")
    local lt,lu,lp,st,su,sp = "NA","NA","NA","NA","NA","NA"
    if rtos and type(rtos.meminfo)=="function" then
        local ok,a,b,c=pcall(rtos.meminfo,"lua")
        if ok and type(a)=="number" and a>0 then lt,lu,lp=a,b,c end
        ok,a,b,c=pcall(rtos.meminfo,"sys")
        if ok and type(a)=="number" and a>0 then st,su,sp=a,b,c end
    end
    log.info("sip_mem_diag","S5-MEM-DIAG",id,stage,phase,"detail",detail or "NA",
        "lua_kb",math.floor(kb),"lua_total",lt,"lua_used",lu,"lua_peak",lp,
        "sys_total",st,"sys_used",su,"sys_peak",sp,"largest_block","NA")
end
function M.mark(stage,phase,detail)
    -- Diagnostics must not replace the original operation's outcome.
    if _G.SIP_MEMORY_VERBOSE then pcall(emit,stage,phase,0,detail) end
end
function M.handler(err)
    pcall(function()
        log.error("sip_mem_diag","ERROR",tostring(err))
        if debug and type(debug.traceback)=="function" then
            log.error("sip_mem_diag",debug.traceback("allocation/lifecycle error",2))
        else log.error("sip_mem_diag","traceback NA") end
    end)
    return err
end
local function finish(stage,id,ok,...)
    if not ok or _G.SIP_MEMORY_VERBOSE then pcall(emit,stage,ok and "END" or "ERROR",id) end
    return ok,...
end
-- Same status/result contract as pcall; handler executes before stack unwinding.
function M.call(stage,fn,...)
    serial=serial+1
    local id=serial
    if _G.SIP_MEMORY_VERBOSE then pcall(emit,stage,"BEGIN",id) end
    return finish(stage,id,xpcall(fn,M.handler,...))
end
local function unwrap(ok,...)
    if not ok then error((...),0) end
    return ...
end
function M.wrap(stage,fn)
    return function(...) return unwrap(M.call(stage,fn,...)) end
end
return M
