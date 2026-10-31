-- 本轮只验证：SIP 呼入 -> CC 拨打 10086 -> 桥接就绪 -> 自动发送一次 2。
-- 填入与原 PCM demo 相同的 SIP 服务配置；软电话使用另一个 SIP 账号。
local config = {
    sip_server_addr = "YOUR_SIP_SERVER",
    sip_server_port = 5060,
    sip_domain = "", -- 空字符串时使用服务器地址
    sip_username = "YOUR_SIP_USERNAME",
    sip_password = "YOUR_SIP_PASSWORD",
    sip_transport = "udp",
    -- TLS 时使用你自己的服务器 CA，并在 Luatools 加入对应文件：
    -- sip_tls = {ca_cert = io.readFile("/luadb/sip-ca.pem")},
    media_encryption = "none",
    remote_sip_uri = "", -- 本轮不启用手机呼入转 SIP

    -- 固定拨号目标。软电话呼叫模组 SIP 账号即可，无需服务器识别号码 10086。
    -- 不解析 SIP URI 中的目标号，也不要在此填写 "10086,2"。
    target_phone_number = "10086",
    auto_answer_sip = true,
    auto_handle_mobile_incoming = false,

    -- 两侧接通且媒体就绪后计时；每通只尝试一次，重复事件不会重复发送。
    -- 若当地 10086 尚未开放按键输入，可将 delay_ms 改为 5000 或更长。
    dtmf_delay_ms = 2000,
    dtmf_duration_ms = 300, -- cc.sendDtmf 支持 100-1000 ms；按键固定为 "2"

    rtp_port = 40000,
    codec = "PCMA", -- 首轮用 PCMA；仍保留原 demo 的其他 codec 能力
    ptime = 20,
    adapter = socket.LWIP_GP,
    cc_audio_start_timeout_ms = 3000,
    cc_media_min_connected_ms = 2000,
    cc_media_missing_call_limit = 3,
    cc_media_reboot_on_error = false, -- 诊断阶段保留日志，不因连续无 PCM 自动重启
}

-- Air780EHV 未连接外置看门狗时不占用 GPIO23；有该硬件才开启。
config.WDT_CONFIG = {ENABLE = false, FEED_PIN = 23, FEED_INTERVAL = 180}
return config
