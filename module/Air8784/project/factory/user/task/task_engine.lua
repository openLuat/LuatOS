--[[
@module  task_engine
@summary 设备任务校验、持久保存与轮拨状态机
@version 2.0
@date    2026.09.29
@author  王世豪
@usage
协同配置版本：运行模式独立于主动任务保存，删除任务不改变模式。
通过 new(opts) 注入存储、通话适配器和回执接口。
处理 get/put/delete/stop/set_mode 命令；保存不拨号，primary() 由按键触发。
tick(ms) 控制30秒等待、挂断等待与顺序拨号；完整接通后停止轮拨。
]]

local M = {}
function M.new(opts)
    local a, store = opts.adapter, opts.store
    local record = store.read() or {revision="0", boot_count=0}
    assert(type(record)=="table" and type(record.revision)=="string", "Invalid task storage")
    if record.runtime_mode ~= "single" and record.runtime_mode ~= "phone" then
        record.runtime_mode = record.task and record.task.mode ~= "phone" and "single" or "phone"
    end
    record.boot_count = (record.boot_count or 0) + 1
    assert(store.write(record), "Task storage unavailable")
    local boot, seq = tostring(record.boot_count), 0
    local running, index, phase, elapsed, closing_elapsed = false, 0, "ready", 0, 0
    local connected, advance = false, false
    local announce_wait=0
    local last_req, last_result = "", "ok"
    local function state()
        if running then return phase end
        if a.connected() then return "connected" end
        if a.incoming and a.incoming() then return "incoming" end
        if not a.idle() then return "busy" end
        return a.ready() and "ready" or "offline"
    end
    local function snapshot(req,result)
        seq=seq+1
        return {schema="air8784.sip.v1",kind="snapshot",imei=opts.imei,boot=boot,seq=seq,
            revision=record.revision,task=record.task,modes=a.modes,state=state(),
            index=index,req=req or last_req,result=result or last_result,
            sip_account_targets=true,round_sip_account_targets=true,mode_switch=a.mode_switch or false,active_mode=a.active_mode,
            reboot_pending=a.reboot_pending and a.reboot_pending() or false,
            runtime_mode=record.runtime_mode,coordination_v1=true,
            health=a.health and a.health() or nil}
    end
    local function emit(req,result)
        if req then last_req,last_result=req,result or "ok" end
        local s=snapshot(req,result);opts.report(s);return s
    end
    local function valid(t)
        if type(t)~="table" or t.imei~=opts.imei or t.wait~=30 or type(t.name64)~="string" or #t.name64>256 then return false end
        if not t.name64:match("^[%w+/=]*$") or type(t.targets)~="table" then return false end
        if t.mode~="pair" and t.mode~="round" and t.mode~="phone" then return false end
        local n=#t.targets;if n<1 or n>(t.mode=="pair" and 1 or 3) then return false end
        local seen={}
        for _,v in ipairs(t.targets) do
            if type(v)~="string" or not v:match("^%d+$") or seen[v] then return false end
            if t.mode=="phone" then if #v~=11 or v:sub(1,1)~="1" then return false end
            elseif t.mode~="phone" and v==opts.imei.."1" then
                -- Explicit local peer SIP account; never call this device account itself.
            elseif #v~=15 or v==opts.imei then return false end
            seen[v]=true
        end
        return true
    end
    local function supported(mode) for _,v in ipairs(a.modes) do if v==mode then return true end end return false end
    local function stop(next_target)
        advance=next_target;phase="stopping";closing_elapsed=0;a.hangup();emit()
    end
    local function dial()
        if not a.ready() then running=false;phase="ended";emit();return end
        phase="dialing";elapsed=0;connected=false
        if not a.dial(record.task.targets[index],record.task.mode) then stop(true) else emit() end
    end
    local api={}
    function api.command(c)
        if type(c)~="table" or c.schema~="air8784.sip.v1" or c.imei~=opts.imei or type(c.req)~="string" or #c.req==0 or #c.req>64 then return end
        if c.op=="get" then return emit(c.req,"ok") end
        if c.op=="stop" then
            if a.cancel_announcement then a.cancel_announcement() end
            -- Stop is idempotent; never advance to a subsequent target.
            advance=false
            if running or not a.idle() then running=true;stop(false) end
            return emit(c.req,"ok")
        end
        if c.op~="put" and c.op~="delete" and c.op~="set_mode" then return emit(c.req,"invalid") end
        if record.last_req==c.req then return emit(c.req,"ok") end
        if running or not a.idle() then return emit(c.req,"busy") end
        if c.expected~=record.revision or type(c.revision)~="string" or #c.revision~=36 or c.revision==record.revision then return emit(c.req,"conflict") end
        if c.op=="put" then
            if not valid(c.task) then return emit(c.req,"invalid") end
            if not supported(c.task.mode) then return emit(c.req,"unsupported") end
            if record.task and record.task.mode~=c.task.mode and not a.mode_switch then return emit(c.req,"conflict") end
        end
        if c.op=="set_mode" then
            if c.runtime_mode~="single" and c.runtime_mode~="phone" then return emit(c.req,"invalid") end
            if c.runtime_mode~="phone" and not a.mode_switch then return emit(c.req,"unsupported") end
            local task_mode = record.task and (record.task.mode=="phone" and "phone" or "single")
            if task_mode and task_mode~=c.runtime_mode then return emit(c.req,"task_conflict") end
        end
        local next_record={revision=c.revision,boot_count=record.boot_count,last_req=c.req,runtime_mode=record.runtime_mode}
        if c.op=="set_mode" then
            next_record.runtime_mode=c.runtime_mode
            next_record.task=record.task
        elseif c.op=="put" then
            next_record.runtime_mode=c.task.mode=="phone" and "phone" or "single"
        end
        if c.op=="put" then next_record.task=c.task end
        next_record.announcement_pending=c.op=="put" or (c.op=="set_mode" and c.runtime_mode~=record.runtime_mode)
        if not store.write(next_record) then return emit(c.req,"storage") end
        record=next_record;index=0;announce_wait=0
        if a.cancel_announcement then a.cancel_announcement() end
        if a.mode_changed then a.mode_changed(record.runtime_mode) end
        return emit(c.req,"ok")
    end
    function api.primary()
        if a.cancel_announcement then a.cancel_announcement() end
        if a.incoming and a.incoming() then if a.accept then a.accept() end return end
        if running or not record.task or not valid(record.task) or not supported(record.task.mode) or not a.idle() or not a.ready() then return false end
        running=true;index=1;advance=false;dial();return true
    end
    function api.stop() if running or not a.idle() then running=true;stop(false) end end
    function api.tick(ms)
        if not running then
            if record.announcement_pending and a.announce and a.ready() and not (a.reboot_pending and a.reboot_pending())
                and (not a.announcement_available or a.announcement_available()) then
                local h=a.health and a.health()
                if h and h.sip_registered and h.audio_ready and h.call_idle and record.runtime_mode==a.active_mode then
                    announce_wait=announce_wait+ms
                    if announce_wait>=1000 then
                        -- 播前持久化消耗标记：断电/来电打断不反复播报旧任务。
                        local next_record={}
                        for k,v in pairs(record) do next_record[k]=v end
                        next_record.announcement_pending=false
                        if store.write(next_record) then
                            record=next_record
                            local ok,err=pcall(a.announce,record)
                            if not ok then log.warn("task_voice","announce failed",tostring(err)) end
                        end
                        announce_wait=0
                    end
                else announce_wait=0 end
            else announce_wait=0 end
            return
        end
        if phase=="stopping" then
            closing_elapsed=closing_elapsed+ms
            if a.idle() then
                if advance and record.task and index<#record.task.targets then index=index+1;advance=false;phase="waiting-ready";elapsed=0
                else running=false;phase="ended";emit() end
            elseif closing_elapsed>=10000 then
                -- Do not overlap calls if the previous call never became idle.
                advance=false;a.hangup();closing_elapsed=0
            end
            return
        end
        if phase=="waiting-ready" then
            elapsed=elapsed+ms
            if a.ready() then dial()
            elseif elapsed>=15000 then running=false;phase="ended";emit() end
            return
        end
        if a.connected() then
            if not connected then connected=true;phase="connected";emit() end
            return
        end
        if connected then stop(false);return end
        elapsed=elapsed+ms
        if a.failed and a.failed() then stop(true)
        elseif elapsed>=record.task.wait*1000 then stop(true) end
    end
    function api.snapshot() return emit() end
    return api
end
return M
