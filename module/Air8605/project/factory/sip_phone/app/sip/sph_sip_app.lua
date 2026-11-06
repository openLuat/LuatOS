-- SIP_APP account/call/message coordinator. UI entry points never yield.
local store = require "sph_store"
local audio = require "sph_audio_app"
local net = require "sph_net_app"
local engine = require "sph_sipapp_exsip"
local client = require "sph_sipapp_client"
local M = {}
local wanted, worker, initialized = false, false, false
local generation, epoch = 0, 0
local registered, pending, call, reconnect = false, nil, nil, false
local S = {state="idle",detail="",user="",since=0,muted=false}
local function elapsed_clock()
    if mcu and mcu.ticks2 then
        local seconds,micros=mcu.ticks2(0)
        return seconds+(micros or 0)/1000000
    end
    return os.time()
end
local function emit_error(text) sys.publish("SIP_ERROR",text); return false,text end
local function online() return net.is_up() end
-- Called by the visible call timer: no contacts/messages/fskv reads.
function M.call_duration()
    if not call or not call.connected_tick then return nil end
    return math.max(0,math.floor(elapsed_clock()-call.connected_tick))
end
function M.status()
    local t={}; for k,v in pairs(S) do t[k]=v end
    t.registered=registered; t.mic=audio.is_ready(); t.audio_verified=store.is_audio_verified()
    t.duration=M.call_duration() or 0
    t.name=S.peer and store.find_name(S.peer); return t
end
local function state(value,detail)
    S.state=value; if detail then S.detail=detail end
    sys.publish("SIP_STATE",M.status())
end
local function idle_state() return registered and "ready" or (wanted and "connecting" or "idle") end
local function finish_message(status,reason)
    if not pending then return end
    local id=pending.id; pending=nil
    local ok,err=store.update_msg(id,status,reason)
    if not ok then emit_error(err) end
    sys.publish("SIP_MSG",{id=id,status=status,reason=reason})
end
local function record(result)
    if not call or call.logged then return end
    call.logged=true
    local duration=call.connected_tick and math.max(0,math.floor(elapsed_clock()-call.connected_tick)) or 0
    local ok,err=store.add_call({num=call.peer,dir=call.direction,ts=call.ts,dur=duration,
        result=result or (call.direction=="out" and "dialed" or (call.connected and "answered" or "missed"))})
    if not ok then emit_error(err) end
    sys.publish("SIP_CALL_LOGGED")
end
local function clear_call(result)
    if not call then return end
    record(result)
    audio.stop_ringback(true); audio.stop()
    call=nil; S.peer=nil; S.direction=nil; S.since=0; S.muted=false
    if audio.set_mute then pcall(audio.set_mute,false) end
    local ok,err=audio.play_hangup()
    if not ok then log.warn("sip_app","hangup tone unavailable",err) end
end
local function audio_gate()
    local ok,diag=pcall(require,"sph_audio_diag")
    if ok and diag.status().busy then return false,"正在执行音频诊断，请稍候" end
    if not store.is_audio_verified() then return false,"请先完成音频自检并确认听到声音" end
    if not audio.is_ready() then return false,"音频尚未就绪，请检查麦克风和语音芯片" end
    return true
end
local function user(value)
    if type(value)~="string" then return "" end
    return value:match("[sS][iI][pP]:([^@>;%s]+)") or value
end
local function call_matches(data)
    if not call then return false end
    if not call.id then return false end
    if data.call_id and call.id and data.call_id~=call.id then return false end
    if data.call_id then call.id=data.call_id end
    return true
end
local function on_event(token,event,action,data)
    if token~=epoch or not wanted then return end
    data=type(data)=="table" and data or {}
    if event=="register" then
        if action=="ok" then
            registered=true; store.set_logged(true)
            if not call then state("ready","注册成功") end
        elseif action~="challenge" then
            registered=false; store.set_logged(false); reconnect=true
            clear_call(); finish_message("unknown","注册失效，发送结果未知")
            state("connecting","注册失败，请检查账号或网络")
        end
    elseif event=="lifecycle" and (action=="offline" or action=="stopped") then
        registered=false; store.set_logged(false); reconnect=true
        clear_call(); finish_message("unknown","连接中断，发送结果未知")
        state("connecting","连接断开，等待重连")
    elseif event=="call" then
        if action=="incoming" then
            if call then return end
            call={id=data.call_id,peer=user(data.from),direction="in",ts=os.time()}
            S.peer=call.peer; S.direction="in"; S.since=call.ts
            local ok,err=audio_gate()
            if not ok then
                record("rejected"); engine.fail(480,"Audio unavailable"); state("ending",err); return
            end
            state("incoming","来电")
            -- 同拨号：先让 UI 把通话层建出来，再起铃声，避免起播点被整屏重建抽干。
            local ringing=call
            sys.timerStart(function()
                if token~=epoch or call~=ringing or S.state~="incoming" then return end
                local ok,err=audio.play_ringback_loop()
                if not ok then log.warn("sip_app","incoming tone unavailable",err) end
            end,100)
            if store.get_acct().auto_answer then
                local incoming=call
                sys.timerStart(function() if token==epoch and call==incoming and S.state=="incoming" then M.answer() end end,1000)
            end
        elseif action=="dialing" and call and call.direction=="out" and not call.id then
            call.id=data.call_id
        elseif action=="dial_rejected" and call and call.direction=="out" and not call.id then
            clear_call(); state(idle_state(),"呼出失败: "..tostring(data.reason))
        elseif call_matches(data) then
            if action=="ringing" then
                -- The client emits ringing for both inbound and outbound calls.
                -- Only advance an outgoing call that is still dialing; never
                -- replace incoming/answering/talking with the outgoing UI.
                if call.direction=="out" and S.state=="dialing" then
                    state("dialing","对方响铃中")
                end
            elseif action=="connected" or action=="established" then
                call.connected=call.connected or os.time()
                call.connected_tick=call.connected_tick or elapsed_clock()
                audio.stop_ringback(true)
                S.since=call.connected; state("talking","通话中")
            elseif action=="ended" or action=="failed" then clear_call(); state(idle_state(),"通话结束") end
        end
    elseif event=="media" and action=="ready" then
        -- This notification precedes asynchronous bridge startup. Verify later against the same call.
        local active=call
        sys.timerStart(function()
            if token~=epoch or call~=active or not call then return end
            if not audio.is_bridge_ok() then
                emit_error("音频桥启动失败，已结束通话")
                engine.hangUp(); state("ending","音频异常")
            end
        end,2000)
    elseif event=="message" then
        if action=="rx" then
            local num,text=user(data.from),data.body or data.text or ""
            local ok,id=store.add_msg(num,"in",text,"recv")
            if ok then sys.publish("SIP_MSG",{id=id,num=num,dir="in",text=text}) else emit_error(id) end
        elseif pending and data.message and data.message.app_id==pending.id then
            if action=="sent" then finish_message("sent","服务器已接受；不代表对方已读")
            elseif action=="failed" then finish_message(data.unknown and "unknown" or "failed",data.reason or tostring(data.code)) end
        end
    elseif event=="error" then emit_error("SIP错误: "..tostring(action)) end
end
local function config(a)
    -- audio_mode 显式留空：非 nil 时 exsip.start() 会立刻执行 voip.setAudioMode()，
    -- 等于"刚打开 SIP 页、还没打电话"就改底层 VoIP 音频路由，而且该状态退出页面也不还原。
    -- 留空后路由由 start_voip_engine_now() 在通话媒体真正启动时才选择，
    -- 780EHM+Air1103 下 audio_v2 与 pcm 桥接都可用，自动选出来的仍是 AUDIO_MODE_BRIDGE，
    -- 通话行为不变，只是不在开页面这一刻动全局音频状态。
    return {sip_server_addr=a.server,sip_server_port=tonumber(a.port) or 5060,
        sip_domain=a.domain~="" and a.domain or a.server,sip_username=a.user,sip_password=a.password,
        sip_transport=a.transport,codecs={"PCMA","PCMU"},ptime=20,auto_answer=false,expires=600,
        call_timeout=45}
end
local function run()
    while wanted do
        local mine=generation
        registered=false; store.set_logged(false); state("connecting","等待网络")
        while wanted and mine==generation and not online() do sys.wait(500) end
        if wanted and mine==generation then
            epoch=epoch+1; local token=epoch; reconnect=false
            local a=store.get_acct(); S.user=a.user.."@"..a.server
            engine.on(function(...) on_event(token,...) end)
            state("connecting","注册中")
            local ok=engine.init(config(a)) and engine.start()
            if not ok then emit_error("SIP初始化失败，请检查固件及配置") end
            local elapsed=0
            while ok and wanted and mine==generation and online() and not reconnect do
                sys.wait(500); elapsed=elapsed+500
                if not registered and elapsed>=30000 then break end
            end
            epoch=epoch+1; registered=false; store.set_logged(false)
            clear_call(); finish_message("unknown","会话结束，发送结果未知")
            engine.stop() -- yields; only called from this worker
            -- Do not attach a new account to the old client's asynchronous worker.
            while client.is_running() do sys.wait(100) end
            if wanted and mine==generation then
                state("connecting","连接失败，稍后重试")
                for _=1,16 do if not wanted or generation~=mine then break end; sys.wait(500) end
            end
        end
    end
    worker=false; state("idle","已注销")
end
local function start_worker()
    if worker then return end
    worker=true; sys.taskInit(run)
end
function M.login(a)
    if call then return false,"请先结束当前通话" end
    if type(a)~="table" or type(a.server)~="string" or a.server=="" or type(a.user)~="string" or a.user=="" then return false,"请填写服务器和用户名" end
    if type(a.password)~="string" or a.password=="" then return false,"请填写密码" end
    if a.transport~="udp" and a.transport~="tcp" then return false,"仅支持UDP/TCP" end
    local port=tonumber(a.port); if not port or port%1~=0 or port<1 or port>65535 then return false,"端口范围为1到65535" end
    for _,k in ipairs({"server","domain","user"}) do if a[k] and a[k]:find("[\r\n]") then return false,"账号字段不能包含换行" end end
    local ok,err=store.save_acct(a); if not ok then return false,err end
    ok,err=store.set_auto_register(true); if not ok then return false,err end
    generation=generation+1; epoch=epoch+1; wanted=true; registered=false; store.set_logged(false)
    start_worker(); return true
end
function M.logout()
    if call then return false,"请先结束当前通话" end
    local ok,err=store.set_auto_register(false); if not ok then return false,err end
    wanted=false; registered=false; generation=generation+1; epoch=epoch+1; store.set_logged(false)
    state(worker and "connecting" or "idle","正在注销"); return true
end
function M.init()
    if initialized then return true end; initialized=true
    store.recover_messages()
    -- 工厂集成：首次打开 SIP 页默认自动注册（默认账号 cc.luatos.com:8910 始终存在）。
    -- 一旦用户在页面内手动「注销」，会写入 auto=false 及 auto_seen=true，
    -- 之后尊重该选择，不再自动连。
    local auto
    if fskv and fskv.get("sipapp_auto_seen")==true then
        auto = store.get_auto_register()
    else
        auto = true
        pcall(function()
            fskv.set("sipapp_auto_seen", true)
            store.set_auto_register(true)
        end)
    end
    if not wanted and store.has_acct() and auto then
        return M.login(store.get_acct())
    end
    return true
end
function M.dial(num)
    if type(num)~="string" or num=="" or #num>128 or num:find("[\r\n]") then return false,"号码格式错误" end
    if not registered or S.state~="ready" then return false,"未注册或当前忙" end
    local ok,err=audio_gate(); if not ok then return false,err end
    call={peer=num,direction="out",ts=os.time()}; S.peer=num; S.direction="out"; S.since=call.ts
    if not engine.dial(num) then call=nil; S.peer=nil; S.direction=nil; S.since=0; return false,"呼出失败" end
    state("dialing","正在呼叫")
    -- 延后 100ms 再起回铃音：state() 会触发 UI 重建整屏通话层，那是几十到上百毫秒的
    -- LVGL 分配；若正好压在起播点上，喂数协程被按住，下行队列被掏空，驱动补静音帧，
    -- 听感就是一阵断续的"电报声"。先让 UI 建完，再开声。
    sys.timerStart(function()
        if S.state~="dialing" or not call then return end
        local tone_ok,tone_err=audio.play_ringback_loop()
        if not tone_ok then log.warn("sip_app","ringback unavailable",tone_err) end
    end,100)
    return true
end
function M.answer()
    if S.state~="incoming" or not call then return false,"当前没有来电" end
    local ok,err=audio_gate(); if not ok then return false,err end
    if not engine.accept() then return false,"接听失败" end
    audio.stop_ringback(true)
    state("answering","正在接通"); return true
end
function M.hangup()
    if not call then return false,"当前没有通话" end
    audio.stop_ringback(true)
    if S.state=="incoming" then record("rejected"); engine.fail(486,"Busy Here") else engine.hangUp() end
    state("ending","正在挂断"); return true
end
function M.set_mute(on)
    if S.state~="talking" then return false,"当前不在通话中" end
    if not audio.set_mute then return false,"音频驱动不支持静音" end
    local ok,result=pcall(audio.set_mute,on==true)
    if not ok or result==false then return false,"静音设置失败" end
    S.muted=on==true; state(S.state); return true
end
function M.send_message(num,text)
    if not registered then return false,"未注册，无法发送" end
    if pending then return false,"上一条消息仍在发送，请稍候" end
    if type(num)~="string" or num=="" or #num>128 or num:find("[\r\n]") then return false,"号码格式错误" end
    if type(text)~="string" or text=="" or #text>1024 then return false,"消息须为1至1024字节" end
    local ok,id=store.add_msg(num,"out",text,"pending"); if not ok then return false,id end
    pending={id=id}; local current=pending
    if not engine.message(num,text,id) then finish_message("failed","发送请求未受理"); return false,"发送失败" end
    sys.publish("SIP_MSG",{id=id,num=num,dir="out",text=text,status="pending"})
    sys.timerStart(function() if pending==current then finish_message("unknown","响应超时，请确认对方是否收到；不会自动重发") end end,16000)
    return true,id
end
function M.retry_message(id)
    for _,m in ipairs(store.get_msgs()) do
        if m.id==id then
            if m.dir~="out" or m.status~="failed" then return false,"仅明确失败的消息可重试；未知结果请先与对方确认" end
            return M.send_message(m.num,m.text)
        end
    end
    return false,"消息不存在"
end
function M.is_ready() return registered and S.state=="ready" end
sys.subscribe("AUDIO_BRIDGE_FAILED",function(reason)
    if not call or S.state=="ending" then return end
    emit_error("音频故障: "..tostring(reason)); engine.hangUp(); state("ending","音频故障，正在挂断")
end)
return M
