--[[
@module  gb28181_app
@summary GB28181 设备侧应用：注册/目录 + 点播推流 + 语音对讲
@usage
启动顺序：等 IP → NTP → 装载 H.264 → client.start() → 事件循环/状态打印。
音频搬运/编解码在 exgb28181audio；本文件负责业务调度和板级音频初始化
（codec 上电、ES8311 I2C 初始化）。
]]

local client       = require "exgb28181client"
local gba          = require "exgb28181audio"
local cfg          = require "gb28181_config"
local video_source = require "video_source"
local gb = gb28181

-- 所选网卡的 socket 适配器（gb28181_config.lua 的 M.NETDRV）；
-- 未配置时与 netdrv_device.lua 保持一致，按以太网处理
local ADAPTER = ((cfg.NETDRV or "eth") == "eth")
                and socket.LWIP_ETH or socket.LWIP_GP

-- 等所选网卡（4G / CH390）拿到 IP
local function wait_ip(timeout_ms)
    local waited = 0
    while waited < timeout_ms do
        if socket.adapter(ADAPTER) then return true end
        sys.waitUntil("IP_READY", 1000)
        waited = waited + 1000
    end
    return false
end

--=============================================================================
-- 板级音频（引脚/电源/I2S 都留在 demo，库只做通用音频搬运）
--=============================================================================

-- 每次起音频前都要重设：驱动默认 channel=STEREO，8k 单声道会被当交错
local function apply_i2s_mode()
    if not (audio_v2 and audio_v2.config) then return "n/a(无 audio_v2)" end
    local mode = cfg.AUDIO_I2S_MODE or "i2s"
    local chan = cfg.AUDIO_I2S_CHANNEL or "right"
    local bits = cfg.AUDIO_I2S_FRAME_BITS or 16
    local r_bits = tostring(audio_v2.config(audio_v2.CFG_PARAM_I2S_FRAME_BITS,
                                            bits, bits))
    local r_chan = tostring(audio_v2.config(audio_v2.CFG_PARAM_I2S_CHANNEL_TYPE,
                        chan == "left" and audio_v2.CFG_VALUE_I2S_CHANNEL_TYPE_LEFT
                                        or  audio_v2.CFG_VALUE_I2S_CHANNEL_TYPE_RIGHT))
    local mode_val = {
        i2s = audio_v2.CFG_VALUE_I2S_MODE_I2S,
        lsb = audio_v2.CFG_VALUE_I2S_MODE_LSB,
        msb = audio_v2.CFG_VALUE_I2S_MODE_MSB,
    }
    local r_mode = tostring(audio_v2.config(audio_v2.CFG_PARAM_I2S_MODE,
                        mode_val[mode] or audio_v2.CFG_VALUE_I2S_MODE_I2S))
    return string.format("%s/%s/%s (位宽=%s 声道=%s 模式=%s)",
                         mode, chan, bits, r_bits, r_chan, r_mode)
end

-- 开机一次：codec 上电 + I2C 初始化（ES8311）
local function setup_audio_hw()
    if cfg.AUDIO_CODEC_PWR_PIN and gpio then
        gpio.setup(cfg.AUDIO_CODEC_PWR_PIN, cfg.AUDIO_CODEC_POWER_LEVEL or 1)
        log.info("gb28181", "codec 电源已拉高",
                 "GPIO" .. tostring(cfg.AUDIO_CODEC_PWR_PIN))
        sys.wait(cfg.AUDIO_CODEC_READY_MS or 200)
    end

    local i2c_id = cfg.AUDIO_CODEC_I2C_ID or 0
    local rate   = cfg.AUDIO_CODEC_I2S_SAMPLE or 8000
    local okr, es8311 = pcall(require, "es8311")
    if not okr then
        log.error("gb28181", "require es8311 失败", tostring(es8311))
    else
        i2c.setup(i2c_id, i2c.FAST)
        if not es8311.init(i2c_id) then
            log.error("gb28181", "ES8311 init 失败，先查供电 GPIO"
                      .. tostring(cfg.AUDIO_CODEC_PWR_PIN))
        else
            local sr_ok = es8311.set_sample_rate(i2c_id, rate,
                                                 cfg.AUDIO_CODEC_MCLK_DIV or 256)
            es8311.set_data_bits(i2c_id, 16)
            es8311.set_format(i2c_id)
            es8311.resume(i2c_id)
            es8311.set_voice_vol(i2c_id, 50)
            es8311.set_mic_vol(i2c_id, 85)
            log.info("gb28181", "ES8311 已初始化", "i2c" .. tostring(i2c_id),
                     rate .. "Hz", "set_sample_rate=" .. tostring(sr_ok))
        end
    end
end

-- 每次 gba.start 前由库回调：重设 I2S 参数
local function audio_hw_prepare()
    log.info("gb28181", "本次 I2S =", tostring(apply_i2s_mode()))
end

-- 当前音频会话；audio_starting 防止并发启动
local audio_session = nil
local audio_starting = false

local function stop_audio()
    if audio_session then
        local call_id = audio_session.call_id
        audio_session = nil            -- 先清，避免 stop_talk 的 ended 回调重入
        gba.stop()
        client.stop_talk(call_id)      -- 同步清掉 talks 里的会话，避免泄漏
    end
end

--[[
开/切对讲音频。
  · 设备发起的广播会话（平台 Broadcast 通知）只收；
  · 平台发起的对讲会话（Talk INVITE）才上行。
  · 先停旧会话、等音频设备释放，再起新的：voip/audio_v2 的 stop 是异步的。
]]
local function do_start_audio(sess, platform_talk)
    local ok, why = gba.available()
    if not ok then
        log.warn("gb28181", "跳过对讲", why)
        return
    end

    -- 旧会话可能因媒体断开自行结束（voip 已非 running），但 audio_session
    -- 还留着；不清理会让新的广播会话被"已经开着"直接挡掉，表现为喊话没声音。
    if audio_session and not gba.is_running() then
        log.info("gb28181", "上一个音频会话已结束，清理", audio_session.call_id)
        stop_audio()
    end

    if audio_session then
        -- 同一路广播会话的重复通知：已经开着，直接返回；
        -- 其它情况（换了会话、平台对讲到达、旧对讲媒体已死）都先停旧的再起新的。
        if not platform_talk and audio_session.call_id == sess.call_id then return end
        stop_audio()
    end

    -- 等上一路音频引擎真正释放（voip/audio_v2 的 stop 是异步的）
    gba.wait_idle(300, { voip = true })

    if not (client.talks() or {})[sess.call_id] then
        log.info("gb28181", "对讲会话在启动等待期间已结束", sess.call_id)
        return
    end

    --[[
    **只有平台发起的对讲（Talk INVITE）才发送上行**：
      · 喊话/广播（设备发起）是平台→设备单向，设备只播放；
      · 即使 SDP 写了 sendrecv，喊话会话的上行也没有消费者，只会堆在
        本机发送队列里，最终吃光 PSRAM。
    ]]
    local allow_tx = (platform_talk == true)
    local opts = {}
    for k, v in pairs(cfg.AUDIO_OPTS or {}) do opts[k] = v end
    opts.hw_prepare = audio_hw_prepare
    opts.tx = allow_tx
    local started, err = gba.start(sess, opts)
    log.info("gb28181", "音频引擎 start",
             started and "OK" or ("失败: " .. tostring(err)),
             "engine=voip",
             "上行=" .. (allow_tx and "on" or "off"))
    if started then
        audio_session = sess
    end
end

local function start_audio(sess, platform_talk)
    if not cfg.ENABLE_TALK then return end
    -- 客户端在收包回调里调用本函数，那里不能 yield；wait_idle 需要协程
    sys.taskInit(function()
        if audio_starting then return end
        audio_starting = true
        local okp, errp = pcall(do_start_audio, sess, platform_talk)
        if not okp then
            log.error("gb28181", "音频启动异常", errp)
        end
        audio_starting = false
    end)
end

-- 点播建立后持续推流（推流循环要 sys.wait，放独立任务）
local function start_pushing(sess, call_id)
    sys.taskInit(function()
        local n = video_source.push_loop(sess, client)
        log.info("gb28181", "推流循环退出", call_id, "本次共推", n, "帧")
    end)
end

local function on_event(ev, act, p)
    p = p or {}

    if ev == "register" and act == "ok" then
        log.info("gb28181", "★ 注册成功", "有效期", p.expires)

    elseif ev == "register" and act == "fail" then
        log.error("gb28181", "注册失败", "code", p.code, "reason", p.reason)

    elseif ev == "invite" and act == "accepted" then
        log.info("gb28181", "平台请求点播", p.call_id, p.session_name or "",
                 p.is_playback and "(历史回放)" or "(实时)")

    elseif ev == "media" and act == "ready" then
        -- ACK 后两表都会发 media/ready，只处理 sessions 里的视频会话
        local sess = client.sessions()[p.call_id]
        if not sess then
            -- 对讲会话，走 start_audio
        elseif sess.is_playback then
            log.warn("gb28181", "平台发起了历史回放，本 demo 不支持(需要 exgb28181playback)", p.call_id)
        else
            log.info("gb28181", "★ 对话已建立，开始推流", p.call_id, "ssrc", p.ssrc)
            start_pushing(sess, p.call_id)
        end

    elseif ev == "invite" and act == "rejected" then
        log.warn("gb28181", "拒绝了平台的 INVITE", tostring(p.reason))

    elseif ev == "talk" and act == "accepted" then
        -- accepted 的 payload 没有 stream 字段，必须从 talks() 取会话
        local platform_talk = (p.incoming == true)
        log.info("gb28181", "对讲会话建立",
                 platform_talk and "对讲(平台发起)" or "广播(设备发起)",
                 "方向=" .. tostring(p.direction or "?"))
        local sess = (client.talks() or {})[p.call_id]
        if sess then start_audio(sess, platform_talk) end

    elseif ev == "talk" and act == "failed" then
        log.error("gb28181", "平台拒绝了对讲", "code", p.code, "reason", p.reason)

    elseif (ev == "talk" or ev == "call") and act == "ended" then
        -- 只关引擎所在那一路；点播结束也会发 call/ended，别误伤对讲
        log.info("gb28181", "会话结束", ev, p.call_id, tostring(p.reason or ""))
        if audio_session and (audio_session.call_id == p.call_id
                              or not (client.talks() or {})[audio_session.call_id]) then
            stop_audio()
        end

    elseif ev == "net" and act == "closed" then
        log.warn("gb28181", "信令链路断开", tostring(p.reason))

    elseif ev == "error" then
        log.error("gb28181", "错误", act, tostring(p.reason))
    end
end

--=============================================================================
-- 主流程
--=============================================================================
sys.taskInit(function()
    -- 1、等网卡
    local netdrv = cfg.NETDRV or "eth"
    log.info("gb28181", "等待网络(" .. netdrv .. ")获取 IP ...")
    if not wait_ip(60000) then
        log.error("gb28181", "等 IP 超时：" .. ((netdrv == "eth")
            and "检查网线/路由器 DHCP，以及 netdrv_eth_spi 里的接线参数"
            or "检查 SIM 卡/天线/信号，以及 4G 是否附着成功"))
        return
    end
    log.info("gb28181", "网络就绪", socket.localIP(ADAPTER))

    -- 2、对时（失败不阻塞）
    if cfg.ENABLE_NTP then
        socket.sntp()
        if sys.waitUntil("NTP_UPDATE", 5000) then
            log.info("gb28181", "NTP 同步成功", os.date("%Y-%m-%d %H:%M:%S"))
        else
            log.warn("gb28181", "NTP 同步失败，继续启动")
        end
    end

    -- 3、视频源（没有源就拒绝点播）
    local has_video = false
    if cfg.ENABLE_VIDEO then
        local src, err = video_source.load(cfg.VIDEO_PATH)
        if src then
            video_source.src = src
            has_video = true
            log.info("gb28181", "视频源就绪", cfg.VIDEO_PATH,
                     "访问单元", src.count, "个")
        else
            log.warn("gb28181", "视频源不可用，改为拒绝视频点播", err)
        end
    end

    -- 4、板级音频初始化（对讲用）
    if cfg.ENABLE_TALK then
        setup_audio_hw()
    end

    -- 5、起客户端
    log.info("gb28181", "平台配置 =", "luatos",
             cfg.SERVER_ADDR .. ":" .. cfg.SERVER_PORT, cfg.TRANSPORT,
             "设备编码", cfg.DEVICE_ID, "通道", cfg.CHANNEL_ID,
             "对讲offer", cfg.AUDIO_OFFER_TCP and "tcp" or "udp")
    local ok, err = client.start({
        server_addr = cfg.SERVER_ADDR,
        server_port = cfg.SERVER_PORT,
        server_id   = cfg.SERVER_ID,
        domain      = cfg.DOMAIN,
        device_id   = cfg.DEVICE_ID,
        password    = cfg.PASSWORD,
        transport   = cfg.TRANSPORT,
        local_port  = cfg.LOCAL_PORT,
        keepalive   = cfg.KEEPALIVE,
        expires     = cfg.EXPIRES,

        adapter     = ADAPTER,

        rtp_port_base = cfg.RTP_PORT_BASE,
        -- 音频媒体始终由外部引擎接管（voip），本层只协商端口
        audio_port     = cfg.ENABLE_TALK and cfg.AUDIO_PORT or nil,
        -- 引擎自行停止（平台关媒体后 voip 会自己停）时，由库回收 talks 会话
        audio_alive    = function(_sess) return gba.is_running() end,
        audio_offer_tcp = cfg.AUDIO_OFFER_TCP or nil,
        debug_sip      = cfg.DEBUG_SIP or nil,
        no_video       = (not has_video) or nil,

        device = {
            name         = "LuatOS-780EHV",
            manufacturer = "LuatOS",
            model        = "Air780EHV",
            firmware     = "V1.0",
            channel      = #cfg.CHANNELS,
        },

        -- 视频 PS 流里不内嵌音频
        ps_cfg = {
            video_stream_type = 0x1B,
            has_audio = 0,
        },

        channels       = cfg.CHANNELS,
        event_callback = on_event,
    })
    if not ok then
        log.error("gb28181", "client.start 失败", err)
        return
    end

    if not has_video then
        log.warn("gb28181", "当前无视频源：平台上点播放会被拒(488)，目录和对讲不受影响")
    end
    if cfg.ENABLE_TALK then
        local ready, why = gba.available()
        if not ready then
            log.warn("gb28181", "对讲不可用：" .. why)
        else
            gba.warn_optional()
            log.info("gb28181", "对讲已就绪：等平台的 Broadcast 通知或 Talk INVITE",
                     "engine=voip")
        end
    end

    -- 6、状态打印
    while true do
        sys.wait(cfg.STAT_MS)

        -- 引擎自行停止→库按 audio_alive 钩子回收 talks 会话并发 call/ended，
        -- 本处的 stop_audio（见 on_event）负责收掉引擎自己的资源。
        local nsess, ntalk = 0, 0
        for _ in pairs(client.sessions() or {}) do nsess = nsess + 1 end
        for _ in pairs(client.talks() or {}) do ntalk = ntalk + 1 end

        local line = string.format(
            "注册=%s 点播会话=%d 对讲会话=%d",
            tostring(client.is_registered()), nsess, ntalk)
        local s = gba.stats()
        if s.running then
            line = line .. string.format(
                " 音频下行=%d 字节 上行=%d 字节 丢=%d",
                s.down_bytes, s.up_bytes, s.up_drop)

            local vs = s.voip
            if type(vs) == "table" then
                line = line .. string.format(
                    " voip[rx=%s bad=%s pf=%s fdr=%s txerr=%s jbsil=%s]",
                    tostring(vs.rx_packets), tostring(vs.rx_bad_payload),
                    tostring(vs.rx_parse_fail), tostring(vs.rx_frame_dropped),
                    tostring(vs.tx_errors), tostring(vs.jb_silence))

                -- 欠载/提交失败/已渲染/AEC参考欠：查播放侧撕裂
                line = line .. string.format(
                    " 音频[欠载=%s 提交失败=%s 已渲染=%s AEC参考欠=%s]",
                    tostring(vs.audio_tx_underrun), tostring(vs.audio_tx_commit_fail),
                    tostring(vs.audio_render_samples), tostring(vs.aec_ref_underflow))
            end
        end
        -- 内存水位：PSRAM 碎片化/泄漏会先表现在 netdrv 收包分配失败上
        local sys_total, sys_used = rtos.meminfo("sys")
        local ps_total, ps_used = rtos.meminfo("psram")
        line = line .. string.format(
            " 内存[sys=%d/%d psram=%d/%d lua=%dKB]",
            sys_used or 0, sys_total or 0, ps_used or 0, ps_total or 0,
            math.floor(collectgarbage("count")))
        log.info("gb28181", line)
    end
end)
