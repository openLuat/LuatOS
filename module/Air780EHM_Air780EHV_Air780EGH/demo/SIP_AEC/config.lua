local config = {}

-- 填写自己的SIP服务器和账号；两台设备应使用不同账号。
config.sip = {
    sip_server_addr = "180.152.6.34",
    sip_server_port = 8910,
    sip_domain = "180.152.6.34", -- 空字符串时使用服务器地址
    sip_username = hmeta.devid().."0",
    sip_password = "123456",
    sip_transport = "udp",
    rtp_port = 40000,
    expires = 300,
    codecs = {"PCMA", "PCMU"},
    ptime = 20,
    call_timeout = 30,
    early_media = false,
    aec = false, -- 此处控制模组软件AEC；外置Air1103自行处理声学回声
}

config.dial_number = hmeta.devid().."1" -- BOOT键呼出的对端SIP号码

config.audio = {
    uart_id = 1, -- UART1，Air1103 PCM协议固定使用2Mbps
    -- Air1103直接接VBAT，本工程不使用GPIO开关其电源。
    volume = 31, -- Air1103扬声器音量0..31
    mic_gain = 2, -- 上行数字增益1..8
    play_buffer_ms = 60,
    boot_ms = 1500,
    ready_timeout_ms = 10000,
    mic_timeout_ms = 3000,
}

config.keys = {
    enabled = true,
    boot_gpio = 0, -- 与Air780EHV原SIP demo一致：BOOT高电平按下
    debounce_ms = 200,
}

return config
