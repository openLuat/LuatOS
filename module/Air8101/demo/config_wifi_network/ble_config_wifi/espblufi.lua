--[[
@module espblufi
@summary espblufi esp blufi 蓝牙配网(注意:初版暂不支持加密功能!!!!!!!!)
@version 1.1
@date    2025.08.07
@author  拓毅恒
@usage
-- 此为Blufi 配网库
-- BluFi 配网指南:https://www.espressif.com/sites/default/files/documentation/esp32_bluetooth_networking_user_guide_cn.pdf

-- 安卓测试APP下载地址:https://github.com/EspressifApp/EspBlufiForAndroid/releases
-- 安卓APP源码下载地址:https://github.com/EspressifApp/EspBlufiForAndroid

-- 小程序测试:微信搜索小程序:ESP Config
-- 小程序源码下载地址:https://github.com/EspressifApps/ESP-Config-WeChat

-- 注意:初版暂不支持加密功能!!!!!!!!

-- 业务逻辑总结：
-- 1. 此函数库需跟APP搭配使用，调用前首先需要初始化蓝牙。
-- 2. 初始化 espblufi 模块，并传入蓝牙设备实例和回调函数。
-- 3. 启动 espblufi 配网功能来进行APP配网。
-- 4. 在APP端点击配网后，会根据配的是station还是softap发布相应的消息 "STA_CONNED"、"STA_DISCONNED"、"AP_CONNED"，用户只需要根据消息设置自己的逻辑即可。
-- 具体业务逻辑实现可以参考下面实例代码。

-- 用法实例
local espblufi = require("espblufi")
local taskName = "config_wifi"

local function network_event_handler()
    while true do
        msg = sysplus.waitMsg(taskName, nil)
        if type(msg) == 'table' then
            -- 检查消息的第一个元素是否为 "STA_CONNED"，即 STA 连接成功消息
            if msg[1] == "STA_CONNED" then
                ...
                写入自己的逻辑函数
                ...
            end
            -- 检查消息的第一个元素是否为 "STA_DISCONNED"，即 STA 断开连接消息
            if msg[1] == "STA_DISCONNED" then
                ...
                写入自己的逻辑函数
                ...
            end
            -- 检查消息的第一个元素是否为 "AP_CONNED"，即 AP 创建连接消息
            if msg[1] == "AP_CONNED" then
                ...
                写入自己的逻辑函数
                ...
            end
        end
        sys.wait(10)
    end
end

-- 定义 espblufi 回调函数，用于处理不同类型的事件，如EVENT_STA_INFO、EVENT_SOFTAP_INFO等
-- 详情可以在espblufi.lua中查看，demo中演示收到APP下发的连接消息后，打印输入的ssid和passwd
local function espblufi_callback(event, data)
    if event == espblufi.EVENT_STA_INFO then
        for i, v in pairs(data) do
            print("STA:", i, v)
        end
    elseif event == espblufi.EVENT_SOFTAP_INFO then
        for i, v in pairs(data) do
            print("SoftAP:", i, v)
        end
    end
end

-- 定义网络配置任务函数
local function ble_wifi_config_task()
    local bluetooth_device = bluetooth.init()
    espblufi.init(bluetooth_device, espblufi_callback)
    espblufi.start()
end

-- 初始化网络配置任务
sysplus.taskInitEx(ble_wifi_config_task, "ble_wifi_config_task")
-- 初始化网络测试任务
sysplus.taskInitEx(network_event_handler, taskName)

]]

local espblufi = {}

local sys = require "sys"
local sysplus = require "sysplus"

local BLUFI_TOPIC = "espblufi"
local taskName = "config_wifi"

local BTC_BLUFI_GREAT_VER = 0x01 -- Version + Subversion
local BTC_BLUFI_SUB_VER = 0x03 -- Version + Subversion
local BTC_BLUFI_VERSION = ((BTC_BLUFI_GREAT_VER << 8) | BTC_BLUFI_SUB_VER) -- Version + Subversion

-- packet type
local BLUFI_TYPE_MASK = 0x03
local BLUFI_TYPE_SHIFT = 0
local BLUFI_SUBTYPE_MASK = 0xFC
local BLUFI_SUBTYPE_SHIFT = 2

local function BLUFI_GET_TYPE(type)
    return ((type) & BLUFI_TYPE_MASK)
end
local function BLUFI_GET_SUBTYPE(type)
    return (((type) & BLUFI_SUBTYPE_MASK) >> BLUFI_SUBTYPE_SHIFT)
end
local function BLUFI_BUILD_TYPE(type, subtype)
    return (((type) & BLUFI_TYPE_MASK) | ((subtype) << BLUFI_SUBTYPE_SHIFT))
end

local BLUFI_TYPE_CTRL = 0x0
local BLUFI_TYPE_CTRL_SUBTYPE_ACK = 0x00
local BLUFI_TYPE_CTRL_SUBTYPE_SET_SEC_MODE = 0x01
local BLUFI_TYPE_CTRL_SUBTYPE_SET_WIFI_OPMODE = 0x02
local BLUFI_TYPE_CTRL_SUBTYPE_CONN_TO_AP = 0x03
local BLUFI_TYPE_CTRL_SUBTYPE_DISCONN_FROM_AP = 0x04
local BLUFI_TYPE_CTRL_SUBTYPE_GET_WIFI_STATUS = 0x05
local BLUFI_TYPE_CTRL_SUBTYPE_DEAUTHENTICATE_STA = 0x06
local BLUFI_TYPE_CTRL_SUBTYPE_GET_VERSION = 0x07
local BLUFI_TYPE_CTRL_SUBTYPE_DISCONNECT_BLE = 0x08
local BLUFI_TYPE_CTRL_SUBTYPE_GET_WIFI_LIST = 0x09

local BLUFI_TYPE_DATA = 0x1
local BLUFI_TYPE_DATA_SUBTYPE_NEG = 0x00
local BLUFI_TYPE_DATA_SUBTYPE_STA_BSSID = 0x01
local BLUFI_TYPE_DATA_SUBTYPE_STA_SSID = 0x02
local BLUFI_TYPE_DATA_SUBTYPE_STA_PASSWD = 0x03
local BLUFI_TYPE_DATA_SUBTYPE_SOFTAP_SSID = 0x04
local BLUFI_TYPE_DATA_SUBTYPE_SOFTAP_PASSWD = 0x05
local BLUFI_TYPE_DATA_SUBTYPE_SOFTAP_MAX_CONN_NUM = 0x06
local BLUFI_TYPE_DATA_SUBTYPE_SOFTAP_AUTH_MODE = 0x07
local BLUFI_TYPE_DATA_SUBTYPE_SOFTAP_CHANNEL = 0x08
local BLUFI_TYPE_DATA_SUBTYPE_USERNAME = 0x09
local BLUFI_TYPE_DATA_SUBTYPE_CA = 0x0a
local BLUFI_TYPE_DATA_SUBTYPE_CLIENT_CERT = 0x0b
local BLUFI_TYPE_DATA_SUBTYPE_SERVER_CERT = 0x0c
local BLUFI_TYPE_DATA_SUBTYPE_CLIENT_PRIV_KEY = 0x0d
local BLUFI_TYPE_DATA_SUBTYPE_SERVER_PRIV_KEY = 0x0e
local BLUFI_TYPE_DATA_SUBTYPE_WIFI_REP = 0x0f
local BLUFI_TYPE_DATA_SUBTYPE_REPLY_VERSION = 0x10
local BLUFI_TYPE_DATA_SUBTYPE_WIFI_LIST = 0x11
local BLUFI_TYPE_DATA_SUBTYPE_ERROR_INFO = 0x12
local BLUFI_TYPE_DATA_SUBTYPE_CUSTOM_DATA = 0x13
local BLUFI_TYPE_DATA_SUBTYPE_STA_MAX_CONN_RETRY = 0x14
local BLUFI_TYPE_DATA_SUBTYPE_STA_CONN_END_REASON = 0x15
local BLUFI_TYPE_DATA_SUBTYPE_STA_CONN_RSSI = 0x16

local function BLUFI_TYPE_IS_CTRL(type)
    return (BLUFI_GET_TYPE((type)) == BLUFI_TYPE_CTRL)
end
local function BLUFI_TYPE_IS_DATA(type)
    return (BLUFI_GET_TYPE((type)) == BLUFI_TYPE_DATA)
end

-- packet frame control
local BLUFI_FC_ENC_MASK = 0x01
local BLUFI_FC_CHECK_MASK = 0x02
local BLUFI_FC_DIR_MASK = 0x04
local BLUFI_FC_REQ_ACK_MASK = 0x08
local BLUFI_FC_FRAG_MASK = 0x10

local BLUFI_FC_ENC = 0x01
local BLUFI_FC_CHECK = 0x02
local BLUFI_FC_DIR_P2E = 0x00
local BLUFI_FC_DIR_E2P = 0x04
local BLUFI_FC_REQ_ACK = 0x08
local BLUFI_FC_FRAG = 0x10

local BLUFI_SEQUENCE_ERROR = 0x00
local BLUFI_CHECKSUM_ERROR = 0x01
local BLUFI_DECRYPT_ERROR = 0x02
local BLUFI_ENCRYPT_ERROR = 0x03
local BLUFI_INIT_SECURITY_ERROR = 0x04
local BLUFI_DH_MALLOC_ERROR = 0x05
local BLUFI_DH_PARAM_ERROR = 0x06
local BLUFI_READ_PARAM_ERROR = 0x07
local BLUFI_MAKE_PUBLIC_ERROR = 0x08
local BLUFI_DATA_FORMAT_ERROR = 0x09
local BLUFI_CALC_MD5_ERROR = 0x0a
local BLUFI_WIFI_SCAN_FAIL = 0x0b
local BLUFI_MSG_STATE_ERROR = 0x0c

local BLUFI_OPMODE_NULL = 0x00
local BLUFI_OPMODE_STA = 0x01
local BLUFI_OPMODE_SOFTAP = 0x02
local BLUFI_OPMODE_SOFTAPSTA = 0x03

local BLUFI_STA_CONN_SUCCESS = 0x00
local BLUFI_STA_CONN_FAIL = 0x01
local BLUFI_STA_CONNECTING = 0x02
local BLUFI_STA_NO_IP = 0x03

local BLUFI_BLE_STATE_DISCONN = 0x00
local BLUFI_BLE_STATE_CONNED = 0x01

local BLUFI_WLAN_STATE_DISCONN = 0x00
local BLUFI_WLAN_STATE_CONNING = 0x01
local BLUFI_WLAN_STATE_CONNED = 0x02

local BLUFI_SEQUENCE_ERROR = 0x00
local BLUFI_CHECKSUM_ERROR = 0x01
local BLUFI_DECRYPT_ERROR = 0x02
local BLUFI_ENCRYPT_ERROR = 0x03
local BLUFI_INIT_SECURITY_ERROR = 0x04
local BLUFI_DH_MALLOC_ERROR = 0x05
local BLUFI_DH_PARAM_ERROR = 0x06
local BLUFI_READ_PARAM_ERROR = 0x07
local BLUFI_MAKE_PUBLIC_ERROR = 0x08
local BLUFI_DATA_FORMAT_ERROR = 0x09
local BLUFI_CALC_MD5_ERROR = 0x0a
local BLUFI_WIFI_SCAN_FAIL = 0x0b
local BLUFI_MSG_STATE_ERROR = 0x0c

local function BLUFI_FC_IS_ENC(fc)
    return ((fc) & BLUFI_FC_ENC_MASK) ~= 0
end
local function BLUFI_FC_IS_CHECK(fc)
    return ((fc) & BLUFI_FC_CHECK_MASK) ~= 0
end
local function BLUFI_FC_IS_REQ_ACK(fc)
    return ((fc) & BLUFI_FC_REQ_ACK_MASK) ~= 0
end
local function BLUFI_FC_IS_FRAG(fc)
    return ((fc) & BLUFI_FC_FRAG_MASK) ~= 0
end

local BLUFI_PROTOCOL_DATA = "BLUFI_PROTOCOL_DATA"
local BLUFI_TASK_EXIT = "BLUFI_TASK_EXIT"

local espblufi_uuid_service = "0xFFFF"
local espblufi_uuid2device = "0xFF01"
local espblufi_uuid2mobile = "0xFF02"

local espblufi_att_db = {string.fromHex(espblufi_uuid_service), {string.fromHex(espblufi_uuid2device), ble.WRITE},
                         {string.fromHex(espblufi_uuid2mobile), ble.NOTIFY | ble.READ}}

local blufi_env = {
    ble_device = nil,
    callback = nil,
    isfrag = nil,
    ble_state = BLUFI_BLE_STATE_DISCONN,
    wlan_state = BLUFI_WLAN_STATE_DISCONN,
    opmode = BLUFI_OPMODE_NULL,
    recv_seq = 0,
    send_seq = 0,
    sec_mode = 0,
    softap_conn_num = 0,
    softap_auth_mode = 0,
    softap_max_conn_num = 0,
    softap_channel = nil,
    sta_max_conn_retry = nil,
    sta_conn_end_reason = nil,
    sta_ssid = nil,
    sta_passwd = nil,
    softap_ssid = nil,
    softap_passwd = nil
}

local blufi_hdr = {
    type = nil,
    fc = nil,
    seq = nil,
    data_len = nil,
    data = nil
}

espblufi.EVENT_STA_INFO = 0x01
espblufi.EVENT_SOFTAP_INFO = 0x02
espblufi.EVENT_CUSTOM_DATA = 0x03

sys.subscribe("WLAN_AP_INC", function(state, mac)
    if state == "CONNECTED" then
        blufi_env.softap_conn_num = blufi_env.softap_conn_num + 1
    elseif state == "DISCONNECTED" and blufi_env.softap_conn_num > 0 then
        blufi_env.softap_conn_num = blufi_env.softap_conn_num - 1
    end
end)

local function blufi_crc_checksum(data)
    return crypto.crc16("IBM", data)
end

local function blufi_send_encap(blufi_hdr_send)
    local send_data = string.char(blufi_hdr_send.type, blufi_hdr_send.fc, blufi_hdr_send.seq, #blufi_hdr_send.data) ..
                          blufi_hdr_send.data
    if BLUFI_TYPE_IS_CTRL(blufi_hdr_send.type) then
        blufi_hdr_send.fc = blufi_hdr_send.fc | BLUFI_FC_CHECK
        send_data = send_data .. blufi_crc_checksum(send_data)
    end
    blufi_env.send_seq = blufi_env.send_seq + 1
    blufi_env.ble_device:write_notify({
        uuid_service = string.fromHex(espblufi_uuid_service),
        uuid_characteristic = string.fromHex(espblufi_uuid2mobile)
    }, send_data)
end

local function btc_blufi_send_encap(type, data)
    if blufi_env.ble_state == BLUFI_BLE_STATE_DISCONN then
        return
    end
    local blufi_hdr_send = {
        type = type,
        fc = 0,
        seq = blufi_env.send_seq,
        data = data
    }
    blufi_send_encap(blufi_hdr_send)
end

local function btc_blufi_wifi_conn_report(sta_conn_state)
    local data = string.char(blufi_env.opmode, blufi_env.wlan_state, blufi_env.softap_conn_num)
    local wlan_info = wlan.getInfo()
    if wlan_info then
        if wlan_info.bssid then
            data = data .. string.char(BLUFI_TYPE_DATA_SUBTYPE_STA_BSSID, 6) .. string.fromHex(wlan_info.bssid)
        end
        if wlan_info.rssi then
            data = data .. string.char(BLUFI_TYPE_DATA_SUBTYPE_STA_CONN_RSSI, 1, wlan_info.rssi % 256)
        end
    end
    if blufi_env.sta_ssid then
        data = data .. string.char(BLUFI_TYPE_DATA_SUBTYPE_STA_SSID, #blufi_env.sta_ssid) .. blufi_env.sta_ssid
    end
    if blufi_env.sta_passwd then
        data = data .. string.char(BLUFI_TYPE_DATA_SUBTYPE_STA_PASSWD, #blufi_env.sta_passwd) .. blufi_env.sta_passwd
    end
    if blufi_env.softap_ssid then
        data = data .. string.char(BLUFI_TYPE_DATA_SUBTYPE_SOFTAP_SSID, #blufi_env.softap_ssid) .. blufi_env.softap_ssid
    end
    if blufi_env.softap_passwd then
        data = data .. string.char(BLUFI_TYPE_DATA_SUBTYPE_SOFTAP_PASSWD, #blufi_env.softap_passwd) ..
                   blufi_env.softap_passwd
    end
    if blufi_env.softap_authmode then
        data = data .. string.char(BLUFI_TYPE_DATA_SUBTYPE_SOFTAP_AUTH_MODE, 1) .. blufi_env.softap_authmode
    end
    if blufi_env.softap_max_conn_num then
        data = data .. string.char(BLUFI_TYPE_DATA_SUBTYPE_SOFTAP_MAX_CONN_NUM, 1) .. blufi_env.softap_max_conn_num
    end
    if blufi_env.softap_channel then
        data = data .. string.char(BLUFI_TYPE_DATA_SUBTYPE_SOFTAP_CHANNEL, 1) .. blufi_env.softap_channel
    end
    if blufi_env.sta_max_conn_retry then
        data = data .. string.char(BLUFI_TYPE_DATA_SUBTYPE_STA_MAX_CONN_RETRY, 1) .. blufi_env.sta_max_conn_retry
    end
    if blufi_env.sta_conn_end_reason then
        data = data .. string.char(BLUFI_TYPE_DATA_SUBTYPE_STA_CONN_END_REASON, 1) .. blufi_env.sta_conn_end_reason
    end
    btc_blufi_send_encap(BLUFI_BUILD_TYPE(BLUFI_TYPE_DATA, BLUFI_TYPE_DATA_SUBTYPE_WIFI_REP), data);
end

local function btc_blufi_send_wifi_list(results)
    local data = ""
    for k, v in pairs(results) do
        data = data .. string.char(#v["ssid"] + 1, v["rssi"] % 256) .. v["ssid"]
    end
    btc_blufi_send_encap(BLUFI_BUILD_TYPE(BLUFI_TYPE_DATA, BLUFI_TYPE_DATA_SUBTYPE_WIFI_LIST), data)
end

local function btc_blufi_send_ack(seq)
    btc_blufi_send_encap(BLUFI_BUILD_TYPE(BLUFI_TYPE_CTRL, BLUFI_TYPE_CTRL_SUBTYPE_ACK), string.char(seq))
end

local function btc_blufi_send_error_info(state)
    btc_blufi_send_encap(BLUFI_BUILD_TYPE(BLUFI_TYPE_DATA, BLUFI_TYPE_DATA_SUBTYPE_ERROR_INFO), string.char(state))
end

local function btc_blufi_send_custom_data(data)
    btc_blufi_send_encap(BLUFI_BUILD_TYPE(BLUFI_TYPE_DATA, BLUFI_TYPE_DATA_SUBTYPE_CUSTOM_DATA), data)
end

local SEC_TYPE_DH_PARAM_LEN = 0x00
local SEC_TYPE_DH_PARAM_DATA = 0x01
local SEC_TYPE_DH_P = 0x02
local SEC_TYPE_DH_G = 0x03
local SEC_TYPE_DH_PUBLIC = 0x04

local blufi_sec = {
    dh_param_len = 0
}

local function blufi_dh_negotiate_data_handler(data)
    if #data < 3 then
        btc_blufi_send_error_info(BLUFI_DATA_FORMAT_ERROR)
    end

    local type = data:byte(1)
    if type == SEC_TYPE_DH_PARAM_LEN then
        blufi_sec.dh_param_len = ((data:byte(2) << 8) | data:byte(3));
        -- print("dh_param_len",blufi_sec.dh_param_len)
    elseif type == SEC_TYPE_DH_PARAM_DATA then
        -- print("SEC_TYPE_DH_PARAM_DATA")
        if #data < (blufi_sec.dh_param_len + 1) then
            btc_blufi_send_error_info(BLUFI_DH_PARAM_ERROR);
            return;
        end

        -- 秘钥待实现，功能需要mbedtls引出c接口
        btc_blufi_send_error_info(BLUFI_INIT_SECURITY_ERROR);

    elseif type == SEC_TYPE_DH_P then
        print("SEC_TYPE_DH_P")
    elseif type == SEC_TYPE_DH_G then
        print("SEC_TYPE_DH_G")
    elseif type == SEC_TYPE_DH_PUBLIC then
        print("SEC_TYPE_DH_PUBLIC")
    end

end

local function btc_blufi_protocol_handler(parse_data)
    local target_data_len = 0
    local parse_data_len = #parse_data

    if parse_data_len < 4 then
        return
    end

    blufi_hdr.type, blufi_hdr.fc, blufi_hdr.seq, blufi_hdr.data_len = string.unpack('<BBBB', parse_data)

    if BLUFI_FC_IS_CHECK(blufi_hdr.fc) then
        target_data_len = blufi_hdr.data_len + 4 + 2 -- // Data + (Type + Frame Control + Sequence Number + Data Length) + Checksum
    else
        target_data_len = blufi_hdr.data_len + 4 -- Data + (Type + Frame Control + Sequence Number + Data Length)
    end
    -- print("target_data_len",target_data_len,"parse_data_len",parse_data_len)
    if target_data_len ~= parse_data_len then
        return
    end

    if blufi_hdr.seq ~= blufi_env.recv_seq then
        return
    end
    blufi_env.recv_seq = blufi_env.recv_seq + 1

    if BLUFI_FC_IS_ENC(blufi_hdr.fc) then
        -- 解密功能需要mbedtls引出c接口
    end
    if BLUFI_FC_IS_CHECK(blufi_hdr.fc) and crypto then
        -- 需要app配合调试,暂时不强制校验
        local checksum = blufi_crc_checksum()
    end

    if BLUFI_FC_IS_REQ_ACK(blufi_hdr.fc) then
        btc_blufi_send_ack(blufi_hdr.seq)
    end

    if blufi_hdr.data_len and blufi_hdr.data_len > 0 then
        if blufi_env.isfrag then
            blufi_hdr.data = blufi_hdr.data .. parse_data:sub(5)
        else
            blufi_hdr.data = parse_data:sub(5)
        end
    end

    if BLUFI_FC_IS_FRAG(blufi_hdr.fc) then
        blufi_env.isfrag = true
        return
    else
        blufi_env.isfrag = false
    end

    -- print(blufi_hdr.type,blufi_hdr.fc,blufi_hdr.seq,blufi_hdr.data_len)
    -- print(blufi_hdr.data,blufi_hdr.data:toHex())

    -- 从 blufi_hdr.type 中提取数据包的类型，使用 BLUFI_GET_TYPE 函数
    local blufi_type = BLUFI_GET_TYPE(blufi_hdr.type)
    -- 从 blufi_hdr.type 中提取数据包的子类型，使用 BLUFI_GET_SUBTYPE 函数
    local blufi_subtype = BLUFI_GET_SUBTYPE(blufi_hdr.type)

    -- 检查数据包类型是否为控制类型
    if blufi_type == BLUFI_TYPE_CTRL then
        -- 检查子类型是否为确认(ACK)类型
        if blufi_subtype == BLUFI_TYPE_CTRL_SUBTYPE_ACK then
            -- 此处为空，未实现具体逻辑
            -- 检查子类型是否为设置安全模式类型
        elseif blufi_subtype == BLUFI_TYPE_CTRL_SUBTYPE_SET_SEC_MODE then
            -- 将接收到的数据赋值给环境变量中的安全模式字段
            blufi_env.sec_mode = blufi_hdr.data;
            -- 检查子类型是否为设置WiFi工作模式类型
        elseif blufi_subtype == BLUFI_TYPE_CTRL_SUBTYPE_SET_WIFI_OPMODE then
            -- 从接收到的数据中提取第一个字节，将其作为WiFi工作模式并更新到环境变量中
            blufi_env.opmode = blufi_hdr.data:byte(1)
            -- 检查子类型是否为连接到AP的类型
        elseif blufi_subtype == BLUFI_TYPE_CTRL_SUBTYPE_CONN_TO_AP then
            -- 调用回调函数，传递STA信息事件类型和包含SSID和密码的信息表
            blufi_env.callback(espblufi.EVENT_STA_INFO, {
                ssid = blufi_env.sta_ssid,
                password = blufi_env.sta_passwd
            })
            -- 使用之前存储的SSID和密码连接到WiFi
            wlan.connect(blufi_env.sta_ssid, blufi_env.sta_passwd)
            -- 创建一个DHCP服务器，适配器使用STA模式
            dhcpsrv.create({adapter = socket.LWIP_STA})
            -- 将WiFi连接状态更新为正在连接
            blufi_env.wlan_state = BLUFI_WLAN_STATE_CONNING
            -- 初始化计数器为0，用于后续等待IP地址获取的循环计数
            local count = 0
            -- 初始化IP地址变量为nil，用于存储获取到的IPv4地址
            local ip = nil
            local rdy = false
            -- 等待1秒，防止切换连接时IP地址未清理
            sys.wait(1000)
            -- 最多等待30s
            while count < 300 do
                -- 获取STA模式下的IPv4地址
                ip = netdrv.ipv4(socket.LWIP_STA)
                rdy = wlan.ready()
                -- 如果获取到有效的IP地址
                if ip and ip ~= "0.0.0.0" then
                    if rdy then
                        -- 将WiFi连接状态更新为已连接
                        blufi_env.wlan_state = BLUFI_WLAN_STATE_CONNED
                        -- 发送STA已连接的消息
                        sysplus.sendMsg(taskName, "STA_CONNED")
                        -- 跳出循环
                        break
                    end
                end
                sys.wait(100)
                count = count + 1
            end
            -- 如果未获取到有效IP地址
            if not ip or ip == "0.0.0.0" then
                -- 将WiFi连接状态更新为已断开
                blufi_env.wlan_state = BLUFI_WLAN_STATE_DISCONN
                -- 发送STA已断开的消息
                sysplus.sendMsg(taskName, "STA_DISCONNED")
                -- 断开 STA 连接
                wlan.disconnect()
            end
            -- 发送WiFi连接状态报告
            btc_blufi_wifi_conn_report()
            -- 检查子类型是否为断开与AP连接的类型
        elseif blufi_subtype == BLUFI_TYPE_CTRL_SUBTYPE_DISCONN_FROM_AP then
            -- 断开当前的WiFi连接
            wlan.disconnect()
            -- 检查子类型是否为获取WiFi状态的类型
        elseif blufi_subtype == BLUFI_TYPE_CTRL_SUBTYPE_GET_WIFI_STATUS then
            -- 发送WiFi连接状态报告
            btc_blufi_wifi_conn_report()
            -- 检查子类型是否为使STA认证失效的类型
        elseif blufi_subtype == BLUFI_TYPE_CTRL_SUBTYPE_DEAUTHENTICATE_STA then
            -- 注释掉的打印语句，可用于调试
            -- print("BLUFI_TYPE_CTRL_SUBTYPE_DEAUTHENTICATE_STA")
            -- 检查子类型是否为获取版本号的类型
        elseif blufi_subtype == BLUFI_TYPE_CTRL_SUBTYPE_GET_VERSION then
            -- 构建一个数据类型的数据包，子类型为回复版本号，内容为大版本号和子版本号
            btc_blufi_send_encap(BLUFI_BUILD_TYPE(BLUFI_TYPE_DATA, BLUFI_TYPE_DATA_SUBTYPE_REPLY_VERSION),
                string.char(BTC_BLUFI_GREAT_VER, BTC_BLUFI_SUB_VER))
            -- 检查子类型是否为断开BLE连接的类型
        elseif blufi_subtype == BLUFI_TYPE_CTRL_SUBTYPE_DISCONNECT_BLE then
            -- 断开当前的BLE连接
            blufi_env.ble_device:disconnect()
        elseif blufi_subtype == BLUFI_TYPE_CTRL_SUBTYPE_GET_WIFI_LIST then
            wlan.scan()
            sys.waitUntil("WLAN_SCAN_DONE", 15000)
            local results = wlan.scanResult()
            if results and #results > 0 then
                btc_blufi_send_wifi_list(results)
            else
                btc_blufi_send_error_info(BLUFI_WIFI_SCAN_FAIL)
            end
        end
    elseif blufi_type == BLUFI_TYPE_DATA then
        if blufi_subtype == BLUFI_TYPE_DATA_SUBTYPE_NEG then
            local data = blufi_dh_negotiate_data_handler(blufi_hdr.data)
            if data then
                btc_blufi_send_encap(BLUFI_BUILD_TYPE(BLUFI_TYPE_DATA, BLUFI_TYPE_DATA_SUBTYPE_NEG), data)
            end
        elseif blufi_subtype == BLUFI_TYPE_DATA_SUBTYPE_STA_BSSID then
            blufi_env.sta_bssid = blufi_hdr.data
        elseif blufi_subtype == BLUFI_TYPE_DATA_SUBTYPE_STA_SSID then
            blufi_env.sta_ssid = blufi_hdr.data
        elseif blufi_subtype == BLUFI_TYPE_DATA_SUBTYPE_STA_PASSWD then
            blufi_env.sta_passwd = blufi_hdr.data
        elseif blufi_subtype == BLUFI_TYPE_DATA_SUBTYPE_SOFTAP_SSID then
            blufi_env.softap_ssid = blufi_hdr.data
        elseif blufi_subtype == BLUFI_TYPE_DATA_SUBTYPE_SOFTAP_PASSWD then
            blufi_env.softap_passwd = blufi_hdr.data
        elseif blufi_subtype == BLUFI_TYPE_DATA_SUBTYPE_SOFTAP_MAX_CONN_NUM then
            blufi_env.softap_max_conn_num = blufi_hdr.data:byte(1)
            -- 检查当前子类型是否为设置SoftAP认证模式的类型
        elseif blufi_subtype == BLUFI_TYPE_DATA_SUBTYPE_SOFTAP_AUTH_MODE then
            -- 从接收到的数据中提取第一个字节，将其作为SoftAP的认证模式，并更新到环境变量中
            blufi_env.softap_auth_mode = blufi_hdr.data:byte(1)
            -- 调用回调函数，传递SoftAP信息事件类型和包含SSID和密码的信息表
            blufi_env.callback(espblufi.EVENT_SOFTAP_INFO, {
                ssid = blufi_env.softap_ssid,
                password = blufi_env.softap_passwd
            })
            sysplus.sendMsg(taskName, "AP_CONNED")
        elseif blufi_subtype == BLUFI_TYPE_DATA_SUBTYPE_SOFTAP_CHANNEL then
            blufi_env.softap_max_channel = blufi_hdr.data:byte(1)
        elseif blufi_subtype == BLUFI_TYPE_DATA_SUBTYPE_USERNAME then
            -- print("BLUFI_TYPE_DATA_SUBTYPE_USERNAME")
        elseif blufi_subtype == BLUFI_TYPE_DATA_SUBTYPE_CA then
            -- print("BLUFI_TYPE_DATA_SUBTYPE_CA")
        elseif blufi_subtype == BLUFI_TYPE_DATA_SUBTYPE_CLIENT_CERT then
            -- print("BLUFI_TYPE_DATA_SUBTYPE_CLIENT_CERT")
        elseif blufi_subtype == BLUFI_TYPE_DATA_SUBTYPE_SERVER_CERT then
            -- print("BLUFI_TYPE_DATA_SUBTYPE_SERVER_CERT")
        elseif blufi_subtype == BLUFI_TYPE_DATA_SUBTYPE_CLIENT_PRIV_KEY then
            -- print("BLUFI_TYPE_DATA_SUBTYPE_CLIENT_PRIV_KEY")
        elseif blufi_subtype == BLUFI_TYPE_DATA_SUBTYPE_SERVER_PRIV_KEY then
            -- print("BLUFI_TYPE_DATA_SUBTYPE_SERVER_PRIV_KEY")
        elseif blufi_subtype == BLUFI_TYPE_DATA_SUBTYPE_CUSTOM_DATA then
            blufi_env.callback(espblufi.EVENT_CUSTOM_DATA, blufi_hdr.data)
        end
    else
        return
    end
end

local function espblufi_task()
    while true do
        local result, event, data = sys.waitUntil(BLUFI_TOPIC)
        if result then
            if event == BLUFI_PROTOCOL_DATA then
                btc_blufi_protocol_handler(data)
            elseif event == BLUFI_TASK_EXIT then
                break
            end
        end
    end

end

local function espblufi_ble_callback(ble_device, ble_event, ble_param)
    if ble_event == ble.EVENT_CONN then
        blufi_env.ble_state = BLUFI_BLE_STATE_CONNED
    elseif ble_event == ble.EVENT_DISCONN then
        blufi_env.ble_state = BLUFI_BLE_STATE_DISCONN
        ble_device:adv_start()
    elseif ble_event == ble.EVENT_WRITE then
        sys.publish(BLUFI_TOPIC, BLUFI_PROTOCOL_DATA, ble_param.data)
    end
end

--[[
初始化espblufi
@api espblufi.init(bluetooth_device,espblufi_callback,local_name)
@userdata bluetooth_device 蓝牙设备对象
@function 事件回调函数
@number 蓝牙名，可选，默认为"BLUFI_xxx",xxx为设备型号(因为esp的配网测试app默认过滤蓝牙名称为BLUFI_开头的设备进行显示,可手动修改)
@usage
espblufi.init(espblufi_callback)
]]
function espblufi.init(bluetooth_device, espblufi_callback, local_name)
    if not bluetooth or not ble or not wlan then
        log.error("need bluetooth ble and wlan")
        return
    end
    if bluetooth_device == nil or type(bluetooth_device) ~= "userdata" then
        log.error("bluetooth_device is nil")
        return
    end
    if not espblufi_callback then
        log.error("espblufi_callback is nil")
        return
    else
        blufi_env.callback = espblufi_callback
    end
    if not local_name then
        local_name = "BLUFI_" .. rtos.bsp()
    end
    wlan.init()
    local ble_device = bluetooth_device:ble(espblufi_ble_callback)
    ble_device:gatt_create(espblufi_att_db)
    ble_device:adv_create({
        adv_data = {{ble.FLAGS, string.char(0x06)}, {ble.COMPLETE_LOCAL_NAME, local_name}}
    })
    blufi_env.ble_device = ble_device
    return
end

--[[
开始配网
@api espblufi.start()
@usage
espblufi.start()
]]
function espblufi.start()
    sys.taskInit(espblufi_task)
    blufi_env.ble_device:adv_start()
end

--[[
停止配网
@api espblufi.stop()
@usage
espblufi.stop()
]]
function espblufi.stop()
    blufi_env.ble_device:adv_stop()
    sys.publish(BLUFI_TOPIC, BLUFI_TASK_EXIT)
end

function espblufi.deinit()

end

--[[
发送自定义数据，一般用于接收到客户端发送的自定义命令后进行回复
@api espblufi.send_custom_data(data)
@string 回复的数据包内容
@usage
espblufi.send_custom_data(data)
]]
function espblufi.send_custom_data(data)
    btc_blufi_send_custom_data(data)
end

return espblufi
