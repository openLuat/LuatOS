--[[
@module  task_cloud
@summary AirCloud 任务收发与 fskv 存储接入
@version 1.1
@date    2026.09.29
@author  王世豪
@usage
由 task_adapter 调用 start(adapter) 启动。
通过 Tag19 接收 air8784.sip.v1 命令，Tag20 上报完整配置与状态。
额外支持 update/fota 命令（JSON 或文本短命令），触发 libfota3 手动升级检查。
额外支持文本模式切换 mode:cc / mode:sip（映射 phone / single，自动补齐 set_mode 字段）。
使用 fskv 单键 sip_task_v1 持久保存；定时推进状态机并每30秒上报。
依赖 script 中默认烧录的 excloud、httpplus、exmtn，不在工程重复存放。
]]

local M={}
function M.start(adapter)
    local cloud=require "excloud"
    local engine=require "task_engine"
    local update=require "update"
    assert(fskv and fskv.init(), "fskv unavailable")
    local key, imei="sip_task_v1", mobile.imei()
    local controller
    local function report(value)
        log.info("task_cloud", "snapshot", value.result, value.state, "revision", value.revision, "index", value.index)
        local s=cloud.status()
        if s.is_authenticated then
            local ok,err=cloud.send({{field_meaning=20,data_type=3,value=json.encode(value)}},false)
            if not ok then log.warn("task_cloud", "snapshot send failed", err) end
        end
    end
    local function read_task_record()return fskv.get(key)end
    local function write_task_record(value)
            if not fskv.set(key,value) then return false end
            local saved=fskv.get(key)
            return type(saved)=="table" and saved.revision==value.revision and saved.boot_count==value.boot_count
        end
    controller=engine.new({imei=imei,adapter=adapter,report=report,store={
        read=read_task_record,
        write=write_task_record}})
    local function trigger_update()
        log.info("task_cloud", "AirCloud update command; trigger FOTA check")
        sys.taskInit(function()
            local ok, err = pcall(update.check_update)
            if not ok then log.error("task_cloud", "FOTA check failed", tostring(err)) end
        end)
        if cloud.status().is_authenticated then
            cloud.send({{field_meaning=20,data_type=3,value=json.encode({schema="air8784.sip.v1",kind="ack",op="update",result="ok",imei=imei})}},false)
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
        local saved=fskv.get(key)
        local cur_rev=(type(saved)=="table" and type(saved.revision)=="string" and saved.revision) or "0"
        mode_seq=mode_seq+1
        log.info("task_cloud","mode command -> set_mode",m)
        controller.command({schema="air8784.sip.v1",imei=imei,op="set_mode",
            req="mode"..tostring(mode_seq),expected=cur_rev,revision=new_revision(mode_seq),runtime_mode=m})
    end
    local function on_cloud_event(event,data)
        if event=="auth_result" then
            if data and data.success then
                log.info("task_cloud", "AirCloud authenticated")
                controller.snapshot()
            else log.warn("task_cloud", "AirCloud authentication failed") end
        elseif event=="message" and type(data)=="table" then
            for _,tlv in ipairs(data.tlvs or {}) do
                if tlv.field==19 and type(tlv.value)=="string" and #tlv.value<=1200 then
                    local ok,c=pcall(json.decode,tlv.value)
                    if ok and type(c)=="table" then
                        local op = c.op or c.type or c.command
                        if op=="update" or op=="fota" then
                            trigger_update()
                        elseif op=="mode_set" or op=="mode" then
                            switch_mode(c.mode or c.value or c.runtime_mode)
                        else
                            log.info("task_cloud", "command", c.op, "req", c.req)
                            controller.command(c)
                        end
                    else
                        -- 文本短命令兜底：update / fota / mode:cc|sip|single|phone
                        local s = tostring(tlv.value):match("^%s*(.-)%s*$")
                        local low = s and s:lower() or ""
                        if low=="update" or low=="fota" then
                            trigger_update()
                        else
                            local head, arg = low:match("^([%a_]+)[:,#](.+)$")
                            if head=="mode" then switch_mode(arg)
                            else log.warn("task_cloud", "invalid command JSON") end
                        end
                    end
                end
            end
        end
    end
    cloud.on(on_cloud_event)
    -- TCP is the control connection; SIP signalling remains UDP.
    local ok,err=cloud.setup({transport="tcp",use_getip=true,auto_reconnect=true,debug=false})
    assert(ok, "AirCloud setup failed: "..tostring(err))
    local function cloud_connect_task()
        while true do
            while not socket.adapter(socket.LWIP_GP) do sys.waitUntil("IP_READY",1000) end
            -- getip may fail before excloud starts its own reconnect machinery.
            if cloud.status().is_open then break end
            local opened,reason=cloud.open()
            if opened then log.info("task_cloud", "AirCloud opening");break end
            log.warn("task_cloud", "AirCloud open failed; retry in 15s", reason)
            sys.wait(15000)
        end
    end
    sys.taskInit(cloud_connect_task)
    local last_s,last_us=mcu.ticks2(0)
    local function on_controller_tick()
        local s,us=mcu.ticks2(0)
        local ms=math.max(0,(s-last_s)*1000+(us-last_us)/1000)
        last_s,last_us=s,us;controller.tick(ms)
    end
    sys.timerLoopStart(on_controller_tick,250)
    local function on_snapshot_timer()controller.snapshot()end
    sys.timerLoopStart(on_snapshot_timer,30000)
    local function on_primary_key()
        if controller.primary()==false then
            log.warn("task_cloud", "key ignored: no supported task, call busy or SIP/CC not ready")
            controller.snapshot()
        end
    end
    sys.subscribe("SIP_TASK_PRIMARY",on_primary_key)
    local function on_stop_key()log.info("task_cloud", "stop key");controller.stop()end
    sys.subscribe("SIP_TASK_STOP",on_stop_key)
    return controller
end
return M
