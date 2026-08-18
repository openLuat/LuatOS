--[[
@module  config
@summary 项目集中配置
@version 1.0
@date    2026.07.17
@author  蒋骞
@usage
所有与账号、网络、桥接行为相关的配置集中在此，烧录前请按实际环境修改。
]]

local config = {
    -- SIP 服务器
    sip_server_addr = "180.152.6.34",
    sip_server_port = 8910,
    sip_domain = "180.152.6.34",
    sip_transport = "udp",

    -- 4G 模组 SIP 账号
    sip_username = "11234561",
    sip_password = "Air.123456",

    -- 远程 SIP 客户端（控制端 / 被叫端）
    remote_sip_uri = "sip:11234560@180.152.6.34",

    -- 默认桥接目标手机号（呼出场景）
    -- target_phone_number = "15050000000",
    target_phone_number = "13781142418",

    -- 音频参数
    rtp_port = 40000,
    codec = "PCMU",
    ptime = 20,
    sample_rate = 8000,

    -- 网络适配器：4G only 默认使用 LWIP_GP
    -- 若 netdrv_device 切换为 WiFi/以太网，请同步改为 socket.LWIP_STA / socket.LWIP_ETH
    adapter = socket.LWIP_GP,

    -- 自动行为
    auto_answer_sip = true,            -- SIP 来电时自动接听
    auto_handle_mobile_incoming = true,  -- 手机来电时自动拨打 SIP
    auto_answer_mobile_incoming = true,  -- 不转 SIP 时自动接听手机来电

    -- 默认本地音频开关：false 表示仅桥接，true 表示本地也能听到/说话
    local_audio_default = false,

    -- 早期媒体（SIP 来电后先回 183 + SDP，等手机接通后再回 200 OK）
    early_media = true,                -- 是否启用早期媒体
    early_media_response = 183,        -- 早期媒体 SIP 响应码
    outgoing_early_timeout = 90,       -- SIP->CC 早期拨号阶段最大等待时间（秒）
    outgoing_failure_prompt_grace = 6, -- CC 失败时保留运营商语音播报窗口（秒）

    -- 日志标签
    log_tag = "sip_cc_demo",
}

-- local config = {
--     -- SIP 服务器
--     sip_server_addr = "v3.800ing.com",
--     sip_server_port = 31136,
--     sip_domain = "v3.800ing.com",
--     sip_transport = "udp",

--     -- 4G 模组 SIP 账号
--     sip_username = "407857001",
--     sip_password = "407857001",

--     -- 远程 SIP 客户端（控制端 / 被叫端）
--     -- remote_sip_uri = "sip:11234560@180.152.6.34",
--     remote_sip_uri = "sip:407857201@v3.800ing.com",

--     -- 默认桥接目标手机号（呼出场景）
--     -- target_phone_number = "15050000000",
--     -- target_phone_number = "13883162550",
--     target_phone_number = "15057721363",

--     -- 音频参数
--     rtp_port = 40000,
--     codec = "PCMU",
--     ptime = 20,
--     sample_rate = 8000,

--     -- 网络适配器：4G only 默认使用 LWIP_GP
--     -- 若 netdrv_device 切换为 WiFi/以太网，请同步改为 socket.LWIP_STA / socket.LWIP_ETH
--     adapter = socket.LWIP_GP,

--     -- 自动行为
--     auto_answer_sip = true,            -- SIP 来电时自动接听
--     auto_handle_mobile_incoming = true,  -- 手机来电时自动拨打 SIP
--     auto_answer_mobile_incoming = true,  -- 不转 SIP 时自动接听手机来电

--     -- 默认本地音频开关：false 表示仅桥接，true 表示本地也能听到/说话
--     local_audio_default = false,

--     -- 早期媒体（SIP 来电后先回 183 + SDP，等手机接通后再回 200 OK）
--     early_media = true,                -- 是否启用早期媒体
--     early_media_response = 183,        -- 早期媒体 SIP 响应码
--     outgoing_early_timeout = 90,       -- SIP->CC 早期拨号阶段最大等待时间（秒）
--     outgoing_failure_prompt_grace = 6, -- CC 失败时保留运营商语音播报窗口（秒）

--     -- 日志标签
--     log_tag = "sip_cc_demo",
-- }

return config
