--[[
@module  sos_config
@summary SOS 配置校验与协议数据转换
@usage
提供模式、号码列表及映射的校验、归一化和复制功能。
本模块不操作硬件或持久化存储，由各项目配置模块调用。
]]

-- Pure SOS wire validation. No hardware or storage side effects.
local M = {}
M.fields={"sos_mode","sos_sip_numbers","sos_sip_cc_numbers","sos_sip_cc_peers","sos_sip_cc_map","sos_cc_numbers","sos_numbers"}
local modes={sip="sos_sip_numbers",sip_cc="sos_sip_cc_numbers",cc="sos_cc_numbers",sip_grade="sos_numbers"}
function M.copy(v)
    if type(v)~="table" then return v end
    local r={};for k,x in pairs(v) do r[k]=M.copy(x) end;return r
end
function M.empty() return {sos_mode="",sos_sip_numbers={},sos_sip_cc_numbers={},sos_sip_cc_peers={},sos_sip_cc_map={},sos_cc_numbers={},sos_numbers={}} end
function M.is_field(k) for _,f in ipairs(M.fields) do if k==f then return true end end return false end
function M.present(p) for _,f in ipairs(M.fields) do if p[f]~=nil then return true end end return false end
local function array(t,max)
    if type(t)~="table" or #t>max then return false end
    local n=0;for k in pairs(t) do if type(k)~="number" or k%1~=0 or k<1 or k>#t then return false end;n=n+1 end
    return n==#t
end
local function account(s) return type(s)=="string" and #s>0 and #s<=64 and s:match("^[%w%+%*#_.%-]+$")~=nil end
local function phone(s) return type(s)=="string" and #s>0 and #s<=32 and s:match("^%+?%d+$")~=nil end
local function equal(a,b)
    if not array(a,3) or #a~=#b then return false end
    for i,v in ipairs(a) do if v~=b[i] then return false end end;return true
end
function M.normalize(p)
    if not M.present(p) then return nil end
    local mode=p.sos_mode
    if mode==nil then
        for m,f in pairs(modes) do
            if p[f]~=nil then
                if not array(p[f],3) then return nil,"invalid_"..f end
                if #p[f]>0 then if mode then return nil,"ambiguous_sos_mode" end;mode=m end
            end
        end
    end
    if not modes[mode] then return nil,"invalid_sos_mode" end
    local result=M.empty();result.sos_mode=mode
    local selected=modes[mode];local list=p[selected]
    if not array(list,3) or (mode~="sip_grade" and #list==0) then return nil,"invalid_"..selected end
    local seen={}
    for _,n in ipairs(list) do
        if not ((mode=="sip_cc" or mode=="cc") and phone(n) or (mode=="sip" or mode=="sip_grade") and account(n))
            or seen[n] then return nil,"invalid_sos_number" end
        seen[n]=true
    end
    for m,f in pairs(modes) do
        if m~=mode and f~="sos_numbers" and p[f]~=nil and (not array(p[f],3) or #p[f]>0) then return nil,"conflicting_sos_fields" end
    end
    result[selected]=M.copy(list);result.sos_numbers=M.copy(list)
    if mode~="sip_grade" and p.sos_numbers~=nil and not equal(p.sos_numbers,list) then return nil,"sos_mirror_mismatch" end
    if mode=="sip_cc" then
        local peers=p.sos_sip_cc_peers
        if not array(peers,3) or #peers~=#list then return nil,"invalid_sos_sip_cc_peers" end
        local groups,lookup={},{}
        for i,peer in ipairs(peers) do
            if not account(peer) then return nil,"invalid_sos_peer" end
            if not lookup[peer] then local g={peer_sip=peer,numbers={}};lookup[peer]=g;groups[#groups+1]=g end
            table.insert(lookup[peer].numbers,list[i])
        end
        if p.sos_sip_cc_map~=nil then
            if not array(p.sos_sip_cc_map,3) then return nil,"invalid_sos_map" end
            local mapped,peer_seen={},{}
            for _,g in ipairs(p.sos_sip_cc_map) do
                if type(g)~="table" or not account(g.peer_sip) or peer_seen[g.peer_sip]
                    or not array(g.numbers,3) or #g.numbers==0 then return nil,"invalid_sos_map" end
                for k in pairs(g) do if k~="peer_sip" and k~="numbers" then return nil,"invalid_sos_map" end end
                peer_seen[g.peer_sip]=true
                for _,n in ipairs(g.numbers) do
                    if not phone(n) or mapped[n] then return nil,"invalid_sos_map" end
                    mapped[n]=g.peer_sip
                end
            end
            for i,n in ipairs(list) do if mapped[n]~=peers[i] then return nil,"sos_map_mismatch" end;mapped[n]=nil end
            if next(mapped) then return nil,"sos_map_mismatch" end
        end
        result.sos_sip_cc_peers=M.copy(peers);result.sos_sip_cc_map=groups
    else
        for _,f in ipairs({"sos_sip_cc_peers","sos_sip_cc_map"}) do
            if p[f]~=nil and (not array(p[f],3) or #p[f]>0) then return nil,"conflicting_sos_fields" end
        end
    end
    return result
end
function M.public(cfg)
    local r={};for _,f in ipairs(M.fields) do r[f]=M.copy(cfg[f]) end;return r
end
function M.encode(value)
    local encoded=json.encode(value)
    -- LuatOS JSON represents empty Lua tables as objects on some builds.
    -- These protocol fields are arrays even when inactive.
    for _,f in ipairs(M.fields) do
        if f~="sos_mode" then encoded=encoded:gsub('("'..f..'"%s*:%s*){%s*}', '%1[]') end
    end
    return encoded
end
return M
