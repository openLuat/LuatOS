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

function M.build_status_payload(wifi_state, storage_config)
    local status_payload = {
        connected = wifi_state.connected,
        ready = wifi_state.ready,
        current_ssid = wifi_state.current_ssid,
        rssi = wifi_state.rssi,
        ip = wifi_state.ip,
        netmask = wifi_state.netmask,
        gateway = wifi_state.gateway,
        bssid = wifi_state.bssid,
    }
    if storage_config then
        status_payload.wifi_enabled = storage_config.wifi_enabled
    end
    return status_payload
end

function M.update_status(wifi_state, storage_config)
    local status_payload = M.build_status_payload(wifi_state, storage_config)
    log.info("wifi_app", "WiFi状态更新:", json.encode(status_payload))
    sys.publish("WIFI_STATUS_UPDATED", status_payload)
end

function M.refresh_network_info(wifi_state, on_refresh)
    if not socket.adapter(socket.LWIP_STA) then
        log.warn("wifi_app", "正在获取IP地址")
        return
    end
    local wifi_info = wlan.getInfo()
    if wifi_info then
        if wifi_info.rssi then wifi_state.rssi = wifi_info.rssi end
        if wifi_info.bssid then wifi_state.bssid = wifi_info.bssid end
        if wifi_info.gateway then wifi_state.gateway = wifi_info.gateway end
    end
    local ip_addr, netmask, gateway = socket.localIP(socket.LWIP_STA)
    if ip_addr then
        wifi_state.ip = ip_addr
        wifi_state.netmask = netmask
        wifi_state.gateway = gateway
        wifi_state.ready = true
    else
        wifi_state.ready = false
    end
    if on_refresh then on_refresh(wifi_state) end
    M.update_status(wifi_state)
end

function M.handle_ip_ready(ip_addr, adapter, wifi_state, refresh_func)
    if adapter == socket.LWIP_STA then
        log.info("wifi_app", "WiFi IP就绪:", ip_addr)
        refresh_func()
    end
end

function M.handle_ip_lose(adapter, wifi_state)
    if adapter == socket.LWIP_STA then
        log.info("wifi_app", "WiFi IP断开")
        wifi_state.ready = false
        wifi_state.ip = "--"
        wifi_state.netmask = "--"
        wifi_state.gateway = "--"
        M.update_status(wifi_state)
    end
end

function M.handle_scan_done(wifi_state, scan_ref, on_done)
    if scan_ref[1] then
        sys.timerStop(scan_ref[1])
        scan_ref[1] = nil
    end
    local raw_results = wlan.scanResult() or {}
    local filtered_results = {}
    for _, wifi_entry in ipairs(raw_results) do
        if wifi_entry.ssid and wifi_entry.ssid ~= "" then
            table.insert(filtered_results, wifi_entry)
        end
    end
    wifi_state.scan_results = filtered_results
    sys.publish("WIFI_SCAN_DONE", wifi_state.scan_results)
    log.info("wifi_app", "扫描完成，找到", #wifi_state.scan_results, "个热点")
    if on_done then on_done() end
end

function M.handle_scan_timeout(scan_ref, on_timeout)
    scan_ref[1] = nil
    sys.publish("WIFI_SCAN_TIMEOUT")
    log.warn("wifi_app", "扫描超时")
    if on_timeout then on_timeout() end
end

function M.auto_scan_and_verify(storage_config, scan_timeout)
    scan_timeout = scan_timeout or 20000
    log.info("wifi_app", "开始自动扫描并查找最佳已保存网络")
    sys.publish("WIFI_STORAGE_GET_SAVED_LIST_REQ")
    local got_list, storage_data = sys.waitUntil("WIFI_STORAGE_GET_SAVED_LIST_RSP", 3000)
    local saved_list = (got_list and storage_data and storage_data.list) or {}
    if storage_config.ssid and storage_config.ssid ~= "" and storage_config.password and storage_config.password ~= "" then
        local found = false
        for _, status_msg in ipairs(saved_list) do
            if status_msg.ssid == storage_config.ssid then found = true; break end
        end
        if not found then
            table.insert(saved_list, {ssid = storage_config.ssid, password = storage_config.password,
                need_ping = storage_config.need_ping, local_network_mode = storage_config.local_network_mode,
                ping_ip = storage_config.ping_ip, ping_time = storage_config.ping_time,
                auto_socket_switch = storage_config.auto_socket_switch})
        end
    end
    if #saved_list == 0 then
        log.info("wifi_app", "没有已保存的网络")
        return { verified = false }
    end
    sys.publish("WIFI_SCAN_REQ")
    local sdone, raw_results = sys.waitUntil("WIFI_SCAN_DONE", scan_timeout)
    if not sdone then
        log.error("wifi_app", "自动扫描超时")
        return { verified = false }
    end
    local best_ssid, best_password, best_rssi = nil, nil, -200
    local best_config = nil
    for _, wifi_entry in ipairs(raw_results or {}) do
        for _, saved_network in ipairs(saved_list) do
            if wifi_entry.ssid == saved_network.ssid and (wifi_entry.rssi or -200) > best_rssi then
                best_ssid = saved_network.ssid
                best_password = saved_network.password
                best_rssi = wifi_entry.rssi or -200
                best_config = saved_network
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

function M.on_storage_set_enabled_rsp(data, storage_config)
    log.info("wifi_app", "设置开关响应:", data.success, data.enabled)
    if storage_config then
        storage_config.wifi_enabled = data.enabled
    end
end

function M.on_get_status_req(wifi_state, storage_config)
    log.info("wifi_app", "收到获取状态请求")
    local status = {}
    for k, v in pairs(wifi_state) do
        status[k] = v
    end
    if storage_config then
        status.wifi_enabled = storage_config.wifi_enabled
    end
    sys.publish("WIFI_STATUS_UPDATED", status)
end

function M.on_get_config_req(storage_config)
    log.info("wifi_app", "收到获取配置请求")
    sys.publish("WIFI_CONFIG_RSP", {config = storage_config})
end

function M.on_get_saved_list_req(storage_config, callback)
    log.info("wifi_app", "收到获取已保存网络列表请求")
    if _G.model_str:find("PC") then
        local status_payload = {
            {ssid = "TP-LINK_ABC", password = "12345678", need_ping = true, local_network_mode = false, ping_ip = "8.8.8.8", ping_time = "10000", auto_socket_switch = true},
            {ssid = "ChinaNet-5G", password = "abcdefgh", need_ping = true, local_network_mode = true, ping_ip = "192.168.1.1", ping_time = "5000", auto_socket_switch = false},
            {ssid = "CMCC-8888", password = "88888888", need_ping = false, local_network_mode = false, ping_ip = "", ping_time = "20000", auto_socket_switch = true},
            {ssid = "HUAWEI-123", password = "huawei123", need_ping = true, local_network_mode = true, ping_ip = "114.114.114.114", ping_time = "15000", auto_socket_switch = true},
            {ssid = "NETGEAR_5GHz", password = "netgear5g", need_ping = true, local_network_mode = false, ping_ip = "8.8.4.4", ping_time = "10000", auto_socket_switch = false},
        }
        sys.publish("WIFI_SAVED_LIST_RSP", {list = status_payload})
    else
        sys.publish("WIFI_STORAGE_GET_SAVED_LIST_REQ")
    end
end

function M.on_storage_get_saved_list_rsp(data)
    log.info("wifi_app", "收到已保存网络列表，数量:", #data.list)
    sys.publish("WIFI_SAVED_LIST_RSP", {list = data.list})
end

function M.on_storage_load_rsp(data, storage_config, after_init)
    storage_config = data.config
    log.info("wifi_app", "加载配置完成:", storage_config.ssid, "enabled:", storage_config.wifi_enabled)
    sys.taskInit(after_init)
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

function M.init(storage_config, on_storage_init)
    log.info("wifi_app", "开始初始化")
    sys.subscribe("WIFI_STORAGE_INIT_RSP", on_storage_init)
    sys.publish("WIFI_STORAGE_INIT_REQ")
end

function M.resolve_disconnect_reason(data)
    local reason_name = "未知错误"
    if data == 260 then reason_name = "DHCP超时"
    elseif data == 259 then reason_name = "程序主动断开"
    elseif data == 258 then reason_name = "密码错误"
    elseif data == 257 then reason_name = "找不到对应SSID"
    elseif data == 256 then reason_name = "信号丢失"
    elseif data == 3 then reason_name = "软件主动断开"
    end
    return reason_name
end

return M
