--[[
@module  ble_config_wifi
@summary ble_config_wifi 主应用功能模块（支持STA配网 + SoftAP热点配置）
@version 1.1
@date    2025.08.11
@author  拓毅恒
@usage
用法实例（支持双模式）：
    本模块实现了基于 BLE 的 Wi-Fi 配网功能，支持 STA 配网和 SoftAP 热点（Air8101暂不支持）配置两种模式，使用方法如下：
    1. 模块加载：在 main.lua 中使用 `require "ble_config_wifi"` 即可加载并运行本模块。
    2. 本demo中 手机端APP 下载地址：
        安卓测试APP下载地址1:https://github.com/EspressifApp/EspBlufiForAndroid/releases(如果打不开就用下面的)
        安卓测试APP下载地址2:https://docs.openluat.com/cdn2/apk/blufi-1.6.5-31.apk
    3. STA 配网流程：
        - 系统会初始化蓝牙设备并启动 espblufi 配网功能。
        - 通过手机APP端与设备进行 BLE 连接，配置 STA 的 SSID 和密码(APP端打开如果没有搜到蓝牙就在APP内多次下拉刷新，并且重启一下模组)。
        - 当收到 "STA_CONNED" 消息时，系统会发起 HTTP 请求验证网络可用性。
        - 当收到 "STA_DISCONNED" 消息时，系统会主动断开 STA 连接并禁用多网融合代理。
    4. 注：Air8101本身没有4G，所以暂时不支持SoftAP 功能！！！
    5. 消息处理：
        - 定义 `network_event_handler` 函数监听网络消息，处理 STA 连接、断开等事件。
        - 定义 `espblufi_callback` 回调函数，处理 STA 的信息事件并打印配置信息。
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
                log.info("AP:", "Air8101本身没有4G")
                log.info("AP:", "暂不支持配置AP功能")
                log.info("AP:", "请使用STA配网功能")
            end
        end
        sys.wait(10)
    end
end

-- 定义 espblufi 回调函数，用于处理不同类型的事件，如 EVENT_STA_INFO、EVENT_SOFTAP_INFO 等。
-- EVENT_STA_INFO 事件：当收到 APP 下发的 STA 连接信息时触发，会打印出设备连接 WiFi STA 所输入的键值对，其中 i 为配置项名称（如 "ssid"、"passwd"），v 为对应的值。
local function espblufi_callback(event, data)
    -- 检查事件类型是否为 STA 信息事件
    if event == espblufi.EVENT_STA_INFO then
        -- 遍历 STA 信息数据
        for i, v in pairs(data) do
            -- 打印 STA 信息数据的键值对
            log.info("STA:", i, v)
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
    log.info("espblufi_InIt","启动espblufi配网功能")
    espblufi.start()
end

-- 初始化网络配置任务
sysplus.taskInitEx(ble_wifi_config_task, "ble_wifi_config_task")
-- 初始化网络测试任务
sysplus.taskInitEx(network_event_handler, taskName)
