--[[
@module sip_srtp
@summary SIP over TLS + SDES/DTLS-SRTP 加密通话验收脚本（Air8101 / BK7258）
@version 1.0
@date    2026.10.21
@usage

用途：docs/voip-dtls-srtp-air8101-port.md 的 M1/M3 上机验收入口。

固件要求：106 / 107 / 108（16M Flash），需带 LUAT_USE_SRTP + LUAT_USE_DTLS_SRTP。
  直接 `python build_luatos_types.py Air8101 106` 编出来的固件即满足。

三段自检，日志前缀 [srtp]：
  1) 能力自检：voip.securityIdentity / securityCreate / securityInfo 是否存在，
     并打印本机 DTLS 指纹（SHA-256），用于与对端 SDP 里的 a=fingerprint 对照；
  2) 信令：sip_transport="tls"，加载 ca.pem，注册；
  3) 媒体：按 MEDIA_MODE 协商 sdes / dtls-srtp，外呼 → 通话 10s → 挂断。

失败判据（M1/M3 的硬要求）：
  * CA 不对、指纹不匹配、DTLS 握手超时 —— 都必须是 register/call 的 failed，
    绝不允许出现"注册成功但媒体明文"的情况。
]]

PROJECT = "Air8101_SipSrtp_Demo"
VERSION = "001.999.000"

local exaudio = require "exaudio"
local exsip = require "exsip"

log.info("main", PROJECT, VERSION)

-- ======== 需要修改的部分 ========
local WIFI_SSID     = "admin-降功耗，找合宙！"
local WIFI_PASSWORD = "Air123456"

-- 设备 ID：WiFi 模组的 hmeta.devid() 返回的是 6 字节原始 MAC（二进制），不是十六进制文本，
-- 所以先按 wlan.getMac() 同款规则统一成 12 位十六进制字符串。
-- SIP 平台账号规则：MAC 转十进制数字，末尾补一个 "0"。
local function mac_to_hex()
    local raw
    if hmeta and type(hmeta.devid) == "function" then
        raw = hmeta.devid()
    end
    if type(raw) == "string" and #raw == 6 then
        -- 原始 6 字节，逐字节转十六进制
        return (raw:gsub(".", function(c)
            return string.format("%02X", string.byte(c))
        end))
    end
    if type(raw) == "string" and #raw > 0 then
        local hex = raw:gsub("[:%-%s]", "")
        if hex:match("^%x+$") then
            return (hex:upper())
        end
    end
    -- 兜底：wlan.getMac() 直接返回十六进制字符串
    if wlan and type(wlan.getMac) == "function" then
        local mac = wlan.getMac()
        if type(mac) == "string" and #mac == 12 and mac:match("^%x+$") then
            return (mac:upper())
        end
    end
    return nil
end

-- 十六进制字符串 -> 十进制数字字符串。
-- 注意：本固件 printf 未链接浮点支持（无 _printf_float），string.format("%.0f", ...)
-- 会输出成 "2e+14" 这种形式，因此这里用十进制逐位进位，全程整数运算。
local function hex_to_dec(hex)
    local digits = { 0 }                    -- 十进制各位，低位在 index 1
    for i = 1, #hex do
        local carry = tonumber(hex:sub(i, i), 16)
        if not carry then
            return nil
        end
        for j = 1, #digits do
            local v = digits[j] * 16 + carry
            digits[j] = v % 10
            carry = math.floor(v / 10)
        end
        while carry > 0 do
            digits[#digits + 1] = carry % 10
            carry = math.floor(carry / 10)
        end
    end
    local out = {}
    for i = #digits, 1, -1 do
        out[#out + 1] = string.char(48 + digits[i])
    end
    return table.concat(out)
end

local function device_sip_dec()
    local hex = mac_to_hex()
    if not hex then
        return nil
    end
    return hex_to_dec(hex)
end

-- 账号规则：STA MAC 十进制末尾补 "0"；默认被叫：同一前缀末尾补 "1"
local mac_dec = device_sip_dec()
local sip_username = mac_dec and (mac_dec .. "0") or nil
local callee_number = mac_dec and (mac_dec .. "1") or nil
log.info("srtp", "设备 SIP 账号:", sip_username or "nil", "默认被叫:", callee_number or "nil")

-- ======== 需要修改的部分 ========
local sip_config = {
    sip_server_addr = "cc.luatos.com",
    sip_server_port = 5061,
    sip_domain      = "cc.luatos.com",
    sip_username    = sip_username, -- 设备ID(STA MAC)转十进制后末尾补 0
    sip_password    = "123456",
}

-- "dtls-srtp"（M3）| "sdes"（M2）| "none"（M1，只验信令 TLS）
local MEDIA_MODE = "sdes"

-- 可信 CA（PEM 文本）。放文件系统里，避免写进固件：
--   Luatools 把 ca.pem 传到设备 /luadb/ca.pem，或用 fskv/io 自行写入其他路径
local CA_FILE = "/luadb/ca.pem"

-- 默认被叫为设备ID十进制末尾补 1，实际号码不同时直接改这里
local callee_override = nil
if type(callee_override) == "string" and #callee_override > 0 then
    callee_number = callee_override
end
local AEC = true

-- 打印完整 SIP 响应（含 SDP）。排查"对端到底回没回加密"时必须打开。
local DEBUG_SIP = false
-- 麦克风增益 {数字, 模拟}，0-100。nil = 用 exaudio 默认值(数字60/模拟50)。
-- 对端听不到你时，先设成 {90, 80} 再试一次。
local MIC_GAIN = nil
-- ================================

-- Air8101 使用内置 DAC 输出，PA 控制脚按实际底板调整
local audio_setup_param = {
    model = "dac",
    pa_ctrl = 27,
    pa_on_level = 1,
    dac_delay = 6,
}

local function read_ca()
    if not io or type(io.readFile) ~= "function" then
        return nil, "io.readFile 不可用"
    end
    local pem = io.readFile(CA_FILE)
    if not pem or #pem == 0 then
        return nil, "读不到 CA 文件: " .. CA_FILE
    end
    if not pem:find("BEGIN CERTIFICATE", 1, true) then
        return nil, "CA 不是 PEM 证书: " .. CA_FILE
    end
    return pem
end

-- 能力自检：缺 voip.security* 说明固件没开 LUAT_USE_SRTP
local function probe_security()
    if not voip then
        return false, "voip 库不存在"
    end
    for _, name in ipairs({ "securityIdentity", "securityCreate", "securityInfo", "securityRelease" }) do
        if type(voip[name]) ~= "function" then
            return false, "voip." .. name .. " 缺失（固件未启用 LUAT_USE_SRTP，请烧 106/107/108）"
        end
    end

    local identity = voip.securityIdentity()
    if not identity then
        return false, "securityIdentity 生成失败"
    end

    local mode = MEDIA_MODE
    if mode ~= "dtls-srtp" then mode = "sdes" end
    local ctx = voip.securityCreate(mode, identity)
    if not ctx then
        voip.securityRelease(identity)
        return false, "securityCreate(" .. mode .. ") 失败"
    end

    local info = voip.securityInfo(ctx)
    if info and info.mode then
        log.info("srtp", "本机安全模式:", info.mode)
        if info.fingerprint then
            log.info("srtp", "本机 DTLS 指纹(sha-256):", info.fingerprint)
        end
        if info.suite then
            log.info("srtp", "SDES 套件:", info.suite)
        end
    else
        log.warn("srtp", "securityInfo 未返回信息")
    end

    -- 探测用的上下文用完即释放，真实协商由 exsipclient 自己创建
    voip.securityRelease(ctx)
    voip.securityRelease(identity)
    return true
end

local registered = false
local connected = false
local t0 = 0

-- 失败原因 → 可执行提示。这些字符串来自共享层 exsipproto/exsipclient，不要改其本义。
local REASON_HINT = {
    dtls_srtp_required = "对端 SDP 不是 UDP/TLS/RTP/SAVP：服务器没开 DTLS-SRTP（把媒体降回了明文）。"
        .. "先试 MEDIA_MODE=sdes，或换一台开了 SRTP 的 PBX（见 docs 附录 A）。把 DEBUG_SIP 打开可看到对端 SDP。",
    sdes_required = "对端 SDP 不是 RTP/SAVP：服务器没开 SDES-SRTP。",
    unsupported_sdes_crypto = "对端没有 AES_CM_128_HMAC_SHA1_80 套件。",
    media_encryption_mismatch = "本地未加密但对端发了加密 SDP，或反之——两侧策略不一致。",
    invalid_fingerprint = "对端 a=fingerprint 不是合法的 sha-256（长度/字符不对）。",
    invalid_dtls_setup = "对端 a=setup 非法（answer 里不允许出现 actpass）。",
    tls_ca_required = "没给 CA：sip_tls.ca_cert 为空。",
    tls_verification_required = "sip_tls.verify=false 被拒绝：本实现强制校验证书。",
}

local function hint_of(reason)
    if type(reason) ~= "string" then return "" end
    local h = REASON_HINT[reason]
    return h and ("\n  → " .. h) or ""
end

local function on_sip_event(event_type, action, data)
    local ms = t0 > 0 and (mcu.ticks() - t0) or 0
    local reason = data and data.reason or nil
    if event_type == "register" then
        log.info("srtp", "注册事件:", action, "t_ms=", ms, reason or "")
        if action == "ok" then registered = true end
        if action == "failed" then
            log.error("srtp", "注册失败:" .. hint_of(reason))
        end
    elseif event_type == "call" then
        log.info("srtp", "通话事件:", action, "t_ms=", ms, reason or "")
        if action == "connected" then connected = true end
        if action == "failed" then
            log.error("srtp", "通话失败:" .. hint_of(reason))
        end
    elseif event_type == "media" then
        log.info("srtp", "媒体事件:", action, "t_ms=", ms, reason or "")
        if action == "ready" and data and data.encryption then
            log.info("srtp", "协商结果: encryption=", data.encryption)
        elseif action == "rejected" then
            -- 安全协商失败（指纹不符 / 套件不匹配 / 协议不是 RTP-SAVP）在这里暴露
            log.error("srtp", "媒体被拒绝:" .. hint_of(reason))
        end
    elseif event_type == "error" then
        log.error("srtp", "错误:", action)
    end
end

sys.taskInit(function()
    t0 = mcu.ticks()

    -- 0) 配置自检：这些变量来自文件顶部的配置区。裁剪/合并脚本时最容易漏掉其中一个，
    --    一旦为 nil 会在 exsip.init 处直接把 Lua VM 打崩并重启，所以先显式检查。
    if type(sip_config) ~= "table" then
        log.error("srtp", "配置缺失: sip_config")
        return
    end
    do
        local missing = {}
        for _, key in ipairs({ "sip_server_addr", "sip_server_port", "sip_domain", "sip_username", "sip_password" }) do
            if sip_config[key] == nil then missing[#missing + 1] = key end
        end
        if #missing > 0 then
            log.error("srtp", "配置缺失:", table.concat(missing, ","))
            return
        end
    end
    if type(MEDIA_MODE) ~= "string" then
        log.error("srtp", "配置缺失: MEDIA_MODE")
        return
    end
    if type(CA_FILE) ~= "string" then
        log.error("srtp", "配置缺失: CA_FILE")
        return
    end

    -- 1) 能力自检
    local ok, err = probe_security()
    if not ok then
        log.error("srtp", "自检失败:", err)
        return
    end
    log.info("srtp", "自检通过，媒体模式:", MEDIA_MODE)

    -- 2) CA
    local ca, ca_err = read_ca()
    if not ca then
        log.error("srtp", ca_err)
        return
    end
    log.info("srtp", "CA 已加载:", #ca, "字节")

    -- 音频（双向通话需要）
    if not exaudio.setup(audio_setup_param) then
        log.error("srtp", "音频初始化失败，请检查 DAC/PA 配置")
        return
    end
    if MIC_GAIN and type(exaudio.mic_vol) == "function" then
        exaudio.mic_vol(MIC_GAIN[1], MIC_GAIN[2])
        log.info("srtp", "麦克风增益: 数字", MIC_GAIN[1], "模拟", MIC_GAIN[2])
    end

    exsip.on(on_sip_event)
    exsip.init({
        sip_server_addr = sip_config.sip_server_addr,
        sip_server_port = sip_config.sip_server_port,
        sip_domain      = sip_config.sip_domain,
        sip_username    = sip_config.sip_username,
        sip_password    = sip_config.sip_password,
        sip_transport   = "tls",
        media_encryption = MEDIA_MODE,
        sip_tls         = { ca_cert = ca },
        aec             = AEC,
        aec_mode        = "speex",
        debug_sip_response = DEBUG_SIP,
    })

    if type(WIFI_SSID) == "string" and #WIFI_SSID > 0 then
        log.info("srtp", "连接 WiFi:", WIFI_SSID)
        wlan.init()
        wlan.connect(WIFI_SSID, WIFI_PASSWORD, 1)
    end

    exsip.start()

    local waited = 0
    while not exsip.isRegistered() and waited < 30000 do
        sys.wait(1000)
        waited = waited + 1000
    end
    if not exsip.isRegistered() then
        log.error("srtp", "M1 失败：30s 内未通过 TLS 注册成功")
        return
    end
    log.info("srtp", "M1 通过：TLS 注册成功，耗时", waited, "ms")

    if type(callee_number) ~= "string" or #callee_number == 0 then
        log.info("srtp", "未配置被叫号码，只做注册验证（M1 结束）")
        return
    end

    -- 3) 外呼 + 保持 10s + 挂断
    --    等 connected 之后再打 stats：媒体未建立时 stats 全是 0，打了反而误导。
    --    每 2s 一次：rx_packets 增长说明**下行**真的收到对端 RTP，tx_packets 增长说明
    --    **上行**在发；两者独立，能区分"单向有声"与"双向通"。jb_played≈rx_frames 才是
    --    真的把对端音频放出来了；rx_security_fail 非 0 则是密钥/解密问题。
    exsip.dial(callee_number)
    local waited_conn = 0
    while not connected and waited_conn < 30000 do
        sys.wait(200)
        waited_conn = waited_conn + 200
    end
    if not connected then
        log.error("srtp", "30s 内未接通，跳过媒体统计")
    end
    for i = 1, 5 do
        if not connected then break end
        sys.wait(2000)
        if type(voip.stats) == "function" then
            local st = voip.stats()
            if type(st) == "table" then
                log.info("srtp", string.format(
                    "voip.stats #%d: tx=%s rx=%s tx_bytes=%s rx_bytes=%s jb_played=%s jb_silence=%s rx_lost=%s rx_ooo=%s rx_sec_fail=%s encode_frames=%s decode_frames=%s aec_max_us=%s",
                    i, tostring(st.tx_packets), tostring(st.rx_packets),
                    tostring(st.tx_bytes), tostring(st.rx_bytes),
                    tostring(st.jb_played), tostring(st.jb_silence),
                    tostring(st.rx_lost), tostring(st.rx_out_of_order),
                    tostring(st.rx_security_fail), tostring(st.encode_frames),
                    tostring(st.decode_frames), tostring(st.aec_max_process_us)))
            end
        end
    end
    log.info("srtp", "保持 10s 结束，准备挂断；voip 状态:", voip.getState())
    exsip.hangUp()
    sys.wait(2000)
    log.info("srtp", "通话结束，voip 状态:", voip.getState())
end)

-- 用户代码已结束---------------------------------------------
sys.run()
