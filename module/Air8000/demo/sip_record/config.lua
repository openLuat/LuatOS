-- 复制本文件为 config.lua，再填写实际测试参数。
-- 请勿将包含真实 SIP 密码的 config.lua 提交到代码仓库。
return {
    -- sip_server_addr = "sip.example.com",
    -- sip_server_port = 5060,
    -- sip_domain = "sip.example.com",
    -- sip_username = "1001",
    -- sip_password = "replace-with-your-password",
    -- sip_transport = "udp",
    sip_server_addr = "180.152.6.34",
    sip_server_port = 8910,
    sip_domain = "180.152.6.34",
    sip_username = "1903CFC1",
    sip_password = "Air.903CFC",
    sip_transport = "udp",

    -- BOOT 键在 SIP 就绪且无通话时拨打此号码。
    dial_target = "1002",
    auto_answer = false,
    adapter = socket.LWIP_GP,
    codecs = {"PCMU", "PCMA"},
    ptime = 20,

    record = {
        auto = true,
        dir = "/sd/record",
        prefix = "sip",
        max_seconds = 7200
    },

    -- Air8000 V2.0 开发板：TF 卡与 CH390 共用 SPI1，TF 卡 CS 为 GPIO20。
    sd = {
        hardware_env = "DEV_BOARD_8000_V2.0",
        spi_id = 1,
        cs_pin = 20,
        spi_hz = 24 * 1000 * 1000,
        mount_point = "/sd"
    }
}
