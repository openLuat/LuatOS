--[[
@module  aircloud_tcp_adapter
@summary AirCloud TCP 业务适配层
@usage
独立环境加载上游原版 excloud，处理 TCP 半包、粘包、连接代次、回复流水号及浮点编码。
仅用于 AirCloud，SIP 传输独立；打包必须包含原版 excloud。
]]

-- Business-only TCP compatibility. The upstream excloud file is loaded unchanged.
-- Luatools discovers dependencies from literal require statements, not loadfile.
-- Declare the dependency without executing a second, non-isolated instance.
if false then
    require "excloud"
end
local M={}
function M.new(path)
    local native=socket
    local proxy=setmetatable({},{__index=native})
    local env=setmetatable({socket=proxy},{__index=_G})
    local raw,api,callback,current,reply_sequence,sending
    local timeout=30000
    local scheduler=setmetatable({},{__index=sys})
    env.sys=scheduler
    function scheduler.subscribe(event,fn,...)
        -- Business owns reconnect/backoff and shutdown gates. Do not let the
        -- original library's IP_READY hook bypass those gates.
        if event=="IP_READY" then return end
        return sys.subscribe(event,fn,...)
    end
    function scheduler.timerStart(fn,ms,...)
        local rec=current
        local args=table.pack(...)
        return sys.timerStart(function()
            if rec and (current~=rec or rec.dead) then return end
            fn(table.unpack(args,1,args.n))
        end,ms)
    end
    local function emit(event,data)
        if callback then callback(event,data) end
    end
    local function detach(rec)
        if not rec or rec.dead then return end
        rec.dead=true;rec.pending=""
        if rec.timer then sys.timerStop(rec.timer);rec.timer=nil end
    end
    local function fail(rec,reason,event)
        if current~=rec or rec.dead then return end
        local online=rec.online
        detach(rec)
        raw.close()
        emit(event or (online and "disconnect" or "connect_result"),{success=false,error=reason})
    end
    function proxy.create(adapter,cb)
        local rec={pending=""};current=rec
        local h=native.create(adapter,function(netc,event,param)
            if current~=rec or rec.dead then return end
            if event==native.LINK then return end -- LINK is not a completed connection.
            if event==native.CLOSED or (event==native.ON_LINE and param~=0) then
                fail(rec,"socket ended: "..tostring(param));return
            end
            if event==native.TX_OK and param and param~=0 then
                fail(rec,"send failed: "..tostring(param),"send_failed");return
            end
            if event==native.ON_LINE then
                rec.online=true
                if rec.timer then sys.timerStop(rec.timer);rec.timer=nil end
            elseif event==native.EVENT then
                local b=rec.buffer
                local ok=native.rx(netc,b)
                if ok==false then fail(rec,"receive failed");return end
                rec.pending=rec.pending..(b:used()>0 and b:query() or "")
                b:del()
                while #rec.pending>=16 do
                    local n=rec.pending:byte(11)*256+rec.pending:byte(12)
                    if n>1400 then fail(rec,"invalid TCP body length");return end
                    if #rec.pending<16+n then break end
                    rec.packet=rec.pending:sub(1,16+n)
                    rec.pending=rec.pending:sub(17+n)
                    cb(netc,event,param)
                    rec.packet=nil
                    if current~=rec or rec.dead then return end
                end
                native.wait(netc);return
            end
            cb(netc,event,param)
        end)
        rec.handle=h
        if h then
            rec.buffer=zbuff.create(2048)
            if not rec.buffer then
                detach(rec);native.close(h);native.release(h);return nil
            end
        else detach(rec) end
        return h
    end
    function proxy.connect(h,...)
        local rec=current
        rec.timer=sys.timerStart(function() fail(rec,"TCP connect timeout") end,timeout)
        local ok,reason=native.connect(h,...)
        if rec.dead then return false,"connection ended during connect" end
        return ok,reason
    end
    function proxy.rx(_,b)
        local packet=current.packet or ""
        b:del()
        -- zbuff.write only advances cursor; copy updates used(), which the
        -- original parser reads. del() does not reset the write cursor.
        return b:copy(0,packet)==#packet
    end
    function proxy.close(h)
        if not h then return end
        if current and current.handle==h then
            detach(current)
            if current.closed then return end
            current.closed=true
        end
        return native.close(h)
    end
    function proxy.release(h)
        if not h then return end
        if current and current.handle==h then
            detach(current)
            if current.released then return end
            current.released=true
        end
        return native.release(h)
    end
    function proxy.tx(h,data,...)
        if type(data)~="string" or #data<16 or #data-16>1400 then return false,"invalid TCP frame length" end
        if reply_sequence~=nil then data=data:sub(1,8)..string.pack(">I2",reply_sequence)..data:sub(11) end
        return native.tx(h,data,...)
    end
    local loader,err
    if path then
        loader,err=loadfile(path,"bt",env)
    else
        -- LuatOS uses a custom require searcher, not necessarily package.path.
        -- Luatools normally stores compiled scripts with the .luac suffix.
        local candidates={"/luadb/excloud.luac","/luadb/excloud.lua",
            "/excloud.luac","/excloud.lua","/lua/excloud.luac","/lua/excloud.lua"}
        local found=package and package.searchpath and type(package.path)=="string"
            and package.searchpath("excloud",package.path)
        if found then candidates[#candidates+1]=found end
        for _,candidate in ipairs(candidates) do
            loader,err=loadfile(candidate,"bt",env)
            if loader then break end
        end
    end
    assert(loader,"excloud missing or incompatible; include original excloud.lua in Luatools script files: "..tostring(err))
    raw=loader()
    api=setmetatable({},{__index=raw})
    local build=raw.build_tlv
    -- Override the isolated instance's public codec, never the upstream source.
    raw.build_tlv=function(field,kind,value)
        if kind==1 then
            if type(field)~="number" or type(value)~="number" then return false,"invalid float TLV" end
            return true,string.pack(">I2I2f",0x1000+field%0x1000,4,value)
        end
        return build(field,kind,value)
    end
    local parse=raw.parse_tlv
    local function fix_float(t)
        if t and t.type==1 and type(t.raw_value)=="string" and #t.raw_value==4 then
            t.value=string.unpack(">f",t.raw_value)
        end
        return t
    end
    raw.parse_tlv=function(...)
        local t,pos,reason=parse(...);return fix_float(t),pos,reason
    end
    raw.on(function(event,data)
        if event=="message" and data then for _,t in ipairs(data.tlvs or {}) do fix_float(t) end end
        if event=="send_result" and data and reply_sequence~=nil then data.sequence_num=reply_sequence end
        if event=="connect_result" and data and data.success==false then
            if current then detach(current) end
            raw.close()
        end
        emit(event,data)
    end)
    function api.on(fn) callback=fn end
    function api.setup(params)
        if params and params.transport and params.transport~="tcp" then return false,"TCP only" end
        local p={};for k,v in pairs(params or {}) do p[k]=v end
        p.transport="tcp";p.auto_reconnect=false
        timeout=(tonumber(p.timeout) or 30)*1000
        return raw.setup(p)
    end
    function api.status()
        local s=raw.status();s.transport="tcp"
        if current and current.dead then s.is_connected=false;s.is_authenticated=false end
        return s
    end
    function api.open()
        if current and current.dead and raw.status().is_open then raw.close() end
        return raw.open()
    end
    function api.close()
        detach(current);return raw.close()
    end
    function api.send(fields,need_reply,is_auth,sequence)
        if sequence~=nil and (type(sequence)~="number" or sequence%1~=0 or sequence<0 or sequence>65535) then
            return false,"invalid reply sequence"
        end
        if sending then return false,"reentrant send" end
        sending=true;reply_sequence=sequence
        local ok,result,reason=pcall(raw.send,fields,need_reply,is_auth)
        reply_sequence=nil;sending=false
        if not ok then return false,tostring(result) end
        return result,reason
    end
    return api
end
-- Lazy singleton: business scripts use the same interface as excloud.
local instance
return setmetatable(M,{__index=function(_,key)
    if not instance then instance=M.new() end
    return instance[key]
end})
