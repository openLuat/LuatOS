-- Air1601: animate one opaque parent, using elapsed wall time rather than raw
-- MCU ticks or frame counts. Global touch hit tests also follow the moving panel.
local Gesture=require("drawer_gesture")
local Clock=require("clock_ms")
local Drawer={}
Drawer.__index=Drawer
local C={panel=0x0B1B30,card=0x10243A,border=0x203E59,text=0xE4F3FF,
    muted=0x7F9DB7,cyan=0x36D7F2,green=0x35E5A0,yellow=0xF5C65B,red=0xFF596E,gray=0x7D8B9C}
local STAGE={TRIPPED="等待维修",CHECKING="逐台复检",READY="待人工恢复",RUNNING="已恢复",OFF="断电停机"}
local HEALTH={GREEN="正常",YELLOW="繁忙",RED="故障",GRAY="异常"}
local NET={OFF="未连接",CONNECTING="模拟连接中",CONNECTED="模拟已连接",DISCONNECTING="模拟断开中"}
local hidden_cache=setmetatable({},{__mode="k"})
local disabled_cache=setmetatable({},{__mode="k"})
local function hidden(widget,value)
    if hidden_cache[widget]~=value then widget:set_hidden(value);hidden_cache[widget]=value end
end
local function disabled(widget,value)
    if disabled_cache[widget]~=value then widget:set_disabled(value);disabled_cache[widget]=value end
end
local function box(parent,x,y,w,h,fill,border,radius,opacity)
    return airui.container({parent=parent,x=x,y=y,w=w,h=h,color=fill,
        color_opacity=opacity or 255,border_color=border,border_width=border and 1 or 0,radius=radius or 0})
end
local function text(parent,x,y,w,h,value,size,fill)
    return airui.label({parent=parent,x=x,y=y,w=w,h=h,text=value,font_size=size,color=fill})
end
local function field(widget) return {widget=widget} end
local function write(ref,value)
    value=tostring(value or "")
    if ref.last~=value then ref.widget:set_text(value);ref.last=value end
end
local function color(ref,value)
    if ref.color~=value then ref.widget:set_color(value);ref.color=value end
end
local function time(ms)
    if ms==nil then return "--:--:--" end
    local s=math.floor(ms/1000)
    return string.format("%02d:%02d:%02d",math.floor(s/3600),math.floor(s/60)%60,s%60)
end
local function inside(x,y,r)
    return x>=r[1] and y>=r[2] and x<=r[1]+r[3] and y<=r[2]+r[4]
end
local function button(parent,x,y,w,h,value,fn)
    return airui.button({parent=parent,x=x,y=y,w=w,h=h,text=value,font_size=13,
        style={bg_color=C.card,border_color=C.border,border_width=1,radius=3,text_color=C.cyan,pad=0},on_click=fn})
end

function Drawer.new(owner,config)
    config=config or {}
    local self=setmetatable({owner=owner,height=516,y=-516,opened=false,visible=false,
        animation=nil,records={},record_by_id={},page=1,selected_id=nil,follow_latest=true,
        open_ms=math.max(0,math.min(400,tonumber(config.drawer_animation_ms) or 220)),
        close_ms=math.max(0,math.min(400,tonumber(config.drawer_close_animation_ms) or 180)),
        touch_seq=0,last_input_ms=0,timeline_offset=0},Drawer)
    self.animation_callback=function() self:tick() end
    self.gesture=Gesture.new({top_zone=64,open_threshold=72,close_threshold=48,
        drawer_height=516,close_zone_height=40,max_duration_ms=2000})
    -- A fully transparent hit surface keeps the dashboard visible. The moving
    -- drawer itself is opaque, so no full-screen alpha fade is needed.
    self.mask=box(nil,0,0,1024,600,0x030B14,nil,0,0)
    self.mask:set_on_click(function() self:_activate("close",nil,"click") end)
    local mask_hint=box(self.mask,386,520,252,20,C.panel,C.border,3)
    text(mask_hint,16,2,220,16,"点击下方区域收起",12,C.muted)
    self.panel=box(nil,0,self.y,1024,self.height,C.panel,C.border)
    self.panel:set_on_click(function() end)
    box(self.panel,0,0,1024,3,C.cyan)
    text(self.panel,24,13,830,29,"工厂产线中控 · 网络与故障中心",23,C.text)
    text(self.panel,24,43,850,17,"WIFI / 4G / 以太网 / 蓝牙  ·  模拟控制，不操作通信硬件",12,C.muted)
    self.close_button=button(self.panel,912,15,88,36,"收起",function() self:_activate("close",nil,"click") end)
    self.net_widgets={}
    local cards=owner.network:snapshot().cards
    for i,card in ipairs(cards) do
        local x=24+(i-1)*248
        local node=box(self.panel,x,65,232,94,C.card,C.border,4)
        node:set_on_click(function() self:_activate("network",card.key,"click") end)
        text(self.panel,x+13,75,150,24,card.title,20,C.text)
        self.net_widgets[i]={node=node,key=card.key,
            state=field(text(self.panel,x+13,108,199,20,"",15,C.gray)),
            detail=field(text(self.panel,x+13,136,208,16,"",12,C.muted)),
            toggle=field(text(self.panel,x+177,78,42,20,"",14,C.cyan))}
    end
    text(self.panel,24,178,100,24,"故障记录",19,C.text)
    self.record_count=field(text(self.panel,118,181,81,18,"",12,C.muted))
    self.previous=button(self.panel,204,176,68,27,"上一页",function() self:_activate("page",-1,"click") end)
    self.next=button(self.panel,280,176,68,27,"下一页",function() self:_activate("page",1,"click") end)
    text(self.panel,368,178,630,24,"故障详细情况",19,C.text)
    box(self.panel,24,209,328,271,C.card,C.border,4)
    -- AirUI 1.2.6 labels do not expose set_hidden. Hide the parent instead.
    self.empty=box(self.panel,46,235,280,45,C.card)
    text(self.empty,0,0,280,45,"暂无异常记录\n发生故障后自动记录详情",14,C.muted)
    self.rows={}
    for i=1,4 do
        local y=216+(i-1)*65
        local node=box(self.panel,32,y,312,58,C.panel,C.border,3)
        node:set_on_click(function()
            local record=self.records[(self.page-1)*4+i]
            if record then self:_activate("select",record.id,"click") end
        end)
        self.rows[i]={node=node,
            heading=field(text(node,9,4,291,16,"",12,C.muted)),
            title=field(text(node,9,22,291,18,"",14,C.text)),
            state=field(text(node,9,42,291,14,"",12,C.red))}
    end
    box(self.panel,368,209,632,271,C.card,C.border,4)
    self.detail={
        title=field(text(self.panel,383,220,601,22,"",17,C.text)),
        meta=field(text(self.panel,383,248,601,18,"",12,C.muted)),
        cause=field(text(self.panel,383,273,601,32,"",14,C.text)),
        process=field(text(self.panel,383,313,601,19,"",13,C.cyan)),
        stats=field(text(self.panel,383,340,601,18,"",12,C.muted))}
    self.device_fields={}
    for i=1,4 do
        local x=383+(i-1)*151
        box(self.panel,x,367,143,25,C.panel,C.border,3)
        self.device_fields[i]=field(text(self.panel,x+7,372,129,17,"",12,C.gray))
    end
    text(self.panel,383,401,420,16,"处置时间线",12,C.muted)
    self.timeline_previous=button(self.panel,860,396,58,23,"更早",function() self:_activate("timeline",-1,"click") end)
    self.timeline_next=button(self.panel,926,396,58,23,"较新",function() self:_activate("timeline",1,"click") end)
    self.timeline={}
    for i=1,3 do self.timeline[i]=field(text(self.panel,383,422+(i-1)*18,601,17,"",12,C.muted)) end
    text(self.panel,300,487,424,17,"上滑底部把手，或点击下方遮罩收起",12,C.muted)
    self.grip=box(self.panel,468,507,88,4,C.cyan,nil,2)
    self.mask:set_hidden(true);self.panel:set_hidden(true)
    owner.drawer_mask,owner.drawer_panel=self.mask,self.panel
    owner.drawer_open=false
    return self
end

function Drawer:blocks_controls() return self.visible end
function Drawer:_place(y)
    y=math.max(-self.height,math.min(0,math.floor(y+0.5)))
    if y~=self.y then self.y=y;self.panel:set_pos(0,y) end
end
function Drawer:_stop_timer()
    if self.animation_timer then
        sys.timerStop(self.animation_timer)
        self.animation_timer=nil
    end
end
function Drawer:_finish()
    self:_stop_timer()
    self.animation=nil
    self:_place(self.opened and 0 or -self.height)
    if self.opened then
        self:update(self.owner.model:snapshot(),self.owner.reporter)
    else
        self.visible=false
        self.panel:set_hidden(true);self.mask:set_hidden(true)
        self.owner:render(self.owner.model:snapshot())
    end
end
function Drawer:_slide(target,duration)
    self:_stop_timer()
    local distance=math.abs(target-self.y)
    if duration<=0 or distance==0 then self:_finish();return end
    self.animation={from=self.y,target=target,elapsed_ms=0,started_ms=Clock.now(self.last_input_ms),
        duration_ms=math.max(20,math.floor(duration*distance/self.height+0.5))}
    if type(sys.timerLoopStart)=="function" then
        self.animation_timer=sys.timerLoopStart(self.animation_callback,20)
    end
    -- A failed timer must not leave the transparent hit layer stuck on screen.
    if not self.animation_timer then self:_finish() end
end
function Drawer:open()
    if self.opened then return false end
    -- Reversing an in-flight close starts at the current position.
    self.animation=nil
    self.opened,self.visible,self.owner.drawer_open=true,true,true
    self.gesture:set_open(true)
    self:update(self.owner.model:snapshot(),self.owner.reporter)
    self.mask:set_hidden(false);self.panel:set_hidden(false)
    self:_slide(0,self.open_ms)
    log.info("drawer","open")
    return true
end
function Drawer:close()
    if not self.visible or not self.opened then return false end
    self.opened,self.owner.drawer_open=false,false
    self.gesture:set_open(false)
    self:_slide(-self.height,self.close_ms)
    log.info("drawer","close")
    return true
end
function Drawer:tick(dt)
    local a=self.animation
    if not a then return end
    -- Native timers use absolute elapsed time: a delayed frame skips ahead.
    -- Explicit deltas are for deterministic desktop preview/test playback.
    if type(dt)=="number" then
        a.elapsed_ms=a.elapsed_ms+math.max(0,dt)
    else
        a.elapsed_ms=Clock.elapsed(Clock.now(self.last_input_ms),a.started_ms)
    end
    local progress=math.min(1,a.elapsed_ms/a.duration_ms)
    local eased=1-(1-progress)^3
    self:_place(a.from+(a.target-a.from)*eased)
    if progress>=1 then self:_finish() end
end

function Drawer:_activate(action,arg,origin)
    if action~="close" and (not self.visible or self.animation) then return false end
    local key=action..":"..tostring(arg)
    local now=Clock.now(self.last_input_ms)
    -- Observer UP and native on_click can both deliver one physical tap.
    if self.last_action_key==key and self.last_action_seq==self.touch_seq and
        Clock.elapsed(now,self.last_action_ms or 0)<350 then return false end
    self.last_action_key,self.last_action_seq,self.last_action_ms=key,self.touch_seq,now
    if action=="close" then return self:close() end
    if not self.visible then return false end
    if action=="network" then
        local current=self.owner.network:snapshot().by_key[arg]
        if current then self.owner.network:request(arg,not current.enabled) end
    elseif action=="select" then
        self.selected_id,self.follow_latest=arg,false
        self.timeline_offset=0
    elseif action=="page" then
        local pages=math.max(1,math.ceil(#self.records/4))
        self.page=math.max(1,math.min(pages,self.page+arg))
        local first=self.records[(self.page-1)*4+1]
        self.selected_id=first and first.id or nil
        self.follow_latest=false
        self.timeline_offset=0
    elseif action=="timeline" then
        local selected=self.selected_id and self.record_by_id[self.selected_id]
        local max_offset=selected and math.max(0,#(selected.timeline or {})-3) or 0
        self.timeline_offset=math.max(0,math.min(max_offset,self.timeline_offset-arg*3))
    else return false end
    self:update(self.owner.model:snapshot(),self.owner.reporter)
    return true
end

function Drawer:_hit(x,y)
    if not self.visible then return nil end
    local bottom=self.y+self.height
    if y>=bottom or inside(x,y,{900,self.y,124,62}) then return "close",nil end
    if self.animation then return nil end
    if y>=65 and y<=159 then
        for i,w in ipairs(self.net_widgets) do
            if inside(x,y,{24+(i-1)*248,65,232,94}) then return "network",w.key end
        end
    end
    if inside(x,y,{204,176,68,27}) then return "page",-1 end
    if inside(x,y,{280,176,68,27}) then return "page",1 end
    if inside(x,y,{860,396,58,23}) then return "timeline",-1 end
    if inside(x,y,{926,396,58,23}) then return "timeline",1 end
    for i=1,4 do
        if inside(x,y,{32,216+(i-1)*65,312,58}) then
            local record=self.records[(self.page-1)*4+i]
            if record then return "select",record.id end
        end
    end
end

function Drawer:touch(state,x,y,track_id,timestamp)
    local name
    if state==nil then return false
    elseif state==airui.TP_DOWN or state=="DOWN" then name="DOWN"
    elseif state==airui.TP_HOLD or state=="HOLD" then name="HOLD"
    elseif state==airui.TP_UP or state=="UP" then name="UP"
    elseif state=="CANCEL" then name="CANCEL" else return false end
    local now=Clock.now(timestamp or self.last_input_ms)
    self.last_input_ms=now
    local id=track_id or 0
    if name=="CANCEL" then self.primary=nil;self.gesture:cancel();return false end
    if type(x)~="number" or type(y)~="number" then return false end
    if name=="DOWN" then
        if self.primary and Clock.elapsed(now,self.primary.start)>2000 then
            self.primary=nil;self.gesture:cancel()
        end
        if self.primary and self.primary.id~=id then return false end
        self.gesture:cancel()
        self.touch_seq=self.touch_seq+1
        local hit,arg=self:_hit(x,y)
        local bottom=self.y+self.height
        self.primary={id=id,x=x,y=y,start=now,seq=self.touch_seq,drift=0,hit=hit,arg=arg,
            close_grip=self.visible and y>=bottom-40 and y<=bottom}
    end
    local p=self.primary
    if not p or p.id~=id then return false end
    p.drift=math.max(p.drift,math.abs(x-p.x),math.abs(y-p.y))
    local action=self.gesture:touch(name,x,y,id,now)
    if name~="UP" then return false end
    self.primary=nil
    if action=="OPEN" then self:open();return true end
    -- Closing is deliberately forgiving: it never drives equipment outputs.
    if self.visible and p.close_grip and y-p.y<=-36 and math.abs(x-p.x)<=120 then
        self:close();return true
    end
    if action=="CLOSE" then self:close();return true end
    if p.drift<=18 and Clock.elapsed(now,p.start)<=900 then
        local hit,arg=self:_hit(x,y)
        if p.hit and p.hit==hit and p.arg==arg then
            self:_activate(hit,arg,"touch")
            return true
        end
        -- The native callback may already have closed before this observer UP.
        if p.hit=="close" then return true end
    end
    return false
end

function Drawer:update(s,_reporter)
    if not self.visible or self.animation then return end
    for i,card in ipairs(self.owner.network:snapshot().cards) do
        local w=self.net_widgets[i]
        write(w.state,NET[card.state] or card.state)
        color(w.state,card.connected and C.green or (card.enabled and C.yellow or C.gray))
        write(w.detail,card.connected and card.address or card.detail)
        write(w.toggle,card.enabled and "开" or "关")
        color(w.toggle,card.enabled and C.cyan or C.gray)
    end
    local revision=self.owner.history:revision()
    if self.history_revision~=revision then
        self.records=self.owner.history:snapshot()
        self.record_by_id={}
        for _,record in ipairs(self.records) do self.record_by_id[record.id]=record end
        self.history_revision=revision
    end
    local pages=math.max(1,math.ceil(#self.records/4))
    self.page=math.min(pages,self.page)
    if self.selected_id and not self.record_by_id[self.selected_id] then
        self.selected_id=nil;self.follow_latest=true;self.timeline_offset=0
    end
    if self.follow_latest or not self.selected_id then
        self.selected_id=self.records[1] and self.records[1].id or nil
        self.page=1
    end
    write(self.record_count,string.format("%d 条 %d/%d",#self.records,self.page,pages))
    disabled(self.previous,self.page<=1);disabled(self.next,self.page>=pages)
    hidden(self.empty,#self.records>0)
    for i,row in ipairs(self.rows) do
        local record=self.records[(self.page-1)*4+i]
        hidden(row.node,record==nil)
        if record then
            write(row.heading,time(record.started_ms).."  #"..tostring(record.id))
            write(row.title,(record.line_id or "-").." 线 / "..(record.device_id or "-").."  "..(HEALTH[record.status] or "异常"))
            write(row.state,record.resolved and "已恢复" or (STAGE[record.phase] or record.phase))
            color(row.state,record.resolved and C.green or C.red)
            local border=record.id==self.selected_id and C.cyan or C.border
            if row.border~=border then row.node:set_border_color(border,1);row.border=border end
        end
    end
    local record=self.selected_id and self.record_by_id[self.selected_id]
    if not record then
        write(self.detail.title,"暂无故障 / 异常记录")
        write(self.detail.meta,"记录包含发生时间、设备状态、维修与复检过程")
        write(self.detail.cause,"发生模拟异常后，这里会自动展示详细情况。")
        write(self.detail.process,"");write(self.detail.stats,"")
        for _,f in ipairs(self.device_fields) do write(f,"--") end
        for _,f in ipairs(self.timeline) do write(f,"") end
        disabled(self.timeline_previous,true);disabled(self.timeline_next,true)
        return
    end
    write(self.detail.title,string.format("#%s  %s 线 · %s  / %s",record.id,record.line_id or "-",record.device_id or "-",record.code or "--"))
    write(self.detail.meta,"发生 "..time(record.started_ms).."   恢复 "..time(record.recovered_ms).."   "..(record.resolved and "已恢复" or (STAGE[record.phase] or record.phase)))
    write(self.detail.cause,record.description)
    write(self.detail.process,"当前处置："..(record.latest_process or "等待维修"))
    local elapsed=(record.recovered_ms or s.elapsed_ms)-(record.started_ms or 0)
    write(self.detail.stats,string.format("复检 %d/4  ·  维修 %d 次  ·  受阻 %d 次  ·  持续 %d 秒",record.check_passed_count or 0,record.repair_count or 0,record.check_blocked_count or 0,math.max(0,math.floor(elapsed/1000))))
    for i,f in ipairs(self.device_fields) do
        local d=(record.devices or {})[i]
        write(f,d and (d.id.." "..(HEALTH[d.health] or d.health)) or "--")
        color(f,d and ({GREEN=C.green,YELLOW=C.yellow,RED=C.red,GRAY=C.gray})[d.health] or C.gray)
    end
    local entries=record.timeline or {}
    self.timeline_offset=math.min(self.timeline_offset,math.max(0,#entries-3))
    local first=math.max(1,#entries-2-self.timeline_offset)
    disabled(self.timeline_previous,first<=1)
    disabled(self.timeline_next,self.timeline_offset<=0)
    for i,f in ipairs(self.timeline) do
        local e=entries[first+i-1]
        write(f,e and (time(e.timestamp_ms).."  "..e.message) or "")
    end
end

return Drawer
