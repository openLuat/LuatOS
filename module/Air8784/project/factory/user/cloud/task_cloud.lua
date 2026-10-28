--[[
@module  task_cloud
@summary AirCloud 统一收发入口（TCP 云通道 + 旧文本协议 + 远程 TTS + FOTA 触发）
@version 1.0
@date    2026.10.27
@author  王世豪
@usage
- start(adapter) 启动云通道：对接 task_engine、aircloud_protocol、aircloud_settings
- 保留旧文本协议：version 查询（Tag1027 回包）、update/fota 触发升级
- play_tts 经 business_voice 通过 Air1103 本地 TTS 播报
- 运行模式切换(set_mode)/传输切换(set_transport) 由此入口处理
]]
-- Unified AirCloud transport with the original task/text protocol retained.
local M={}
function M.start(adapter)
    local cloud=require "aircloud_tcp_adapter"
    local engine=require "task_engine"
    local update=require "update"
    local sip_config=require "sip_config"
    local settings=require "aircloud_settings"
    local speech=require("business_voice").new(adapter)
    settings.on_persisted=speech.changed
    local key,imei="sip_task_v1",mobile.imei()
    local controller,protocol
    local primary_wait=false
    local primary_generation=0
    local startup_reports={}
    local function report(value)
        if protocol then protocol.legacy(value,settings.record.revision)
        else startup_reports[#startup_reports+1]=value end
    end
    controller=engine.new({imei=imei,adapter=adapter,report=report,store={
        read=function()return settings.record end,
        write=settings.legacy_write}})
    local backend={idle=function()return not primary_wait and speech.idle() and adapter.safe_idle()end,
    play_tts=function(text,notify)
        if primary_wait then return false,"audio_busy" end
        return speech.remote(text,notify)
    end,status=function()
        local st=adapter.call_status();local snap=controller.peek()
        st.state=snap.state;st.index=snap.index;return st
    end,audio=adapter.audio_status,auth=function()controller.snapshot()end}
    protocol=require("aircloud_protocol").new(backend,cloud)
    settings.on_saved=function()
        controller.adopt(settings.record)
        adapter.mode_changed(settings.record.runtime_mode)
    end
    local function trigger_update()
        log.info("task_cloud", "AirCloud update command; trigger FOTA check")
        sys.taskInit(function()
            local ok, err = pcall(update.check_update)
            if not ok then log.error("task_cloud", "FOTA check failed", tostring(err)) end
        end)
        do
            protocol.legacy({schema="air8784.sip.v1",kind="ack",op="update",result="ok",imei=imei}, settings.record.revision)
        end
    end
    -- 模式切换：兼容老固件文本 mode:cc / mode:sip（映射 phone / single）
    local mode_seq=0
    local function map_mode(value)
        local m=tostring(value or ""):lower()
        if m=="cc" or m=="phone" then return "phone" end
        if m=="sip" or m=="single" then return "single" end
        return nil
    end
    local function new_revision(seq)
        return string.format("%08x-%04x-%04x-%04x-%08x%04x",os.time(),seq,0,0,os.time(),seq)
    end
    local function switch_mode(value)
        local m=map_mode(value)
        if not m then log.warn("task_cloud","invalid mode",tostring(value));return end
        local saved=settings.record
        local cur_rev=(type(saved)=="table" and type(saved.revision)=="string" and saved.revision) or "0"
        mode_seq=mode_seq+1
        log.info("task_cloud","mode command -> set_mode",m)
        controller.command({schema="air8784.sip.v1",imei=imei,op="set_mode",
            req="mode"..tostring(mode_seq),expected=cur_rev,revision=new_revision(mode_seq),runtime_mode=m})
    end
    -- 传输切换：udp / tcp / tls；tls 默认端口 5061，udp/tcp 默认 8910。
    local DEFAULT_PORT={udp=8910,tcp=8910,tls=5061}
    local function switch_transport(t,port)
        if t~="udp" and t~="tcp" and t~="tls" then
            log.warn("task_cloud","invalid sip_transport",tostring(t));return
        end
        port=port or DEFAULT_PORT[t]
        local ok,err=settings.update({sip={sip_transport=t,sip_server_port=port}})
        protocol.legacy({schema="air8784.sip.v1",kind="ack",op="set_transport",result=ok and "ok" or err,
            sip_transport=t,sip_server_port=port,imei=imei},ok and settings.record.revision or nil)

    end
    backend.legacy=function(raw)
        if type(raw)~="string" or #raw>1396 then return end
                    local ok,c=pcall(json.decode,raw)
                    if ok and type(c)=="table" then
                        local op = c.op or c.type or c.command
                        if op=="update" or op=="fota" then
                            trigger_update()
                        elseif op=="mode_set" or op=="mode" then
                            switch_mode(c.mode or c.value or c.runtime_mode)
                        elseif op=="set_transport" or op=="transport" then
                            switch_transport(c.sip_transport or c.value or c.transport, c.sip_server_port)
                        else
                            log.info("task_cloud", "command", c.op, "req", c.req)
                            controller.command(c)
                        end
                    else
                        -- 文本短命令兜底：update / fota / mode:cc|sip|single|phone
                        local s = tostring(raw):match("^%s*(.-)%s*$")
                        local low = s and s:lower() or ""
                        if low=="update" or low=="fota" then
                            trigger_update()
                        else
                            local head, arg = low:match("^([%a_]+)[:,#](.+)$")
                            if head=="mode" then switch_mode(arg)
                            elseif head=="transport" then switch_transport(arg)
                            else log.warn("task_cloud", "invalid command JSON") end
                        end
                    end
    end
    for _,value in ipairs(startup_reports) do protocol.legacy(value) end
    protocol.start()
    local last_s,last_us=mcu.ticks2(0)
    local function on_controller_tick()
        local s,us=mcu.ticks2(0)
        local ms=math.max(0,(s-last_s)*1000+(us-last_us)/1000)
        last_s,last_us=s,us;controller.tick(ms)
        if not primary_wait then speech.step(ms) end
    end
    sys.timerLoopStart(on_controller_tick,250)
    -- Authentication, commands and task transitions already send snapshots.
    -- Do not duplicate those with an unconditional periodic full snapshot.
    local function run_primary()
        if controller.primary()==false then
            log.warn("task_cloud", "key ignored: no supported task, call busy or SIP/CC not ready")
            controller.snapshot()
        end
    end
    local function on_primary_key()
        if primary_wait then return end
        local voice=require "task_voice"
        if not voice.is_playing() then run_primary();return end
        primary_wait=true;primary_generation=primary_generation+1
        local generation=primary_generation
        voice.cancel("call_preemption")
        sys.taskInit(function()
            for _=1,250 do
                if generation~=primary_generation then return end
                if not voice.is_playing() then
                    -- A newly arriving call must not be answered by an older dial key.
                    if not (adapter.incoming and adapter.incoming()) then run_primary() end
                    primary_wait=false;return
                end
                sys.wait(20)
            end
            if generation==primary_generation then primary_wait=false end
            log.warn("task_cloud","primary key: TTS release timeout")
        end)
    end
    sys.subscribe("SIP_TASK_PRIMARY",on_primary_key)
    local function on_stop_key()
        primary_generation=primary_generation+1;primary_wait=false
        local voice = require "task_voice"
        voice.cancel("stop_key")
        log.info("task_cloud", "stop key");controller.stop()
    end
    sys.subscribe("SIP_TASK_STOP",on_stop_key)
    return controller
end
return M
