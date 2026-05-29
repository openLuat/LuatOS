--[[
@module  wifi_app_common
@summary WiFi应用模块公共逻辑，被 wifi_app_air8000w / wifi_app_air1601 共用
@version 1.1
@date    2026.05.19
@author  江访
@usage
提取两个平台 wifi_app 共享的函数：状态更新、IP事件、扫描处理、自动连接、配置管理、
联网连通性确认（NTP同步）。
]]

local CONNECTIVITY_TIMEOUT = 15000

local M = {}

--[[
构建WiFi状态负载（用于发布WIFI_STATUS_UPDATED）
@param table wifi_state - WiFi状态表
@param table storage_config - 存储的WiFi配置（可选）
@return table status_payload - 状态负载
]]
function M.build_status_payload(wifi_state, storage_config)
    local status_payload = {
        connected = wifi_state.connected,
        ready = wifi_state.ready,
        connectivity_verified = wifi_state.connectivity_verified,
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

--[[
发布WiFi状态更新事件
@param table wifi_state - WiFi状态表
@param table storage_config - 存储的WiFi配置（可选）
]]
local last_wifi_status_json = ""
function M.update_status(wifi_state, storage_config)
    local status_payload = M.build_status_payload(wifi_state, storage_config)
    -- 仅在状态变化时打印日志，避免RSSI波动导致日志风暴
    local current_json = json.encode(status_payload)
    if current_json ~= last_wifi_status_json then
        last_wifi_status_json = current_json
        log.info("wifi_app", "WiFi状态更新:", current_json)
    end
    sys.publish("WIFI_STATUS_UPDATED", status_payload)
end

--[[
刷新网络信息（IP、RSSI、网关等）
@param table wifi_state - WiFi状态表
@param function on_refresh - 刷新完成后的回调（可选）
]]
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

--[[
处理IP就绪事件
@param string ip_addr - IP地址
@param number adapter - 网卡适配器类型
@param table wifi_state - WiFi状态表
@param function refresh_func - 刷新回调
]]
function M.handle_ip_ready(ip_addr, adapter, wifi_state, refresh_func)
    if adapter == socket.LWIP_STA then
        log.info("wifi_app", "WiFi IP就绪:", ip_addr)
        refresh_func()
    end
end

--[[
处理IP丢失事件
@param number adapter - 网卡适配器类型
@param table wifi_state - WiFi状态表
]]
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

--[[
处理扫描完成事件
@param table wifi_state - WiFi状态表
@param table scan_ref - 扫描定时器引用 {timer_id}
@param function on_done - 完成回调（可选）
]]
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

--[[
处理扫描超时事件
@param table scan_ref - 扫描定时器引用
@param function on_timeout - 超时回调（可选）
]]
function M.handle_scan_timeout(scan_ref, on_timeout)
    scan_ref[1] = nil
    sys.publish("WIFI_SCAN_TIMEOUT")
    log.warn("wifi_app", "扫描超时")
    if on_timeout then on_timeout() end
end

--[[
自动扫描并验证附近是否有已保存网络
@param table storage_config - 存储配置
@param number scan_timeout - 扫描超时时间（毫秒）
@return table {verified, ssid, password, signal, config}
]]
function M.auto_scan_and_verify(storage_config, scan_timeout)
    scan_timeout = scan_timeout or 20000
    log.info("wifi_app", "开始自动扫描并查找最佳已保存网络")
    sys.publish("WIFI_STORAGE_GET_SAVED_LIST_REQ")
    local got_list, storage_data = sys.waitUntil("WIFI_STORAGE_GET_SAVED_LIST_RSP", 3000)
    local saved_list = (got_list and storage_data and storage_data.list) or {}
    if storage_config.ssid and storage_config.ssid ~= "" then  -- 无密码热点允许password为空
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

--[[
开始联网连通性确认
等待NTP_UPDATE事件作为"有真实互联网访问"的标志。
若超时则标记为未确认，不影响已有连接（可继续使用）。
@param table wifi_state - WiFi状态表
@param number timeout_ms - 超时时间（毫秒）
]]
function M.start_connectivity_verification(wifi_state, timeout_ms)
    timeout_ms = timeout_ms or CONNECTIVITY_TIMEOUT
    if wifi_state.connectivity_verified then
        log.info("wifi_app", "联网连通性已确认，跳过")
        return
    end
    log.info("wifi_app", "开始联网连通性确认（等待NTP同步）")
    local ok = sys.waitUntil("NTP_UPDATE", timeout_ms)
    if ok then
        wifi_state.connectivity_verified = true
        log.info("wifi_app", "联网连通性确认成功（NTP同步已完成）")
        M.update_status(wifi_state)
    else
        log.warn("wifi_app", "联网连通性确认超时，连接可能受限")
        -- connectivity_verified 保持 false，图标不受影响
    end
end

--[[
重置联网连通性状态（断连时调用）
@param table wifi_state - WiFi状态表
]]
function M.reset_connectivity(wifi_state)
    wifi_state.connectivity_verified = false
end

--[[
处理存储开关响应
@param table data - 响应数据
@param table storage_config - 存储配置
]]
function M.on_storage_set_enabled_rsp(data, storage_config)
    log.info("wifi_app", "设置开关响应:", data.success, data.enabled)
    if storage_config then
        storage_config.wifi_enabled = data.enabled
    end
end

--[[
处理获取状态请求
@param table wifi_state - WiFi状态表
@param table storage_config - 存储配置
]]
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

--[[
处理获取配置请求
@param table storage_config - 存储配置
]]
function M.on_get_config_req(storage_config)
    log.info("wifi_app", "收到获取配置请求")
    sys.publish("WIFI_CONFIG_RSP", {config = storage_config})
end

--[[
处理获取已保存列表请求
@param table storage_config - 存储配置
@param function callback - 回调查询结果
]]
function M.on_get_saved_list_req(storage_config, callback)
    log.info("wifi_app", "收到获取已保存网络列表请求")
    if _G.project_config and _G.project_config.chip == "PC" then
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

--[[
处理存储返回的已保存列表
@param table data - 存储数据
]]
function M.on_storage_get_saved_list_rsp(data)
    log.info("wifi_app", "收到已保存网络列表，数量:", #data.list)
    sys.publish("WIFI_SAVED_LIST_RSP", {list = data.list})
end

function M.on_storage_load_rsp(data, storage_config, after_init)
    storage_config = data.config
    log.info("wifi_app", "加载配置完成:", storage_config.ssid, "enabled:", storage_config.wifi_enabled)
    sys.taskInit(after_init)
end

--[[
处理存储初始化响应
@param table data - 响应数据
@param function on_success - 初始化成功后的回调（可选）
]]
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

--[[
初始化wifi_app（订阅存储事件并发送初始化请求）
@param table storage_config - 存储配置
@param function on_storage_init - 存储初始化回调
]]
function M.init(storage_config, on_storage_init)
    log.info("wifi_app", "开始初始化")
    sys.subscribe("WIFI_STORAGE_INIT_RSP", on_storage_init)
    sys.publish("WIFI_STORAGE_INIT_REQ")
end

--[[
解析断开原因码
@param number data - 断开原因码 (WLAN_STA_DISCONNECT 事件的 data 字段)
@return string - 可读的原因描述，格式: "原因名(code)"
]]
function M.resolve_disconnect_reason(data)
    local reason_name
    -- LuatOS 封装层自定义码 (256+)
    if data == 260 then reason_name = "DHCP超时"
    elseif data == 259 then reason_name = "程序主动断开"
    elseif data == 258 then reason_name = "密码错误"
    elseif data == 257 then reason_name = "找不到对应SSID"
    elseif data == 256 then reason_name = "信号丢失"
    -- WiFi 协议标准断开原因码 (1~255，来自 AP 或底层驱动)
    elseif data == 1  then reason_name = "未指定原因"
    elseif data == 2  then reason_name = "认证过期"
    elseif data == 3  then reason_name = "软件主动断开"
    elseif data == 4  then reason_name = "接入点无响应"
    elseif data == 5  then reason_name = "接入点过载"
    elseif data == 6  then reason_name = "未认证"
    elseif data == 7  then reason_name = "未关联"
    elseif data == 8  then reason_name = "关联离开"
    elseif data == 13 then reason_name = "四次握手MIC校验失败"
    elseif data == 14 then reason_name = "四次握手超时"
    elseif data == 15 then reason_name = "组密钥更新超时"
    elseif data == 200 then reason_name = "Beacon丢失(AP离线)"
    elseif data == 201 then reason_name = "找不到AP"
    elseif data == 202 then reason_name = "802.11认证被拒"
    elseif data == 203 then reason_name = "关联被拒"
    elseif data == 204 then reason_name = "握手超时"
    elseif data == 205 then reason_name = "连接超时"
    end
    -- 未匹配则显示原始码，不再返回"未知错误"
    if reason_name then
        return reason_name .. "(" .. tostring(data) .. ")"
    else
        return "断开(" .. tostring(data) .. ")"
    end
end

return M
