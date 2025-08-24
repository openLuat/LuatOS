--[[
@module  ble_config_wifi
@summary ble_config_wifi 主应用功能模块（支持STA配网 + SoftAP热点配置）
@version 1.1
@date    2025.08.11
@author  拓毅恒
@usage
用法实例（支持双模式）：
    本模块实现了基于 BLE 的 Wi-Fi 配网功能，支持 STA 配网和 SoftAP 热点配置两种模式，使用方法如下：
    1. 模块加载：在 main.lua 中使用 `require "ble_config_wifi"` 即可加载并运行本模块。
    2. 本demo中 手机端APP 下载地址：
        安卓测试APP下载地址1:https://github.com/EspressifApp/EspBlufiForAndroid/releases(如果打不开就用下面的)
        安卓测试APP下载地址2:https://docs.openluat.com/cdn2/apk/blufi-1.6.5-31.apk
    3. STA 配网流程：
        - 系统会初始化蓝牙设备并启动 espblufi 配网功能。
        - 通过手机APP端与设备进行 BLE 连接，配置 STA 的 SSID 和密码(APP端打开如果没有搜到蓝牙就在APP内多次下拉刷新，并且重启一下模组)。
        - 当收到 "STA_CONNED" 消息时，系统会发起 HTTP 请求验证网络可用性。
        - 当收到 "STA_DISCONNED" 消息时，系统会主动断开 STA 连接并禁用多网融合代理。
    4. SoftAP 配置流程：
        - 手机APP端通过 BLE 配置 SoftAP 的 SSID、密码、信道和最大连接数。
        - espblufi 模块收到配置后，调用 `wlan.createAP()` 创建热点。
        - 当收到 "AP_CONNED" 消息时，系统会发起 SoftAP 创建请求。
        - 同时调用 `exnetif.setproxy()` 启用多网融合，使连接热点的设备可通过 4G 或 STA 上网。
    5. 消息处理：
        - 定义 `network_event_handler` 函数监听网络消息，处理 STA 连接、断开及 AP 创建等事件。
        - 定义 `espblufi_callback` 回调函数，处理 STA 和 SoftAP 的信息事件并打印配置信息。
    6. 任务管理：
        - 初始化 `ble_wifi_config_task` 任务负责蓝牙设备和 espblufi 模块的初始化及配网功能启动。
        - 初始化 `network_event_handler` 任务持续监听网络消息，保持系统持续运行。
本文件没有对外接口，直接在 main.lua 中 require "ble_config_wifi" 即可加载运行。
]]

-- 加载espblufi应用功能模块
local espblufi = require("espblufi")
local exnetif = require("exnetif")
local taskName = "config_wifi"

-- 定义网络测试函数
local function network_event_handler()
    while true do
        -- 等待指定任务的消息，不设置超时时间
        msg = sysplus.waitMsg(taskName, nil)
        -- 检查接收到的消息是否为表类型
        if type(msg) == 'table' then
            log.info("MSG:", msg[1])
            -- 检查消息的第一个元素是否为 "STA_CONNED"，即 STA 连接成功消息
            if msg[1] == "STA_CONNED" then
                -- 打印 STA 连接成功日志
                log.info("STA:", "STA CONNED OK!")
                sys.wait(3000)
                -- 发起一个 GET 请求，请求 https://httpbin.air32.cn/bytes/2048 地址，使用 STA 适配器，超时时间为 5000 毫秒
                local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil, {adapter = socket.LWIP_STA,timeout = 5000,debug = false}).wait()
                -- 打印 HTTP 请求执行结果，包含状态码、响应头和响应体长度
                log.info("http执行结果", code, headers, body and #body)
            end
            -- 检查消息的第一个元素是否为 "STA_DISCONNED"，即 STA 断开连接消息
            if msg[1] == "STA_DISCONNED" then
                -- 打印 STA 断开连接日志
                log.info("STA:", "STA DISCONNED!")
            end
            -- 检查消息的第一个元素是否为 "AP_CONNED"，即 AP 创建连接消息
            if msg[1] == "AP_CONNED" then
                log.info("AP:", "接收到AP创建消息，开始启动AP")
                -- 调用 exnetif.setproxy 函数，设置 AP 网卡与 4G 网卡的多网融合代理
                exnetif.setproxy(socket.LWIP_AP, socket.LWIP_GP, {
                    ssid = msg[2], -- WiFi名称(string)，网卡包含wifi时填写
                    password = msg[3], -- WiFi密码(string)，网卡包含wifi时填写
                    adapter_addr = "192.168.5.1",    -- adapter网卡的ip地址
                    adapter_gw= {192, 168, 5, 1},   -- adapter网卡的网关地址
                    ap_opts={                        -- AP模式下配置项
                        hidden = false,                  -- 是否隐藏SSID, 默认false,不隐藏
                        max_conn = msg[4]                  -- 最大客户端数量
                    },
                    channel=msg[5]                        -- AP建立的通道
                })
                log.info("AP:", "AP创建成功")
            end
        end
        sys.wait(10)
    end
end

-- 定义 espblufi 回调函数，用于处理不同类型的事件，如 EVENT_STA_INFO、EVENT_SOFTAP_INFO 等。
-- EVENT_STA_INFO 事件：当收到 APP 下发的 STA 连接信息时触发，会打印出设备连接 WiFi STA 所输入的键值对，其中 i 为配置项名称（如 "ssid"、"passwd"），v 为对应的值。
-- EVENT_SOFTAP_INFO 事件：当收到 APP 下发的 SoftAP 配置信息时触发，会打印出 SoftAP 配置的键值对，其中 i 为配置项名称（如 "ssid"、"passwd"、"channel" 等），v 为对应的值。
local function espblufi_callback(event, data)
    -- 检查事件类型是否为 STA 信息事件
    if event == espblufi.EVENT_STA_INFO then
        -- 遍历 STA 信息数据
        for i, v in pairs(data) do
            -- 打印 STA 信息数据的键值对
            log.info("STA:", i, v)
        end
        -- 检查事件类型是否为 SoftAP 信息事件
    elseif event == espblufi.EVENT_SOFTAP_INFO then
        -- 遍历 SoftAP 信息数据
        for i, v in pairs(data) do
            -- 打印 SoftAP 信息数据的键值对
            log.info("SoftAP:", i, v)
        end
    end
end

-- 定义网络配置任务函数
local function ble_wifi_config_task()
    -- 初始化蓝牙设备，并将初始化结果存储在 bluetooth_device 变量中
    local bluetooth_device = bluetooth.init()
    -- 初始化 espblufi 模块，传入蓝牙设备实例和回调函数
    espblufi.init(bluetooth_device, espblufi_callback)
    -- 启动 espblufi 配网功能
    espblufi.start()
end

-- 初始化网络配置任务
sysplus.taskInitEx(ble_wifi_config_task, "ble_wifi_config_task")
-- 初始化网络测试任务
sysplus.taskInitEx(network_event_handler, taskName)
