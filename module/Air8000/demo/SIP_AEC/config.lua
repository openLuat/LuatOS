local config = {}

-- 填写自己的SIP服务器与账号，两台设备使用不同账号。
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
    aec = false, -- 模组软件AEC关闭，由Air1103芯片处理回声
}

config.dial_number = hmeta.devid().."1" -- BOOT键呼出的对端SIP号码

config.audio = {
    uart_id = 1, -- Air1103串口PCM协议固定2Mbps
    volume = 31,
    mic_gain = 2,
    play_buffer_ms = 60,
    boot_ms = 1500,
    ready_timeout_ms = 10000,
    mic_timeout_ms = 3000,
}

config.keys = {
    enabled = true,
    boot_gpio = 0,
    debounce_ms = 200,
}

return config
