-- Native AirUI only. All positions target the Air8601 1024x600 panel.
-- Component APIs: https://docs.openluat.com/osapi/core/airui/
local UI = {}
UI.__index = UI
local Drawer = require("drawer")
local Clock = require("clock_ms")
local Network = require("network_model")
local AlarmHistory = require("alarm_history")

local C = {
    bg = 0x061221, panel = 0x0B1B30, card = 0x10243A,
    border = 0x203E59, cyan = 0x36D7F2, text = 0xE4F3FF,
    muted = 0x7F9DB7, green = 0x35E5A0, yellow = 0xF5C65B,
    red = 0xFF596E, gray = 0x7D8B9C, dim = 0x14283D,
}
local COLORS = {GREEN=C.green, YELLOW=C.yellow, RED=C.red, GRAY=C.gray}
local STATUS = {GREEN="顺畅运行", YELLOW="设备繁忙", RED="设备故障", GRAY="状态异常"}
local PHASE = {RUNNING="运行中", TRIPPED="紧急停线", CHECKING="安全复检", READY="待恢复", OFF="电源关闭"}
local NAMES = {"上料单元", "装配机械臂", "视觉检测", "自动包装"}
local KIND = {
    STARTUP="系统就绪", FAULT_REPORTED="异常已上报", REPAIR_STARTED="开始逐台复检",
    CHECK_PASSED="设备复检通过", CHECK_BLOCKED="设备复检受阻",
    CHECK_TIMEOUT="复检超时停线", CHECK_INVALIDATED="复检失效保持停线", LINE_READY="全部通过待恢复",
    LINE_RESUMED="产线已恢复", POWER_OFF="总电源已关闭", POWER_ON="总电源已接通",
}

local function box(x,y,w,h,color,border,radius,parent,opacity)
    return airui.container({parent=parent,x=x,y=y,w=w,h=h,color=color or C.panel,
        color_opacity=opacity or 255,radius=radius or 0,
        border_color=border,border_width=border and 1 or 0})
end
local function label(x,y,w,h,text,size,color,align,parent)
    return airui.label({parent=parent,x=x,y=y,w=w,h=h,text=text or "",
        font_size=size or 14,color=color or C.text,
        align=align or airui.TEXT_ALIGN_LEFT})
end
local function set_text(obj,text)
    if obj.cache ~= text then obj.widget:set_text(text); obj.cache=text end
end
local function ref(widget) return {widget=widget} end
local function clock(ms)
    local s=math.floor(ms/1000)
    return string.format("%02d:%02d:%02d",math.floor(s/3600),math.floor(s/60)%60,s%60)
end
local function button(x,y,w,text,color,callback)
    return airui.button({x=x,y=y,w=w,h=46,text=text,font_size=16,
        style={bg_color=C.card,border_color=color,border_width=1,radius=5,
            text_color=color,pad=0,pressed_bg_color=0x164561,pressed_text_color=C.text},
        on_click=callback})
end

function UI.new(model, reporter, config)
    local self=setmetatable({model=model,reporter=reporter,config=config,
        selected_line=2,selected_device=3,device_widgets={},flow={},last_notice="",
        notice_until=0,network=Network.new(config.network),
        history=AlarmHistory.new(32),seen_event_id=0},UI)
    box(0,0,1024,600,C.bg)
    -- Header: fine structural rails, restrained cyan accents.
    box(16,10,267,1,C.border); box(741,10,267,1,C.border)
    box(16,11,32,2,C.cyan); box(976,11,32,2,C.cyan)
    box(303,6,418,2,C.cyan)
    box(328,55,368,1,C.border)
    label(22,22,190,22,"FACTORY / 工厂产线中控",16,C.cyan)
    label(260,19,504,32,"工厂设备 · 产线实时监控",26,C.text,airui.TEXT_ALIGN_CENTER)
    label(842,21,166,19,"AIR8601  /  模拟演示",13,C.muted,airui.TEXT_ALIGN_RIGHT)
    self.uptime=ref(label(842,42,166,16,"",12,C.cyan,airui.TEXT_ALIGN_RIGHT))

    local xs={16,268,520,772}
    local titles={"运行产线", "运行设备", "累计异常", "告警上报"}
    self.kpis={}
    for i=1,4 do
        box(xs[i],72,236,62,C.panel,C.border,4)
        box(xs[i],87,2,30,i==3 and C.yellow or C.cyan)
        label(xs[i]+14,82,116,18,titles[i],13,C.muted)
        self.kpis[i]=ref(label(xs[i]+14,101,206,27,"",22,i==3 and C.yellow or C.text))
    end

    -- Power cabinet and the single-line electrical branching diagram.
    box(16,148,138,369,C.panel,C.border,4)
    label(28,162,114,22,"电力拓扑",16,C.text)
    label(28,189,114,17,"MAIN POWER",12,C.muted)
    self.power_dot=box(40,225,16,16,C.green,nil,8)
    label(65,220,65,26,"总电源",18,C.text)
    self.power_text=ref(label(29,253,112,25,"",22,C.green,airui.TEXT_ALIGN_CENTER))
    label(28,287,116,19,"380 V / 模拟",13,C.muted,airui.TEXT_ALIGN_CENTER)
    box(132,264,29,2,C.cyan)
    self.power_bus=box(159,264,2,197,C.cyan)
    self.branch_a=box(159,281,24,2,C.green)
    self.branch_b=box(159,461,24,2,C.green)
    self.feed_a=ref(label(28,335,112,20,"",14,C.green))
    self.feed_b=ref(label(28,367,112,20,"",14,C.green))
    label(28,410,112,35,"一总电源\n两路独立联锁",12,C.muted)
    self.power_button=button(28,463,112,"关闭电源",C.cyan,function()
        if self:is_drawer_blocking() then return end
        self.model:set_power(not self.model:snapshot().power)
        self:render(self.model:snapshot())
    end)

    -- Two photo-like digital twin conveyor rows. Assets are baseline JPEG,
    -- 640x128, both dimensions multiples of 16 for the official decoder.
    self.backgrounds={
        airui.image({x=166,y=215,w=640,h=128,src=config.background_a}),
        airui.image({x=166,y=391,w=640,h=128,src=config.background_b}),
    }
    self.line_badges={}
    self.production={}
    self.countdown={}
    self.rows={}
    local anchors={258,394,571,720}
    for line=1,2 do
        local y=line==1 and 151 or 327
        box(174,y+1,3,22,line==1 and C.cyan or C.green)
        label(184,y,186,23,line==1 and "A 线 / 自动装配" or "B 线 / 自动装配",18,C.text)
        self.line_badges[line]=ref(label(375,y+2,110,20,"",14,C.green))
        self.production[line]=ref(label(508,y+3,116,18,"",12,C.muted))
        self.countdown[line]=ref(label(631,y+3,173,18,"",12,C.cyan,airui.TEXT_ALIGN_RIGHT))
        self.rows[line]=box(174,y+29,630,1,C.border)
        self.device_widgets[line]={}
        for d=1,4 do
            local x=anchors[d]-56
            local card_y=y+34
            local card=box(x,card_y,112,39,C.card,C.border,3)
            -- Labels are siblings so that card dimensions and hit regions stay
            -- identical in firmware and the generated layout preview.
            label(x+7,card_y+4,91,17,(line==1 and "A" or "B")..d.." "..NAMES[d],12,C.text)
            local dot=box(x+98,card_y+7,7,7,C.green,nil,4)
            local value=ref(label(x+7,card_y+22,101,16,"",12,C.green))
            box(anchors[d],card_y+40,1,7,C.border)
            -- The documented container callback also catches child clicks.
            card:set_on_click(function()
                if self:is_drawer_blocking() then return end
                self.selected_line,self.selected_device=line,d
                self:render(self.model:snapshot())
            end)
            self.device_widgets[line][d]={card=card,dot=dot,value=value}
        end
        -- Small moving packets are UI objects, not baked into the illustration.
        self.flow[line]={}
        local flow_y=line==1 and 315 or 491
        for p=1,4 do
            self.flow[line][p]=box(220+p*110,flow_y,18,3,C.cyan,nil,1)
        end
    end

    -- Equipment detail panel.
    box(820,148,188,160,C.panel,C.border,4)
    box(820,148,3,22,C.cyan)
    label(834,160,154,21,"设备状态 / DETAIL",14,C.text)
    self.detail_name=ref(label(834,189,160,25,"",19,C.cyan))
    self.detail_status=ref(label(834,221,160,20,"",15,C.green))
    self.detail_health=ref(label(834,249,160,19,"",12,C.muted))
    self.detail_check=ref(label(834,276,160,20,"",12,C.muted))
    -- Event stream: new events displace old entries; bounded model history.
    box(820,318,188,199,C.panel,C.border,4)
    box(820,318,3,22,C.cyan)
    label(834,330,162,21,"事件记录 / REPORT",14,C.text)
    self.event_rows={}
    for i=1,4 do
        self.event_rows[i]={
            time=ref(label(834,360+(i-1)*38,160,15,"",12,C.muted)),
            text=ref(label(834,377+(i-1)*38,160,18,"",12,C.text)),
        }
    end

    -- Bottom control rail.
    box(16,527,992,1,C.border)
    self.workflow=ref(label(20,538,420,22,"",16,C.text))
    self.hint=ref(label(20,566,420,18,"",12,C.muted))
    self.inject_button=button(460,541,150,"模拟立即异常",C.yellow,function()
        if self:is_drawer_blocking() then return end
        local s=self.model:snapshot()
        local ok,why=self.model:inject_fault(3,(math.floor(s.elapsed_ms/1000)%2==0) and "RED" or "GRAY")
        if not ok then self:notice("当前状态不能注入异常："..tostring(why)) end
        self:render(self.model:snapshot())
    end)
    self.repair_button=button(622,541,178,"已维修 · 开始复检",C.cyan,function()
        if self:is_drawer_blocking() then return end
        local ok,why=self.model:repair()
        if not ok then self:notice("暂不能复检："..tostring(why)) end
        self:render(self.model:snapshot())
    end)
    self.resume_button=button(812,541,196,"恢复 B 线",C.green,function()
        if self:is_drawer_blocking() then return end
        local ok,why=self.model:resume()
        if not ok then self:notice("未满足恢复条件："..tostring(why)) end
        self:render(self.model:snapshot())
    end)
    -- Compact shared legend in the top line, away from the machinery.
    local lx={420,511,602,693}
    local lc={C.green,C.yellow,C.red,C.gray}
    local lt={"顺畅", "繁忙", "故障", "异常/停机"}
    for i=1,4 do
        box(lx[i],137,6,6,lc[i],nil,3)
        label(lx[i]+10,134,90,16,lt[i],12,C.muted)
    end
    -- A narrow visible handle also provides a tap fallback for accessibility.
    self.drawer_handle=box(470,55,84,11,C.bg,nil,3)
    box(484,59,56,3,C.cyan,nil,2)
    self.drawer_handle:set_on_click(function() self:open_drawer() end)
    self.drawer=Drawer.new(self,config)
    self.drawer_touch_registered=airui.touch_subscribe(function(state,x,y,track_id,timestamp)
        -- The native UP callback may clear its timestamp. Use one monotonic
        -- board clock for every phase instead of mixing DOWN and UP clocks.
        local now=Clock.now(timestamp)
        return self:on_touch(state,x,y,track_id,now)
    end)
    if not self.drawer_touch_registered then log.warn("drawer","touch subscription failed; tap handle remains available") end
    self:render(model:snapshot())
    return self
end

function UI:is_drawer_blocking()
    return self.drawer and self.drawer:blocks_controls() or false
end

function UI:open_drawer() return self.drawer and self.drawer:open() or false end
function UI:close_drawer() return self.drawer and self.drawer:close() or false end
function UI:drawer_tick(dt_ms) if self.drawer then self.drawer:tick(dt_ms) end end
function UI:step(dt_ms) self.network:step(dt_ms) end
function UI:on_touch(state,x,y,track_id,timestamp)
    return self.drawer and self.drawer:touch(state,x,y,track_id,timestamp) or false
end

function UI:notice(text)
    self.last_notice=text
    self.notice_until=self.model:snapshot().elapsed_ms+3000
end

function UI:render(s)
    for _,event in ipairs(s.events or {}) do
        if event.id>self.seen_event_id then
            self.history:consume(event,s)
            self.seen_event_id=event.id
        end
    end
    -- Updating the covered dashboard invalidates large RGB/alpha regions.
    -- Keep the model running and refresh only the visible drawer on Air1601.
    if self.drawer and self.drawer.visible then
        self.drawer:update(s,self.reporter)
        return
    end
    -- Focus a newly latched alarm once; manual selection stays available after.
    if s.active_alarm and self.seen_alarm_id~=s.active_alarm.id then
        self.seen_alarm_id=s.active_alarm.id
        self.selected_line=s.active_alarm.line_id=="A" and 1 or 2
        self.selected_device=s.active_alarm.device_index or 1
    end
    local running,working=0,0
    for l=1,2 do
        local ln=s.lines[l]
        if ln.phase=="RUNNING" then running=running+1 end
        for d=1,4 do
            local dev=ln.devices[d]
            if ln.phase=="RUNNING" and (dev.status=="GREEN" or dev.status=="YELLOW") then working=working+1 end
            local w=self.device_widgets[l][d]
            local col=COLORS[dev.status] or C.gray
            if dev.status=="RED" and math.floor(s.elapsed_ms/500)%2==1 then col=0x943546 end
            if dev.checking and dev.health=="GREEN" then col=C.yellow end
            w.dot:set_color(col)
            local selected=self.selected_line==l and self.selected_device==d
            w.card:set_border_color(selected and C.cyan or (dev.status=="RED" and C.red or C.border),1)
            local text=STATUS[dev.status] or "未知状态"
            if not s.power then text="电源关闭"
            elseif ln.phase=="CHECKING" then
                if dev.verified then text="复检通过"
                elseif ln.check_index==d then text="正在检测..."
                else text="等待复检" end
            elseif ln.phase=="READY" then text="复检通过"
            elseif ln.phase=="TRIPPED" and dev.interlocked then text="联锁停机" end
            set_text(w.value,text)
            w.value.widget:set_color(col)
        end
        local line_col=ln.phase=="RUNNING" and C.green or
            (ln.phase=="TRIPPED" and C.red or (ln.phase=="CHECKING" and C.yellow or C.gray))
        set_text(self.line_badges[l],PHASE[ln.phase] or ln.phase)
        self.line_badges[l].widget:set_color(line_col)
        set_text(self.production[l],string.format("产量 %04d 件",ln.produced or 0))
        local counter=l==1 and (ln.phase=="RUNNING" and "稳定运行 / 独立联锁" or "停止运行") or
            (ln.phase=="RUNNING" and string.format("下次异常 %02d s",math.ceil((ln.remaining_ms or 0)/1000)) or
            (ln.phase=="CHECKING" and string.format("逐台检测 %d / 4",ln.check_index or 4) or "联锁已锁定"))
        if ln.phase=="OFF" then counter="总电源已关闭"
        elseif ln.phase=="READY" then counter="4 / 4 通过 · 等待恢复" end
        set_text(self.countdown[l],counter)
        for p=1,4 do
            local marker=self.flow[l][p]
            marker:set_hidden(ln.phase~="RUNNING")
            if ln.phase=="RUNNING" then
                marker:set_pos(210+((math.floor(s.elapsed_ms/24)+p*140)%568),l==1 and 315 or 491)
            end
        end
    end
    set_text(self.kpis[1],string.format("%02d / 02",running))
    set_text(self.kpis[2],string.format("%02d / 08",working))
    set_text(self.kpis[3],string.format("%02d 次",s.alarm_seq or 0))
    local report_states={LOCAL="本地事件已就绪",QUEUED="等待网络上报",SENDING="正在上报",SENT="服务器已确认",FAILED="网络上报失败"}
    local report_text=report_states[self.reporter.state] or "本地记录"
    if self.reporter.state=="LOCAL" and self.reporter.local_count>0 then
        report_text=string.format("本地已上报 %02d 次",self.reporter.local_count)
    end
    set_text(self.kpis[4],report_text)
    self.kpis[4].widget:set_font_size(18)
    set_text(self.uptime,"UPTIME  "..clock(s.elapsed_ms))
    set_text(self.power_text,s.power and "已接通" or "已断开")
    self.power_text.widget:set_color(s.power and C.green or C.gray)
    self.power_dot:set_color(s.power and C.green or C.gray)
    self.power_bus:set_color(s.power and C.cyan or C.gray)
    self.branch_a:set_color(s.power and C.green or C.gray)
    self.branch_b:set_color(s.power and (s.lines[2].phase=="RUNNING" and C.green or C.red) or C.gray)
    set_text(self.feed_a,"A 线  "..(s.power and "供电正常" or "断电"))
    set_text(self.feed_b,"B 线  "..(s.power and "供电正常" or "断电"))
    self.power_button:set_text(s.power and "关闭电源" or "接通电源")

    local line=s.lines[self.selected_line]
    local dev=line.devices[self.selected_device]
    local display_status=STATUS[dev.status] or "未知"
    if line.phase=="TRIPPED" and dev.interlocked then display_status="联锁停机" end
    if line.phase=="CHECKING" then
        if dev.verified then display_status="复检通过 / 保持停机"
        elseif dev.checking then display_status="正在复检 / 保持停机"
        else display_status="等待复检 / 保持停机" end
    elseif line.phase=="READY" then display_status="复检通过 / 等待恢复" end
    if not s.power then display_status="电源关闭" end
    set_text(self.detail_name,dev.id.." · "..NAMES[self.selected_device])
    set_text(self.detail_status,display_status)
    self.detail_status.widget:set_color(COLORS[dev.status] or C.gray)
    set_text(self.detail_health,"原始状态："..(STATUS[dev.health] or dev.health))
    set_text(self.detail_check,"复检："..(dev.verified and "连续采样通过" or
        ((line.phase=="CHECKING" and line.check_index==self.selected_device) and "检测中" or "未确认")))

    local events=s.events or {}
    for i=1,4 do
        local e=events[#events-i+1]
        local row=self.event_rows[i]
        set_text(row.time,e and (clock(e.timestamp_ms or 0).."  "..(e.device_id or e.line_id or "SYS")) or "")
        set_text(row.text,e and (KIND[e.kind] or e.kind) or "")
        row.text.widget:set_color(e and (e.severity=="ERROR" and C.red or
            (e.severity=="WARN" and C.yellow or C.text)) or C.text)
    end
    local b=s.lines[2]
    self.inject_button:set_disabled(not s.power or b.phase~="RUNNING")
    self.repair_button:set_disabled(not s.power or b.phase~="TRIPPED")
    self.resume_button:set_disabled(not s.power or b.phase~="READY")
    local workflow,hint
    if not s.power then
        workflow="总电源已关闭 / 全部设备停止"
        hint="接通后保留故障联锁，B 线需重新复检。"
    elseif b.phase=="TRIPPED" then
        workflow="01 停线锁定  >  02 等待维修"
        hint="完成维修后按“已维修”，逐台读取设备状态。"
    elseif b.phase=="CHECKING" then
        workflow="03 安全复检 / 设备 "..tostring(b.check_index or 4).." / 4"
        hint="每台连续 2 次健康采样；异常或繁忙阻止恢复。"
    elseif b.phase=="READY" then
        workflow="04 四台设备通过 / 可恢复产线"
        hint="按“恢复 B 线”后启动下一轮 60 秒模拟。"
    else
        workflow="双线运行 / B 线每 60 秒模拟一次异常"
        hint="触摸设备卡片查看详情 · 红故障 / 灰异常交替。"
    end
    if s.elapsed_ms<self.notice_until then hint=self.last_notice end
    set_text(self.workflow,workflow)
    set_text(self.hint,hint)
    if self.drawer then self.drawer:update(s,self.reporter) end
end

return UI
