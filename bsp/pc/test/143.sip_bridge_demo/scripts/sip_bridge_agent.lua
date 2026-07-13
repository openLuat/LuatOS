--[[
@module sip_bridge_agent
@summary SIP-VoLTE 音频桥接代理
@version 1.0
@date    2026.07.13

功能：4G模组作为 SIP ↔ VoLTE 音频网关
- 4G模组 SIP 用户名: 1903CFC1
- 远程 SIP 客户端: 1903CFC0
- 写死手机号: 13781142418
- SIP服务器: 180.152.6.34:8910

呼出流程（SIP客户端1903CFC0 → 4G模组1903CFC1 → 手机）:
1. 1903CFC0 拨打 SIP 1903CFC1 (INVITE) 或发送 MESSAGE 含手机号
2. 4G模组接听 SIP 通话 (exsip.accept)
3. 4G模组同时拨打手机 (cc.dial)
4. 两路通话建立后，音频自动桥接

呼入流程（手机 → 4G模组1903CFC1 → SIP客户端1903CFC0）:
1. 手机来电 (cc INCOMINGCALL)
2. 4G模组拨打 SIP 1903CFC0 (exsip.dial)
3. 1903CFC0 接听 SIP → 4G模组接听手机 (cc.accept)
4. 两路通话建立后，音频自动桥接

参数说明:
- g_enable_local_audio: 是否打开本地麦克风和喇叭
  true  = 本地可以听到/说话（音频混音）
  false = 本地静音，仅桥接两端音频
]]

local sip_bridge_agent = {}

local exsip = require("exsip")
local exaudio = require("exaudio")

-- ==================== 配置 ====================

local CONFIG = {
    sip_server_addr = "180.152.6.34",
    sip_server_port = 8910,
    sip_domain = "180.152.6.34",
    sip_username = "1903CFC1",
    sip_password = "Air.903CFC",
    sip_transport = "udp",
    
    -- 远程 SIP 客户端（控制端/被叫端）
    remote_sip_uri = "sip:1903CFC0@180.152.6.34",
    
    -- 写死的手机号码（用于呼出）
    target_phone_number = "13781142418",
    
    -- 音频参数
    rtp_port = 40000,
    codec = "PCMU",
    ptime = 20,
    sample_rate = 8000,
    
    -- 自动接听 SIP 来电（测试中建议开启）
    auto_answer_sip = true,
    
    -- 自动接听手机来电（呼入场景：收到手机来电后自动拨出 SIP）
    auto_handle_mobile_incoming = true,
}

-- ==================== 状态 ====================

-- SIP 通话状态
local SIP_STATE_IDLE = "sip_idle"
local SIP_STATE_INCOMING = "sip_incoming"
local SIP_STATE_DIALING = "sip_dialing"
local SIP_STATE_CONNECTED = "sip_connected"
local SIP_STATE_DISCONNECTING = "sip_disconnecting"

-- CC 通话状态
local CC_STATE_IDLE = "cc_idle"
local CC_STATE_DIALING = "cc_dialing"
local CC_STATE_RINGING = "cc_ringing"
local CC_STATE_CONNECTED = "cc_connected"
local CC_STATE_DISCONNECTING = "cc_disconnecting"

local g_started = false
local g_sip_registered = false
local g_sip_state = SIP_STATE_IDLE
local g_cc_state = CC_STATE_IDLE
local g_cc_ready = false

-- 音频控制参数
local g_enable_local_audio = true

-- 通话统计
local g_call_start_time = nil
local g_call_direction = nil  -- "outgoing" 或 "incoming"

-- ==================== 日志工具 ====================

local function logi(...)
    log.info("sip_bridge", ...)
end

local function logw(...)
    log.warn("sip_bridge", ...)
end

local function loge(...)
    log.error("sip_bridge", ...)
end

-- ==================== 音频控制 ====================

local function apply_audio_settings()
    if not exaudio then
        return
    end
    if g_enable_local_audio then
        -- 打开本地音频
        if exaudio.vol then
            exaudio.vol(35)
            logi("本地音频已打开: 扬声器音量=35")
        end
        if exaudio.mic_vol then
            exaudio.mic_vol(96)
            logi("本地音频已打开: 麦克风音量=96")
        end
    else
        -- 关闭本地音频（仅桥接，本地静音）
        if exaudio.vol then
            exaudio.vol(0)
            logi("本地音频已关闭: 扬声器静音")
        end
        if exaudio.mic_vol then
            exaudio.mic_vol(0)
            logi("本地音频已关闭: 麦克风静音")
        end
    end
end

function sip_bridge_agent.set_local_audio(enabled)
    g_enable_local_audio = enabled
    logi("设置本地音频开关:", enabled)
    apply_audio_settings()
end

function sip_bridge_agent.get_local_audio()
    return g_enable_local_audio
end

-- ==================== CC 事件处理 ====================

local function on_cc_event(status, value, extra)
    logi("CC事件:", status, value, extra)
    
    -- CC 未就绪时，只处理 READY 事件
    if not g_cc_ready then
        if status == "READY" then
            g_cc_ready = true
            logi("CC 系统已就绪")
        else
            logw("CC 未就绪，忽略事件:", status)
        end
        return
    end
    
    if status == "INCOMINGCALL" then
        local number = cc.lastNum()
        logi("手机来电:", number)
        
        if g_cc_state ~= CC_STATE_IDLE then
            logw("CC 忙，拒绝手机来电")
            -- 如果已经在通话中，挂断手机来电
            if cc and cc.hangUp then
                cc.hangUp(0)
            end
            return
        end
        
        g_cc_state = CC_STATE_RINGING
        
        if CONFIG.auto_handle_mobile_incoming then
            -- 呼入场景：自动拨打 SIP 到远程客户端
            logi("呼入场景：自动拨打 SIP 到", CONFIG.remote_sip_uri)
            g_call_direction = "incoming"
            
            if g_sip_state == SIP_STATE_IDLE or g_sip_state == SIP_STATE_CONNECTED then
                -- 如果 SIP 空闲，发起 SIP 呼叫
                if g_sip_state == SIP_STATE_CONNECTED then
                    -- SIP 已经连接，直接接听手机
                    logi("SIP 已连接，直接接听手机")
                    g_cc_state = CC_STATE_CONNECTED
                    if cc and cc.accept then
                                cc.accept(0)
                            end
                    apply_audio_settings()
                    g_call_start_time = os.time()
                else
                    g_sip_state = SIP_STATE_DIALING
                    local ok = exsip.dial(CONFIG.remote_sip_uri)
                    if not ok then
                        loge("SIP 拨打失败")
                        g_sip_state = SIP_STATE_IDLE
                        g_cc_state = CC_STATE_IDLE
                        g_call_direction = nil
                    end
                end
            else
                logw("SIP 状态不空闲，无法处理手机来电:", g_sip_state)
                g_cc_state = CC_STATE_IDLE
                g_call_direction = nil
            end
        end
        
    elseif status == "CONNECTED" then
        logi("CC 通话已连接")
        g_cc_state = CC_STATE_CONNECTED
        apply_audio_settings()
        if not g_call_start_time then
            g_call_start_time = os.time()
        end
        
    elseif status == "AUDIO_START" then
        -- 真机：AUDIO_START 代表通话实际已建立
        logi("CC 音频通道已启动")
        if g_cc_state ~= CC_STATE_CONNECTED then
            g_cc_state = CC_STATE_CONNECTED
            apply_audio_settings()
            if not g_call_start_time then
                g_call_start_time = os.time()
            end
        end
        
    elseif status == "DISCONNECTED" then
        logi("CC 通话已断开")
        g_cc_state = CC_STATE_IDLE
        
        -- 同步挂断 SIP 通话
        if g_sip_state == SIP_STATE_CONNECTED or g_sip_state == SIP_STATE_DIALING then
            logi("同步挂断 SIP 通话")
            g_sip_state = SIP_STATE_DISCONNECTING
            exsip.hangUp()
        end
        
        g_call_start_time = nil
        g_call_direction = nil
        
    elseif status == "MAKE_CALL_OK" then
        logi("CC 拨号请求已发送")
        
    elseif status == "MAKE_CALL_FAILED" then
        loge("CC 拨号失败")
        g_cc_state = CC_STATE_IDLE
        
        -- 同步挂断 SIP
        if g_sip_state == SIP_STATE_CONNECTED or g_sip_state == SIP_STATE_DIALING then
            logi("同步挂断 SIP 通话")
            g_sip_state = SIP_STATE_DISCONNECTING
            exsip.hangUp()
        end
        
        g_call_start_time = nil
        g_call_direction = nil
        
    elseif status == "ANSWER_CALL_DONE" then
        logi("CC 接听完成")
        
    elseif status == "HANGUP_CALL_DONE" then
        logi("CC 挂断完成")
        
    elseif status == "SPEECH_START" then
        logi("CC 语音开始")
        
    elseif status == "PLAY" then
        logi("CC 播放事件")
        
    elseif status == "DIAL_TONE" then
        logi("CC 拨号音")
        
    elseif status == "READY" then
        g_cc_ready = true
        logi("CC 系统就绪")
    end
    
    logi("状态更新: SIP=", g_sip_state, "CC=", g_cc_state)
end

-- ==================== SIP 事件处理 ====================

local function on_sip_event(event, action, data)
    logi("SIP事件:", event, action)
    
    if event == "register" then
        if action == "ok" then
            g_sip_registered = true
            logi("SIP 注册成功")
        else
            g_sip_registered = false
            logw("SIP 注册失败:", action)
        end
        
    elseif event == "ready" then
        logi("SIP 服务已就绪")
        
    elseif event == "call" then
        if action == "incoming" then
            -- 呼出场景：收到 SIP 来电
            logi("SIP 来电:", data and data.from or "unknown")
            
            if g_sip_state ~= SIP_STATE_IDLE then
                logw("SIP 忙，拒绝来电")
                exsip.hangUp()
                return
            end
            
            g_sip_state = SIP_STATE_INCOMING
            g_call_direction = "outgoing"
            
            -- 自动接听 SIP 来电
            if CONFIG.auto_answer_sip then
                logi("自动接听 SIP 来电")
                exsip.accept()
            end
            
        elseif action == "ringing" then
            logi("SIP 响铃中")
            
        elseif action == "connected" or action == "established" then
            logi("SIP 通话已建立")
            g_sip_state = SIP_STATE_CONNECTED
            
            -- 呼出场景：SIP 建立后，拨打手机
            if g_call_direction == "outgoing" and g_cc_state == CC_STATE_IDLE then
                if g_cc_ready and cc then
                    logi("SIP 已建立，开始拨打手机:", CONFIG.target_phone_number)
                    g_cc_state = CC_STATE_DIALING
                    local ok = cc.dial(0, CONFIG.target_phone_number)
                    if not ok then
                        loge("CC 拨号失败")
                        g_cc_state = CC_STATE_IDLE
                        -- 同步挂断 SIP
                        g_sip_state = SIP_STATE_DISCONNECTING
                        exsip.hangUp()
                        g_call_direction = nil
                    end
                else
                    loge("CC 未就绪，无法拨打手机")
                    g_sip_state = SIP_STATE_DISCONNECTING
                    exsip.hangUp()
                    g_call_direction = nil
                end
            end
            
            -- 呼入场景：SIP 建立后，接听手机
            if g_call_direction == "incoming" and g_cc_state == CC_STATE_RINGING then
                logi("SIP 已建立，接听手机来电")
                g_cc_state = CC_STATE_CONNECTED
                if cc and cc.accept then
                    cc.accept(0)
                end
                apply_audio_settings()
                g_call_start_time = os.time()
            end
            
        elseif action == "ended" then
            logi("SIP 通话已结束，原因:", data and data.reason or "unknown")
            g_sip_state = SIP_STATE_IDLE
            
            -- 同步挂断 CC 通话
            if g_cc_state == CC_STATE_CONNECTED or g_cc_state == CC_STATE_DIALING or g_cc_state == CC_STATE_RINGING then
                logi("同步挂断 CC 通话")
                g_cc_state = CC_STATE_DISCONNECTING
                if cc and cc.hangUp then
                    cc.hangUp(0)
                end
            end
            
            g_call_start_time = nil
            g_call_direction = nil
            
        elseif action == "failed" then
            logw("SIP 通话失败:", data and data.reason or "unknown")
            g_sip_state = SIP_STATE_IDLE
            
            -- 同步挂断 CC
            if g_cc_state == CC_STATE_CONNECTED or g_cc_state == CC_STATE_DIALING or g_cc_state == CC_STATE_RINGING then
                logi("同步挂断 CC 通话")
                g_cc_state = CC_STATE_DISCONNECTING
                if cc and cc.hangUp then
                    cc.hangUp(0)
                end
            end
            
            g_call_start_time = nil
            g_call_direction = nil
        end
        
    elseif event == "media" then
        if action == "ready" then
            local remote_ip = data.remote_ip or (data.session and data.session.remote_ip) or ""
            local remote_port = data.remote_port or (data.session and data.session.remote_port) or 0
            logi("SIP 媒体通道就绪:", remote_ip, ":", remote_port, "codec:", data.codec)
            
        elseif action == "stop" then
            logi("SIP 媒体通道已关闭，原因:", data.reason)
        end
        
    elseif event == "message" then
        if action == "rx" then
            local body = data and data.body or ""
            logi("收到 SIP MESSAGE:", data.from, "body:", body)
            -- 可以解析 body 中的 JSON 命令，但当前方案中主要用 SIP INVITE 触发
            -- 这里保留作为备用控制通道
            sip_bridge_agent.handle_sip_message(body)
            
        elseif action == "sent" then
            logi("SIP MESSAGE 已发送:", data.to)
        end
        
    elseif event == "voip" then
        if action == "state" then
            logi("VoIP 状态:", data)
        elseif action == "stats" then
            logi("VoIP 统计 - 发送:", data.tx_packets, "接收:", data.rx_packets, "丢失:", data.rx_lost)
        elseif action == "error" then
            loge("VoIP 错误:", data)
        end
        
    elseif event == "lifecycle" then
        if action == "online" then
            logi("SIP 服务已在线，本地IP:", data.local_ip)
        elseif action == "stopped" then
            logi("SIP 服务已停止")
            g_sip_registered = false
        end
        
    elseif event == "error" then
        loge("SIP 错误:", action, data)
    end
    
    logi("状态更新: SIP=", g_sip_state, "CC=", g_cc_state)
end

-- ==================== 处理 SIP MESSAGE 中的命令 ====================

function sip_bridge_agent.handle_sip_message(body)
    -- 解析 JSON 命令（备用控制通道）
    local cmd = nil
    local ok, result = pcall(function()
        -- 简单的 JSON 解析
        local t = {}
        for k, v in body:gmatch('"([^"]+)":%s*"([^"]*)"') do
            t[k] = v
        end
        for k, v in body:gmatch('"([^"]+)":%s*(true|false)') do
            t[k] = (v == "true")
        end
        for k, v in body:gmatch('"([^"]+)":%s*(%d+)') do
            t[k] = tonumber(v)
        end
        return t
    end)
    if ok and result then
        cmd = result
    end
    
    if not cmd or not cmd.cmd then
        logw("无法解析 SIP MESSAGE:", body)
        return
    end
    
    local command = cmd.cmd
    logi("执行 SIP MESSAGE 命令:", command)
    
    if command == "dial" then
        -- 通过 MESSAGE 触发拨号
        local number = cmd.number or CONFIG.target_phone_number
        logi("MESSAGE 命令拨号:", number)
        sip_bridge_agent.dial_phone(number)
        
    elseif command == "hangup" then
        logi("MESSAGE 命令挂断")
        sip_bridge_agent.hangup_all()
        
    elseif command == "answer" then
        logi("MESSAGE 命令接听")
        sip_bridge_agent.answer_sip()
        
    elseif command == "set_audio" then
        local enabled = cmd.enabled
        if enabled ~= nil then
            sip_bridge_agent.set_local_audio(enabled)
        end
        
    elseif command == "status" then
        logi("状态查询请求")
        
    else
        logw("未知命令:", command)
    end
end

-- ==================== 公共 API ====================

function sip_bridge_agent.start(opts)
    opts = opts or {}
    
    if g_started then
        logw("已经启动")
        return true
    end
    
    -- 合并配置
    for k, v in pairs(CONFIG) do
        if opts[k] ~= nil then
            CONFIG[k] = opts[k]
        end
    end
    
    logi("=" .. string.rep("=", 50))
    logi("  SIP-VoLTE 音频桥接代理启动")
    logi("=" .. string.rep("=", 50))
    logi("SIP 服务器:", CONFIG.sip_server_addr, ":", CONFIG.sip_server_port)
    logi("SIP 用户:", CONFIG.sip_username)
    logi("远程 SIP 客户端:", CONFIG.remote_sip_uri)
    logi("目标手机号:", CONFIG.target_phone_number)
    logi("=" .. string.rep("=", 50))
    
    -- 初始化 CC 模块
    if rtos.bsp() == "PC" then
        -- PC 模拟器：加载 cc_stub
        local cc_ok, cc_err = pcall(function()
            cc = require("cc_stub_pc")
        end)
        if cc_ok and cc then
            logi("PC 模拟器: 使用 CC stub")
            g_cc_ready = true
        else
            logw("PC 模拟器: CC stub 不可用")
            g_cc_ready = false
        end
    else
        -- 真机：CC 库可能异步加载
        if cc then
            logi("真机: CC 库已可用")
            g_cc_ready = true
        else
            logw("真机: CC 库未就绪，等待 READY 事件")
            g_cc_ready = false
        end
    end
    
    -- 初始化 CC
    if g_cc_ready and cc and cc.init then
        local ok = cc.init(0)
        if ok then
            logi("CC 初始化成功")
        else
            loge("CC 初始化失败")
        end
    end
    
    -- 订阅 CC 事件
    sys.subscribe("CC_IND", on_cc_event)
    
    -- 设置默认网卡
    local use_adapter = socket.LWIP_GP
    if rtos.bsp() == "PC" then
        socket.dft(socket.ETH0)
        use_adapter = socket.ETH0
        logi("网络适配器: ETH0 (PC)")
    end
    
    -- 初始化 exsip
    local sip_ok = exsip.init({
        sip_server_addr = CONFIG.sip_server_addr,
        sip_server_port = CONFIG.sip_server_port,
        sip_domain = CONFIG.sip_domain,
        sip_username = CONFIG.sip_username,
        sip_password = CONFIG.sip_password,
        sip_transport = CONFIG.sip_transport,
        rtp_port = CONFIG.rtp_port,
        codecs = {CONFIG.codec},
        ptime = CONFIG.ptime,
        auto_answer = CONFIG.auto_answer_sip,
        adapter = use_adapter,
    })
    
    if not sip_ok then
        loge("exsip 初始化失败")
        return false
    end
    
    exsip.on(on_sip_event)
    
    -- 设置 voip 为桥接模式（不控制 I2S，通过 PCM 缓冲区与 cc 交换数据）
    -- 必须在 exsip.start() 之前设置，因为 exsip 内部会在 media ready 时调用 voip.start()
    if voip and voip.setAudioMode then
        local ok = voip.setAudioMode(voip.AUDIO_MODE_BRIDGE)
        if ok then
            logi("voip 已设置为桥接模式（AUDIO_MODE_BRIDGE）")
        else
            logw("voip 设置桥接模式失败，可能正在运行中。尝试先停止...")
            if voip.stop then voip.stop() end
            sys.wait(500)
            ok = voip.setAudioMode(voip.AUDIO_MODE_BRIDGE)
            if ok then
                logi("voip 桥接模式设置成功（先停止后重试）")
            else
                loge("voip 桥接模式设置失败，音频桥接可能无法正常工作")
            end
        end
    else
        logw("voip 模块不可用，跳过桥接模式设置（PC模拟器可能未编译voip）")
    end
    
    local start_ok = exsip.start()
    if not start_ok then
        loge("exsip 启动失败")
        return false
    end
    
    g_started = true
    logi("SIP-VoLTE 桥接代理启动成功")
    return true
end

function sip_bridge_agent.stop()
    if not g_started then
        return
    end
    
    logi("停止桥接代理...")
    
    -- 挂断所有通话
    sip_bridge_agent.hangup_all()
    
    exsip.stop()
    sys.unsubscribe("CC_IND", on_cc_event)
    
    g_started = false
    g_sip_registered = false
    g_sip_state = SIP_STATE_IDLE
    g_cc_state = CC_STATE_IDLE
    g_cc_ready = false
    g_call_start_time = nil
    g_call_direction = nil
    
    logi("桥接代理已停止")
end

-- 手动拨打手机（呼出场景）
function sip_bridge_agent.dial_phone(number)
    number = number or CONFIG.target_phone_number
    
    if not g_started then
        loge("未启动")
        return false
    end
    
    if g_cc_state ~= CC_STATE_IDLE then
        logw("CC 忙")
        return false
    end
    
    if g_sip_state ~= SIP_STATE_IDLE and g_sip_state ~= SIP_STATE_CONNECTED then
        logw("SIP 忙:", g_sip_state)
        return false
    end
    
    if not g_cc_ready or not cc then
        loge("CC 未就绪")
        return false
    end
    
    g_call_direction = "outgoing"
    
    -- 如果 SIP 未连接，先拨打 SIP
    if g_sip_state == SIP_STATE_IDLE then
        logi("拨打 SIP 到远程客户端:", CONFIG.remote_sip_uri)
        g_sip_state = SIP_STATE_DIALING
        local ok = exsip.dial(CONFIG.remote_sip_uri)
        if not ok then
            loge("SIP 拨打失败")
            g_sip_state = SIP_STATE_IDLE
            g_call_direction = nil
            return false
        end
    end
    
    -- 拨打手机（如果 SIP 已连接，直接拨打）
    if g_sip_state == SIP_STATE_CONNECTED then
        logi("SIP 已连接，直接拨打手机:", number)
        g_cc_state = CC_STATE_DIALING
        local ok = cc.dial(0, number)
        if not ok then
            loge("CC 拨号失败")
            g_cc_state = CC_STATE_IDLE
            return false
        end
    end
    
    return true
end

-- 手动接听 SIP 来电
function sip_bridge_agent.answer_sip()
    if g_sip_state == SIP_STATE_INCOMING then
        logi("手动接听 SIP 来电")
        exsip.accept()
        return true
    end
    logw("没有 SIP 来电可接听:", g_sip_state)
    return false
end

-- 手动挂断所有通话
function sip_bridge_agent.hangup_all()
    logi("挂断所有通话...")
    
    -- 挂断 SIP
    if g_sip_state ~= SIP_STATE_IDLE then
        g_sip_state = SIP_STATE_DISCONNECTING
        exsip.hangUp()
    end
    
    -- 挂断 CC
    if g_cc_state ~= CC_STATE_IDLE then
        g_cc_state = CC_STATE_DISCONNECTING
        if cc and cc.hangUp then
            cc.hangUp(0)
        end
    end
    
    g_call_start_time = nil
    g_call_direction = nil
end

-- 手动接听手机来电（呼入场景）
function sip_bridge_agent.answer_mobile()
    if g_cc_state == CC_STATE_RINGING then
        logi("手动接听手机来电")
        g_cc_state = CC_STATE_CONNECTED
        if cc and cc.accept then
            cc.accept(0)
        end
        apply_audio_settings()
        g_call_start_time = os.time()
        return true
    end
    logw("没有手机来电可接听:", g_cc_state)
    return false
end

-- 手动拨打 SIP（呼入场景）
function sip_bridge_agent.dial_sip(uri)
    uri = uri or CONFIG.remote_sip_uri
    
    if g_sip_state ~= SIP_STATE_IDLE then
        logw("SIP 忙")
        return false
    end
    
    g_sip_state = SIP_STATE_DIALING
    g_call_direction = "incoming"
    local ok = exsip.dial(uri)
    if not ok then
        g_sip_state = SIP_STATE_IDLE
        g_call_direction = nil
        return false
    end
    return true
end

-- 获取当前状态
function sip_bridge_agent.get_state()
    return {
        started = g_started,
        sip_registered = g_sip_registered,
        sip_state = g_sip_state,
        cc_state = g_cc_state,
        cc_ready = g_cc_ready,
        in_call = (g_sip_state == SIP_STATE_CONNECTED and g_cc_state == CC_STATE_CONNECTED),
        call_direction = g_call_direction,
        call_duration = g_call_start_time and (os.time() - g_call_start_time) or 0,
        local_audio = g_enable_local_audio,
    }
end

-- 模拟手机来电（仅测试用）
function sip_bridge_agent.simulate_mobile_incoming(number, delay_ms)
    if cc and cc.simulate_incoming then
        cc.simulate_incoming(number or "13800138000", delay_ms or 100)
    else
        logw("simulate_mobile_incoming 不可用")
    end
end

return sip_bridge_agent
