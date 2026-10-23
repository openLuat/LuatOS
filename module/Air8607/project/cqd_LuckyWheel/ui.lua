-- AirUI 1.2.6: rotate a PNG with integer 0.1-degree units, fit=center.
-- Winner text breathes through supported label font-size and position APIs.
local Clock=require("clock_ms")
local UI={};UI.__index=UI
local C={bg=0x0B0D23,panel=0x171B35,border=0x383552,text=0xFFF5E3,
    muted=0xA9A8C2,gold=0xFFD58A,purple=0xAE93FF,dark=0x292039}
local function box(parent,x,y,w,h,color,radius,border)
    return airui.container({parent=parent,x=x,y=y,w=w,h=h,color=color,color_opacity=255,
        radius=radius or 0,border_color=border,border_width=border and 1 or 0})
end
local function label(parent,x,y,w,h,value,size,color,center)
    return airui.label({parent=parent,x=x,y=y,w=w,h=h,text=value,font="hzfont",font_size=size,
        color=color,align=center and airui.TEXT_ALIGN_CENTER or airui.TEXT_ALIGN_LEFT})
end
local function inside(x,y,r)
    return x>=r[1] and y>=r[2] and x<=r[1]+r[3] and y<=r[2]+r[4]
end
local function text_units(text)
    local units=0
    for _,cp in utf8.codes(text) do units=units+(cp<128 and 0.6 or 1) end
    return math.max(1,units)
end
function UI:_text(key,widget,value)
    if self.cache[key]~=value then widget:set_text(value);self.cache[key]=value end
end
function UI:_rolling(value)
    if self.cache.rolling==value then return end
    self:_text("rolling",self.rolling,value)
    local size=self.name_sizes[value]
    if not size then
        size=math.max(12,math.min(23,math.floor(300/text_units(value))))
        self.name_sizes[value]=size
    end
    if self.rolling_size~=size then self.rolling:set_font_size(size);self.rolling_size=size end
end
function UI.new(model,config)
    local self=setmetatable({model=model,config=config,cache={},name_sizes={},touch_seq=0,suppress_until=0},UI)
    for _,person in ipairs(config.participants) do
        self.name_sizes[person.name]=math.max(12,math.min(23,math.floor(300/text_units(person.name))))
    end
    self.main=box(nil,0,0,1024,600,C.bg)
    airui.image({parent=self.main,x=0,y=0,w=1024,h=608,src="/luadb/background.jpg",fit="center"})
    label(self.main,44,24,610,42,"粉丝幸运转盘",32,C.text)
    label(self.main,46,68,570,18,"FANS GIVEAWAY  /  让好运，转到你",13,C.muted)
    box(self.main,798,31,178,31,C.panel,15,C.border)
    label(self.main,807,38,160,18,"评论区福利专场",14,C.gold,true)
    -- Static 480px rim preserves the visual size; only the native 352px disc
    -- rotates. Clip transformed bounds before they invalidate the main screen.
    airui.image({parent=self.main,x=54,y=94,w=480,h=480,src="/luadb/wheel_frame.jpg",fit="center"})
    self.wheel_viewport=box(self.main,118,158,352,352,C.bg)
    airui.image({parent=self.wheel_viewport,x=-64,y=-64,w=480,h=480,
        src="/luadb/wheel_frame.jpg",fit="center"})
    self.wheel=airui.image({parent=self.wheel_viewport,x=0,y=0,w=352,h=352,
        src="/luadb/wheel.png",fit="center",pivot={x=176,y=176},zoom=256})
    self.wheel:set_pivot(176,176)
    airui.image({parent=self.main,x=270,y=126,w=48,h=48,src="/luadb/pointer.png",fit="center"})
    box(self.main,248,288,92,92,C.bg,46,C.gold)
    label(self.main,255,308,78,32,"幸运",25,C.gold,true)
    label(self.main,255,341,78,18,"LUCKY",12,C.muted,true)
    box(self.main,610,124,352,138,C.panel,14,C.border)
    label(self.main,632,144,180,18,"本轮奖品",14,C.muted)
    label(self.main,630,174,310,43,config.prize,32,C.gold)
    label(self.main,632,229,308,18,"1 台整机  /  送给一直支持的你",14,C.text)
    box(self.main,610,282,352,148,C.panel,14,C.border)
    label(self.main,632,301,308,22,string.format("%02d 位参与者 · 每人一票",#config.participants),18,C.text)
    self.rolling=label(self.main,632,348,308,34,"好运正在等你",23,C.purple,true)
    self.round_label=label(self.main,632,399,308,17,"全员参与 · 点击下方开始",12,C.muted,true)
    self.start_rect={610,454,352,68}
    self.start_button=airui.button({parent=self.main,x=610,y=454,w=352,h=68,text="开始抽奖",font="hzfont",font_size=25,
        style={bg_color=C.gold,text_color=C.dark,radius=14,border_width=0,pad=0},
        on_click=function() self:start() end})
    self.footer=label(self.main,610,542,352,26,"每轮独立随机 · 同一昵称可以再次中奖",12,C.muted,true)
    label(self.main,54,575,480,18,"转盘编号与参与名单一一对应",12,C.muted,true)
    self.winner_layer=box(nil,0,0,1024,600,C.bg)
    airui.image({parent=self.winner_layer,x=0,y=0,w=1024,h=608,src="/luadb/background.jpg",fit="center"})
    box(self.winner_layer,309,98,406,406,0x14162D,203,0x34314F)
    box(self.winner_layer,359,148,306,306,0x1C1B36,153,0x4A3C59)
    label(self.winner_layer,312,83,400,22,"L U C K Y   W I N N E R",15,C.gold,true)
    label(self.winner_layer,142,147,740,50,"恭喜这位幸运观众",34,C.text,true)
    self.winner_name=label(self.winner_layer,48,260,928,112,"",64,C.gold,true)
    self.winner_id=label(self.winner_layer,212,401,600,25,"",16,C.muted,true)
    label(self.winner_layer,212,455,600,38,config.prize.." × 1",26,C.text,true)
    label(self.winner_layer,152,548,720,23,"轻触屏幕任意位置，返回主界面重新抽奖",15,C.muted,true)
    self.winner_layer:set_on_click(function() self:dismiss("native") end)
    self.winner_layer:set_hidden(true)
    airui.touch_subscribe(function(state,x,y,id,timestamp) return self:touch(state,x,y,id,timestamp) end)
    return self
end
function UI:start()
    if Clock.now()<self.suppress_until then return false end
    local ok,reason=self.model:start()
    if not ok then
        if reason~="not_idle" then
            self:_text("footer",self.footer,"随机源不可用，请重试或检查底层固件")
            log.error("lottery","draw rejected",reason)
        end
        return false,reason
    end
    self:_text("footer",self.footer,"每轮独立随机 · 同一昵称可以再次中奖")
    self:render(self.model:snapshot(true))
    return true
end
function UI:dismiss(origin)
    local now=Clock.now()
    if origin=="native" then
        -- A release that began during the spin must not hide the new winner,
        -- regardless of whether native click arrives before or after TP_UP.
        if self.pointer and self.pointer.phase~="WINNER" then return false end
        if not self.pointer and self.last_release_phase and self.last_release_phase~="WINNER" and
            now-(self.last_release_at or 0)<350 then return false end
    end
    if not self.model:dismiss() then return false end
    self.suppress_until=now+350
    self:render(self.model:snapshot(true))
    return true
end
function UI:touch(state,x,y,id,_timestamp)
    local now=Clock.now()
    if type(x)~="number" or type(y)~="number" then self.pointer=nil;return false end
    if state==airui.TP_DOWN then
        if self.pointer and now-self.pointer.at<2000 then return false end
        self.pointer={id=id or 0,x=x,y=y,at=now,phase=self.model.phase,drift=0}
        return false
    end
    local p=self.pointer
    if not p or p.id~=(id or 0) or type(x)~="number" or type(y)~="number" then return false end
    p.drift=math.max(p.drift,math.abs(x-p.x),math.abs(y-p.y))
    if state~=airui.TP_UP then return false end
    self.pointer=nil
    self.last_release_phase,self.last_release_at=p.phase,now
    if p.drift>22 or now-p.at>1000 then return false end
    if p.phase=="WINNER" then self:dismiss();return true end
    if p.phase=="IDLE" and inside(p.x,p.y,self.start_rect) and inside(x,y,self.start_rect) then
        self:start();return true
    end
    return false
end
function UI:render(s)
    if s.phase~=self.phase then
        self.phase=s.phase
        self.main:set_hidden(s.phase=="WINNER")
        self.winner_layer:set_hidden(s.phase~="WINNER")
        self.start_button:set_disabled(not s.can_start)
        self:_text("button",self.start_button,s.phase=="SPINNING" and "好运转动中…" or "开始抽奖")
        if s.phase=="WINNER" then
            self:_text("winner",self.winner_name,s.winner.name)
            self:_text("winner_id",self.winner_id,string.format("参与编号 %s  ·  第 %02d 轮",s.winner.id,s.round))
            self.pulse_started=s.elapsed_ms
            self.peak_font=math.max(24,math.min(82,math.floor(890/text_units(s.winner.name))))
            log.info("lottery","winner",s.winner.id,s.winner.name,"round",s.round)
        elseif s.phase=="IDLE" then
            self:_rolling(s.last_winner and ("上轮："..s.last_winner.name) or "好运正在等你")
            self:_text("round",self.round_label,s.round>0 and string.format("已完成 %02d 轮 · 可再次抽奖",s.round) or "全员参与 · 点击下方开始")
            self:_text("footer",self.footer,"每轮独立随机 · 同一昵称可以再次中奖")
        elseif s.phase=="SPINNING" then
            self.next_candidate_ms=s.elapsed_ms
            self:_text("round",self.round_label,string.format("第 %02d 轮  /  好运正在靠近…",s.round))
        end
    end
    if s.phase~="WINNER" then
        local rotation=math.floor(s.angle_normalized_deg*10+0.5)%3600
        if rotation~=self.rotation then self.wheel:set_rotation(rotation);self.rotation=rotation end
        if s.phase=="SPINNING" and s.elapsed_ms>=(self.next_candidate_ms or 0) then
            local sector=math.floor(((-90-s.angle_normalized_deg)%360)/s.sector_angle_deg)+1
            local person=self.config.participants[sector]
            self:_rolling(person.name)
            self.next_candidate_ms=s.elapsed_ms+(self.config.candidate_refresh_ms or 120)
        end
    else
        local phase=((s.elapsed_ms-self.pulse_started)%self.config.pulse_period_ms)/self.config.pulse_period_ms
        local size=math.floor(self.peak_font-12+6*(1-math.cos(phase*math.pi*2))+0.5)
        size=math.max(12,size)
        if size~=self.font_size then
            self.winner_name:set_font_size(size)
            self.winner_name:set_pos(48,math.floor(312-size*0.6+0.5))
            self.font_size=size
        end
    end
end
return UI
