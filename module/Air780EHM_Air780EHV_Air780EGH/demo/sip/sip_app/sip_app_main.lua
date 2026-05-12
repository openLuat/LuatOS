local exsip = require "exsip"
local audio_drv = require "audio_drv"
local exaudio = require "exaudio"

local TASK_NAME = "sip_app_main_task"
--测试账号，根据自己实际情况修改
local SIP_CONFIG = {
    sip_server_addr = "180.152.6.34",
    sip_server_port = 8910,
    sip_domain = "180.152.6.34",
    sip_username = "100001",
    sip_password = "Mm123..",
    sip_transport = exsip.TRANSPORT_UDP,
    auto_answer = false,
}

-- 状态机的状态
-- "STATE_IDLE"：空闲状态，task 未启动
-- "STATE_INITING"：正在初始化 SIP服务
-- "STATE_READY"：SIP服务准备就绪
-- "STATE_DIALING"：正在呼出
-- "STATE_INCOMING"：正在呼入
-- "STATE_CONNECTED"：已连接
-- "STATE_DISCONNECTING"：正在断开连接（挂断后等待 SIP 断开事件）
local g_sip_status = "STATE_IDLE"

-- 状态机的消息名
-- "MSG_READY"
-- "MSG_STOP"
-- "MSG_DIAL"：呼出
-- "MSG_INCOMING"：呼入
-- "MSG_ACCEPT"：接听
-- "MSG_HANGUP"：拒绝接听
-- "MSG_CONNECTED"：已连接
-- "MSG_DISCONNECTED"：已经断开连接
-- "MSG_ERROR"：出现异常

local g_audio_inited = false

local function start()
    log.info("start", "开始初始化 SIP，当前状态:", g_sip_status)

    if SIP_CONFIG.sip_server_addr == "xxx.xxx.xxx.xxx" then
        log.error("start", "请先配置 SIP 服务器地址和账号密码")
        return false
    end

    if not g_audio_inited then
        g_audio_inited = audio_drv.init()
        if not g_audio_inited then
            log.error("start", "音频驱动初始化失败")
            return false
        end
    end

    if not exsip.init(SIP_CONFIG) then
        log.error("start", "sip配置失败")
        return false
    end

    if not exsip.start() then
        log.error("start", "sip启动失败")
        return false
    end

    return true
end

-- 停止会失败吗？如果停止失败了，需要做什么处理吗？
-- 如果没有启动，调用停止接口也不应该出问题
local function stop()
    log.info("stop", "开始停止 SIP，当前状态:", g_sip_status)
    exsip.stop()
    exaudio.pm(0, audio.SHUTDOWN)
end

--主动拨号，未接通，挂断（如无特别标注，则主动挂断和对方挂断出发的事件顺序相同）
--sip事件触发顺序：call_ringing -> call_ended

--收到来电，未接通，挂断
--sip事件触发顺序：call_incoming -> call_ringing -> call_ended
--
--主动拨号，接通，挂断
--sip事件触发顺序：call_ringing -> media_ready -> call_connected -> voip_state:started -> voip_media:stats -> media_stopped -> call_ended -> voip_state:stopped
--
--来电，接通，挂断
--sip事件触发顺序：call_incoming -> call_ringing -> media_ready -> call_connected -> voip_state:started -> voip_media:stats -> media_stopped -> call_ended -> voip_state:stopped

--异常情况
--拨号中出现网络切换
--sip事件触发顺序：call_ringing -> error_network_changed -> lifecycle_stopped -> lifecycle_online -> register_ok-> ready

--通话中出现网络切换
--sip事件触发顺序：call_ringing -> media_ready -> call_connected -> voip_state:started -> voip_media:stats -> -> error_network_changed -> lifecycle_stopped -> lifecycle_online -> register_ok-> ready

--4g单网卡拨号未接听断网
--sip事件触发顺序：call_ringing -> 拔卡 -> error_net -> lifecycle_stopped ->一直等待网络就绪，重新插卡还是一直在等待网络就绪

--4g单网卡拨号接通断网
--sip事件触发顺序：call_ringing -> media_ready -> call_connected -> voip_state:started -> voip_media:stats -> 拔卡(通话维持了一会儿) -> error_net -> lifecycle_stopped ->一直等待网络就绪，重新插卡还是一直在等待网络就绪

--wifi和以太网会重连重新建立SIP
--wifi单网卡拨号未接听断网
--sip事件触发顺序：call_ringing -> 断wifi -> error_net -> lifecycle_stopped ->打开wifi -> error_network_changed -> lifecycle_stopped -> lifecycle_online -> register_challenge -> register_ok-> ready

--wifi单网卡拨号接通断网
--sip事件触发顺序：call_ringing -> media_ready -> call_connected -> voip_state:started -> voip_media:stats -> 断wifi(通话断开) -> error_net -> lifecycle_stopped -> 打开wifi -> error_network_changed -> lifecycle_stopped -> lifecycle_online -> register_challenge -> register_ok-> ready

--单以太网拨号未接听断网
--sip事件触发顺序：call_ringing -> 拔网线 -> error_net -> lifecycle_stopped -> 插网线 -> error_network_changed -> lifecycle_stopped -> lifecycle_online -> register_challenge -> register_ok-> ready

--单以太网拨号接通断网  
--sip事件触发顺序：call_ringing -> media_ready -> call_connected -> voip_state:started -> voip_media:stats -> 拔网线(通话断开) -> error_net -> lifecycle_stopped -> 插网线 -> error_network_changed -> lifecycle_stopped -> lifecycle_online -> register_challenge -> register_ok-> ready

--多网融合,优先级以太网>wifi>4g,拨号未接听断网
--sip事件触发顺序：call_ringing -> 拔网线 -> 连wifi -> error_network_changed -> lifecycle_stopped -> lifecycle_online -> register_challenge -> register_ok-> ready -> call_ended(timeout)
-- (wifi状态下再拨号)-> call_ringing -> 断wifi -> 切4g -> error_network_changed -> lifecycle_stopped -> lifecycle_online -> register_challenge -> register_ok-> ready -> call_ended(timeout)

--多网融合,优先级以太网>4g>wifi,拨号未接听断网
--sip事件触发顺序：call_ringing -> 拔网线 -> 切4g -> error_network_changed -> lifecycle_stopped -> lifecycle_online -> register_challenge -> register_ok-> ready -> call_ended(timeout)
-- (4g状态下再拨号)-> call_ringing -> 拔卡 -> error_net -> lifecycle_stopped -> 切wifi -> （没有error_network_changed）lifecycle_online -> register_challenge -> register_ok-> ready -> call_ended(timeout)

--多网融合,优先级>wifi>以太网>4g,拨号未接听断网
--sip事件触发顺序：call_ringing -> 断wifi -> (约30s)连以太网 -> error_network_changed -> lifecycle_stopped -> lifecycle_online -> register_challenge -> register_ok-> ready（没有出现外呼超时30s引起的挂断）
-- (以太网状态下再拨号)-> call_ringing -> 插网线 -> 切4g -> error_network_changed -> lifecycle_stopped -> lifecycle_online -> register_challenge -> register_ok-> ready -> call_ended(timeout)

--多网融合,优先级wifi>4g>以太网,拨号未接听断网
--sip事件触发顺序：call_ringing -> 断wifi -> 切4g -> error_network_changed -> lifecycle_stopped -> lifecycle_online -> register_challenge -> register_ok-> ready没有出现外呼超时30s引起的挂断）
--(4g状态下再拨号)-> call_ringing -> 拔卡 -> error_net -> lifecycle_stopped ->（没有error_network_changed）lifecycle_online -> register_challenge -> register_ok-> ready -> call_ended(timeout)

--多网融合,优先级4g>wifi>以太网,拨号未接听断网
--sip事件触发顺序：call_ringing -> 拔卡 -> call_ended(timeout) -> error_net -> lifecycle_stopped -> 切wifi -> (没有error_network_changed)lifecycle_online -> register_challenge -> register_ok-> ready
--(wifi状态下再拨号)-> call_ringing -> 断wifi -> 切以太网 -> error_network_changed -> lifecycle_stopped -> lifecycle_online -> register_challenge -> register_ok-> ready(没有call_ended(timeout))

--多网融合,优先级4g>以太网>wifi,拨号未接听断网
--sip事件触发顺序：call_ringing -> 拔卡 -> error_net -> lifecycle_stopped -> 连以太网 -> (没有error_network_changed)lifecycle_online -> register_challenge -> register_ok-> ready（没有出现外呼超时30s引起的挂断）
--(以太网状态下再拨号)-> call_ringing -> 断以太网 -> 连wifi -> error_network_changed -> lifecycle_stopped -> lifecycle_online -> register_challenge -> register_ok-> ready -> call_ended(timeout)

local function sip_callback(event, arg1, arg2, arg3)
    local tag = "sip_callback"

    log.info("sip_callback", g_sip_status,event, arg1, arg2, arg3)

    if event == "register" then
        local action, data = arg1, arg2
        if action == "ok" then
            log.info("sip_callback", "注册成功，有效期:", data.expires, "SIP响应头:", data.headers)
        elseif action == "challenge" then
            log.info("sip_callback", "收到认证挑战，继续注册流程")
        else
            log.error("sip_callback", "注册失败，action:", action)
            sys.sendMsg(TASK_NAME, tag, "MSG_ERROR")
        end
    elseif event == "ready" then
        sys.sendMsg(TASK_NAME, tag, "MSG_READY")
        log.info("sip_callback", "SIP 服务已就绪","当前SIP状态:", g_sip_status)
    elseif event == "call" then
        local sub_event, data = arg1, arg2
        log.info("sip_callback", "call event sub_event=", sub_event)
        if sub_event == "incoming" then
            log.info("sip_callback", "来电:", data.from, data.call_id, data.uri, data.headers, data.remote_sdp)
            sys.sendMsg(TASK_NAME, tag, "MSG_INCOMING", data.from)
        elseif sub_event == "ringing" then
            log.info("sip_callback", "对方响铃中")
        elseif sub_event == "connected" or sub_event == "established" then
            log.info("sip_callback", "通话已建立")
            sys.sendMsg(TASK_NAME, tag, "MSG_CONNECTED")
        elseif sub_event == "ended" then
            log.info("sip_callback", "通话已结束，结束原因为：", data.reason, "通话对象：", data.dialog)
            sys.sendMsg(TASK_NAME, tag, "MSG_DISCONNECTED")
        end
    elseif event == "media" then
        local sub_event, data = arg1, arg2
        if sub_event == "ready" then
            local remote_ip = data.remote_ip or (data.session and data.session.remote_ip) or ""
            local remote_port = data.remote_port or (data.session and data.session.remote_port) or ""
            log.info("sip_callback", "媒体通道就绪", remote_ip .. ":" .. remote_port)
        elseif sub_event == "stop" then
            log.info("sip_callback", "媒体通道已关闭，关闭原因：", data.reason)
        end
    elseif event == "message" then
        local sub_event, data = arg1, arg2
        if sub_event == "rx" then
            log.info("sip_callback", "收到消息:", data.from, data.body)
        elseif sub_event == "sent" then
            log.info("sip_callback", "消息已发送到:", data.to, data.body)
        end
    elseif event == "voip" then
        local sub_event, data = arg1, arg2
        if sub_event == "state" then
            log.info("sip_callback", "VoIP状态:", data)
        elseif sub_event == "stats" then
            log.info("sip_callback", "VoIP统计 - 发送:", data.tx_packets, "接收:", data.rx_packets, "丢失:", data.rx_lost)
        elseif sub_event == "error" then
            log.error("sip_callback", "VoIP错误:", data)
            sys.sendMsg(TASK_NAME, tag, "MSG_ERROR")
        end
    elseif event == "lifecycle" then
        local sub_event, data = arg1, arg2
        log.info("sip_callback", "lifecycle event:", sub_event)
        if sub_event == "online" then
            log.info("sip_callback", "SIP 服务已在线，本地IP地址为：", data.local_ip)
        else
            sys.sendMsg(TASK_NAME, tag, "MSG_ERROR")
        end
    elseif event == "error" then
        local action = arg1
        local payload = arg2
        log.error("sip_callback", "错误:", action, payload.event, payload.param)
        sys.sendMsg(TASK_NAME, tag, "MSG_ERROR")
    end
end



local function sip_app_main_task_func()
    local result, msg, stop_flag
    
    exsip.on(sip_callback)

    while true do
        g_sip_status = "STATE_INITING"

        -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
        while not socket.adapter(socket.dft()) do
            log.warn("sip_app_main_task_func", "wait IP_READY", socket.dft())
            -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
            -- 或者等待1秒超时退出阻塞等待状态;
            -- 注意：此处的1000毫秒超时不要修改的更长；
            -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
            -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
            -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
            sys.waitUntil("IP_READY", 1000)
        end

        -- 检测到了IP_READY消息
        log.info("sip_app_main_task_func", "recv IP_READY", socket.dft())

        -- 清空此task绑定的消息队列中的未处理的消息
        sys.cleanMsg(TASK_NAME)
        
        local tag, event, para

        result = start()
        if not result then
            log.error("sip_app_main_task_func", "start error")
            goto EXCEPTION_PROC
        end


        while true do
            msg = sys.waitMsg(TASK_NAME)
            tag, event, para = msg[1], msg[2], msg[3]

            log.info("sip_app_main_task_func waitMsg", g_sip_status, tag, event, para)

            if event == "MSG_STOP" then
                stop_flag = true
                break
            elseif event == "MSG_DIAL" then
                if g_sip_status == "STATE_READY" then
                    if not exsip.dial(para) then
                        log.error("sip_app_main_task_func", "dial error")
                        sys.publish("SIP_APP_MAIN_DIAL_RSP", tag, false, "exsip.dial")
                    else
                        g_sip_status = "STATE_DIALING"
                    end
                else
                    sys.publish("SIP_APP_MAIN_DIAL_RSP", tag, false, g_sip_status)
                end
            elseif event == "MSG_ERROR" then
                    break
            elseif event == "MSG_READY" then
                if g_sip_status == "STATE_INITING" then
                    g_sip_status = "STATE_READY"
                    sys.publish("SIP_APP_MAIN_READY")
                else
                    log.warn("sip_app_main_task_func", g_sip_status, tag, "invalid event", event)
                end
            elseif event == "MSG_INCOMING" then
                if g_sip_status == "STATE_READY" then
                    g_sip_status = "STATE_INCOMING"
                    sys.publish("SIP_APP_MAIN_INCOMING", para)
                else
                    log.warn("sip_app_main_task_func", g_sip_status, tag, "invalid event", event)
                end
            elseif event == "MSG_ACCEPT" then
                if g_sip_status == "STATE_INCOMING" then
                    if not exsip.accept() then
                        log.error("sip_app_main_task_func", "accept error")
                    end
                else
                    log.warn("sip_app_main_task_func", g_sip_status, tag, "invalid event", event)
                end
            elseif event == "MSG_HANGUP" then
                if g_sip_status == "STATE_DIALING" or g_sip_status == "STATE_INCOMING" or g_sip_status == "STATE_CONNECTED" then--or g_sip_status == "STATE_DISCONNECTING" then
                    if not exsip.hangUp() then
                        log.error("sip_app_main_task_func", "hangUp error")
                    end
                else
                    log.warn("sip_app_main_task_func", g_sip_status, tag, "invalid event", event)
                end
            elseif event == "MSG_CONNECTED" then
                if g_sip_status == "STATE_DIALING" or g_sip_status == "STATE_INCOMING" then
                    g_sip_status = "STATE_CONNECTED"
                    sys.publish("SIP_APP_MAIN_CONNECTED")
                else
                    log.warn("sip_app_main_task_func", g_sip_status, tag, "invalid event", event)
                end
            elseif event == "MSG_DISCONNECTED" then
                if g_sip_status == "STATE_DIALING" or g_sip_status == "STATE_INCOMING" or g_sip_status == "STATE_CONNECTED" or g_sip_status == "STATE_DISCONNECTING" then
                    g_sip_status = "STATE_READY"
                    sys.publish("SIP_APP_MAIN_DISCONNECTED")
                else
                    log.warn("sip_app_main_task_func", g_sip_status, tag, "invalid event", event)
                end
                exaudio.pm(0, audio.SHUTDOWN)
            else
                log.warn("sip_app_main_task_func", g_sip_status, tag, "invalid event", event)
            end
            log.info("sip_app_main_task_func after process", g_sip_status)
        end
        

        -- 出现异常
        ::EXCEPTION_PROC::

        stop()
        if g_sip_status ~= "STATE_INITING" then
            sys.publish("SIP_APP_MAIN_LOSE")
        end

        -- 清空此task绑定的消息队列中的未处理的消息
        sys.cleanMsg(TASK_NAME)

        if stop_flag then
            break
        else
            -- 5秒后跳转到循环体开始位置，自动重试
            sys.wait(5000)
        end        
    end

    exsip.on(nil)
    g_sip_status = "STATE_IDLE"
    -- 清除此task对应的管理表资源
    sys.taskDel(TASK_NAME)
end


local function start_req()
    if g_sip_status == "STATE_IDLE" then
        sys.taskInitEx(sip_app_main_task_func, TASK_NAME)
        log.info("start_req", "SIP 主任务已启动")
    end
end

local function stop_req(tag)
    if g_sip_status ~= "STATE_IDLE" then
        sys.sendMsg(TASK_NAME, tag, "MSG_STOP")
    end    
end

local function dial_req(tag, num)
    sys.sendMsg(TASK_NAME, tag, "MSG_DIAL", num)
end

local function accept_req(tag)
    sys.sendMsg(TASK_NAME, tag, "MSG_ACCEPT")
end

local function hangup_req(tag)
    sys.sendMsg(TASK_NAME, tag, "MSG_HANGUP")
end

sys.subscribe("SIP_APP_MAIN_START_REQ", start_req)
sys.subscribe("SIP_APP_MAIN_STOP_REQ", stop_req)

sys.subscribe("SIP_APP_MAIN_DIAL_REQ", dial_req)
sys.subscribe("SIP_APP_MAIN_ACCEPT_REQ", accept_req)
sys.subscribe("SIP_APP_MAIN_HANGUP_REQ", hangup_req)

