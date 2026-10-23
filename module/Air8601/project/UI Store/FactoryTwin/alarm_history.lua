-- Independent in-memory alarm records; survives the model's short event window.
-- consume(event[, model_snapshot]) prefers event-time alarm/devices payloads.
-- Snapshot/get return detached records. Timeline is oldest-first (max 12),
-- while snapshot records are newest-first (default 32). Nothing writes files.
local History={}
History.__index=History
local kinds={FAULT_REPORTED=true,REPAIR_STARTED=true,CHECK_PASSED=true,
    CHECK_BLOCKED=true,CHECK_TIMEOUT=true,CHECK_INVALIDATED=true,
    LINE_READY=true,LINE_RESUMED=true,POWER_OFF=true,POWER_ON=true}
local process={FAULT_REPORTED="故障锁定，等待维修",REPAIR_STARTED="已维修，开始逐台复检",
    CHECK_PASSED="设备复检通过",CHECK_BLOCKED="设备未就绪，复检受阻",
    CHECK_TIMEOUT="复检超时，保持停线",CHECK_INVALIDATED="状态变化，需重新复检",
    LINE_READY="全部通过，等待人工恢复",LINE_RESUMED="人工恢复，故障流程结束",
    POWER_OFF="总电源关闭，复检已取消",POWER_ON="总电源接通，需重新复检"}
local function finite(value)
    return type(value)=="number" and value==value and value~=math.huge and value~=-math.huge
end
local function copy(value)
    if type(value)~="table" then return value end
    local result={}
    for key,item in pairs(value) do result[key]=copy(item) end
    return result
end
local function id_valid(id)
    return (finite(id) and id>0 and id%1==0) or (type(id)=="string" and id~="")
end
local function limit(value,fallback)
    return finite(value) and value>=1 and math.floor(value) or fallback
end
local function matching_line(lines,line_id)
    if type(lines)~="table" then return nil end
    for _,line in ipairs(lines) do if line.id==line_id then return line end end
end
local function event_alarm(event,snapshot,id)
    if type(event.alarm)=="table" and (not id or event.alarm.id==id) then return event.alarm end
    if type(snapshot)=="table" then
        local line=matching_line(snapshot.lines,event.line_id)
        if line and line.alarm and line.alarm.id==id then return line.alarm end
        if snapshot.active_alarm and snapshot.active_alarm.id==id then return snapshot.active_alarm end
    end
end
local function event_devices(event,snapshot,line_id)
    if type(event.devices)=="table" and (not event.line_id or event.line_id==line_id) then return event.devices end
    local line=matching_line(event.lines,line_id)
    if line and type(line.devices)=="table" then return line.devices end
    line=type(snapshot)=="table" and matching_line(snapshot.lines,line_id) or nil
    if line and type(line.devices)=="table" then return line.devices end
end

function History.new(capacity)
    local config=type(capacity)=="table" and capacity or {capacity=capacity}
    return setmetatable({capacity=limit(config.capacity,32),
        timeline_limit=limit(config.timeline_limit,12),records={},by_id={},state={},_revision=0},History)
end

function History:_append(record,event,devices)
    self._revision=self._revision+1
    local entry={event_id=event.id,timestamp_ms=event.timestamp_ms,kind=event.kind,
        severity=event.severity,message=event.message or process[event.kind],
        device_id=event.device_id,phase=record.phase,power=event.power,
        devices=devices and copy(devices) or nil}
    record.timeline[#record.timeline+1]=entry
    if #record.timeline>self.timeline_limit then table.remove(record.timeline,1) end
    record.updated_ms=event.timestamp_ms
    record.latest_kind=event.kind
    record.latest_process=event.message or process[event.kind]
    if devices then record.devices=copy(devices) end
    local state=self.state[record.id]
    if event.id~=nil then
        state.seen[event.id]=true
        state.seen_order[#state.seen_order+1]=event.id
        if #state.seen_order>64 then state.seen[table.remove(state.seen_order,1)]=nil end
    end
end

function History:_update(record,event,snapshot)
    local state=self.state[record.id]
    if event.id~=nil and state.seen[event.id] then return false,"duplicate_event" end
    -- UI callbacks may observe a fault before main drains an earlier power
    -- event from the same model tick. That event predates this alarm.
    if type(event.id)=="number" and type(state.created_event_id)=="number" and
        event.id<state.created_event_id then return false,"stale_event" end
    if event.timestamp_ms<record.updated_ms then return false,"stale_event" end
    if record.resolved then return false,"alarm_resolved" end
    local kind=event.kind
    if event.line_id and event.line_id~=record.line_id then return false,"line_mismatch" end
    local devices=event_devices(event,snapshot,record.line_id)
    if kind=="REPAIR_STARTED" then
        record.phase="CHECKING"
        record.repair_count=record.repair_count+1
        record.repair_started_ms=record.repair_started_ms or event.timestamp_ms
        record.last_repair_started_ms=event.timestamp_ms
        record.check_passed_count=0
        record.blocked_device_id,record.blocked_status=nil,nil
        state.verified={}
    elseif kind=="CHECK_PASSED" then
        record.phase="CHECKING"
        if event.device_id and not state.verified[event.device_id] then
            state.verified[event.device_id]=true
            record.check_passed_count=record.check_passed_count+1
        end
        record.check_pass_total=record.check_pass_total+1
        record.checked_device_id=event.device_id
        if record.blocked_device_id==event.device_id then record.blocked_device_id,record.blocked_status=nil,nil end
    elseif kind=="CHECK_BLOCKED" then
        record.phase="CHECKING"
        record.check_blocked_count=record.check_blocked_count+1
        record.blocked_device_id=event.device_id
        record.blocked_status=nil
        for _,device in ipairs(devices or {}) do
            if device.id==event.device_id then record.blocked_status=device.health or device.status end
        end
    elseif kind=="CHECK_TIMEOUT" then
        record.phase="TRIPPED"
        record.timeout_count=record.timeout_count+1
    elseif kind=="CHECK_INVALIDATED" then
        record.phase="TRIPPED"
        record.invalidation_count=record.invalidation_count+1
        record.check_passed_count=0
        state.verified={}
    elseif kind=="LINE_READY" then
        record.phase="READY"
        record.ready_ms=event.timestamp_ms
    elseif kind=="LINE_RESUMED" then
        record.phase="RECOVERED"
        record.resolved=true
        record.recovered_ms=event.timestamp_ms
    elseif kind=="POWER_OFF" or kind=="POWER_ON" then
        record.phase=kind=="POWER_OFF" and "OFF" or "TRIPPED"
        record.check_passed_count=0
        state.verified={}
        if kind=="POWER_OFF" then record.power_interruption_count=record.power_interruption_count+1 end
    else return false,"ignored_event" end
    self:_append(record,event,devices)
    return true
end

function History:consume(event,snapshot)
    if type(event)~="table" or type(event.kind)~="string" then return false,"invalid_event" end
    if not kinds[event.kind] then return false,"ignored_event" end
    if not finite(event.timestamp_ms) or event.timestamp_ms<0 then return false,"invalid_timestamp" end
    if event.id~=nil and not id_valid(event.id) then return false,"invalid_event_id" end
    if event.kind=="POWER_OFF" or event.kind=="POWER_ON" then
        local changed=false
        for _,record in ipairs(self.records) do
            if not record.resolved and (not event.line_id or event.line_id==record.line_id) then
                local ok=self:_update(record,event,snapshot)
                changed=ok or changed
            end
        end
        return changed,changed and nil or "no_active_alarm"
    end
    local alarm=type(event.alarm)=="table" and event.alarm or nil
    local id=event.alarm_id or (alarm and alarm.id)
    if not id_valid(id) then return false,"invalid_alarm_id" end
    alarm=event_alarm(event,snapshot,id) or {}
    local record=self.by_id[id]
    if event.kind~="FAULT_REPORTED" then
        if not record then return false,"unknown_alarm" end
        return self:_update(record,event,snapshot)
    end
    if record then return false,"alarm_exists" end
    local original_status=alarm.status or event.alarm_status or event.status or "UNKNOWN"
    if original_status~="RED" and original_status~="GRAY" then original_status="UNKNOWN" end
    local code=alarm.code or event.fault_code or
        (original_status=="RED" and "E_DEVICE_FAULT" or
        (original_status=="GRAY" and "E_DEVICE_ABNORMAL" or "E_UNKNOWN"))
    local line_id=event.line_id or alarm.line_id or "?"
    local devices=event_devices(event,snapshot,line_id) or {}
    record={id=id,started_ms=alarm.created_ms or event.timestamp_ms,
        line_id=line_id,device_id=event.device_id or alarm.device_id or "?",
        status=original_status,code=code,
        description=alarm.description or event.description or event.message or alarm.message or "设备异常",
        phase=event.line_phase=="OFF" and "OFF" or "TRIPPED",
        updated_ms=event.timestamp_ms,latest_process=event.message or process.FAULT_REPORTED,
        repair_count=0,check_passed_count=0,check_pass_total=0,check_blocked_count=0,
        timeout_count=0,invalidation_count=0,power_interruption_count=0,
        resolved=false,initial_devices=copy(devices),devices=copy(devices),timeline={}}
    table.insert(self.records,1,record)
    self.by_id[id]=record
    self.state[id]={verified={},seen={},seen_order={},created_event_id=event.id}
    self:_append(record,event,devices)
    if #self.records>self.capacity then
        local removed=table.remove(self.records)
        self.by_id[removed.id],self.state[removed.id]=nil,nil
    end
    return true
end

function History:snapshot()
    return copy(self.records)
end

-- Cache invalidation token: advances once per accepted record/event append.
-- A global power event updating two unresolved records advances it twice.
function History:revision()
    return self._revision
end

function History:get(id)
    return copy(self.by_id[id])
end

return History
