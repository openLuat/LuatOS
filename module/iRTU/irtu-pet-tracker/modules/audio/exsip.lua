--[[
@module exsip
@summary SIP 适配层，将 exsipclient 封装为 sip_talk 所需接口
]]

local exsip = {}
local exsipclient = require("exsipclient")

exsip.TRANSPORT_UDP = "udp"
exsip.TRANSPORT_TCP = "tcp"

local g_callback = nil
local g_started = false

function exsip.init(cfg)
    if not exsipclient then
        log.error("exsip", "exsipclient不可用")
        return false
    end
    if g_started then
        log.warn("exsip", "已经初始化")
        return true
    end

    local transport = cfg.sip_transport or "udp"
    local ok = exsipclient.start({
        server = cfg.sip_server_addr,
        port = cfg.sip_server_port,
        domain = cfg.sip_domain,
        user = cfg.sip_username,
        password = cfg.sip_password,
        transport = transport,
        event_callback = function(event, action, payload)
            if not g_callback then return end
            if event == "register" then
                if action == "ok" then
                    g_callback("register", "ok", payload)
                    g_callback("ready")
                elseif action == "challenge" then
                    g_callback("register", "challenge")
                else
                    g_callback("register", "failed")
                end
            elseif event == "call" then
                if action == "incoming" then
                    g_callback("call", "incoming", payload)
                elseif action == "established" then
                    g_callback("call", "connected", payload)
                elseif action == "ended" then
                    g_callback("call", "ended", payload)
                end
            elseif event == "lifecycle" then
                if action == "online" then
                    g_callback("lifecycle", "online", payload)
                else
                    g_callback("error", action)
                end
            elseif event == "error" then
                g_callback("error", payload and payload.event or "net")
            end
        end
    })
    if ok then
        g_started = true
    end
    return ok
end

function exsip.start()
    -- exsipclient.start() 已经启动了，这里是空操作
    return true
end

function exsip.stop()
    g_started = false
    if exsipclient then
        exsipclient.stop()
    end
end

function exsip.on(callback)
    g_callback = callback
end

function exsip.dial(target)
    if not g_started then return false end
    exsipclient.call(target)
    return true
end

function exsip.accept()
    exsipclient.answer()
end

function exsip.hangUp()
    exsipclient.hangup()
end

return exsip
