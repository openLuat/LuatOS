PROJECT = "sip_demo"
VERSION = "1.0.0"
local sip = require "sip_client"

-- ======== 配置 ========

-- SIP 服务器
local SIP_SERVER = "xxx.xxx.xxx.xxx"
local SIP_PORT = 8910
local SIP_DOMAIN = "xxx.xxx.xxx.xxx"
local SIP_USER = "xxx"
local SIP_PASSWORD = "xxxxxxxxx"

-- ======== VoIP 回调 ========
if voip then
    voip.on("state", function(state)
        log.info("voip", "state:", state) -- "started" / "stopped" / "error"
    end)

    voip.on("stats", function(stats)
        log.info("voip-stats", "tx", stats.tx_packets, "rx", stats.rx_packets, "lost", stats.rx_lost, "ooo",
            stats.rx_out_of_order, "jb", stats.jb_played, "silence", stats.jb_silence)
    end)

    voip.on("error", function(err)
        log.error("voip", "error:", err)
    end)
end
-- ======== SIP + VoIP 集成 ========

--- 当 SIP 层协商完 SDP 后, 用 C voip 引擎启动 RTP 音频
local function start_voip_engine(session)
    if not voip then
        log.error("voip", "core not support voip")
        return
    end
    -- session 由 SIP 层提供, 包含:
    --   remote_ip, remote_port, local_rtp_port, codec, ptime, sample_rate

    local codec_map = {
        PCMU = voip.PCMU,
        PCMA = voip.PCMA
    }
    local codec = codec_map[session.codec] or voip.PCMU

    local ok = voip.start({
        remote_ip = session.remote_ip,
        remote_port = tonumber(session.remote_port) or 10000,
        local_port = tonumber(session.local_rtp_port) or 0,
        codec = codec,
        ptime = tonumber(session.ptime) or 20,
        sample_rate = tonumber(session.sample_rate) or 8000,
        jitter_depth = 3,
        multimedia_id = 0,
        stats_interval = 5000
    })

    if ok then
        log.info("voip", "engine started", session.remote_ip .. ":" .. session.remote_port,
            "codec=" .. tostring(session.codec))
    else
        log.error("voip", "engine start failed")
    end
end

--- 停止 VoIP 引擎
local function stop_voip_engine()
    if not voip then
        return
    end
    if voip.isRunning() then
        voip.stop()
        log.info("voip", "engine stopping")
    end
end

-- exaudio配置参数
local audio_configs = {
    model = "es8311", -- dac类型: "es8311"
    i2c_id = 0, -- i2c_id: 可填入0，1 并使用pins 工具配置对应的管脚
    pa_ctrl = gpio.AUDIOPA_EN, -- 音频放大器电源控制管脚
    dac_ctrl = 20, -- 音频编解码芯片电源控制管脚

    -- 【注意：固件版本＜V2026，这里单位为1ms，这里填600，否则可能第一个字播不出来】
    dac_delay = set_dac_delay, -- DAC启动前冗余时间

    pa_delay = 100, -- DAC启动后延迟打开PA的时间(单位1ms)
    dac_time_delay = 100, -- 播放完毕后PA与DAC关闭间隔(单位1ms)
    bits_per_sample = 16, -- 采样位深
    pa_on_level = 1 -- PA打开电平 1:高 0:低
}

-- ======== 主任务 ========
local exaudio = require "exaudio"

local function sip_event_cb(event, action, payload)
    if event == "register" and action == "ok" then
        log.info("sip", "registered, expires=", payload.expires)
        -- sip.message("1011", "Hello from LuatOS SIP client!")
        -- sip.call("1013") -- 主动拨打电话
    elseif event == "media" then
        log.info("sip", "media", action)
        if action == "ready" then
            local session = payload.session or payload
            log.info("sip", "media ready", session.remote_ip, session.remote_port, session.codec)
            start_voip_engine(session)
        end
    elseif event == "call" then
        log.info("sip", "call state:", action)
        if action == "incoming" then
            log.info("sip", "call from", payload.from, "call_id:", payload.call_id)
            -- 自动接听 (不传 media 对象, SDP 协商仍由 SIP 层完成)
            sip.answer()
        elseif action == "ended" or action == "failed" then
            stop_voip_engine()
        end
    elseif event == "message" then
        if action == "rx" then
            log.info("sip", "message:", payload.from, payload.body)
        elseif action == "sent" then
            log.info("sip", "message sent to", payload.to)
        end
    elseif event == "error" then
        log.error("sip", "error:", action, payload.event, payload.param)
    end
end

sys.taskInit(function()

    if exaudio.setup(audio_configs) then
        log.info("audio_drv", "exaudio.setup初始化成功")
    else
        log.error("audio_drv", "exaudio.setup初始化失败")
    end

    if SIP_SERVER == "xxx.xxx.xxx.xxx" then
        log.error("sip", "请先配置 SIP 服务器地址和账号密码")
        return
    end

    sys.waitUntil("IP_READY")
    sip.start({
        server = SIP_SERVER,
        port = SIP_PORT,
        domain = SIP_DOMAIN,
        user = SIP_USER,
        password = SIP_PASSWORD,
        transport = "TCP",
        event_callback = sip_event_cb
    })
end)

sys.run()
