-- 示例配置：烧录前填写自己的 SIP 服务器、账号、密码和目标号码。
-- SIP 编码仅 PCMA/PCMU，ptime 固定 20；接通后媒体启动超时默认 1500 ms。
-- 网络选择见 netdrv_device.lua；adapter 必须与所选网卡一致。
return {
    sip_server_addr = "sip.example.com",
    sip_server_port = 5060,
    sip_domain = "sip.example.com",
    sip_transport = "udp",
    sip_username = "YOUR_SIP_USERNAME",
    sip_password = "YOUR_SIP_PASSWORD",
    remote_sip_uri = "sip:REMOTE_USER@sip.example.com",
    target_phone_number = "YOUR_PHONE_NUMBER",
    rtp_port = 40000,
    codec = "PCMU",
    ptime = 20,
    adapter = socket.LWIP_GP,
    auto_answer_sip = true,            -- SIP 来电时自动接听
    auto_handle_mobile_incoming = true,  -- 手机来电时自动拨打 SIP
    cc_audio_start_timeout_ms = 1500,
}
