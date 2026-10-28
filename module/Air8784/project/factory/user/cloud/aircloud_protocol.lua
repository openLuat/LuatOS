--[[
@module  aircloud_protocol
@summary AirCloud v1 上报/下发协议封装（兼容 SOS 028 后台）
@version 1.0
@date    2026.10.27
@author  王世豪
@usage
- packets() 组装上报字段，大负载自动分片（fragment）
- new(backend,cloud) 创建协议对象，处理 get/set/sos/tts 等命令
- 上报使用 device_id=hmeta.devid()，携带 project/project_version
硬件能力由后端(backend)提供；本模块只做协议编解码。
]]
-- AirCloud v1 envelope compatible with SOS 028; hardware is supplied by backend.
local M={}
local settings=require "aircloud_settings"
local sos=require "sos_config"
local function now()
    local s,us=mcu.ticks2(0);return s*1000+(us or 0)/1000
end
local serial=0
local function base(kind)
    serial=serial+1;local stamp=os.time()
    return {version=1,type=kind,device_id=hmeta.devid(),timestamp=stamp,
        report_id=tostring(stamp).."-"..serial,beijing_time=os.date("!%Y-%m-%d %H:%M:%S",stamp+28800),
        time_valid=stamp>=1735689600,timezone="UTC+08:00",project=PROJECT,project_version=VERSION}
end
local function ascii(value)
    return sos.encode(value):gsub("[\194-\244][\128-\191]+",function(s)
        local a,b,c,d=s:byte(1,4);local n
        if #s==2 then n=(a-192)*64+b-128
        elseif #s==3 then n=(a-224)*4096+(b-128)*64+c-128
        else n=(a-240)*262144+(b-128)*4096+(c-128)*64+d-128 end
        if n<65536 then return string.format("\\u%04x",n) end
        n=n-65536;return string.format("\\u%04x\\u%04x",55296+math.floor(n/1024),56320+n%1024)
    end)
end
function M.packets(value,field,sequence,active,work)
    local payload=ascii(value);local chunks={};local count=#payload<=1100 and 1 or math.ceil(#payload/500)
    for i=1,count do
        local body=payload
        if count>1 then
            local raw=payload:sub((i-1)*500+1,i*500)
            body=json.encode({type="fragment",report_id=value.report_id..(value.section and ":"..value.section or ""),id=value.id,
                part=i,parts=count,encoding="hex",payload=(raw:gsub(".",function(c)return string.format("%02x",c:byte())end))})
        end
        local fields={{field_meaning=field,data_type=field==20 and 3 or 5,value=body}}
        if active and i==1 then
            fields[#fields+1]={field_meaning=265,data_type=0,value=work and 2 or 1}
            if value.time_valid then fields[#fields+1]={field_meaning=1280,data_type=0,value=value.timestamp} end
        end
        chunks[#chunks+1]={fields=fields,sequence=sequence,active=active}
    end
    return chunks
end
function M.new(backend,cloud)
    local api={};local queue,cache,order={}, {}, {}
    local pending_tts={};local reserved=0
    local boot_pending=true;local heartbeat_at=0;local restart_at,submitted_revision,restart_revision
    local connection_since,next_open,failed=nil,0,false
    local function sos_status()
        local st=backend.status()
        local configured=settings.sos_configured()
        return {saved_mode=settings.saved.sos_mode,active_mode=settings.active,
            configured=configured,config_required=not configured,
            message=not configured and (settings.active=="sip_cc" and "桥接号码待配置" or "SOS号码待配置") or nil,
            implemented=true,reboot_pending=settings.pending or false,state=st.connected and "CONNECTED" or (not configured and "CONFIG_REQUIRED" or string.upper(st.state or "IDLE")),
            index=st.index or 0,sip_state=st.sip_state,cc_state=st.cc_state,error=st.error}
    end
    local function unsupported(message) return {supported=false,error="unsupported_feature",message=message} end
    local function section(name)
        local cfg=settings.public()
        if name=="sip" then
            local status=backend.status();status.config_pending=settings.pending or false
            local r={status=status,config=cfg.sip,sos_status=sos_status(),capabilities=settings.capabilities()}
            for k,v in pairs(sos.public(cfg)) do r[k]=v end;return r
        elseif name=="audio" and settings.capabilities(settings.active).audio then
            return {supported=true,config=cfg.audio,status=backend.audio and backend.audio() or {}}
        end
        return unsupported("此项目不支持"..({battery="电池查询",location="定位",audio="本机音频查询"})[name])
    end
    local function snapshot(kind)
        local r=base(kind);r.sip=section("sip");r.battery=section("battery");r.location=section("location");r.audio=section("audio")
        r.sip_status=backend.status();r.sip_status.config_pending=settings.pending or false
        r.audio_status=r.audio.status or r.audio
        r.config=settings.public();r.sos_status=sos_status();r.capabilities=settings.capabilities();return r
    end
    local function enqueue(group,field,seq,revision,active)
        if #queue+reserved>=32 then return false end
        local packets={}
        for _,r in ipairs(group) do for _,p in ipairs(M.packets(r,field,seq,active,backend.status().connected)) do packets[#packets+1]=p end end
        queue[#queue+1]={packets=packets,index=1,revision=revision};return true
    end
    local function response(c,ok,result,err)
        local r=base("response");r.id=c.id;r.cmd=c.cmd;r.ok=ok;r.result=result;r.error=err;return r
    end
    local function remember(id,group,revision)
        if not cache[id] then order[#order+1]=id end
        cache[id]={group=group,revision=revision}
        if #order>32 then cache[table.remove(order,1)]=nil end
    end
    function api.receive(raw,field,seq)
        if type(raw)~="string" then return false end
        if #raw>1396 then
            if #queue<32 then enqueue({response({id="",cmd=""},false,{message="指令超过 1396 字节"},"command_too_large")},field==19 and 20 or 1281,seq) end
            return true
        end
        if field==19 and raw:match("^%s*(.-)%s*$"):lower()=="version" then
            if #queue+reserved>=32 then
                log.warn("aircloud","VERSION_REPLY_QUEUE_FULL")
                return true
            end
            queue[#queue+1]={packets={{fields={{field_meaning=1027,data_type=3,
                value=_G.PROJECT.."_".._G.VERSION}},sequence=seq,active=false}},index=1}
            return true
        end
        local ok,c=pcall(json.decode,raw)
        if not ok or type(c)~="table" or c.cmd==nil then return false end
        local route=field==19 and 20 or 1281
        if type(c.id)~="string" or #c.id<1 or #c.id>64 or c.id:find("[%c]") or type(c.cmd)~="string" then
            enqueue({response({id="",cmd=""},false,nil,"invalid_command")},route,seq);return true
        end
        local read_only=c.cmd=="get_status" or c.cmd=="get_sip_status" or c.cmd=="get_sip_config"
        local cached=pending_tts[c.id] or cache[c.id]
        if not read_only and cached then enqueue(cached.group,route,seq,cached.revision);return true end
        if #queue+reserved>=31 then return true end -- reserve acceptance and completion before side effects
        local group,revision
        if c.cmd=="get_status" then
            group={};local stamp=base("response");stamp.version=2;stamp.sections=4
            for _,name in ipairs({"sip","battery","location","audio"}) do
                local r=sos.copy(stamp);r.id=c.id;r.cmd=c.cmd;r.section=name;r.result=section(name)
                -- Refresh only needs live state. Configuration/capability lists are
                -- available via get_sip_config; including them forced hex fragments.
                if name=="sip" then r.result={status=r.result.status,sos_status=r.result.sos_status} end
                r.ok=r.result.supported~=false;r.error=not r.ok and "unsupported_feature" or nil;group[#group+1]=r
            end
        elseif c.cmd=="get_sip_status" then
            local st=backend.status();st.config_pending=settings.pending or false;st.sos_status=sos_status()
            group={response(c,true,st)}
        elseif c.cmd=="get_sip_config" then
            local cfg=settings.public();cfg.config_pending=settings.pending or false;cfg.sos_status=sos_status();group={response(c,true,cfg)}
        elseif c.cmd=="set_config" then
            local saved,err,detail=settings.update(c.params)
            if saved then
                revision=settings.record.revision
                restart_at=now()+3000;submitted_revision=nil;restart_revision=revision
                group={response(c,true,{config=settings.public(),sos_status=sos_status(),audio_status=section("audio").status or section("audio"),
                    reboot_pending=detail.reboot_pending,apply="Number changes apply to next call; answer settings apply to next incoming call; SIP connection, peer, mode and audio changes require idle reboot"})}
            else group={response(c,false,detail,err)} end
        elseif c.cmd=="play_tts" then
            local speech=require "business_voice"
            if type(c.params)~="table" or not speech.valid_text(c.params.text) then
                group={response(c,false,nil,"invalid_text")}
            elseif not settings.capabilities().tts or not backend.play_tts then
                group={response(c,false,nil,"unsupported_feature")}
            else
                reserved=reserved+1
                local starting=true;local immediate
                local function completed(status,reason)
                    if starting then immediate={status,reason};return end
                    if not pending_tts[c.id] then return end
                    pending_tts[c.id]=nil;reserved=reserved-1
                    local final={response(c,status=="done",{stage="finished",status=status},status~="done" and (reason or status) or nil)}
                    remember(c.id,final)
                    assert(enqueue(final,route,seq))
                end
                local accepted,err,detail=backend.play_tts(c.params.text,completed)
                if accepted then
                    group={response(c,true,{stage="accepted",queued=true})}
                    pending_tts[c.id]={group=group}
                    assert(enqueue(group,route,seq))
                    starting=false
                    if immediate then completed(immediate[1],immediate[2]) end
                    return true
                end
                starting=false;reserved=reserved-1
                group={response(c,false,detail,err or "audio_busy")}
            end
        elseif c.cmd=="get_location" or c.cmd=="speak_battery" then
            group={response(c,false,{message="当前项目不支持该功能",unsupported_fields={c.cmd}},"unsupported_feature")}
        else group={response(c,false,{message="未知指令"},"unknown_command")} end
        if not read_only then
            remember(c.id,group,revision)
        end
        enqueue(group,route,seq,revision);return true
    end
    function api.legacy(value,revision)
        if #queue+reserved>=32 then return false end
        queue[#queue+1]={packets={{fields={{field_meaning=20,data_type=3,value=json.encode(value)}},active=false}},index=1,revision=revision}
        if revision and revision==settings.record.revision and revision~=restart_revision then
            restart_revision=revision;restart_at=now()+3000;submitted_revision=nil
        end
        return true
    end
    function api.event(event,data)
        if event=="message" and type(data)=="table" then
            for _,t in ipairs(data.tlvs or {}) do
                if t.field==19 or t.field==1281 then
                    local seq=data.header and data.header.sequence_num
                    if type(seq)~="number" or seq%1~=0 or seq<0 or seq>65535 then seq=nil end
                    if not api.receive(t.value,t.field,seq) and t.field==19 and backend.legacy then backend.legacy(t.value) end
                end
            end
        elseif event=="send_failed" or (event=="send_result" and data and data.success==false) then failed=true
        elseif event=="auth_result" and data and data.success and backend.auth then backend.auth() end
    end
    function api.step()
        local stamp=now();local status=cloud.status()
        if failed then cloud.close();failed=false;connection_since=nil;next_open=stamp+10000;status=cloud.status() end
        if not socket.adapter(socket.LWIP_GP) then
            if status.is_open then cloud.close() end;connection_since=nil;return
        end
        if not status.is_authenticated then
            if connection_since and not status.is_open then connection_since=nil;next_open=stamp+10000 end
            if connection_since and stamp-connection_since>=30000 then
                cloud.close();connection_since=nil;next_open=stamp+10000
            elseif not connection_since and stamp>=next_open then
                connection_since=stamp
                local opened=cloud.open()
                if not opened then connection_since=nil;next_open=now()+10000 end
            end
            return
        end
        connection_since=nil
        if boot_pending and #queue+reserved<28 then enqueue({snapshot("boot")},1281,nil,nil,true);boot_pending=false end
        -- Full state is fetched by Web get_status, not resent every 30 seconds.
        -- Reuse the existing active-report fields for a small idle keepalive;
        -- any successful business send postpones it, avoiding redundant traffic.
        if not boot_pending and #queue==0 and stamp>=heartbeat_at then
            local fields={{field_meaning=265,data_type=0,value=backend.status().connected and 2 or 1}}
            local timestamp=os.time()
            if timestamp>=1735689600 then fields[#fields+1]={field_meaning=1280,data_type=0,value=timestamp} end
            queue[#queue+1]={packets={{fields=fields,active=true}},index=1}
        end
        local entry=queue[1]
        if entry then
            local p=entry.packets[entry.index]
            if cloud.send(p.fields,p.active==true,false,p.sequence) then
                heartbeat_at=stamp+30000
                entry.index=entry.index+1
                if entry.index>#entry.packets then
                    table.remove(queue,1)
                    if entry.revision==settings.record.revision then submitted_revision=entry.revision end
                end
            end
        end
        if settings.pending and submitted_revision==settings.record.revision and restart_at and stamp>=restart_at and backend.idle() then
            log.info("aircloud","saved configuration submitted; reboot at idle")
            rtos.reboot();restart_at=nil
        end
    end
    function api.start()
        cloud.on(api.event)
        assert(cloud.setup({transport="tcp",use_getip=true,auto_reconnect=false,max_getip_retry=1,
            keep_idle=60,keep_interval=10,keep_cnt=3,debug=false}))
        sys.taskInit(function() while true do api.step();sys.wait(100) end end)
    end
    api.sos_status=sos_status
    return api
end
return M
