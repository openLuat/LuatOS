--[[
@module  aircloud_settings
@summary SIP 与 SOS 配置持久化后端
@usage
校验云端参数并保存配置，生成公开配置、能力及待重启状态。
接听偏好属于兼容存储字段，不应理解为当前 PCM 业务已经实现对应行为。
]]

-- PCM project configuration backend; answer preferences are storage-only.
local M = {}
local sos = require "sos_config"
local copy = sos.copy
local fields = {sip_server_addr=253,sip_domain=253,sip_username=128,sip_password=128,
    sip_server_port=true,sip_transport=true}
local compatibility={auto_answer=true,delay_auto_answer=true}
local compatibility_fields={"sip.auto_answer","sip.delay_auto_answer"}
local compatibility_message="接听设置已保存；当前 PCM 桥接模式不应用这些设置，仍按原桥接流程接听。"
local function connection(sip)
    local out={};for k,v in pairs(sip) do if not compatibility[k] then out[k]=v end end;return out
end
local function same(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a) do if not same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local function text(s,max,empty)
    if type(s)~="string" or #s>max or (not empty and #s==0) or s:find("[%c]") then return false end
    -- Strict UTF-8, including overlongs, surrogates and > U+10FFFF.
    local i=1
    while i<=#s do
        local a,b,c,d=s:byte(i,i+3); local n=1
        if a>=128 then
            if a>=194 and a<=223 then n=2
            elseif a>=224 and a<=239 then n=3
            elseif a>=240 and a<=244 then n=4 else return false end
            for j=1,n-1 do local x=s:byte(i+j);if not x or x<128 or x>191 then return false end end
            if (a==224 and b<160) or (a==237 and b>=160) or (a==240 and b<144) or (a==244 and b>143) then return false end
        end
        i=i+n
    end
    return true
end
local function integer(n,lo,hi) return type(n)=="number" and n%1==0 and n>=lo and n<=hi end
M.same=same
function M.init(platform,flat)
    if M.platform then return M end
    assert(fskv and fskv.init(),"fskv unavailable")
    M.platform=platform;M.flat=flat
    M.key=platform=="8784" and "sip_task_v1" or "aircloud_pcm_v1"
    local value=fskv.get(M.key) -- native API may return zero values
    M.record=type(value)=="table" and copy(value) or {revision="0",boot_count=0}
    M.migration_warning=M.record.migration_warning
    if platform=="8784" and M.record.runtime_mode~="single" and M.record.runtime_mode~="phone" then
        M.record.runtime_mode=type(M.record.task)=="table" and M.record.task.mode~="phone" and "single" or "phone"
    end
    if type(M.record.revision)~="string" then
        M.record.migration_original=copy(M.record);M.record.revision="0"
        M.migration_warning="???????????????"
    end
    M.switchable=platform=="8784" and cc and type(cc.setBridge)=="function" and rtos and type(rtos.reboot)=="function" or false
    local cfg=sos.empty();cfg.sip={};cfg.audio={}
    for k in pairs(fields) do cfg.sip[k]=flat[k] end
    if platform=="8784" then
        cfg.audio={volume=M.record.runtime_mode=="single" and 31 or (flat.air1103_volume or 20),mic_gain=2}
        if M.record.unified then cfg=copy(M.record.unified)
        else cfg=M.from_legacy(M.record,cfg) end
    elseif M.record.unified then cfg=copy(M.record.unified)
    else
        local peer=(flat.remote_sip_uri or ""):match("^sip:([^@]+)@")
        local normalized=sos.normalize({sos_mode="sip_cc",sos_sip_cc_numbers={flat.target_phone_number},sos_sip_cc_peers={peer}})
        if normalized then for k,v in pairs(normalized) do cfg[k]=v end
        else M.migration_warning="现有桥接映射不能完整转换，保留原始配置" end
    end
    M.saved=cfg;M.boot=copy(cfg);M.applied=copy(cfg)
    for k,v in pairs(connection(cfg.sip)) do flat[k]=v end
    if cfg.sos_mode=="sip_cc" and cfg.sos_sip_cc_peers[1] then
        flat.remote_sip_uri="sip:"..cfg.sos_sip_cc_peers[1].."@"..(flat.sip_domain~="" and flat.sip_domain or flat.sip_server_addr)
        flat.target_phone_number=cfg.sos_sip_cc_numbers[1]
    end
    if platform=="8784" then flat.air1103_volume=cfg.audio.volume end
    M.active=platform=="8784" and (M.switchable and M.record.runtime_mode=="single" and "sip" or "sip_cc") or "sip_cc"
    M.record.unified=copy(cfg);M.record.unified_version=1;M.record.migration_warning=M.migration_warning
    return M
end
function M.from_legacy(record,base)
    local cfg=copy(base);for k,v in pairs(sos.empty()) do cfg[k]=v end
    cfg.sos_mode=record.runtime_mode=="single" and "sip" or "sip_cc"
    local task=record.task
    if not task then return cfg end
    if type(task)~="table" or type(task.targets)~="table" then
        M.migration_warning="??????????????????";return cfg
    end
    local p={sos_mode=task.mode=="phone" and "sip_cc" or "sip"}
    local targets=copy(task.targets or {})
    if p.sos_mode=="sip" then
        for i,n in ipairs(targets) do
            if type(n)~="string" then M.migration_warning="???????????????";return cfg end
            if not task.account_targets then targets[i]=#n==16 and n or n.."0" end
        end
        p.sos_sip_numbers=targets
    else
        p.sos_sip_cc_numbers=targets;p.sos_sip_cc_peers={}
        local peer=(base.sos_sip_cc_peers or {})[1] or (M.flat.remote_sip_uri or ""):match("^sip:([^@]+)@")
        for i in ipairs(targets) do p.sos_sip_cc_peers[i]=peer end
    end
    local normalized=sos.normalize(p)
    if normalized then for k,v in pairs(normalized) do cfg[k]=v end
    else M.migration_warning="旧任务不能完整转换，原任务记录仍保留" end
    return cfg
end
function M.persist(record)
    local ok,result=pcall(fskv.set,M.key,record)
    if not ok or not result then return false end
    M.record=copy(record);M.saved=copy(record.unified);return true
end
function M.legacy_write(record)
    local next_record=copy(record)
    next_record.unified=M.from_legacy(record,M.saved)
    next_record.unified_version=1;next_record.migration_warning=M.migration_warning
    if not M.persist(next_record) then return false end
    -- The task engine must retain the same authoritative payload.
    record.unified=copy(next_record.unified);record.unified_version=1
    return true
end
function M.capabilities(mode)
    mode=mode or M.saved.sos_mode
    local writable={"sip.sip_server_addr","sip.sip_server_port","sip.sip_domain","sip.sip_username","sip.sip_password","sip.sip_transport"}
    for _,f in ipairs(compatibility_fields) do writable[#writable+1]=f end
    for _,f in ipairs(sos.fields) do writable[#writable+1]=f end
    if M.platform=="8784" and mode=="sip" then writable[#writable+1]="audio.volume";writable[#writable+1]="audio.mic_gain" end
    return {commands={"get_sip_status","get_sip_config","get_status","set_config","update","fota"},
        unsupported_commands={"get_location","speak_battery","play_tts"},writable_fields=writable,
        modes=M.switchable and {"sip","sip_cc"} or {"sip_cc"},max_targets=M.platform=="8784" and 3 or 1,
        max_sip_peers=1,keys=M.platform=="8784",outgoing_sos=M.platform=="8784",
        audio=M.platform=="8784" and mode=="sip",battery=false,location=false,tts=false,
        migration_warning=M.migration_warning,compatibility_only_fields=copy(compatibility_fields),
        compatibility_message="接听设置仅兼容保存；当前 PCM 桥接模式仍按原桥接流程接听。"}
end
function M.public()
    local out=copy(M.saved);out.sip.sip_password=nil
    out.compatibility_only_fields=copy(compatibility_fields)
    if out.sip.auto_answer~=nil or out.sip.delay_auto_answer~=nil then out.compatibility_message=compatibility_message end
    if M.platform~="8784" or out.sos_mode~="sip" then out.audio={supported=false,error="unsupported_feature"} end
    out.capabilities=M.capabilities();return out
end
-- Configuration readiness is separate from SIP registration readiness.
function M.sos_configured()
    local cfg=sos.normalize(sos.public(M.saved))
    if not cfg then return false end
    if cfg.sos_mode=="sip" then return M.switchable==true end
    if cfg.sos_mode~="sip_cc" or #cfg.sos_sip_cc_numbers>(M.platform=="8784" and 3 or 1) then return false end
    for _,peer in ipairs(cfg.sos_sip_cc_peers) do
        if peer~=cfg.sos_sip_cc_peers[1] then return false end
    end
    return true
end
local revision_seq=0
function M.update(p)
    if type(p)~="table" or next(p)==nil then return false,"empty_config" end
    local normalized,err=sos.normalize(p)
    if err then
        local message=err=="invalid_sos_number" and "SOS 号码必须为有效且不重复的字符串；同一手机号不能重复映射多个 SIP 对端。"
            or "SOS 配置无效，请检查号码列表、模式及对应映射。"
        return false,err,{message=message}
    end
    local mode=normalized and normalized.sos_mode or M.saved.sos_mode
    local unsupported={}
    -- A SIP-only save must not validate an unconfigured or legacy SOS record.
    if normalized and mode~="sip_cc" and not (mode=="sip" and M.switchable) then unsupported[#unsupported+1]="sos_mode" end
    if normalized and mode=="sip_cc" then
        local ns,ps=normalized.sos_sip_cc_numbers,normalized.sos_sip_cc_peers
        if #ns>(M.platform=="8784" and 3 or 1) then unsupported[#unsupported+1]="sos_sip_cc_numbers" end
        for _,peer in ipairs(ps) do if peer~=ps[1] then unsupported[#unsupported+1]="sos_sip_cc_peers";break end end
    end
    for k,v in pairs(p) do
        if k=="sip" then
            if type(v)~="table" or next(v)==nil then return false,"invalid_sip" end
            for n,x in pairs(v) do
                if n=="auto_answer" then
                    if type(x)~="boolean" then return false,"invalid_auto_answer" end
                elseif n=="delay_auto_answer" then
                    if not integer(x,0,20) then return false,"invalid_delay_auto_answer" end
                elseif not fields[n] then unsupported[#unsupported+1]="sip."..tostring(n)
                elseif n=="sip_server_port" then if not integer(x,1,65535) then return false,"invalid_sip_server_port" end
                elseif n=="sip_transport" then if x~="udp" and x~="tcp" and x~="tls" then return false,"invalid_transport" end
                elseif not text(x,fields[n],n=="sip_domain") then return false,"invalid_"..n end
            end
        elseif k=="audio" then
            if type(v)~="table" or next(v)==nil then return false,"invalid_audio" end
            for n,x in pairs(v) do
                if M.platform~="8784" or mode~="sip" or (n~="volume" and n~="mic_gain") then unsupported[#unsupported+1]="audio."..tostring(n)
                elseif not integer(x,n=="volume" and 0 or 1,n=="volume" and 31 or 8) then return false,"invalid_"..n end
            end
        elseif not sos.is_field(k) then unsupported[#unsupported+1]=tostring(k) end
    end
    if #unsupported>0 then
        table.sort(unsupported)
        local mapping=false;for _,f in ipairs(unsupported) do if f=="sos_sip_cc_numbers" or f=="sos_sip_cc_peers" then mapping=true end end
        return false,"unsupported_feature",{message=mapping and "8783H 当前仅支持一个手机号对应一个 SIP 对端，不能配置多组映射。" or "当前项目或音频模式不支持这些配置",unsupported_fields=unsupported,mode=mode}
    end
    local cfg=copy(M.saved)
    if normalized then for k,v in pairs(normalized) do cfg[k]=v end end
    for _,section in ipairs({"sip","audio"}) do for k,v in pairs(p[section] or {}) do cfg[section][k]=v end end
    local next_record=copy(M.record);next_record.unified=cfg;next_record.unified_version=1
    revision_seq=revision_seq+1
    next_record.revision=string.format("%08x-0000-0000-0000-%012x",os.time(),revision_seq)
    next_record.last_req=nil
    if M.platform=="8784" and normalized then
        next_record.runtime_mode=mode=="sip" and "single" or "phone"
        next_record.task={imei=mobile.imei(),wait=30,name64="",mode=mode=="sip" and "round" or "phone",account_targets=true,
            targets=copy(mode=="sip" and cfg.sos_sip_numbers or cfg.sos_sip_cc_numbers)}
        next_record.announcement_pending=false
    end
    if normalized then next_record.migration_warning=nil end
    if not M.persist(next_record) then return false,"storage_failed" end
    if normalized then M.migration_warning=nil end
    -- Only the next incoming call reads this number; existing calls hold their own copy.
    if M.platform~="8784" and same(connection(cfg.sip),connection(M.boot.sip)) and same(cfg.sos_sip_cc_peers,M.boot.sos_sip_cc_peers) then
        M.flat.target_phone_number=cfg.sos_sip_cc_numbers[1]
    end
    local mode_changed=(mode=="sip_cc" or (mode=="sip" and M.switchable)) and mode~=M.active
    M.configuration_changed=mode_changed or not same(connection(cfg.sip),connection(M.boot.sip)) or not same(cfg.audio,M.boot.audio)
        or not same(cfg.sos_sip_cc_peers,M.boot.sos_sip_cc_peers)
    -- Latch only after successful persistence. Later number/preferences saves cannot cancel it.
    for k in pairs(p.sip or {}) do
        if fields[k] then M.sip_restart_requested=true end
    end
    M.pending=M.sip_restart_requested or M.configuration_changed
    M.reboot_reason=M.sip_restart_requested and "sip_settings_submitted"
        or (M.configuration_changed and "configuration_changed" or nil)
    if not M.pending then M.applied=copy(cfg) end
    if M.on_saved then M.on_saved() end
    return true,nil,{reboot_pending=M.pending or false,reboot_reason=M.reboot_reason}
end
return M
