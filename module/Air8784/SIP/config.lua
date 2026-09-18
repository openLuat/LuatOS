--[[
@module  config
@summary 项目集中配置
@version 1.0
@date    2026.09.16
@description
SIP 服务器、账号、音频和按键参数集中在此，烧录前请按实际环境修改。
保留 config.sip、config.audio、config.keys 和 config.dial_number 接口。
]]

-- 填写实际 SIP 服务器和账号；不把其他测试工程的账号复制进来。
local config = {}

-- ==================== SIP 配置 ====================

config.sip = {
    sip_server_addr = "180.152.6.34", -- 必填：4G 网络可达的 SIP 服务器
    sip_server_port = 8910,
    sip_domain = "180.152.6.34",      -- 留空时使用服务器地址
    sip_username = mobile.imei() .. "0",    -- 必填：测试分机
    sip_password = "123456",    -- 必填：在本地填写，不打印到日志
    sip_transport = "udp", -- udp / tcp；RTP 仍使用 UDP
    rtp_port = 10000,
    expires = 300,
    -- call_timeout = 60,
    auto_answer = false,
    codecs = {"PCMA", "PCMU"},
    ptime = 20,
    aec = false,
    aec_denoise = false,
    aec_agc = false,
    debug_sip_response = false,
}

-- ==================== 默认拨号目标 ====================

config.dial_number = mobile.imei() .. "1"

-- ==================== 音频配置 ====================

config.audio = {
    uart_id = 1,
    power_gpio = 22,
    volume = 31, -- 1103 喇叭 0..31
    mic_gain = 2, -- 软件数字增益 1..8，过大会削顶
    play_buffer_ms = 60, -- 应用层目标水位；AP 驱动不足时补静音
    boot_ms = 1500,
    ready_timeout_ms = 10000,
    mic_timeout_ms = 3000,
}

-- ==================== 按键配置 ====================

config.keys = {
    enabled = true,
    vref_gpio = 23,
    sos_gpio = 20,
    up_gpio = 21,
    debounce_ms = 150,
}

return config
