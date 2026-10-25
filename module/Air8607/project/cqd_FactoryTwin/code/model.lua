-- FactoryTwin: deterministic, dependency-free LuatOS production-line model.
-- Time is supplied by step(milliseconds); this module owns no timer or GPIO.
-- Public status values: GREEN / YELLOW / RED / GRAY.
-- Mutation methods return success:boolean, reason:string (reason on failure).
-- repair([line]) and resume([line]) default to B; line is 1/2 or "A"/"B".
-- set_health(line, device_index, status) is the external input/adapter seam.
-- A manual input is retained until another set_health call changes it.
local Model = {}
Model.__index = Model

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function positive(value, fallback)
    if type(value) ~= "number" or value <= 0 or value ~= value then
        return fallback
    end
    return value
end

local function status(value)
    if type(value) ~= "string" then return nil end
    value = string.upper(value)
    if value == "GREY" then value = "GRAY" end
    if value == "GREEN" or value == "YELLOW" or value == "RED" or value == "GRAY" then
        return value
    end
    return nil
end

local function bounded_append(list, item, limit)
    list[#list + 1] = item
    if #list > limit then table.remove(list, 1) end
end

function Model:_event(kind, severity, message, line, device, alarm)
    self.event_seq = self.event_seq + 1
    local event = {
        id = self.event_seq, timestamp_ms = self.elapsed_ms,
        kind = kind, severity = severity, message = message,
        line_id = line and line.id or nil,
        device_id = device and device.id or nil,
        alarm_id = alarm and alarm.id or nil,
        alarm = copy(alarm), power = self.power,
        line_phase = line and line.phase or nil
    }
    local function device_snapshot(source)
        local items={}
        for _,d in ipairs(source.devices) do
            local shown=d.health
            if not self.power then shown="GRAY"
            elseif source.phase~="RUNNING" and shown~="RED" and shown~="GRAY" then
                shown=((source.phase=="CHECKING" or source.phase=="READY") and d.verified) and "GREEN" or "GRAY"
            end
            items[#items+1]={id=d.id,name=d.name,status=shown,health=d.health,verified=d.verified}
        end
        return items
    end
    if line then event.devices=device_snapshot(line) end
    if kind=="POWER_OFF" or kind=="POWER_ON" then
        event.lines={}
        for _,source in ipairs(self.lines) do
            event.lines[#event.lines+1]={id=source.id,phase=source.phase,
                alarm=copy(source.alarm),devices=device_snapshot(source)}
        end
    end
    bounded_append(self.history, event, self.config.event_limit)
    bounded_append(self.pending_events, event, self.config.event_limit)
    self.last_event = event
end

function Model:_line(which)
    if which == nil then return self.lines[2] end
    if which == 1 or which == "A" or which == "a" or which == "LINE_A" then
        return self.lines[1]
    end
    if which == 2 or which == "B" or which == "b" or which == "LINE_B" then
        return self.lines[2]
    end
    return nil
end

local function clear_verification(line)
    line.check_index = nil
    line.check_samples = 0
    line.next_check_ms = nil
    line.check_deadline_ms = nil
    line.blocked_status = nil
    line.blocked_device_id = nil
    for _, device in ipairs(line.devices) do device.verified = false end
end

function Model:_trip(line, index, fault_status, automatic)
    if line.alarm then return false, "alarm_already_latched" end
    self.alarm_seq = self.alarm_seq + 1
    local device = line.devices[index]
    device.health = fault_status
    if automatic then device.simulated_fault = true end
    clear_verification(line)
    line.phase = self.power and "TRIPPED" or "OFF"
    line.alarm = {
        id = self.alarm_seq, line_id = line.id, device_id = device.id,
        device_index = index, status = fault_status,
        created_ms = self.elapsed_ms, repair_started = false, repaired = false,
        code = fault_status=="RED" and "E_DEVICE_FAULT" or "E_DEVICE_ABNORMAL",
        description = automatic and "模拟状态注入触发，已停止本线全部设备。" or
            "设备状态反馈异常，已停止本线全部设备，等待维修确认。",
        simulated = automatic == true,
        message = line.id .. "线 " .. device.id ..
            (fault_status == "RED" and " 故障，已紧急停线" or " 异常，已紧急停线")
    }
    self:_event("FAULT_REPORTED", "ERROR", line.alarm.message, line, device, line.alarm)
    return true
end

function Model.new(config)
    config = config or {}
    local self = setmetatable({}, Model)
    self.config = {
        fault_interval_ms = positive(config.fault_interval_ms, 60000),
        check_period_ms = positive(config.check_period_ms, 500),
        stable_samples = math.max(1, math.floor(positive(config.stable_samples, 2))),
        verification_timeout_ms = positive(config.verification_timeout_ms, 12000),
        production_cycle_ms = positive(config.production_cycle_ms, 1000),
        event_limit = math.max(8, math.floor(positive(config.event_limit or config.log_limit, 40))),
        enable_auto_fault = config.enable_auto_fault ~= false and config.simulation ~= false,
        enable_simulated_busy = config.enable_simulated_busy ~= false and config.simulation ~= false
    }
    self.power = config.start_power ~= false
    self.elapsed_ms = 0
    self.event_seq, self.alarm_seq, self.auto_fault_seq = 0, 0, 0
    self.history, self.pending_events, self.lines = {}, {}, {}
    local default_names = { "上料设备", "加工设备", "检测设备", "包装设备" }
    for n = 1, 2 do
        local id = n == 1 and "A" or "B"
        local source = config.lines and config.lines[n] or {}
        local line = {
            id = id, name = source.name or (id .. " 产线"),
            phase = self.power and "RUNNING" or "OFF",
            devices = {}, produced = 0, production_accum_ms = 0,
            running_since_fault_ms = 0, check_samples = 0
        }
        for i = 1, 4 do
            local names = config.device_names and (config.device_names[n] or config.device_names[id])
            local source_device = source.devices and source.devices[i] or {}
            line.devices[i] = {
                id = id .. i, name = source_device.name or (names and names[i]) or default_names[i],
                health = "GREEN", verified = false, manual_health = false
            }
        end
        self.lines[n] = line
    end
    self:_event("STARTUP", "INFO", "双产线演示已启动")
    return self
end

function Model:_advance_time(delta)
    for _, line in ipairs(self.lines) do
        if self.power and line.phase == "RUNNING" then
            line.running_since_fault_ms = line.running_since_fault_ms + delta
            line.production_accum_ms = line.production_accum_ms + delta
            local completed = math.floor(line.production_accum_ms / self.config.production_cycle_ms)
            line.produced = line.produced + completed
            line.production_accum_ms = line.production_accum_ms - completed * self.config.production_cycle_ms
        end
    end
    self.elapsed_ms = self.elapsed_ms + delta
end

function Model:_refresh_busy()
    if not self.config.enable_simulated_busy then return end
    for n, line in ipairs(self.lines) do
        if self.power and line.phase == "RUNNING" then
            for i, device in ipairs(line.devices) do
                if not device.manual_health and not device.simulated_fault then
                    local stage = math.floor(self.elapsed_ms / 2400) + i + n * 2
                    device.health = stage % 7 == 0 and "YELLOW" or "GREEN"
                end
            end
        end
    end
end

function Model:_sample(line)
    local index = line.check_index
    local device = line.devices[index]
    if device.health == "GREEN" then
        line.check_samples = line.check_samples + 1
        line.blocked_status, line.blocked_device_id = nil, nil
        if line.check_samples >= self.config.stable_samples then
            device.verified = true
            self:_event("CHECK_PASSED", "INFO", device.id .. " 连续状态检查通过", line, device, line.alarm)
            if index == #line.devices then
                line.phase = "READY"
                line.check_index, line.check_deadline_ms, line.next_check_ms = nil, nil, nil
                line.check_samples = 0
                line.alarm.repaired = true
                self:_event("LINE_READY", "INFO", line.id .. "线全设备检查通过，等待人工恢复", line, nil, line.alarm)
                return
            end
            line.check_index, line.check_samples = index + 1, 0
        end
    else
        line.check_samples = 0
        if line.blocked_status ~= device.health or line.blocked_device_id ~= device.id then
            line.blocked_status, line.blocked_device_id = device.health, device.id
            self:_event("CHECK_BLOCKED", "WARN", device.id .. " 未就绪，等待健康状态", line, device, line.alarm)
        end
    end
    line.next_check_ms = self.elapsed_ms + self.config.check_period_ms
end

-- Large dt values preserve exact fault/check boundaries and event timestamps.
function Model:step(dt_ms)
    if type(dt_ms) ~= "number" or dt_ms ~= dt_ms or dt_ms < 0 or dt_ms == math.huge then
        return false, "invalid_dt"
    end
    local target = self.elapsed_ms + dt_ms
    while self.elapsed_ms < target do
        local next_time = target
        local b = self.lines[2]
        if self.power and b.phase == "RUNNING" and self.config.enable_auto_fault then
            next_time = math.min(next_time, self.elapsed_ms +
                math.max(0, self.config.fault_interval_ms - b.running_since_fault_ms))
        end
        if self.power then
            for _, line in ipairs(self.lines) do
                if line.phase == "CHECKING" then
                    next_time = math.min(next_time, line.next_check_ms, line.check_deadline_ms)
                end
            end
        end
        self:_advance_time(next_time - self.elapsed_ms)
        self:_refresh_busy()
        if self.power and b.phase == "RUNNING" and self.config.enable_auto_fault and
            b.running_since_fault_ms >= self.config.fault_interval_ms then
            self.auto_fault_seq = self.auto_fault_seq + 1
            local index = (self.auto_fault_seq - 1) % 4 + 1
            local fault_status = self.auto_fault_seq % 2 == 1 and "RED" or "GRAY"
            self:_trip(b, index, fault_status, true)
        end
        if self.power then
            for _, line in ipairs(self.lines) do
                if line.phase == "CHECKING" then
                    -- A healthy final sample exactly on the deadline is allowed.
                    if line.next_check_ms <= self.elapsed_ms then self:_sample(line) end
                    if line.phase == "CHECKING" and line.check_deadline_ms <= self.elapsed_ms then
                        line.phase = "TRIPPED"
                        line.next_check_ms, line.check_deadline_ms = nil, nil
                        line.alarm.repaired = false
                        self:_event("CHECK_TIMEOUT", "ERROR", line.id .. "线检查超时，保持停线", line, nil, line.alarm)
                    end
                end
            end
        end
    end
    return true
end

function Model:inject_fault(index, fault_status)
    fault_status = status(fault_status or "RED")
    if fault_status ~= "RED" and fault_status ~= "GRAY" then return false, "invalid_fault_status" end
    if type(index) ~= "number" or index % 1 ~= 0 or not self.lines[2].devices[index] then
        return false, "invalid_device"
    end
    if not self.power then return false, "power_off" end
    if self.lines[2].phase ~= "RUNNING" then return false, "line_not_running" end
    return self:_trip(self.lines[2], index, fault_status, true)
end

function Model:repair(which)
    local line = self:_line(which)
    if not line then return false, "invalid_line" end
    if not self.power then return false, "power_off" end
    if line.phase ~= "TRIPPED" or not line.alarm then return false, "line_not_tripped" end
    clear_verification(line)
    for _, device in ipairs(line.devices) do
        -- The demo maintenance button clears simulated faults only. Physical
        -- inputs supplied through set_health must independently become healthy.
        if not device.manual_health then device.health = "GREEN" end
        device.simulated_fault = false
    end
    line.phase = "CHECKING"
    line.check_index = 1
    line.next_check_ms = self.elapsed_ms + self.config.check_period_ms
    line.check_deadline_ms = self.elapsed_ms + self.config.verification_timeout_ms
    line.alarm.repair_started, line.alarm.repaired = true, false
    self:_event("REPAIR_STARTED", "INFO", line.id .. "线已报维修完成，开始逐台复检", line, nil, line.alarm)
    return true
end

function Model:resume(which)
    local line = self:_line(which)
    if not line then return false, "invalid_line" end
    if not self.power then return false, "power_off" end
    if line.phase ~= "READY" or not line.alarm then return false, "line_not_ready" end
    for _, device in ipairs(line.devices) do
        if not device.verified or device.health ~= "GREEN" then return false, "device_not_ready" end
    end
    local alarm = line.alarm
    self.last_alarm = copy(alarm)
    line.alarm = nil
    line.phase = "RUNNING"
    line.running_since_fault_ms = 0
    clear_verification(line)
    self:_event("LINE_RESUMED", "INFO", line.id .. "线人工确认恢复运行", line, nil, alarm)
    return true
end

function Model:set_power(enabled)
    if type(enabled) ~= "boolean" then return false, "invalid_power" end
    if enabled == self.power then return false, "power_unchanged" end
    self.power = enabled
    for _, line in ipairs(self.lines) do
        clear_verification(line)
        if enabled then
            line.phase = line.alarm and "TRIPPED" or "RUNNING"
        else
            line.phase = "OFF"
        end
        if line.alarm then line.alarm.repaired = false end
    end
    self:_event(enabled and "POWER_ON" or "POWER_OFF", "WARN",
        enabled and "总电源已接通；锁定产线需重新复检" or "总电源已断开；复检已取消")
    return true
end

function Model:set_health(which, index, health)
    local line = self:_line(which)
    if not line then return false, "invalid_line" end
    if type(index) ~= "number" or index % 1 ~= 0 or not line.devices[index] then
        return false, "invalid_device"
    end
    health = status(health)
    if not health then return false, "invalid_status" end
    local device = line.devices[index]
    device.health, device.manual_health, device.simulated_fault = health, true, false
    if not line.alarm and (health == "RED" or health == "GRAY") then
        return self:_trip(line, index, health, false)
    end
    if line.alarm and health ~= "GREEN" and
        (line.phase == "READY" or (line.phase == "CHECKING" and device.verified)) then
        clear_verification(line)
        line.phase = self.power and "TRIPPED" or "OFF"
        line.alarm.repaired = false
        self:_event("CHECK_INVALIDATED", "ERROR", device.id .. " 状态变化，需重新维修复检", line, device, line.alarm)
    end
    return true
end

function Model:drain_events()
    local events = copy(self.pending_events)
    self.pending_events = {}
    return events
end

local function event_header(event)
    if not event then return nil end
    return {id=event.id,timestamp_ms=event.timestamp_ms,kind=event.kind,
        severity=event.severity,message=event.message,line_id=event.line_id,
        device_id=event.device_id,alarm_id=event.alarm_id}
end

-- Compact snapshots preserve logical state but copy only four event headers for
-- the dashboard. drain_events() retains rich event-time payloads for history.
-- Omit the argument for the original complete, detached snapshot API.
function Model:snapshot(compact)
    local events,last_event
    if compact==true then
        events={}
        for i=math.max(1,#self.history-3),#self.history do
            events[#events+1]=event_header(self.history[i])
        end
        last_event=event_header(self.last_event)
    else
        events,last_event=copy(self.history),copy(self.last_event)
    end
    local result = {
        power = self.power, elapsed_ms = self.elapsed_ms,
        alarm_seq = self.alarm_seq, auto_fault_seq = self.auto_fault_seq,
        event_seq = self.event_seq, events = events,
        last_event = last_event, last_alarm = copy(self.last_alarm), lines = {}
    }
    for n, line in ipairs(self.lines) do
        local item = {
            id = line.id, name = line.name, phase = line.phase,
            produced = line.produced, latched = line.alarm ~= nil,
            remaining_ms = n == 2 and math.max(0, self.config.fault_interval_ms - line.running_since_fault_ms) or nil,
            check_index = line.check_index, check_samples = line.check_samples,
            check_required_samples = self.config.stable_samples,
            check_deadline_ms = line.check_deadline_ms,
            blocked_status = line.blocked_status, blocked_device_id = line.blocked_device_id,
            alarm = copy(line.alarm), devices = {}
        }
        for i, device in ipairs(line.devices) do
            local displayed = device.health
            if not self.power then
                displayed = "GRAY"
            elseif line.phase ~= "RUNNING" then
                if device.health == "RED" or device.health == "GRAY" then
                    displayed = device.health
                elseif (line.phase == "CHECKING" or line.phase == "READY") and device.verified then
                    displayed = "GREEN"
                else
                    displayed = "GRAY"
                end
            end
            item.devices[i] = {
                id = device.id, name = device.name,
                status = displayed, health = device.health,
                verified = device.verified, manual_health = device.manual_health,
                interlocked = self.power and line.phase ~= "RUNNING" and
                    device.health ~= "RED" and device.health ~= "GRAY" and not device.verified,
                checking = line.phase == "CHECKING" and line.check_index == i
            }
        end
        result.lines[n] = item
    end
    result.active_alarm = copy(self.lines[2].alarm or self.lines[1].alarm)
    return result
end

return Model
