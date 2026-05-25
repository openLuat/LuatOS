--[[
@module  wifi_app
@summary WiFi应用模块（全平台统一，基于exnetif多网融合）
@version 1.3
@date    2026.05.22
@author  江访
@usage
统一版 WiFi 业务逻辑层，通过 exnetif 框架支持所有平台：
  Air8000W/Air8000A: WIFI(exnetif) + 4G(LWIP_GP) 双网融合自动切换
  Air8101:           WIFI(exnetif) 单网
  Air1601/Air1602:   airlink_wifi(exnetif) 单网

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

-- ==================== 平台检测 ====================
-- 基于配置文件驱动，不再依赖 _G.model_str
local config = _G.project_config or {}
local chip = config.chip or ""
local is_air1601 = chip:find("Air1601") or chip:find("Air1602")
local is_air8000 = chip:find("Air8000")
local is_air8101 = chip:find("Air8101")

-- ==================== 4G 兜底辅助 ====================
-- 根据配置文件区分原生 4G(LWIP_GP) 和 airlink 4G(airlink_4G)
local function build_4g_fallback()
    if not config.features or not config.features.net_4g then
        return nil
    end
    local net_cfg = config.features.net_4g_config or {}
    if net_cfg.type == "airlink" then
        -- airlink 4G（Air1601/Air8101 + Air780EPM 外挂模组）
        local acfg = {
            airlink_type = net_cfg.airlink_type,
            auto_socket_switch = (net_cfg.auto_socket_switch ~= false),
        }
        if net_cfg.airlink_spi_id then acfg.airlink_spi_id = net_cfg.airlink_spi_id end
        if net_cfg.airlink_cs_pin then acfg.airlink_cs_pin = net_cfg.airlink_cs_pin end
        if net_cfg.airlink_rdy_pin then acfg.airlink_rdy_pin = net_cfg.airlink_rdy_pin end
        if net_cfg.airlink_uart_id then acfg.airlink_uart_id = net_cfg.airlink_uart_id end
        if net_cfg.airlink_uart_baud then acfg.airlink_uart_baud = net_cfg.airlink_uart_baud end
        if net_cfg.airlink_adapter then acfg.airlink_adapter = net_cfg.airlink_adapter end
        return { airlink_4G = acfg }
    else
        -- 原生 4G（Air8000/Air780E 系列）
        return { LWIP_GP = true }
    end
end

-- ==================== 配置常量 ====================
local SCAN_TIMEOUT = 15000
local UPDATE_INTERVAL = 5000
local CONNECTIVITY_TIMEOUT = 30000

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
local update_timer = nil
local last_connect = nil
local disconnect_reason = nil
local user_disconnect = false
local user_connect = false

-- Air1601 硬件就绪标记（扫描前需初始化 airlink）
local hw_ready = false
local hw_busy = false

-- ==================== exnetif 平台适配 ====================

--[[
构建 WiFi 配置
@param string ssid
@param string password
@param table cfg - 保存的配置（可选）
@return table - exnetif set_priority_order 的参数
]]
local function build_network_priority(ssid, password, cfg)
    cfg = cfg or {}
    local priority = {}

    if ssid and ssid ~= "" and password and password ~= "" then
        if is_air1601 then
            -- Air1601/Air1602 WiFi 走 SPI 接口（SPI1, CS=8, RDY=14）
            table.insert(priority, {
                airlink_wifi = {
                    airlink_type = airlink.MODE_SPI_MASTER,
                    airlink_spi_id = 1,
                    airlink_cs_pin = 8,
                    airlink_rdy_pin = 14,
                    ssid = ssid,
                    password = password,
                    auto_socket_switch = (cfg.auto_socket_switch ~= false)
                }
            })
        else
            local wifi_cfg = { ssid = ssid, password = password }
            if cfg.need_ping ~= nil then wifi_cfg.need_ping = cfg.need_ping end
            if cfg.local_network_mode ~= nil then wifi_cfg.local_network_mode = cfg.local_network_mode end
            if cfg.ping_ip and cfg.ping_ip ~= "" then wifi_cfg.ping_ip = cfg.ping_ip end
            if cfg.ping_time then wifi_cfg.ping_time = tonumber(cfg.ping_time) or 10000 end
            if cfg.auto_socket_switch ~= nil then wifi_cfg.auto_socket_switch = cfg.auto_socket_switch end
            table.insert(priority, { WIFI = wifi_cfg })
        end
    end

    -- 4G 兜底
    local fb_4g = build_4g_fallback()
    if fb_4g then
        table.insert(priority, fb_4g)
    end

    return priority
end

--[[
Air1601 airlink 硬件初始化（仅用于扫描，不发起连接）
@return boolean
]]
local function air1601_scan_init()
    -- GPIO55 Airlink_PWR 上电时序已移至 platform_loader POWER_ON 阶段
    airlink.config(airlink.CONF_SPI_ID, 1)
    airlink.config(airlink.CONF_SPI_CS, 8)
    airlink.config(airlink.CONF_SPI_RDY, 14)
    airlink.config(airlink.CONF_SPI_SPEED, 20 * 1000000)
    airlink.init()
    netdrv.setup(socket.LWIP_STA, netdrv.WHALE)
    airlink.start(airlink.MODE_SPI_MASTER)
    sys.wait(1000)
    local to = 0
    while not airlink.ready() do
        sys.wait(100)
        to = to + 100
        if to >= 30000 then
            log.error("wifi_app", "airlink 初始化超时")
            hw_busy = false
            return false
        end
    end
    wlan.init()
    wlan.setMode(wlan.STATIONAP)
    wlan.disconnect()
    sys.wait(500)
    return true
end

--[[
确保硬件就绪可用于扫描
@return boolean
]]
local function ensure_scan_ready()
    if hw_ready then return true end
    if is_air1601 then
        if not hw_busy then
            hw_busy = true
            local ok = air1601_scan_init()
            hw_ready = ok
            hw_busy = false
            return ok
        end
        return false
    else
        wlan.init()
        hw_ready = true
        return true
    end
end

-- ==================== 状态更新 ====================

local function update_status(status)
    if not status then return end
    for k, v in pairs(status) do
        wifi_state[k] = v
    end
    common.update_status(wifi_state, saved_config)
end

local function refresh_net_info()
    local function update_signal()
        local info = wlan.getInfo()
        if info and info.rssi then
            local rssi_val = info.rssi
            local level = 0
            if rssi_val > -60 then level = 4
            elseif rssi_val > -70 then level = 3
            elseif rssi_val > -80 then level = 2
            else level = 1 end
            sys.publish("STATUS_WIFI_SIGNAL_UPDATED", level)
        end
    end
    common.refresh_network_info(wifi_state, update_signal)
end

-- ==================== 事件处理 ====================

-- WLAN_STA_INC
local function on_sta_event(evt, data)
    log.info("wifi_app", "WiFi STA事件:", evt, data)

    if evt == "CONNECTED" then
        wifi_state.connected = true
        wifi_state.ready = false
        wifi_state.current_ssid = data
        wifi_state.connectivity_verified = false
        sys.publish("WIFI_CONNECTED", data)
        sys.publish("STATUS_WIFI_SIGNAL_UPDATED", 3)
        last_connect = "CONNECTED"
        user_connect = false
        if update_timer then sys.timerStop(update_timer) end
        update_timer = sys.timerLoopStart(refresh_net_info, UPDATE_INTERVAL)

    elseif evt == "DISCONNECTED" then
        if user_connect then
            log.info("wifi_app", "用户发起的连接失败，重置状态")
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
        wifi_state.connectivity_verified = false
        if update_timer then sys.timerStop(update_timer); update_timer = nil end
        local reason_name = common.resolve_disconnect_reason(data)
        sys.publish("WIFI_DISCONNECTED", reason_name, data)
        sys.publish("STATUS_WIFI_SIGNAL_UPDATED", 0)
        last_connect = "DISCONNECTED"
        user_connect = false
        if user_disconnect then
            user_disconnect = false
            sys.publish("WIFI_SCAN_REQ")
        end
    end
end

-- IP_READY
local function on_ip_ready(ip, adapter)
    common.handle_ip_ready(ip, adapter, wifi_state, refresh_net_info)
    sys.taskInit(function()
        common.start_connectivity_verification(wifi_state, CONNECTIVITY_TIMEOUT)
    end)
end

-- IP_LOSE
local function on_ip_lose(adapter)
    common.handle_ip_lose(adapter, wifi_state)
    wifi_state.connectivity_verified = false
end

-- WLAN_SCAN_DONE
local function on_scan_done()
    local scan_ref = { [1] = scan_timer }
    common.handle_scan_done(wifi_state, scan_ref)
    scan_timer = scan_ref[1]
end

-- 扫描超时
local function on_scan_timeout()
    scan_timer = nil
    common.handle_scan_timeout({})
end

-- ==================== 自动连接 ====================

local function auto_scan_verify()
    return common.auto_scan_and_verify(saved_config, SCAN_TIMEOUT + 5000)
end

local function run_auto_connect()
    if not saved_config.wifi_enabled then return end
    if wifi_state.connected then
        sys.publish("WIFI_SCAN_REQ")
        return
    end
    log.info("wifi_app", "开机自动连接")
    local vrf = auto_scan_verify()
    if vrf.verified then
        log.info("wifi_app", "自动连接:", vrf.ssid, "信号:", vrf.signal)
        sys.publish("WIFI_CONNECT_REQ", {
            ssid = vrf.ssid,
            password = vrf.password,
            advanced_config = vrf.config and {
                need_ping = vrf.config.need_ping,
                local_network_mode = vrf.config.local_network_mode,
                ping_ip = vrf.config.ping_ip,
                ping_time = vrf.config.ping_time,
                auto_socket_switch = vrf.config.auto_socket_switch,
            }
        })
    else
        log.info("wifi_app", "附近没有已保存网络")
    end
end

-- ==================== 请求处理 ====================

-- WIFI_STORAGE_LOAD_RSP
local function on_storage_loaded(data)
    saved_config = data.config
    log.info("wifi_app", "配置加载完成:", saved_config.ssid, "enabled:", saved_config.wifi_enabled)

    -- 如果 WiFi 关闭，仅启用 4G
    if not saved_config.wifi_enabled then
        local fb_4g = build_4g_fallback()
        if fb_4g then
            exnetif.set_priority_order({ fb_4g })
        end
        return
    end

    -- 有保存的 SSID → 自动扫描+连接
    if saved_config.ssid and saved_config.ssid ~= "" and saved_config.password and saved_config.password ~= "" then
        sys.taskInit(run_auto_connect)
    else
        -- 无保存 SSID 但 WiFi 开启 → 先启用 4G（如有）
        local fb_4g = build_4g_fallback()
        if fb_4g then
            exnetif.set_priority_order({ fb_4g })
        end
    end
    sys.taskInit(function() hw_ready = false end)
end

-- WIFI_STORAGE_SET_ENABLED_RSP
local function on_set_enabled(data)
    common.on_storage_set_enabled_rsp(data, saved_config)
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

        local fb_4g = build_4g_fallback()
        if fb_4g then
            exnetif.set_priority_order({ fb_4g })
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
        wifi_state.connectivity_verified = false
        update_status(wifi_state)
    else
        log.info("wifi_app", "开启WiFi")
        if saved_config.ssid and saved_config.ssid ~= "" and saved_config.password then
            sys.taskInit(run_auto_connect)
        else
            local fb_4g = build_4g_fallback()
            if fb_4g then
                exnetif.set_priority_order({ fb_4g })
            end
        end
    end
end

-- WIFI_SCAN_REQ
local function on_scan_req()
    log.info("wifi_app", "扫描请求")
    if scan_timer then return end

    sys.taskInit(function()
        ensure_scan_ready()
        if not is_air1601 then wlan.init() end
        wlan.scan()
        scan_timer = sys.timerStart(on_scan_timeout, SCAN_TIMEOUT)
        sys.publish("WIFI_SCAN_STARTED")
    end)
end

-- WIFI_CONNECT_REQ（exnetif.set_priority_order 含 sys.wait，必须在 task 中）
local function on_connect_req(data)
    sys.taskInit(function()
        local ssid = data.ssid
        local password = data.password
        local adv = data.advanced_config

        log.info("wifi_app", "连接请求:", ssid)
        user_connect = true

        if not ssid or ssid == "" then
            sys.publish("WIFI_DISCONNECTED", "SSID不能为空", -3)
            return
        end
        if not password or password == "" then
            sys.publish("WIFI_DISCONNECTED", "密码不能为空", -4)
            return
        end
        if saved_config and not saved_config.wifi_enabled then return end

        sys.publish("WIFI_STORAGE_SAVE_REQ", { ssid = ssid, password = password, advanced_config = adv })
        sys.publish("WIFI_CONNECTING", ssid)
        disconnect_reason = "config"
        exnetif.close(nil, socket.LWIP_STA)

        local cfg = saved_config or {}
        if adv then
            if adv.need_ping ~= nil then cfg.need_ping = adv.need_ping end
            if adv.local_network_mode ~= nil then cfg.local_network_mode = adv.local_network_mode end
            if adv.ping_ip then cfg.ping_ip = adv.ping_ip end
            if adv.ping_time then cfg.ping_time = adv.ping_time end
            if adv.auto_socket_switch ~= nil then cfg.auto_socket_switch = adv.auto_socket_switch end
        end

        local priority = build_network_priority(ssid, password, cfg)
        local ok = exnetif.set_priority_order(priority)
        if ok then
            log.info("wifi_app", "exnetif 配置成功")
        else
            log.error("wifi_app", "exnetif 配置失败")
            sys.publish("WIFI_DISCONNECTED", "连接参数配置失败", -5)
        end
    end)
end

-- WIFI_DISCONNECT_REQ
local function on_disconnect_req()
    log.info("wifi_app", "断开请求")
    user_disconnect = true
    exnetif.close(nil, socket.LWIP_STA)
    local fb_4g = build_4g_fallback()
    if fb_4g then
        exnetif.set_priority_order({ fb_4g })
    end
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

-- ==================== 初始化 ====================

sys.subscribe("WLAN_STA_INC", on_sta_event)
sys.subscribe("WLAN_SCAN_DONE", on_scan_done)
sys.subscribe("IP_READY", on_ip_ready)
sys.subscribe("IP_LOSE", on_ip_lose)
sys.subscribe("WIFI_STORAGE_LOAD_RSP", on_storage_loaded)
sys.subscribe("WIFI_STORAGE_SET_ENABLED_RSP", on_set_enabled)
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
