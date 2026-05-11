-- Naming convention: local fns ≤5 chars, local vars ≤4 chars
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

function M.build_status_payload(ws, sc)
    local ls = {
        connected = ws.connected,
        ready = ws.ready,
        current_ssid = ws.current_ssid,
        rssi = ws.rssi,
        ip = ws.ip,
        netmask = ws.netmask,
        gateway = ws.gateway,
        bssid = ws.bssid,
    }
    if sc then
        ls.wifi_enabled = sc.wifi_enabled
    end
    return ls
end

function M.update_status(ws, sc)
    local ls = M.build_status_payload(ws, sc)
    log.info("wfap", "WiFi状态更新:", json.encode(ls))
    sys.publish("WIFI_STATUS_UPDATED", ls)
end

function M.refresh_network_info(ws, uc)
    if not socket.adapter(socket.LWIP_STA) then
        log.warn("wfap", "正在获取IP地址")
        return
    end
    local wi = wlan.getInfo()
    if wi then
        if wi.rssi then ws.rssi = wi.rssi end
        if wi.bssid then ws.bssid = wi.bssid end
        if wi.gw then ws.gateway = wi.gw end
    end
    local ip, nm, gw = socket.localIP(socket.LWIP_STA)
    if ip then
        ws.ip = ip
        ws.netmask = nm
        ws.gateway = gw
        ws.ready = true
    else
        ws.ready = false
    end
    if uc then uc(ws) end
    M.update_status(ws)
end

function M.handle_ip_ready(ip, ad, ws, rf)
    if ad == socket.LWIP_STA then
        log.info("wfap", "WiFi IP就绪:", ip)
        rf()
    end
end

function M.handle_ip_lose(ad, ws)
    if ad == socket.LWIP_STA then
        log.info("wfap", "WiFi IP断开")
        ws.ready = false
        ws.ip = "--"
        ws.netmask = "--"
        ws.gateway = "--"
        M.update_status(ws)
    end
end

function M.handle_scan_done(ws, sr, od)
    if sr[1] then
        sys.timerStop(sr[1])
        sr[1] = nil
    end
    local rs = wlan.scanResult() or {}
    local fr = {}
    for _, wf in ipairs(rs) do
        if wf.ssid and wf.ssid ~= "" then
            table.insert(fr, wf)
        end
    end
    ws.scan_results = fr
    sys.publish("WIFI_SCAN_DONE", ws.scan_results)
    log.info("wfap", "扫描完成，找到", #ws.scan_results, "个热点")
    if od then od() end
end

function M.handle_scan_timeout(sr, ot)
    sr[1] = nil
    sys.publish("WIFI_SCAN_TIMEOUT")
    log.warn("wfap", "扫描超时")
    if ot then ot() end
end

function M.auto_scan_and_verify(sc, sto)
    sto = sto or 20000
    log.info("wfap", "开始自动扫描并查找最佳已保存网络")
    sys.publish("WIFI_STORAGE_GET_SAVED_LIST_REQ")
    local gl, sd = sys.waitUntil("WIFI_STORAGE_GET_SAVED_LIST_RSP", 3000)
    local sl = (gl and sd and sd.list) or {}
    if sc.ssid and sc.ssid ~= "" and sc.password and sc.password ~= "" then
        local ex = false
        for _, s in ipairs(sl) do
            if s.ssid == sc.ssid then ex = true; break end
        end
        if not ex then
            table.insert(sl, {ssid = sc.ssid, password = sc.password,
                need_ping = sc.need_ping, local_network_mode = sc.local_network_mode,
                ping_ip = sc.ping_ip, ping_time = sc.ping_time,
                auto_socket_switch = sc.auto_socket_switch})
        end
    end
    if #sl == 0 then
        log.info("wfap", "没有已保存的网络")
        return { verified = false }
    end
    sys.publish("WIFI_SCAN_REQ")
    local sdone, rs = sys.waitUntil("WIFI_SCAN_DONE", sto)
    if not sdone then
        log.error("wfap", "自动扫描超时")
        return { verified = false }
    end
    local bs, bp, br = nil, nil, -200
    local bc = nil
    for _, wf in ipairs(rs or {}) do
        for _, sv in ipairs(sl) do
            if wf.ssid == sv.ssid and (wf.rssi or -200) > br then
                bs = sv.ssid
                bp = sv.password
                br = wf.rssi or -200
                bc = sv
            end
        end
    end
    if bs then
        log.info("wfap", "找到最佳已保存网络:", bs, "信号:", br)
        return { verified = true, ssid = bs, password = bp, signal = br, config = bc }
    end
    log.info("wfap", "未在附近找到任何已保存网络")
    return { verified = false }
end

function M.on_storage_set_enabled_rsp(dt, sc)
    log.info("wfap", "设置开关响应:", dt.success, dt.enabled)
    if sc then
        sc.wifi_enabled = dt.enabled
    end
end

function M.on_get_status_req(ws, sc)
    log.info("wfap", "收到获取状态请求")
    local st = {}
    for k, v in pairs(ws) do
        st[k] = v
    end
    if sc then
        st.wifi_enabled = sc.wifi_enabled
    end
    sys.publish("WIFI_STATUS_UPDATED", st)
end

function M.on_get_config_req(sc)
    log.info("wfap", "收到获取配置请求")
    sys.publish("WIFI_CONFIG_RSP", {config = sc})
end

function M.on_get_saved_list_req(sc, ol)
    log.info("wfap", "收到获取已保存网络列表请求")
    if _G.model_str:find("PC") then
        local ls = {
            {ssid = "TP-LINK_ABC", password = "12345678", need_ping = true, local_network_mode = false, ping_ip = "8.8.8.8", ping_time = "10000", auto_socket_switch = true},
            {ssid = "ChinaNet-5G", password = "abcdefgh", need_ping = true, local_network_mode = true, ping_ip = "192.168.1.1", ping_time = "5000", auto_socket_switch = false},
            {ssid = "CMCC-8888", password = "88888888", need_ping = false, local_network_mode = false, ping_ip = "", ping_time = "20000", auto_socket_switch = true},
            {ssid = "HUAWEI-123", password = "huawei123", need_ping = true, local_network_mode = true, ping_ip = "114.114.114.114", ping_time = "15000", auto_socket_switch = true},
            {ssid = "NETGEAR_5GHz", password = "netgear5g", need_ping = true, local_network_mode = false, ping_ip = "8.8.4.4", ping_time = "10000", auto_socket_switch = false},
        }
        sys.publish("WIFI_SAVED_LIST_RSP", {list = ls})
    else
        sys.publish("WIFI_STORAGE_GET_SAVED_LIST_REQ")
    end
end

function M.on_storage_get_saved_list_rsp(dt)
    log.info("wfap", "收到已保存网络列表，数量:", #dt.list)
    sys.publish("WIFI_SAVED_LIST_RSP", {list = dt.list})
end

function M.on_storage_load_rsp(dt, sc, af)
    sc = dt.config
    log.info("wfap", "加载配置完成:", sc.ssid, "enabled:", sc.wifi_enabled)
    sys.taskInit(af)
end

function M.on_storage_init_rsp(dt, ons)
    log.info("wfap", "storage初始化响应:", dt.success)
    if not dt.success then
        log.error("wfap", "storage初始化失败")
        return
    end
    sys.publish("WIFI_STORAGE_LOAD_REQ")
    log.info("wfap", "初始化完成")
    if ons then ons() end
end

function M.init(sc, osf)
    log.info("wfap", "开始初始化")
    sys.subscribe("WIFI_STORAGE_INIT_RSP", osf)
    sys.publish("WIFI_STORAGE_INIT_REQ")
end

function M.resolve_disconnect_reason(dt)
    local rn = "未知错误"
    if dt == 260 then rn = "DHCP超时"
    elseif dt == 259 then rn = "程序主动断开"
    elseif dt == 258 then rn = "密码错误"
    elseif dt == 257 then rn = "找不到对应SSID"
    elseif dt == 256 then rn = "信号丢失"
    elseif dt == 3 then rn = "软件主动断开"
    end
    return rn
end

return M
