--[[
@module  param_default
@summary Air8301 内置默认配置（兜底使用）
@version 1.0
@date    2026.09.04
@author  江访
@usage
当 device_config.json 不存在时使用此配置。
与 device_config.json 结构完全一致。
]]

return {
    system = {
        screen_br = 70,
        ntp_enabled = true,
        ntp_server = "ntp.aliyun.com",
        ntp_tz = "UTC+8",
        ntp_interval_h = 6
    },
    mqtt = {
        broker = "lbsmqtt.airm2m.com",
        port = 1884,
        cid = "IMEI",
        keep = 60,
        qos = 1,
        tls = false,
        username = "",
        password = "",
        upload_interval = 60
    },
    network = {
        ["4g"] = {
            flight_mode = false,
            apn = ""
        },
        wifi = {
            enabled = false,
            ssid = "",
            password = ""
        },
        ethernet = {
            dhcp = true,
            ip = "192.168.1.100",
            mask = "255.255.255.0",
            gw = "192.168.1.1",
            dns1 = "114.114.114.114",
            dns2 = "8.8.8.8"
        },
        priority = {
            order = {"eth1", "eth2", "wifi", "4g"},
            enabled = { eth1 = true, eth2 = true, wifi = false, ["4g"] = true }
        }
    },
    uart = {
        rs485_1 = {
            enable = true,
            uart_id = 1,
            baud_rate = 115200,
            data_bits = 8,
            stop_bits = 1,
            parity = "none"
        },
        rs485_2 = {
            enable = true,
            uart_id = 11,
            baud_rate = 115200,
            data_bits = 8,
            stop_bits = 1,
            parity = "none"
        },
        rs232_1 = {
            enable = true,
            uart_id = 2,
            baud_rate = 115200,
            data_bits = 8,
            stop_bits = 1,
            parity = "none"
        },
        rs232_2 = {
            enable = true,
            uart_id = 12,
            baud_rate = 115200,
            data_bits = 8,
            stop_bits = 1,
            parity = "none"
        },
        modbus = {
            enable = false,
            mode = "master",         -- master / slave
            port_type = "rs485_1",   -- rs485_1 / rs485_2 / rs232_1 / tcp
            slave_addr = 1,
            poll_interval = 1000,
            frames = {}
        }
    },
    tcp_slave = {
        enable = false,
        local_ip = "192.168.4.1",
        netmask = "255.255.255.0",
        gateway = "192.168.4.1",
        listen_port = 502,
        max_conn = 5,
        timeout = 3000,
        self_addr = 1
    },
    fota = {
        auto_check = true,
        check_interval = 3600,
        power_on_check = false,
        product_key = ""
    },
    backup = {
        auto_backup = {
            enabled = true,
            period = 1,
            retain_count = 3
        },
        last_backup_time = ""
    }
}
