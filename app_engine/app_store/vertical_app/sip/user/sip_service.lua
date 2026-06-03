--[[
@module  sip_service
@summary SIP 业务封装模块
@version 1.0.0
@date    2026.05.28
@usage
封装 exsip 库，提供状态机管理和统一事件发布。
]]

local sip_service = {}

local exsip = require "exsip"
-- local exsip = nil
local g_status = "STATE_IDLE"   -- idle/initing/ready/dialing/incoming/connected
local g_config = nil

-- SIP 事件发布名
local EVT_PREFIX = "SIP_EVT_"

local function emit(event, ...)
    sys.publish(EVT_PREFIX .. event, ...)
end

--[[
获取当前 SIP 状态
@return string 状态名
]]
function sip_service.get_status()
    return g_status
end

--[[
SIP 统一事件回调
]]
local function sip_callback(event, arg1, arg2, arg3)
    log.info("sip_service", "callback", g_status, event, arg1, arg2)

    if event == "register" then
        local action = arg1
        if action == "ok" then
            emit("REGISTER_OK", arg2)
        elseif action == "failed" then
            emit("REGISTER_FAILED", arg2)
        elseif action == "challenge" then
            emit("REGISTER_CHALLENGE")
        end
    elseif event == "ready" then
        if g_status == "STATE_INITING" then
            g_status = "STATE_READY"
        end
        emit("READY")
    elseif event == "call" then
        local sub_event = arg1
        local data = arg2
        if sub_event == "incoming" then
            if g_status == "STATE_READY" then
                g_status = "STATE_INCOMING"
                local from_num = ""
                if data and data.from then
                    from_num = string.match(data.from, ':([^:@]+)@') or data.from
                end
                emit("INCOMING", from_num)
            end
        elseif sub_event == "ringing" then
            emit("RINGING")
        elseif sub_event == "connected" or sub_event == "established" then
            if g_status == "STATE_DIALING" or g_status == "STATE_INCOMING" then
                g_status = "STATE_CONNECTED"
                emit("CONNECTED")
            end
        elseif sub_event == "ended" or sub_event == "failed" then
            local reason = (data and data.reason) or ""
            if g_status == "STATE_DIALING" or g_status == "STATE_INCOMING" or g_status == "STATE_CONNECTED" then
                g_status = "STATE_READY"
                emit("ENDED", reason)
            end
        end
    elseif event == "media" then
        local sub_event = arg1
        if sub_event == "ready" then
            emit("MEDIA_READY", arg2)
        elseif sub_event == "stop" then
            emit("MEDIA_STOP")
        end
    elseif event == "message" then
        local sub_event = arg1
        local data = arg2
        if sub_event == "rx" and data then
            local from_num = ""
            if data.from then
                from_num = string.match(data.from, ':([^:@]+)@') or data.from
            end
            emit("MESSAGE_RX", from_num, data.body or "")
        elseif sub_event == "sent" then
            emit("MESSAGE_SENT", data and data.to)
        end
    elseif event == "lifecycle" then
        emit("LIFECYCLE", arg1, arg2)
    elseif event == "error" then
        emit("ERROR", arg1, arg2)
    elseif event == "voip" then
        emit("VOIP", arg1, arg2)
    end
end

--[[
登录并启动 SIP 服务
@param config table 配置表
  - sip_server_addr: 服务器地址
  - sip_server_port: 端口（默认5060）
  - sip_domain: 域名
  - sip_username: 用户名
  - sip_password: 密码
  - sip_transport: "UDP" 或 "TCP"
@return boolean 启动成功返回 true
]]
function sip_service.login(config)
    if not config then
        log.error("sip_service", "config is nil")
        return false
    end
    log.info("sip_service", "login_start", "status=", g_status)

    if g_status ~= "STATE_IDLE" then
        log.info("sip_service", "already in status:", g_status)
        return true
    end

    while not socket.adapter(socket.dft()) do
        -- 阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end

    local adapter = socket and socket.dft and socket.dft() or nil
    if config.adapter == nil then
        config.adapter = adapter
    end
    local adapter_to_use = config.adapter
    local adapter_ready = (socket and socket.adapter and adapter_to_use ~= nil) and not not socket.adapter(adapter_to_use) or false
    local local_ip = (socket and socket.localIP and adapter_ready and adapter_to_use ~= nil) and socket.localIP(adapter_to_use) or nil
    log.info("sip_service", "login_config", "server=", config.sip_server_addr or "<nil>", "transport=", config.sip_transport or "<nil>")
    if not adapter_ready then
        emit("ERROR", "network_not_ready", adapter_to_use)
        return false
    end

    local ok, mod = pcall(require, "exsip")
    if not ok or not mod then
        log.error("sip_service", "exsip module not found", ok, mod)
        emit("ERROR", "module_not_found", "exsip")
        return false
    end
    exsip = mod

    -- 初始化音频硬件（根据型号自动选择编解码器，仅初始化一次）
    if not audio_initialized then
        local exaudio = require "exaudio"
        local bsp = rtos.bsp() or ""
        local model = bsp:lower()
        local audio_setup_param = nil

        if model:find("air8000") then
            -- Air8000 系列使用 ES8311 (I2S)
            audio_setup_param = {
                model = "es8311",
                i2c_id = 0,
                pa_ctrl = 162,
                dac_ctrl = 164,
            }
        elseif model:find("air1601") then
            audio_setup_param = {
                model = "dac",
                pa_ctrl = 12,
                pa_on_level = 1,
                pa_delay = 10,
                dac_ch = 0,
            }
        elseif model:find("air1602") then
            audio_setup_param = {
                model = "dac",
                pa_ctrl = 45,
                pa_on_level = 1,
                pa_delay = 10,
                dac_ch = 0,
            }
        elseif model:find("air8101") then
            audio_setup_param = {
                model = "dac",
                pa_ctrl = 28,
                pa_on_level = 0,
                pa_delay = 10,
                dac_ch = 0,
            }
        else
            log.error("sip_service", "unsupported bsp for audio init:", bsp)
        end

        if audio_setup_param then
            local audio_ok = exaudio.setup(audio_setup_param)
            if audio_ok then
                exaudio.vol(70)
                if exaudio.mic_vol then
                    exaudio.mic_vol(70)
                end
                log.info("sip_service", "audio hardware initialized for", bsp)
                audio_initialized = true
            else
                log.error("sip_service", "audio hardware init failed")
            end
        end
    end

    g_config = config
    g_status = "STATE_INITING"

    exsip.on(sip_callback)

    if not exsip.init(config) then
        log.error("sip_service", "exsip.init failed")
        g_status = "STATE_IDLE"
        return false
    end

    if not exsip.start() then
        log.error("sip_service", "exsip.start failed")
        g_status = "STATE_IDLE"
        return false
    end

    log.info("sip_service", "SIP service starting...")
    return true
end

--[[
停止 SIP 服务并注销
]]
function sip_service.logout()
    if exsip then
        -- 清空回调，避免销毁后收到事件
        if exsip.on then
            exsip.on(function() end)
        end
        if exsip.stop then
            exsip.stop()
        end
    end
    exsip = nil
    g_status = "STATE_IDLE"
    g_config = nil
    log.info("sip_service", "SIP service stopped")
end

--[[
拨打电话
@param num string 目标号码
@return boolean
]]
function sip_service.dial(num)
    if not exsip or not exsip.dial then
        log.error("sip_service", "not ready to dial")
        return false
    end
    if g_status ~= "STATE_READY" then
        log.warn("sip_service", "cannot dial in status:", g_status)
        return false
    end
    local ok = exsip.dial(num)
    if ok then
        g_status = "STATE_DIALING"
    end
    return ok
end

--[[
接听来电
@return boolean
]]
function sip_service.accept()
    if not exsip or not exsip.accept then
        return false
    end
    if g_status ~= "STATE_INCOMING" then
        log.warn("sip_service", "no incoming call to accept")
        return false
    end
    return exsip.accept()
end

--[[
挂断通话
@return boolean
]]
function sip_service.hangup()
    if not exsip or not exsip.hangUp then
        return false
    end
    return exsip.hangUp()
end

--[[
发送即时消息
@param num string 目标号码
@param text string 消息内容
@return boolean
]]
function sip_service.send_message(num, text)
    if not exsip or not exsip.message then
        return false
    end
    if g_status ~= "STATE_READY" then
        log.warn("sip_service", "cannot send message in status:", g_status)
        return false
    end
    return exsip.message(num, text)
end

--[[
获取当前配置（脱敏）
@return table
]]
function sip_service.get_config()
    if exsip and exsip.get_config then
        return exsip.get_config()
    end
    return nil
end

--[[
获取当前通话号码
@return string
]]
function sip_service.get_current_call()
    if exsip and exsip.get_current_call then
        return exsip.get_current_call()
    end
    return nil
end

--[[
检查是否已注册
@return boolean
]]
function sip_service.is_registered()
    if exsip and exsip.isRegistered then
        return exsip.isRegistered()
    end
    return false
end

return sip_service
