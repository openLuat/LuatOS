-- 独立蜂窝电话配置，与 sip_config/single_config 和云端 SIP 任务无关。
return {
    -- 留空时 SOS 仅接听来电；填入目标手机号后，空闲时按 SOS 拨号。
    number = "",
    uart_id = 1,
    power_gpio = 22,
    volume = 31, -- Air1103: 0..31
    boot_ms = 1500,
    dial_timeout_ms = 60000,
}
