-- 示例配置：烧录前填写自己的 SIP 服务器、账号、密码和目标号码。
-- SIP 支持 PCMA/PCMU/G729/G722；G.729/G.722 别名可用，ptime 固定 20。
-- G722 使用 16 kHz 媒体 PCM，其余为 8 kHz；接通后媒体启动超时默认 3000 ms。
-- 网络选择见 netdrv_device.lua；adapter 必须与所选网卡一致。
local config = {
    sip_server_addr = "cc.luatos.com",
    sip_server_port = 8910,
    sip_domain = "cc.luatos.com", -- 空字符串时使用服务器地址
    sip_username = hmeta.devid().."0",
    sip_password = "123456",
    sip_transport = "udp", -- udp / tcp / tls，tls 需要启用下面的两条注释，并同步烧录 CA 证书
    -- sip_tls = {ca_cert = io.readFile("/luadb/sip-ca.pem")}, -- sip项目通用公开 CA 证书
    -- media_encryption = "none", -- 先验收 TLS 信令；服务器启用后显式改为 "sdes" / "dtls-srtp"
    remote_sip_uri = "sip:"..hmeta.devid().."1".."@cc.luatos.com",
    target_phone_number = "1xxxxxxxxxx",
    rtp_port = 40000,
    codec = "PCMA", -- 支持 PCMA/PCMU/G729/G722
    -- codecs = { -- 多个 codec 时，按顺序尝试
    --     "PCMU",
    --     "PCMA",
    --     "G729",
    --     "G722",
    -- },
    ptime = 20,      -- 本纯 PCM 桥接 demo 固定 20 ms
    adapter = socket.LWIP_GP,
    auto_answer_sip = true,            -- SIP 来电时自动接听
    auto_handle_mobile_incoming = true,  -- 手机来电时自动拨打 SIP
    cc_audio_start_timeout_ms = 3000,
    cc_media_min_connected_ms = 2000,   -- 真实接通后当前媒体阶段至少 2 秒；<=0 关闭统计
    cc_media_missing_call_limit = 3,    -- 连续 3 通接通阶段无下行 PCM 增量；<=0 关闭统计
    cc_media_reboot_on_error = true,    -- false 仅发布异常事件，不自动重启
}

config.WDT_CONFIG = {
    ENABLE = true,
    FEED_PIN = 23,
    FEED_INTERVAL = 180, -- 喂狗周期，单位秒
}

return config
