--[[
@module  wifi_app
@summary WiFi应用模块（全平台统一，基于exnetif多网融合）
@version 1.4
@date    2026.07.01
@author  江访
@usage
统一版 WiFi 业务逻辑层，通过 exnetif 框架支持所有平台：
  Air8000W/Air8000A: WIFI(exnetif) + 4G(LWIP_GP) 双网融合自动切换
  Air8101:           WIFI(exnetif) + 以太网 双网融合自动切换
  Air1601/Air1602:   airlink_wifi(exnetif) + 以太网 双网融合自动切换

== 核心设计原则 ==
1. 网络切换由 exnetif 驱动：wifi_app 只负责构建优先级列表交给 exnetif，
   不自行判断何时切换、切换到哪个网卡。exnetif 内部监控 IP_READY/IP_LOSE，
   按优先级列表自动切换 socket.dft()。
2. exnetif.set_priority_order 包含 WIFI + 兜底网络(以太网/4G) 的完整列表，
   exnetif 会按优先级依次尝试，WiFi 断开后自动落到以太网。
3. 不写死等的循环：所有等待使用 sys.waitUntil 带超时，不使用忙等待。

== 状态机（从初始化到联网的完整链路）==
  自动扫描 → WIFI_SCAN_DONE
    → 连接热点 → exnetif.set_priority_order
      → WLAN_STA_INC CONNECTED  (L2 关联成功)
        → DHCP → IP_READY       (L3 IP 分配成功)
          → NTP sync → NTP_UPDATE (Internet 连通确认)
            → connectivity_verified = true

== 接收的事件（来自UI层）：==
  WIFI_ENABLE_REQ: {enabled}
  WIFI_SCAN_REQ
  WIFI_CONNECT_REQ: {ssid, password, advanced_config}
  WIFI_DISCONNECT_REQ
  WIFI_GET_STATUS_REQ
  WIFI_GET_CONFIG_REQ
  WIFI_GET_SAVED_LIST_REQ

== 发布的事件（给UI层）：==
  WIFI_SCAN_STARTED, WIFI_SCAN_DONE, WIFI_SCAN_TIMEOUT
  WIFI_CONNECTING, WIFI_CONNECTED, WIFI_DISCONNECTED
  WIFI_STATUS_UPDATED: {connected, ready, connectivity_verified, ...}
  WIFI_CONFIG_RSP: {config}
  WIFI_SAVED_LIST_RSP: {list}
  STATUS_WIFI_SIGNAL_UPDATED: level (0-4)

== 与storage层交互的事件：==
  WIFI_STORAGE_INIT_REQ / WIFI_STORAGE_INIT_RSP
  WIFI_STORAGE_LOAD_REQ / WIFI_STORAGE_LOAD_RSP
  WIFI_STORAGE_SAVE_REQ
  WIFI_STORAGE_SET_ENABLED_REQ / WIFI_STORAGE_SET_ENABLED_RSP
]]

require "wifi_storage"
local common = require "wifi_app_common"
local exnetif = require "exnetif"

-- 统一网络管理器：用于构建 WiFi 优先级/兜底网络（替代本地 build_*_fallback 函数）
local net_manager = require "net_manager"

-- ==================== 配置常量 ====================
local SCAN_TIMEOUT = 15000

-- ==================== WiFi 状态 ====================
local wifi_state = {
    connected = false,
    ready = false,
    connectivity_verified = false,
    current_ssid = "",
    rssi = "--",
    ip = "--",
    netmask = "--",
    gateway = "--",
    bssid = "--",
    scan_results = {}
}

local saved_config = {
    wifi_enabled = false,
    ssid = "",
    password = "",
    need_ping = true,
    local_network_mode = false,
    ping_ip = "",
    ping_time = "10000",
    auto_socket_switch = true
}

local scan_timer = nil
local user_disconnect = false
local user_connect = false

local pending_connect = nil

local function update_status(status)
    if not status then return end
    for k, v in pairs(status) do
        wifi_state[k] = v
    end
    common.update_status(wifi_state, saved_config)
end

-- ==================== 事件处理 ====================

-- 扫描超时
local function on_scan_timeout()
    scan_timer = nil
    common.handle_scan_timeout({})
end

-- WLAN_SCAN_DONE
local function on_scan_done()
    local scan_ref = { [1] = scan_timer }
    common.handle_scan_done(wifi_state, scan_ref)
    scan_timer = scan_ref[1]
end

-- STA 状态（L2 关联层）：仅更新 wifi_state 和发布 UI 事件。
-- exnetif 负责网卡切换逻辑，wifi_app 只负责 UI 状态同步。
-- 开机时 net_manager.init() 用已保存WiFi（无则用 "luatos" 占位）初始化 airlink 硬件，
-- 该 placeholder 的 CONNECTED/DISCONNECTED 事件不发布给 UI（wifi_enabled=false 时抑制），
-- 但内部 wifi_state 仍更新以保持与实际硬件状态一致。
local function on_sta_event(evt, data)
    if evt == "CONNECTED" then
        local ssid = tostring(data or "")
        wifi_state.connected = true
        wifi_state.current_ssid = ssid
        wifi_state.connectivity_verified = false
        -- 仅当 WiFi 开关已开启时才发布状态更新给 UI；
        -- wifi_enabled=false 时只更新内部跟踪，不通知 UI 层。
        if saved_config.wifi_enabled then update_status(wifi_state) end
        if not saved_config.wifi_enabled then return end
        -- 发布WiFi信号图标更新（连接中，用等级2表示）
        sys.publish("STATUS_WIFI_SIGNAL_UPDATED", 2)
        if user_connect then
            user_connect = false
            -- 保存到已存储列表
            local save_name = pending_connect and pending_connect.ssid or ssid
            local save_pwd = pending_connect and pending_connect.password or ""
            local save_bssid = pending_connect and pending_connect.bssid or ""
            if save_name and save_name ~= "" then
                sys.publish("WIFI_STORAGE_SAVE_REQ", {ssid = save_name, password = save_pwd, bssid = save_bssid})
            end
            pending_connect = nil
        end
        -- 标记该网络连接成功（无论用户操作还是开机自动连接），避免"未验证"状态
        sys.publish("WIFI_STORAGE_MARK_CONNECTED_REQ", {ssid = ssid, bssid = wifi_state.bssid})
        sys.publish("WIFI_CONNECTED")
    elseif evt == "DISCONNECTED" then
        -- 先保存断开前的连接状态，用于后续判断是否为主动断连还是异常断连
        local was_connected = wifi_state.connected
        local was_ssid = wifi_state.current_ssid
        wifi_state.connected = false
        wifi_state.ready = false
        wifi_state.current_ssid = ""
        wifi_state.rssi = "--"
        wifi_state.ip = "--"
        wifi_state.netmask = "--"
        wifi_state.gateway = "--"
        wifi_state.bssid = "--"
        wifi_state.connectivity_verified = false
        -- 仅当 WiFi 开关已开启时才发布状态更新给 UI
        if saved_config.wifi_enabled then update_status(wifi_state) end
        if not saved_config.wifi_enabled then return end
        -- 连接进行中的断开不通知 UI（exnetif 切换通道时会自动断开再连）
        if pending_connect then return end
        -- 没有用户主动操作且之前未连接真实SSID时的断开不通知 UI：
        -- 1) 开机占位 SSID "luatos" 扫描前被 6205 自动断开
        -- 2) exnetif 切换网卡时的内部断连
        -- 3) 扫描时 6205 自动断开当前连接
        -- user_connect=true: 用户点击了连接
        -- user_disconnect=true: 用户点击了断开
        -- was_connected && was_ssid != "luatos": 之前已连接真实SSID后异常断连（信号丢失等）
        local is_placeholder = (was_ssid == "luatos" or was_ssid == "")
        if not user_connect and not user_disconnect and (not was_connected or is_placeholder) then return end
        -- 发布断开事件后复位主动操作标记
        if user_disconnect then user_disconnect = false end
        sys.publish("WIFI_DISCONNECTED", "断开", data)
        sys.publish("STATUS_WIFI_SIGNAL_UPDATED", 0)
    end
end

-- IP_READY：更新 WiFi 的 IP 和 RSSI 信息（DNS 由 net_init 处理，网卡切换由 exnetif 处理）
-- wifi_enabled=false 时只更新内部状态不发 UI 事件，避免开机 placeholder 触发图标变化
local function on_ip_ready(ip, adapter)
    if adapter ~= socket.LWIP_STA then return end
    wifi_state.ready = true
    wifi_state.ip = ip
    local _, netmask, gateway = socket.localIP(socket.LWIP_STA)
    if netmask then wifi_state.netmask = netmask end
    if gateway then wifi_state.gateway = gateway end
    local info = wlan.getInfo()
    if info then
        if info.rssi then wifi_state.rssi = info.rssi end
        if info.bssid then wifi_state.bssid = info.bssid end
    end
    if saved_config.wifi_enabled then update_status(wifi_state) end
    -- 获取RSSI后更新WiFi信号图标
    if info and info.rssi then
        local level = 0
        local r = info.rssi
        if r > -50 then level = 4 elseif r > -60 then level = 3 elseif r > -70 then level = 2 elseif r > -80 then level = 1 end
        sys.publish("STATUS_WIFI_SIGNAL_UPDATED", level)
    end
end

-- IP_LOSE
local function on_ip_lose(adapter)
    if adapter ~= socket.LWIP_STA then return end
    wifi_state.ready = false
    wifi_state.ip = "--"
    wifi_state.rssi = "--"
    if saved_config.wifi_enabled then update_status(wifi_state) end
end

-- ==================== 请求处理 ====================

-- WIFI_STORAGE_LOAD_RSP
local function on_storage_loaded(data)
    saved_config = data.config
    log.info("wifi_app", "配置加载完成:", saved_config.ssid, "enabled:", saved_config.wifi_enabled)

    if not saved_config.wifi_enabled then
        log.info("wifi_app", "WiFi 已禁用，仅启用兜底网络")
        return
    end

    -- WiFi 启用且有已保存凭证：通过 exnetif.update_wifi 发起连接。
    -- Airlink 平台需等 airlink.ready() 确认硬件就绪，否则 update_wifi
    -- 可能在 airlink 硬件未就绪时执行，走错初始化分支。
    -- 注意：airlink 平台开机时 net_manager.init() 已通过 set_priority_order 将已保存WiFi
    -- 传入 setup_airlink_wifi → wlan.connect()，若凭证相同则跳过 update_wifi，避免
    -- exnetif.update_wifi 内部的 wlan.disconnect() 破坏已建立的连接。
    if saved_config.ssid and saved_config.ssid ~= "" then
        -- Airlink 平台且有相同凭证：跳过 update_wifi，开机已传递
        if net_manager.get_wifi_hw_config()
            and net_manager.is_same_as_boot_credential(saved_config.ssid, saved_config.bssid) then
            log.info("wifi_app", "开机已传递相同WiFi凭证，跳过update_wifi:", saved_config.ssid)
            return
        end
        log.info("wifi_app", "启动时加载已保存WiFi:", saved_config.ssid)
        sys.taskInit(function()
            if net_manager.get_wifi_hw_config() then
                local deadline = mcu.ticks() + 15000
                while not airlink.ready() do
                    if mcu.ticks() > deadline then
                        log.error("wifi_app", "等待airlink.ready()超时")
                        return
                    end
                    sys.wait(500)
                end
            end
            exnetif.update_wifi({
                ssid = saved_config.ssid,
                password = saved_config.password,
                bssid = saved_config.bssid,
            })
        end)
    end
    -- WiFi 启用但无已保存 SSID：airlink 硬件初始化已在 net_manager.init() 开机完成，
    -- 无需再发 build_wifi_priority()，直接等用户扫描/输入凭证即可
end

-- WIFI_ENABLE_REQ
local function on_enable_req(data)
    local enabled = data.enabled
    log.info("wifi_app", "WiFi开关:", enabled)

    if saved_config then saved_config.wifi_enabled = enabled end
    sys.publish("WIFI_STORAGE_SET_ENABLED_REQ", { enabled = enabled })

    if not enabled then
        log.info("wifi_app", "关闭WiFi")
        exnetif.close(nil, socket.LWIP_STA)
        sys.taskInit(function()
            net_manager.apply(net_manager.build_no_wifi_priority())
        end)
        wifi_state.connected = false
        wifi_state.ready = false
        wifi_state.current_ssid = ""
        wifi_state.connectivity_verified = false
        update_status(wifi_state)
        sys.publish("WIFI_DISCONNECTED", "用户关闭WiFi", -1)
        sys.publish("STATUS_WIFI_SIGNAL_UPDATED", 0)
    else
        log.info("wifi_app", "开启WiFi")
        if saved_config.ssid and saved_config.ssid ~= "" then
            sys.taskInit(function()
                if net_manager.get_wifi_hw_config() then
                    local deadline = mcu.ticks() + 15000
                    while not airlink.ready() do
                        if mcu.ticks() > deadline then
                            log.error("wifi_app", "等待airlink.ready()超时")
                            return
                        end
                        sys.wait(500)
                    end
                end
                exnetif.update_wifi({
                    ssid = saved_config.ssid,
                    password = saved_config.password,
                    bssid = saved_config.bssid,
                })
            end)
        end
        -- 无已保存 SSID：airlink 硬件已在开机时初始化，无需再发 build_wifi_priority()
    end
end

-- WIFI_SCAN_REQ
-- Airlink WiFi（Air1601/1602 外挂 6205）：wlan.scan() 通过 airlink 0x205 发给 6205。
-- 开机时 net_manager.init() 已完成 airlink 硬件初始化（有已保存WiFi则直连，否则 wlan.connect("luatos")），
-- 扫描前只需给 6205 足够的处理时间即可，和 demo 里 sys.wait(5000) 后 scan 一致。
-- 原生 WiFi（Air8101/Air8000）：wlan.scan() 直接操作片上 WiFi，无需等待。
local function on_scan_req()
    log.info("wifi_app", "扫描请求")
    if scan_timer then return end

    local is_airlink = net_manager.get_wifi_hw_config() ~= nil

    sys.taskInit(function()
        if is_airlink then
            -- 轮询等待 airlink.ready() 确保 6205 真实就绪，避免 scan 命令发给未启动的模组。
            local deadline = mcu.ticks() + 25000
            while not airlink.ready() do
                if mcu.ticks() > deadline then
                    log.warn("wifi_app", "airlink.ready()等待超时，直接扫描")
                    break
                end
                sys.wait(1000)
            end
            -- airlink 真实就绪后，再等待缓冲区稳定时间
            if airlink.ready() then
                sys.wait(2000)
            end
        end
        wlan.scan()
        scan_timer = sys.timerStart(on_scan_timeout, SCAN_TIMEOUT)
        sys.publish("WIFI_SCAN_STARTED")
    end)
end

-- WIFI_CONNECT_REQ
local function on_connect_req(data)
    sys.taskInit(function()
        local ssid = data.ssid
        local password = data.password
        local adv = data.advanced_config
        local bssid = data.bssid

        log.info("wifi_app", "连接请求:", ssid, "bssid:", bssid)
        user_connect = true

        if not ssid or ssid == "" then
            sys.publish("WIFI_DISCONNECTED", "SSID不能为空", -3)
            return
        end
        if saved_config and not saved_config.wifi_enabled then return end

        pending_connect = { ssid = ssid, password = password, advanced_config = adv, bssid = bssid }

        sys.publish("WIFI_CONNECTING", ssid)
        exnetif.update_wifi({ ssid = ssid, password = password, bssid = bssid, advanced_config = adv })
    end)
end

-- WIFI_DISCONNECT_REQ
local function on_disconnect_req()
    log.info("wifi_app", "断开请求")
    user_disconnect = true
    exnetif.close(nil, socket.LWIP_STA)
    sys.taskInit(function()
        net_manager.apply(net_manager.build_no_wifi_priority())
    end)
    wifi_state.connected = false
    wifi_state.ready = false
    wifi_state.current_ssid = ""
    wifi_state.rssi = "--"
    wifi_state.ip = "--"
    wifi_state.netmask = "--"
    wifi_state.gateway = "--"
    wifi_state.bssid = "--"
    wifi_state.connectivity_verified = false
    common.update_status(wifi_state, saved_config)
end

-- WIFI_GET_STATUS_REQ
local function on_get_status()
    common.on_get_status_req(wifi_state, saved_config)
end

-- WIFI_GET_CONFIG_REQ
local function on_get_config()
    common.on_get_config_req(saved_config)
end

-- WIFI_GET_SAVED_LIST_REQ
local function on_get_saved_list()
    common.on_get_saved_list_req(saved_config)
end

-- WIFI_STORAGE_GET_SAVED_LIST_RSP
local function on_saved_list_rsp(data)
    common.on_storage_get_saved_list_rsp(data)
end

-- WIFI_STORAGE_INIT_RSP
local function on_storage_ready(data)
    common.on_storage_init_rsp(data)
end

-- 连接超时回调
local function on_connect_timeout()
    if not pending_connect then return end
    log.error("wifi_app", "连接超时:", pending_connect.ssid)
    sys.publish("WIFI_DISCONNECTED", "连接超时", -6)
    if pending_connect.ssid then
        sys.publish("WIFI_STORAGE_MARK_FAILED_REQ", {ssid = pending_connect.ssid})
    end
    pending_connect = nil
    user_connect = false
end

-- ==================== 初始化 ====================

sys.subscribe("WLAN_SCAN_DONE", on_scan_done)
sys.subscribe("WLAN_STA_INC", on_sta_event)
sys.subscribe("IP_READY", on_ip_ready)
sys.subscribe("IP_LOSE", on_ip_lose)
sys.subscribe("WIFI_STORAGE_LOAD_RSP", on_storage_loaded)
sys.subscribe("WIFI_ENABLE_REQ", on_enable_req)
sys.subscribe("WIFI_SCAN_REQ", on_scan_req)
sys.subscribe("WIFI_CONNECT_REQ", on_connect_req)
sys.subscribe("WIFI_DISCONNECT_REQ", on_disconnect_req)
sys.subscribe("WIFI_GET_STATUS_REQ", on_get_status)
sys.subscribe("WIFI_GET_CONFIG_REQ", on_get_config)
sys.subscribe("WIFI_GET_SAVED_LIST_REQ", on_get_saved_list)
sys.subscribe("WIFI_STORAGE_GET_SAVED_LIST_RSP", on_saved_list_rsp)
sys.subscribe("WIFI_STORAGE_INIT_RSP", on_storage_ready)

log.info("wifi_app", "初始化")
sys.publish("WIFI_STORAGE_INIT_REQ")
