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
    target_phone_number = "19228137508",

    -- 音频参数
    rtp_port = 40000,
    codec = "PCMU",
    ptime = 20,

    -- 网络适配器：4G only 默认使用 LWIP_GP
    -- 若 netdrv_device 切换为 WiFi/以太网，请同步改为 socket.LWIP_STA / socket.LWIP_ETH
    adapter = socket.LWIP_GP,

    -- 自动行为
    auto_answer_sip = true,            -- SIP 来电时自动接听
    auto_handle_mobile_incoming = true,  -- 手机来电时自动拨打 SIP

    -- 默认本地音频开关：false 表示仅桥接，true 表示本地也能听到/说话
    local_audio_default = false,

    -- 日志标签
    log_tag = "sip_cc_demo",
}

return config
