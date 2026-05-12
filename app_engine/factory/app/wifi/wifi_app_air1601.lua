--[[
@module  wifi_app
@summary WiFi应用模块（业务逻辑层，事件驱动）
@version 1.0
@date    2026.04.05
@author  江访
@usage
-- 接收的事件（来自UI层）：
--   WIFI_ENABLE_REQ: {enabled}
--   WIFI_SCAN_REQ
--   WIFI_CONNECT_REQ: {ssid, password, advanced_config}
--   WIFI_DISCONNECT_REQ
--   WIFI_GET_STATUS_REQ
--   WIFI_GET_CONFIG_REQ
--   WIFI_GET_SAVED_LIST_REQ: 获取已保存网络列表
-- 发布的事件（给UI层）：
--   WIFI_SCAN_STARTED, WIFI_SCAN_DONE, WIFI_SCAN_TIMEOUT
--   WIFI_CONNECTING, WIFI_CONNECTED, WIFI_DISCONNECTED
--   WIFI_STATUS_UPDATED: {status}
--   WIFI_CONFIG_RSP: {config}
--   WIFI_SAVED_LIST_RSP: {list}
-- 与storage层交互的事件：
--   WIFI_STORAGE_INIT_REQ (发送)
--   WIFI_STORAGE_INIT_RSP (接收)
--   WIFI_STORAGE_LOAD_REQ, WIFI_STORAGE_LOAD_RSP
--   WIFI_STORAGE_SAVE_REQ (发送，不等待响应)
--   WIFI_STORAGE_SET_ENABLED_REQ, WIFI_STORAGE_SET_ENABLED_RSP
]]

require "wifi_storage"
local wifi_common = require "wifi_app_common"

local SCAN_TIMEOUT = 20000
local UPDATE_INTERVAL = 5000

local wifi_state = { connected = false, ready = false, current_ssid = "", rssi = "--", ip = "--", netmask = "--", gateway = "--", bssid = "--", scan_results = {} }
local saved_config = { wifi_enabled = false, ssid = "", password = "", need_ping = true, local_network_mode = false, ping_ip = "", ping_time = "10000", auto_socket_switch = true }

local scan_timer = nil
local update_timer = nil
local last_connect = nil
local disconnect_reason = nil
local user_disconnect = false
local user_connect = false

local wifi_ready = false
local wifi_busy = false
local scan_busy = false

local function update_status(s)
    if not s then
        log.error("wifi_app", "更新WiFi状态时，状态对象为空")
        return
    end
    for k, v in pairs(s) do
        wifi_state[k] = v
    end
    wifi_common.update_status(wifi_state, saved_config)
end

local function refresh_net_info()
    local function update_wifi_signal()
        if wlan_info then
            local rssi_val = wlan_info.rssi
            local signal_level = 0
            if rssi_val > -60 then signal_level = 4
            elseif rssi_val > -70 then signal_level = 3
            elseif rssi_val > -80 then signal_level = 2
            else signal_level = 1 end
            sys.publish("STATUS_WIFI_SIGNAL_UPDATED", signal_level)
        end
    end
    wifi_common.refresh_network_info(wifi_state, update_wifi_signal)
end

local function init_wifi_hw()
    if wifi_ready then return end
    log.info("wifi_app", "初始化airlink+wlan硬件")
    gpio.setup(55, 0)
    gpio.set(55, 0)
    sys.wait(50)
    gpio.set(55, 1)
    sys.wait(120)
    airlink.config(airlink.CONF_SPI_ID, 1)
    airlink.config(airlink.CONF_SPI_CS, 8)
    airlink.config(airlink.CONF_SPI_RDY, 14)
    airlink.config(airlink.CONF_SPI_SPEED, 20 * 1000000)
    airlink.init()
    netdrv.setup(socket.LWIP_AP, netdrv.WHALE)
    netdrv.setup(socket.LWIP_STA, netdrv.WHALE)
    airlink.start(airlink.MODE_SPI_MASTER)
    sys.wait(1000)
    while not airlink.ready() do
        log.info("wifi_app", "等待airlink就绪...")
        sys.wait(100)
    end
    log.info("wifi_app", "airlink就绪")
    wlan.init()
    wlan.setMode(wlan.STATIONAP)
    wifi_ready = true
    wifi_busy = false
    sys.wait(5000)
    log.info("wifi_app", "airlink+wlan硬件初始化完成")
    sys.publish("WIFI_HW_READY")
end

local function ensure_wifi_ready()
    if wifi_ready then return true end
    if not wifi_busy then
        wifi_busy = true
        sys.taskInit(init_wifi_hw)
    end
    return false
end

local function handle_sta_event(event, data)
    log.info("wifi_app", "WiFi STA事件:", event, data)
    if event == "CONNECTED" then
        wifi_state.connected = true
        wifi_state.ready = false
        wifi_state.current_ssid = data
        sys.publish("WIFI_CONNECTED", data)
        sys.publish("STATUS_WIFI_SIGNAL_UPDATED", 3)
        last_connect = "CONNECTED"
        user_connect = false
        if update_timer then
            sys.timerStop(update_timer)
            update_timer = nil
        end
        update_timer = sys.timerLoopStart(refresh_net_info, UPDATE_INTERVAL)
    elseif event == "DISCONNECTED" then
        if user_connect then
            log.info("wifi_app", "用户发起的连接失败，重置状态以允许再次弹窗")
            last_connect = nil
        elseif last_connect == "DISCONNECTED" then
            log.info("wifi_app", "已断开状态，跳过重复事件")
            return
        end
        if disconnect_reason == "config" then
            log.info("wifi_app", "配置前断开，跳过事件处理")
            disconnect_reason = nil
            return
        end
        wifi_state.connected = false
        wifi_state.ready = false
        wifi_state.current_ssid = ""
        wifi_state.rssi = "--"
        wifi_state.ip = "--"
        wifi_state.netmask = "--"
        wifi_state.gateway = "--"
        wifi_state.bssid = "--"
        if update_timer then
            sys.timerStop(update_timer)
            update_timer = nil
        end
        local reason_name = wifi_common.resolve_disconnect_reason(data)
        sys.publish("WIFI_DISCONNECTED", reason_name, data)
        sys.publish("STATUS_WIFI_SIGNAL_UPDATED", 0)
        last_connect = "DISCONNECTED"
        user_connect = false
        if user_disconnect then
            log.info("wifi_app", "用户主动断开，只进行扫描")
            user_disconnect = false
            sys.publish("WIFI_SCAN_REQ")
        end
    end
end

local function handle_ip_ready(ip, adapter)
    if adapter == socket.LWIP_STA then
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")
        log.info("wifi_app", "WiFi IP就绪，DNS已设置:", ip)
    end
    wifi_common.handle_ip_ready(ip, adapter, wifi_state, refresh_net_info)
end

local function handle_ip_lose(adapter)
    wifi_common.handle_ip_lose(adapter, wifi_state)
end

local function handle_scan_done()
    local scan_ref = {}
    scan_ref[1] = scan_timer
    wifi_common.handle_scan_done(wifi_state, scan_ref, function() scan_busy = false end)
    scan_timer = scan_ref[1]
end

local function handle_scan_timeout()
    scan_timer = nil
    scan_busy = false
    wifi_common.handle_scan_timeout({})
end

local function auto_scan_verify()
    return wifi_common.auto_scan_and_verify(saved_config, SCAN_TIMEOUT + 5000)
end

local function run_auto_connect()
    if not saved_config.wifi_enabled then
        log.info("wifi_app", "WiFi开关已关闭，跳过自动连接")
        return
    end
    ensure_wifi_ready()
    if not wifi_ready then
        sys.waitUntil("WIFI_HW_READY", 15000)
    end
    if not wifi_ready then
        log.error("wifi_app", "airlink+wlan硬件初始化超时")
        return
    end
    log.info("wifi_app", "开始执行开机自动连接（选择信号最强的已保存网络）")
    if wifi_state.connected then
        log.info("wifi_app", "已连接WiFi，只进行扫描刷新列表")
        sys.publish("WIFI_SCAN_REQ")
        return
    end
    local verify_result = auto_scan_verify()
    if verify_result.verified then
        log.info("wifi_app", "自动连接到最佳网络:", verify_result.ssid, "信号:", verify_result.signal)
        sys.publish("WIFI_CONNECT_REQ", {
            ssid = verify_result.ssid,
            password = verify_result.password,
            advanced_config = verify_result.config and { need_ping = verify_result.config.need_ping, local_network_mode = verify_result.config.local_network_mode, ping_ip = verify_result.config.ping_ip, ping_time = verify_result.config.ping_time, auto_socket_switch = verify_result.config.auto_socket_switch }
        })
    else
        log.info("wifi_app", "附近没有已保存网络，等待用户手动连接")
    end
end

local function on_storage_loaded(data)
    saved_config = data.config
    log.info("wifi_app", "加载配置完成:", saved_config.ssid, "enabled:", saved_config.wifi_enabled)
    sys.taskInit(run_auto_connect)
end

local function on_set_enabled(data)
    wifi_common.on_storage_set_enabled_rsp(data, saved_config)
end

local function on_enable_request(data)
    local enabled = data.enabled
    log.info("wifi_app", "收到开关请求:", enabled)
    if saved_config then
        saved_config.wifi_enabled = enabled
    end
    sys.publish("WIFI_STORAGE_SET_ENABLED_REQ", {enabled = enabled})
    if not enabled then
        log.info("wifi_app", "正在关闭WiFi网卡")
        if wifi_ready then
            wlan.disconnect()
        end
        wifi_state.connected = false
        wifi_state.ready = false
        wifi_state.current_ssid = ""
        wifi_state.rssi = "--"
        wifi_state.ip = "--"
        wifi_state.netmask = "--"
        wifi_state.gateway = "--"
        wifi_state.bssid = "--"
        wifi_state.scan_results = {}
        update_status(wifi_state)
    else
        log.info("wifi_app", "正在开启WiFi网卡")
        sys.taskInit(function()
            ensure_wifi_ready()
            if not wifi_ready then
                sys.waitUntil("WIFI_HW_READY", 15000)
            end
            if saved_config and saved_config.ssid and saved_config.ssid ~= "" then
                if wifi_state.connected then
                    log.info("wifi_app", "已连接WiFi，只进行扫描")
                    sys.publish("WIFI_SCAN_REQ")
                else
                    log.info("wifi_app", "检测到保存的SSID，执行自动连接")
                    run_auto_connect()
                end
            end
        end)
    end
end

local function on_scan_request()
    log.info("wifi_app", "收到扫描请求")
    if not wifi_ready then
        ensure_wifi_ready()
        log.info("wifi_app", "等待WiFi硬件初始化完成后再扫描")
        sys.taskInit(function()
            sys.waitUntil("WIFI_HW_READY", 35000)
            if wifi_ready and not scan_busy then
                scan_busy = true
                wlan.scan()
                if scan_timer then sys.timerStop(scan_timer) end
                scan_timer = sys.timerStart(handle_scan_timeout, SCAN_TIMEOUT)
                sys.publish("WIFI_SCAN_STARTED")
            end
        end)
        return
    end
    if scan_busy then
        log.info("wifi_app", "扫描已在进行中，跳过重复请求")
        return
    end
    scan_busy = true
    wlan.scan()
    if scan_timer then
        sys.timerStop(scan_timer)
    end
    scan_timer = sys.timerStart(handle_scan_timeout, SCAN_TIMEOUT)
    sys.publish("WIFI_SCAN_STARTED")
end

local function on_connect_request(data)
    local ssid = data.ssid
    local password = data.password
    local adv_config = data.advanced_config
    log.info("wifi_app", "收到连接请求:", ssid)
    user_connect = true
    if not ssid or ssid == "" then
        sys.publish("WIFI_DISCONNECTED", "SSID不能为空", -3)
        return
    end
    if not password or password == "" then
        sys.publish("WIFI_DISCONNECTED", "密码不能为空", -4)
        return
    end
    if saved_config and not saved_config.wifi_enabled then
        log.warn("wifi_app", "WiFi已关闭，无法连接")
        return
    end
    sys.publish("WIFI_STORAGE_SAVE_REQ", { ssid = ssid, password = password, advanced_config = adv_config })
    sys.publish("WIFI_CONNECTING", ssid)
    disconnect_reason = "config"
    sys.taskInit(function()
        if not wifi_ready then
            ensure_wifi_ready()
            if not wifi_ready then
                local success = sys.waitUntil("WIFI_HW_READY", 15000)
                if not success then
                    log.error("wifi_app", "WiFi硬件初始化超时，无法连接")
                    sys.publish("WIFI_DISCONNECTED", "硬件初始化超时", -6)
                    return
                end
            end
        end
        disconnect_reason = "config"
        wlan.disconnect()
        sys.wait(500)
        local res = wlan.connect(ssid, password)
        if res then
            log.info("wifi_app", "WiFi连接已发起:", ssid)
        else
            log.error("wifi_app", "WiFi连接发起失败")
            sys.publish("WIFI_DISCONNECTED", "连接发起失败", -5)
        end
    end)
end

local function on_disconnect_request()
    log.info("wifi_app", "收到断开请求")
    user_disconnect = true
    disconnect_reason = "user"
    wlan.disconnect()
    disconnect_reason = nil
end

local function on_get_status()
    wifi_common.on_get_status_req(wifi_state, saved_config)
end

local function on_get_config()
    wifi_common.on_get_config_req(saved_config)
end

local function on_get_saved_list()
    wifi_common.on_get_saved_list_req(saved_config)
end

local function on_saved_list_rsp(data)
    wifi_common.on_storage_get_saved_list_rsp(data)
end

local function on_storage_ready(data)
    wifi_common.on_storage_init_rsp(data)
end

local function init_module()
    log.info("wifi_app", "开始初始化")
    sys.subscribe("WIFI_STORAGE_INIT_RSP", on_storage_ready)
    sys.publish("WIFI_STORAGE_INIT_REQ")
end

sys.subscribe("WLAN_STA_INC", handle_sta_event)
sys.subscribe("WLAN_SCAN_DONE", handle_scan_done)
sys.subscribe("IP_READY", handle_ip_ready)
sys.subscribe("IP_LOSE", handle_ip_lose)
sys.subscribe("WIFI_STORAGE_LOAD_RSP", on_storage_loaded)
sys.subscribe("WIFI_STORAGE_SET_ENABLED_RSP", on_set_enabled)
sys.subscribe("WIFI_ENABLE_REQ", on_enable_request)
sys.subscribe("WIFI_SCAN_REQ", on_scan_request)
sys.subscribe("WIFI_CONNECT_REQ", on_connect_request)
sys.subscribe("WIFI_DISCONNECT_REQ", on_disconnect_request)
sys.subscribe("WIFI_GET_STATUS_REQ", on_get_status)
sys.subscribe("WIFI_GET_CONFIG_REQ", on_get_config)
sys.subscribe("WIFI_GET_SAVED_LIST_REQ", on_get_saved_list)
sys.subscribe("WIFI_STORAGE_GET_SAVED_LIST_RSP", on_saved_list_rsp)

sys.taskInit(init_module)
