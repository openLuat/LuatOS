--[[
@module  wifi_app_common
@summary WiFi应用模块公共逻辑，被 wifi_app_air8000w / wifi_app_air1601 共用
@version 1.0
@date    2026.05.07
@author  江访
@usage
提取两个平台 wifi_app 共享的函数：状态更新、IP事件、扫描处理、自动连接、配置管理等。
]]--
local M = {}

function M.build_status_payload(wifi_status, saved_config)
    local log_status = {
        connected = wifi_status.connected,
        ready = wifi_status.ready,
        current_ssid = wifi_status.current_ssid,
        rssi = wifi_status.rssi,
        ip = wifi_status.ip,
        netmask = wifi_status.netmask,
        gateway = wifi_status.gateway,
        bssid = wifi_status.bssid,
    }
    if saved_config then
        log_status.wifi_enabled = saved_config.wifi_enabled
    end
    return log_status
end

function M.update_status(wifi_status, saved_config)
    local log_status = M.build_status_payload(wifi_status, saved_config)
    log.info("wifi_app", "WiFi状态更新:", json.encode(log_status))
    sys.publish("WIFI_STATUS_UPDATED", log_status)
end

function M.refresh_network_info(wifi_status, update_cb)
    if not socket.adapter(socket.LWIP_STA) then
        log.warn("wifi_app", "正在获取IP地址")
        return
    end
    local wlan_info = wlan.getInfo()
    if wlan_info then
        if wlan_info.rssi then wifi_status.rssi = wlan_info.rssi end
        if wlan_info.bssid then wifi_status.bssid = wlan_info.bssid end
        if wlan_info.gw then wifi_status.gateway = wlan_info.gw end
    end
    local ip, netmask, gateway = socket.localIP(socket.LWIP_STA)
    if ip then
        wifi_status.ip = ip
        wifi_status.netmask = netmask
        wifi_status.gateway = gateway
        wifi_status.ready = true
    else
        wifi_status.ready = false
    end
    if update_cb then update_cb(wifi_status) end
    M.update_status(wifi_status)
end

function M.handle_ip_ready(ip, adapter, wifi_status, refresh_fn)
    if adapter == socket.LWIP_STA then
        log.info("wifi_app", "WiFi IP就绪:", ip)
        refresh_fn()
    end
end

function M.handle_ip_lose(adapter, wifi_status)
    if adapter == socket.LWIP_STA then
        log.info("wifi_app", "WiFi IP断开")
        wifi_status.ready = false
        wifi_status.ip = "--"
        wifi_status.netmask = "--"
        wifi_status.gateway = "--"
        M.update_status(wifi_status)
    end
end

function M.handle_scan_done(wifi_status, scan_timer_ref, on_done_cb)
    if scan_timer_ref[1] then
        sys.timerStop(scan_timer_ref[1])
        scan_timer_ref[1] = nil
    end
    local results = wlan.scanResult() or {}
    local filtered_results = {}
    for _, wifi in ipairs(results) do
        if wifi.ssid and wifi.ssid ~= "" then
            table.insert(filtered_results, wifi)
        end
    end
    wifi_status.scan_results = filtered_results
    sys.publish("WIFI_SCAN_DONE", wifi_status.scan_results)
    log.info("wifi_app", "扫描完成，找到", #wifi_status.scan_results, "个热点")
    if on_done_cb then on_done_cb() end
end

function M.handle_scan_timeout(scan_timer_ref, on_timeout_cb)
    scan_timer_ref[1] = nil
    sys.publish("WIFI_SCAN_TIMEOUT")
    log.warn("wifi_app", "扫描超时")
    if on_timeout_cb then on_timeout_cb() end
end

function M.auto_scan_and_verify(saved_config, scan_timeout)
    scan_timeout = scan_timeout or 15000
    log.info("wifi_app", "开始自动扫描并查找最佳已保存网络")
    sys.publish("WIFI_STORAGE_GET_SAVED_LIST_REQ")
    local got_list, saved_data = sys.waitUntil("WIFI_STORAGE_GET_SAVED_LIST_RSP", 3000)
    local saved_list = (got_list and saved_data and saved_data.list) or {}
    if saved_config.ssid and saved_config.ssid ~= "" and saved_config.password and saved_config.password ~= "" then
        local exists = false
        for _, s in ipairs(saved_list) do
            if s.ssid == saved_config.ssid then exists = true; break end
        end
        if not exists then
            table.insert(saved_list, {ssid = saved_config.ssid, password = saved_config.password,
                need_ping = saved_config.need_ping, local_network_mode = saved_config.local_network_mode,
                ping_ip = saved_config.ping_ip, ping_time = saved_config.ping_time,
                auto_socket_switch = saved_config.auto_socket_switch})
        end
    end
    if #saved_list == 0 then
        log.info("wifi_app", "没有已保存的网络")
        return { verified = false }
    end
    local scan_done, results = sys.waitUntil("WIFI_SCAN_DONE", scan_timeout)
    if not scan_done then
        log.error("wifi_app", "自动扫描超时")
        return { verified = false }
    end
    local best_ssid, best_password, best_rssi = nil, nil, -200
    local best_config = nil
    for _, wifi in ipairs(results or {}) do
        for _, saved in ipairs(saved_list) do
            if wifi.ssid == saved.ssid and (wifi.rssi or -200) > best_rssi then
                best_ssid = saved.ssid
                best_password = saved.password
                best_rssi = wifi.rssi or -200
                best_config = saved
            end
        end
    end
    if best_ssid then
        log.info("wifi_app", "找到最佳已保存网络:", best_ssid, "信号:", best_rssi)
        return { verified = true, ssid = best_ssid, password = best_password, signal = best_rssi, config = best_config }
    end
    log.info("wifi_app", "未在附近找到任何已保存网络")
    return { verified = false }
end

function M.on_storage_set_enabled_rsp(data, saved_config)
    log.info("wifi_app", "设置开关响应:", data.success, data.enabled)
    if saved_config then
        saved_config.wifi_enabled = data.enabled
    end
end

function M.on_get_status_req(wifi_status, saved_config)
    log.info("wifi_app", "收到获取状态请求")
    local status = {}
    for k, v in pairs(wifi_status) do
        status[k] = v
    end
    if saved_config then
        status.wifi_enabled = saved_config.wifi_enabled
    end
    sys.publish("WIFI_STATUS_UPDATED", status)
end

function M.on_get_config_req(saved_config)
    log.info("wifi_app", "收到获取配置请求")
    sys.publish("WIFI_CONFIG_RSP", {config = saved_config})
end

function M.on_get_saved_list_req(saved_config, on_list_ready)
    log.info("wifi_app", "收到获取已保存网络列表请求")
    if _G.model_str:find("PC") then
        local list = {
            {ssid = "TP-LINK_ABC", password = "12345678", need_ping = true, local_network_mode = false, ping_ip = "8.8.8.8", ping_time = "10000", auto_socket_switch = true},
            {ssid = "ChinaNet-5G", password = "abcdefgh", need_ping = true, local_network_mode = true, ping_ip = "192.168.1.1", ping_time = "5000", auto_socket_switch = false},
            {ssid = "CMCC-8888", password = "88888888", need_ping = false, local_network_mode = false, ping_ip = "", ping_time = "20000", auto_socket_switch = true},
            {ssid = "HUAWEI-123", password = "huawei123", need_ping = true, local_network_mode = true, ping_ip = "114.114.114.114", ping_time = "15000", auto_socket_switch = true},
            {ssid = "NETGEAR_5GHz", password = "netgear5g", need_ping = true, local_network_mode = false, ping_ip = "8.8.4.4", ping_time = "10000", auto_socket_switch = false},
        }
        sys.publish("WIFI_SAVED_LIST_RSP", {list = list})
    else
        sys.publish("WIFI_STORAGE_GET_SAVED_LIST_REQ")
    end
end

function M.on_storage_get_saved_list_rsp(data)
    log.info("wifi_app", "收到已保存网络列表，数量:", #data.list)
    sys.publish("WIFI_SAVED_LIST_RSP", {list = data.list})
end

function M.on_storage_load_rsp(data, saved_config, auto_connect_fn)
    saved_config = data.config
    log.info("wifi_app", "加载配置完成:", saved_config.ssid, "enabled:", saved_config.wifi_enabled)
    sys.taskInit(auto_connect_fn)
end

function M.on_storage_init_rsp(data, on_success)
    log.info("wifi_app", "storage初始化响应:", data.success)
    if not data.success then
        log.error("wifi_app", "storage初始化失败")
        return
    end
    sys.publish("WIFI_STORAGE_LOAD_REQ")
    log.info("wifi_app", "初始化完成")
    if on_success then on_success() end
end

function M.init(saved_config, on_storage_init_rsp_fn)
    log.info("wifi_app", "开始初始化")
    sys.subscribe("WIFI_STORAGE_INIT_RSP", on_storage_init_rsp_fn)
    sys.publish("WIFI_STORAGE_INIT_REQ")
end

function M.resolve_disconnect_reason(data)
    local reason = "未知错误"
    if data == 260 then reason = "DHCP超时"
    elseif data == 259 then reason = "程序主动断开"
    elseif data == 258 then reason = "密码错误"
    elseif data == 257 then reason = "找不到对应SSID"
    elseif data == 256 then reason = "信号丢失"
    elseif data == 3 then reason = "软件主动断开"
    end
    return reason
end

return M
