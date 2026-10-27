--[[
@module  aircloud_protocol
@summary AirCloud JSON 指令与回执协议
@usage
处理状态查询、配置保存、升级检查、请求去重及分片回执。
管理 TCP 连接和鉴权重试；配置重启需等待回执提交及设备空闲。
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
    local boot_pending=true;local periodic_at=0;local restart_at,submitted_revision,restart_revision
    local reboot_called=false;local last_wait
    local function check_restart(stamp)
        if reboot_called or not settings.pending then return end
        local reason
        if submitted_revision~=settings.record.revision or not restart_at then reason="response_not_submitted"
        elseif stamp<restart_at then reason="response_grace_period"
        else
            local idle,why=backend.idle()
            if not idle then reason=why or "call_or_media_busy" end
        end
        if reason then
            if reason~=last_wait then log.info("aircloud","reboot waiting",reason);last_wait=reason end
            return
        end
        reboot_called=true
        log.info("aircloud","saved configuration submitted; reboot at idle",settings.reboot_reason)
        rtos.reboot()
    end
    local connection_since,next_open,failed=nil,0,false
    local function current_status()
        local st=backend.status()
        st.config_pending=settings.pending or false
        st.reboot_pending=settings.pending or false
        st.reboot_reason=settings.reboot_reason
        return st
    end
    local function sos_status()
        local st=backend.status()
        local configured=settings.sos_configured()
        return {saved_mode=settings.saved.sos_mode,active_mode=settings.active,
            configured=configured,config_required=not configured,
            message=not configured and (settings.active=="sip_cc" and "桥接号码待配置" or "SOS号码待配置") or nil,
            implemented=true,reboot_pending=settings.pending or false,reboot_reason=settings.reboot_reason,state=st.connected and "CONNECTED" or (not configured and "CONFIG_REQUIRED" or string.upper(st.state or "IDLE")),
            index=st.index or 0,sip_state=st.sip_state,cc_state=st.cc_state,error=st.error}
    end
    local function unsupported(message) return {supported=false,error="unsupported_feature",message=message} end
    local function section(name)
        local cfg=settings.public()
        if name=="sip" then
            local r={status=current_status(),config=cfg.sip,sos_status=sos_status(),capabilities=settings.capabilities()}
            for k,v in pairs(sos.public(cfg)) do r[k]=v end;return r
        elseif name=="audio" and settings.capabilities(settings.active).audio then
            return {supported=true,config=settings.boot.audio,status=backend.audio and backend.audio() or {}}
        end
        return unsupported("此项目不支持"..({battery="电池查询",location="定位",audio="本机音频查询"})[name])
    end
    local function snapshot(kind)
        local r=base(kind);r.sip=section("sip");r.battery=section("battery");r.location=section("location");r.audio=section("audio")
        r.sip_status=current_status()
        r.audio_status=r.audio
        r.config=settings.public();r.sos_status=sos_status();r.capabilities=settings.capabilities();return r
    end
    local function enqueue(group,field,seq,revision,active)
        if #queue>=32 then return false end
        local packets={}
        for _,r in ipairs(group) do for _,p in ipairs(M.packets(r,field,seq,active,backend.status().connected)) do packets[#packets+1]=p end end
        queue[#queue+1]={packets=packets,index=1,revision=revision};return true
    end
    local function response(c,ok,result,err)
        local r=base("response");r.id=c.id;r.cmd=c.cmd;r.ok=ok;r.result=result;r.error=err;return r
    end
    local legacy_ota_serial=0
    function api.receive(raw,field,seq)
        if type(raw)~="string" then return false end
        if #raw>1396 then
            if #queue<32 then enqueue({response({id="",cmd=""},false,{message="指令超过 1396 字节"},"command_too_large")},field==19 and 20 or 1281,seq) end
            return true
        end
        if field==19 and raw:match("^%s*(.-)%s*$"):lower()=="version" then
            if #queue>=32 then
                log.warn("aircloud","VERSION_REPLY_QUEUE_FULL")
                return true
            end
            queue[#queue+1]={packets={{fields={{field_meaning=1027,data_type=3,
                value=_G.PROJECT.."_".._G.VERSION}},sequence=seq,active=false}},index=1}
            return true
        end
        local ok,c=pcall(json.decode,raw)
        -- Tag19 legacy commands used by the TCP platform, matching 8784.
        if field==19 and (not ok or type(c)~="table" or c.cmd==nil) then
            local op=ok and type(c)=="table" and (c.op or c.type or c.command)
                or raw:match("^%s*(.-)%s*$"):lower()
            if op=="fota" or op=="update" then
                legacy_ota_serial=legacy_ota_serial+1
                c={id="legacy-ota-"..legacy_ota_serial,cmd=op};ok=true
            end
        end
        if not ok or type(c)~="table" or c.cmd==nil then return false end
        local route=field==19 and 20 or 1281
        if type(c.id)~="string" or #c.id<1 or #c.id>64 or c.id:find("[%c]") or type(c.cmd)~="string" then
            enqueue({response({id="",cmd=""},false,nil,"invalid_command")},route,seq);return true
        end
        if cache[c.id] then enqueue(cache[c.id].group,route,seq,cache[c.id].revision);return true end
        if #queue>=31 then return true end -- no mutations without a reserved response slot
        local group,revision
        if c.cmd=="get_status" then
            group={};local stamp=base("response");stamp.version=2;stamp.sections=4
            for _,name in ipairs({"sip","battery","location","audio"}) do
                local r=sos.copy(stamp);r.id=c.id;r.cmd=c.cmd;r.section=name;r.result=section(name)
                r.ok=r.result.supported~=false;r.error=not r.ok and "unsupported_feature" or nil;group[#group+1]=r
            end
        elseif c.cmd=="update" or c.cmd=="fota" then
            local accepted,err=require("update").check_update()
            group={response(c,accepted,{stage="check_requested"},err)}
        elseif c.cmd=="get_sip_status" then
            local st=current_status();st.sos_status=sos_status();st.capabilities=settings.capabilities()
            group={response(c,true,st)}
        elseif c.cmd=="get_sip_config" then
            local cfg=settings.public();cfg.config_pending=settings.pending or false;cfg.reboot_pending=settings.pending or false
            cfg.reboot_reason=settings.reboot_reason;cfg.sos_status=sos_status();group={response(c,true,cfg)}
        elseif c.cmd=="set_config" then
            local saved,err,detail=settings.update(c.params)
            if saved then
                revision=settings.record.revision
                restart_at=nil;submitted_revision=nil;restart_revision=revision;last_wait=nil
                if settings.pending then log.info("aircloud","reboot requested",settings.reboot_reason,revision) end
                group={response(c,true,{config=settings.public(),sos_status=sos_status(),audio_status=section("audio"),
                    reboot_pending=detail.reboot_pending,reboot_reason=detail.reboot_reason,apply="SIP connection submissions require idle reboot; number changes apply to next call"})}
            else group={response(c,false,detail,err)} end
        elseif c.cmd=="get_location" or c.cmd=="speak_battery" or c.cmd=="play_tts" then
            group={response(c,false,{message="当前项目不支持该功能",unsupported_fields={c.cmd}},"unsupported_feature")}
        else group={response(c,false,{message="未知指令"},"unknown_command")} end
        cache[c.id]={group=group,revision=revision};order[#order+1]=c.id
        if #order>32 then cache[table.remove(order,1)]=nil end
        enqueue(group,route,seq,revision);return true
    end
    function api.legacy(value,revision)
        if #queue>=32 then return false end
        queue[#queue+1]={packets={{fields={{field_meaning=20,data_type=3,value=json.encode(value)}},active=false}},index=1,revision=revision}
        if revision and revision==settings.record.revision and revision~=restart_revision then
            restart_revision=revision;restart_at=nil;submitted_revision=nil;last_wait=nil
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
        check_restart(stamp)
        if reboot_called then return end
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
        if boot_pending and #queue<28 then enqueue({snapshot("boot")},1281,nil,nil,true);boot_pending=false;periodic_at=stamp+30000 end
        if stamp>=periodic_at and #queue<28 then enqueue({snapshot("status")},1281,nil,nil,true);periodic_at=stamp+30000 end
        local entry=queue[1]
        if entry then
            local p=entry.packets[entry.index]
            if cloud.send(p.fields,p.active==true,false,p.sequence) then
                entry.index=entry.index+1
                if entry.index>#entry.packets then
                    table.remove(queue,1)
                    if entry.revision and entry.revision==settings.record.revision and submitted_revision~=entry.revision then
                        submitted_revision=entry.revision;restart_at=stamp+3000
                        if settings.pending then log.info("aircloud","configuration response submitted; reboot grace period",entry.revision) end
                    end
                end
            end
        end
        check_restart(stamp)
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
