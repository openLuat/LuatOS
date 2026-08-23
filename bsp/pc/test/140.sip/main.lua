-- SIP/VoIP PC 模拟器测试脚本
-- 用于验证 LuatOS PC 模拟器上的 SIP 通话功能

PROJECT = "sip_pc_test"
VERSION = "1.0.0"

require("sys")

local sip = require("exsipclient")

-- local SIP_CONFIG = {
--     sip_server_addr = "180.152.6.34",
--     sip_server_port = 8910,
--     sip_domain = "180.152.6.34",
--     sip_username = "100000",
--     sip_password = "Mm123.",
--     sip_transport = exsip.TRANSPORT_UDP,
--     auto_answer = false,
-- }

-- 配置 SIP 服务器信息（请根据实际情况修改）
local SIP_SERVER = "180.152.6.34"      -- SIP 服务器地址
local SIP_PORT = 8910                -- SIP 服务器端口
local SIP_DOMAIN = "180.152.6.34"       -- SIP 域
-- local SIP_USER = "10123450"              -- 用户名
-- local SIP_PASSWORD = "Air.012345"        -- 密码
local SIP_USER = "195544F0"              -- 用户名
local SIP_PASSWORD = "Air.95544F"        -- 密码
local SIP_TRANSPORT = "udp"          -- 传输协议：udp / tcp / tls

-- voip 运行状态
local voip_running = false

-- 事件回调
local function on_sip_event(event, action, payload)
    log.info("sip", "event", event, action, payload and "payload" or "nil")

    if event == "register" and action == "ok" then
        log.info("sip", "注册成功")
        -- 注册成功后，可以发起呼叫（用于测试）
        -- sip.call("1002")

    elseif event == "call" and action == "incoming" then
        log.info("sip", "收到来电，自动接听")
        sip.answer()

    elseif event == "call" and action == "established" then
        log.info("sip", "通话建立")

    elseif event == "call" and action == "ended" then
        log.info("sip", "通话结束")
        if voip_running then
            voip.stop()
            voip_running = false
        end

    elseif event == "media" and action == "ready" then
        log.info("sip", "媒体协商完成，启动 voip")
        -- payload 包含 remote_ip, remote_port, codec, local_rtp_port 等
        log.info("sip", "media info", payload.remote_ip, payload.remote_port, payload.codec)
        local codec_type = 0
        if payload.codec == "PCMA" then
            codec_type = 1
        end
        local ret = voip.start({
            remote_ip = payload.remote_ip,
            remote_port = payload.remote_port,
            local_port = payload.local_rtp_port,
            codec = codec_type,
            sample_rate = 8000,
            ptime = 20,
        })
        if ret then
            voip_running = true
            log.info("sip", "voip 启动成功")
        else
            log.error("sip", "voip 启动失败", ret)
        end

    elseif event == "media" and action == "stop" then
        log.info("sip", "媒体停止")
        if voip_running then
            voip.stop()
            voip_running = false
        end

    elseif event == "error" then
        log.error("sip", "错误", action, payload)
    end
end

socket.dft(socket.ETH0) -- PC模拟器-使用默认的以太网接口
-- 启动 SIP 客户端
sys.taskInit(function()
    sys.wait(2000)  -- 等待网络就绪

    log.info("sip", "启动 SIP 客户端...")
    local ok = sip.start({
        sip_server_addr = SIP_SERVER,
        sip_server_port = SIP_PORT,
        sip_domain = SIP_DOMAIN,
        sip_username = SIP_USER,
        sip_password = SIP_PASSWORD,
        sip_transport = SIP_TRANSPORT,
        event_callback = on_sip_event,
    })
    if ok then
        log.info("sip", "SIP 客户端启动成功")
    else
        log.error("sip", "SIP 客户端启动失败")
    end

    -- 测试：注册成功后，等待一段时间再发起呼叫
    -- 也可以手动在串口输入命令来发起呼叫
    sys.wait(10000)
    -- sip.stop()  -- 停止 SIP 客户端
    sip.call("1903CFC0")
    -- sip.call("1903CFC0")
end)

-- 启动系统
sys.run()
