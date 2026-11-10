--[[
@module  wifi_app
@summary WiFi应用模块（全平台统一，基于exnetif多网融合）
@version 1.7
@date    2026.11.09
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
4. WiFi 开关只有一个真源：网络设置页（net_manager / net_storage）。
   wifi_storage 里的 wifi_enabled 只是镜像，开机由 start_auto_when_ready 对齐，
   这样「网络设置页显示已开启」与「WiFi 连接管理可扫描/可连接」永远一致。

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

-- tick 与毫秒换算（时间一律用 mcu.ticks() + mcu.hz() 表达）
local tick_time = require "tick_time"

-- ==================== 配置常量 ====================
local SCAN_TIMEOUT = 15000

-- 等 airlink 链路就绪的上限（毫秒）
local AIRLINK_READY_TIMEOUT = 15000
-- 等网络初始化完成的上限（毫秒）
local NET_READY_TIMEOUT = 20000
-- 扫描前等 airlink 就绪的上限（毫秒）
local AIRLINK_SCAN_TIMEOUT = 25000

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

--[[
WiFi 开关的唯一真源是网络设置页（net_manager / net_storage）。
saved_config.wifi_enabled 只是 wifi_storage 里的历史镜像，老固件可能残留 false，
会让「网络设置页显示已开启、WiFi 业务层却是关闭」两边打架，所以 net_manager 就绪后
一律以它为准（顺手把镜像同步过去），只有开机极早期（net_manager.init 还没跑完）
才回落到镜像值。
@return boolean WiFi 是否启用
]]
local function wifi_switch_on()
    if net_manager.is_boot_ready() then
        saved_config.wifi_enabled = net_manager.is_wifi_enabled()
    end
    return saved_config.wifi_enabled == true
end

local scan_timer = nil
local connect_timer = nil
local user_disconnect = false
local user_connect = false

local pending_connect = nil

-- ==================== 自动连接 ====================

-- 自动连接候选链：最近一次连接成功的网络优先，其次默认账号
local auto_chain = nil
local auto_index = 1
local auto_waiting = false
local auto_timer = nil
local AUTO_CONNECT_TIMEOUT = 15000
-- 掉线后重挂自动连接前的静默窗口（毫秒），给链路自愈留机会
local AUTO_RECONNECT_DELAY = 3000

-- 候选链跑完一轮后允许从头再试的轮数
-- 只有默认凭证时链里只有一项，不给重试就是「一次连不上就永久放弃」
local AUTO_RETRY_ROUNDS = 2
-- 重试退避：越往后越宽，少打扰 AP，也给慢速建链留时间
local AUTO_RETRY_BACKOFF = { 15000, 30000, 60000 }
-- 候选跑尽后不放弃，转慢速常驻重试（AP 可能比设备晚开机）
local AUTO_IDLE_RETRY = 300000
local retry_round = 0

--[[
当前轮次的候选连接超时：首轮用 AUTO_CONNECT_TIMEOUT，其后按退避表递增
]]
local function auto_retry_delay()
    return AUTO_RETRY_BACKOFF[retry_round + 1] or AUTO_RETRY_BACKOFF[#AUTO_RETRY_BACKOFF]
end

-- 候选链长度上限：已保存网络最多取 3 条 + 默认账号 1 条，保证一轮跑完的时间可控
local AUTO_CHAIN_MAX = 4

--[[
构建自动连接候选链
已保存网络按「连成功过 → 没验证过 → 连失败过」排序，末尾固定补默认账号
@return table or nil 候选数组，元素为 { ssid, password, bssid, source }；WiFi 开关关闭时返回 nil
]]
local function build_auto_chain()
    if not net_manager.is_wifi_enabled() then
        log.info("wifi_app", "WiFi 网络开关关闭，跳过自动连接")
        return nil
    end
    local chain = net_manager.list_wifi_candidates(AUTO_CHAIN_MAX)
    if #chain < 1 then return nil end
    return chain
end

--[[
超时取证：dump 一次 airlink 从机固件版本与收发统计
用来区分「connect 命令没发出去」与「发出去了对端没回状态」
]]
local function dump_airlink_stat()
    if airlink == nil then return end
    if type(airlink.sver) == "function" then
        local ok, v = pcall(airlink.sver)
        log.info("wifi_app", "airlink 从机固件版本", ok and tostring(v) or "取不到")
    end
    if type(airlink.statistics) == "function" then
        pcall(airlink.statistics)
    end
end

--[[
停止自动连接，清理候选链、超时定时器与待连记录
]]
local function stop_auto_connect()
    auto_chain = nil
    auto_waiting = false
    pending_connect = nil
    if auto_timer then
        sys.timerStop(auto_timer)
        auto_timer = nil
    end
    if connect_timer then
        sys.timerStop(connect_timer)
        connect_timer = nil
    end
end

-- 连接超时回调
local function on_connect_timeout()
    connect_timer = nil
    if not pending_connect then return end
    log.error("wifi_app", "连接超时:", pending_connect.ssid)
    sys.publish("WIFI_DISCONNECTED", "连接超时", -6)
    if pending_connect.ssid then
        sys.publish("WIFI_STORAGE_MARK_FAILED_REQ", {ssid = pending_connect.ssid})
    end
    pending_connect = nil
    user_connect = false
end

--[[
推进自动连接：发起候选链当前项，超时后切换下一项
]]
local function auto_connect_tick()
    if not auto_chain then return end
    if auto_waiting then
        local item = auto_chain[auto_index]
        log.warn("wifi_app", "自动连接超时:", item and item.ssid)
        dump_airlink_stat()
        if item and item.ssid then
            sys.publish("WIFI_STORAGE_MARK_FAILED_REQ", { ssid = item.ssid })
        end
        auto_index = auto_index + 1
        auto_waiting = false
    end
    local item = auto_chain[auto_index]
    if not item then
        retry_round = retry_round + 1
        if retry_round > AUTO_RETRY_ROUNDS then
            -- 候选跑尽：不放弃，转慢速常驻重试，等 AP 自己回来
            log.warn("wifi_app", "自动连接候选已用尽，转慢速常驻重试:", AUTO_IDLE_RETRY, "ms")
            retry_round = 0
            auto_index = 1
            auto_waiting = false
            if auto_timer then sys.timerStop(auto_timer) end
            auto_timer = sys.timerStart(auto_connect_tick, AUTO_IDLE_RETRY)
            return
        end
        auto_index = 1
        item = auto_chain[1]
        log.info("wifi_app", "自动连接候选跑完一轮，从头重试第", retry_round, "轮")
    end
    log.info("wifi_app", "自动连接:", item.ssid, "来源:", item.source)
    user_connect = false
    pending_connect = { ssid = item.ssid, password = item.password, bssid = item.bssid }
    net_manager.apply_wifi(item.ssid, item.password, item.bssid)
    auto_waiting = true
    if auto_timer then sys.timerStop(auto_timer) end
    auto_timer = sys.timerStart(auto_connect_tick, auto_retry_delay())
end

--[[
发起自动连接：按候选链逐个尝试
]]
local function start_auto_connect()
    stop_auto_connect()
    auto_chain = build_auto_chain()
    auto_index = 1
    auto_waiting = false
    retry_round = 0
    auto_connect_tick()
end

--[[
挂自动连接回落看门狗：候选已由开机流程下发，这里只负责超时后换下一项
链里只有一项时也照样挂，超时后按重试轮数从头再来
@param number delay 可选，超时后换候选的等待时间（毫秒），缺省 AUTO_CONNECT_TIMEOUT
@return boolean 是否挂上了看门狗
]]
local function start_auto_watchdog(delay)
    stop_auto_connect()
    auto_chain = build_auto_chain()
    if not auto_chain or #auto_chain < 1 then
        auto_chain = nil
        return false
    end
    auto_index = 1
    auto_waiting = true
    retry_round = 0
    -- 记下本次在试的凭证：on_ip_ready / on_sta_event 成功时要靠它回写 saved_list 与 UI 的 SSID
    local first = auto_chain[1]
    pending_connect = { ssid = first.ssid, password = first.password, bssid = first.bssid }
    if auto_timer then sys.timerStop(auto_timer) end
    auto_timer = sys.timerStart(auto_connect_tick, delay or AUTO_CONNECT_TIMEOUT)
    return true
end

--[[
掉线后重挂自动连接：已有自动连接流程在跑时不打断
用户主动断开 / 正在手动连接时也不介入
@param string reason 触发原因，仅用于日志
]]
local function restart_auto_connect(reason)
    if auto_timer then return end
    if not wifi_switch_on() then return end
    if user_disconnect or user_connect then return end
    log.warn("wifi_app", "连接丢失，重新进入自动连接:", reason)
    start_auto_watchdog(AUTO_RECONNECT_DELAY)
end

--[[
等 airlink 硬件就绪后发起自动连接
]]
local function run_auto_connect()
    if net_manager.get_wifi_hw_config() then
        local deadline = tick_time.deadline(AIRLINK_READY_TIMEOUT)
        while not airlink.ready() do
            if tick_time.expired(deadline) then
                log.error("wifi_app", "等待airlink.ready()超时")
                return
            end
            sys.wait(500)
        end
    end
    start_auto_connect()
end

--[[
等网络初始化完成后再启动自动连接，避免抢在 net_manager.init 之前下发凭证
]]
local function start_auto_when_ready()
    local deadline = tick_time.deadline(NET_READY_TIMEOUT)
    while not net_manager.is_boot_ready() do
        if tick_time.expired(deadline) then
            log.error("wifi_app", "等待网络初始化超时")
            return
        end
        sys.wait(100)
    end
    -- 网络设置页的开关是 WiFi 的唯一真源（net_manager.init 已完成，可以取值）：
    -- 关机前残留的 wifi_enabled=false 镜像不能把 WiFi 业务层钉死在关闭状态，
    -- 否则网络设置页显示已开启、WiFi 连接管理却提示“WiFi 未开启”，且扫描/自动连接全停摆。
    saved_config.wifi_enabled = net_manager.is_wifi_enabled()
    log.info("wifi_app", "WiFi 开关以网络设置页为准，enabled:", saved_config.wifi_enabled)
    if not saved_config.wifi_enabled then
        log.info("wifi_app", "WiFi 网络开关关闭，跳过自动连接")
        stop_auto_connect()
        return
    end
    local ssid, _, bssid = net_manager.pick_wifi_credential()
    if net_manager.is_same_as_boot_credential(ssid, bssid) then
        if start_auto_watchdog() then
            log.info("wifi_app", "开机已下发WiFi凭证，已挂回落看门狗:", ssid)
        else
            log.warn("wifi_app", "开机已下发WiFi凭证，但无可用候选，不挂看门狗:", ssid)
        end
        return
    end
    run_auto_connect()
end

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
-- 开机时 net_manager.init() 用已保存WiFi（无则用默认账号）初始化 airlink 硬件，
-- 该 placeholder 的 CONNECTED/DISCONNECTED 事件不发布给 UI（WiFi 开关关闭时抑制），
-- 但内部 wifi_state 仍更新以保持与实际硬件状态一致。
local function on_sta_event(evt, data)
    if evt == "CONNECTED" then
        local ssid = tostring(data or "")
        wifi_state.connected = true
        wifi_state.current_ssid = ssid
        wifi_state.connectivity_verified = false
        -- 仅当 WiFi 开关已开启时才发布状态更新给 UI；
        -- 开关关闭时只更新内部跟踪，不通知 UI 层。
        local on_air = wifi_switch_on()
        if on_air then update_status(wifi_state) end
        if not on_air then return end
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
        stop_auto_connect()
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
        local on_air = wifi_switch_on()
        if on_air then update_status(wifi_state) end
        if not on_air then return end
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
        local user_dropped = user_disconnect
        if user_disconnect then user_disconnect = false end
        sys.publish("WIFI_DISCONNECTED", "断开", data)
        sys.publish("STATUS_WIFI_SIGNAL_UPDATED", 0)
        -- 异常掉线才重连，用户主动断开不重连
        if not user_dropped then restart_auto_connect("WLAN_STA_INC DISCONNECTED") end
    end
end

-- IP_READY：更新 WiFi 的 IP 和 RSSI 信息（DNS 由 net_init 处理，网卡切换由 exnetif 处理）
-- wifi_enabled=false 时只更新内部状态不发 UI 事件，避免开机 placeholder 触发图标变化
-- 注意：airlink 6205 桥接模式下 WLAN_STA_INC CONNECTED 不触发（L2 状态由 6205 内部维护），
--       因此以 L3 IP_READY 作为联网成功信号，在此补齐 connected/WIFI_CONNECTED/连通性验证。
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

    -- airlink 平台：以 IP_READY 补齐"已连接"状态（防止与原生平台重复处理）
    if not wifi_state.connected and net_manager.get_wifi_hw_config() then
        wifi_state.connected = true
        local ssid = pending_connect and pending_connect.ssid or ""
        if ssid == "" then
            -- 自动连接链之外的路径没有 pending_connect，回落到开机已下发的凭证
            local boot = net_manager.get_boot_wifi_credential()
            ssid = boot and boot.ssid or ""
        end
        if ssid ~= "" then wifi_state.current_ssid = ssid end
        wifi_state.connectivity_verified = false
        log.info("wifi_app", "airlink 桥接已联网, ssid:", ssid, "ip:", ip)
        -- 用户主动连接：保存到已存储列表（与 on_sta_event CONNECTED 分支一致）
        if user_connect then
            user_connect = false
            local save_name = pending_connect and pending_connect.ssid or ssid
            local save_pwd = pending_connect and pending_connect.password or ""
            local save_bssid = pending_connect and pending_connect.bssid or ""
            if save_name and save_name ~= "" then
                sys.publish("WIFI_STORAGE_SAVE_REQ", {ssid = save_name, password = save_pwd, bssid = save_bssid})
            end
            pending_connect = nil
        end
        sys.publish("WIFI_STORAGE_MARK_CONNECTED_REQ", {ssid = ssid, bssid = wifi_state.bssid})
        sys.publish("WIFI_CONNECTED")
        -- 启动联网连通性验证（NTP 同步确认），需在独立协程中执行（含 sys.waitUntil）
        sys.taskInit(function()
            common.start_connectivity_verification(wifi_state)
        end)
    end

    stop_auto_connect()

    if wifi_switch_on() then update_status(wifi_state) end
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
    wifi_state.connected = false
    wifi_state.ip = "--"
    wifi_state.rssi = "--"
    wifi_state.current_ssid = ""
    wifi_state.connectivity_verified = false
    if wifi_switch_on() then update_status(wifi_state) end
    restart_auto_connect("IP_LOSE")
end

-- ==================== 请求处理 ====================

-- WIFI_STORAGE_LOAD_RSP
local function on_storage_loaded(data)
    saved_config = data.config
    log.info("wifi_app", "配置加载完成:", saved_config.ssid, "镜像enabled:", saved_config.wifi_enabled)

    -- 这里不能按 saved_config.wifi_enabled 早退：它只是 wifi_storage 的历史镜像，
    -- 真源是网络设置页开关，要等 net_manager.init() 完成后才能取值（见 start_auto_when_ready）。
    -- WiFi 启用：开机连接由 net_manager.init() 按自动连接策略下发，
    -- 这里等网络初始化完成后再判断是补发凭证还是只挂回落看门狗。
    -- 抢在 init 之前 apply_wifi 会占用 set_priority_order 每次开机唯一一次机会，
    -- 以太网/4G 将永远进不了优先级表。
    log.info("wifi_app", "启动时进入自动连接流程")
    sys.taskInit(start_auto_when_ready)
end

-- WIFI_ENABLE_REQ
local function on_enable_req(data)
    local enabled = data.enabled
    log.info("wifi_app", "WiFi开关:", enabled)

    if saved_config then saved_config.wifi_enabled = enabled end
    sys.publish("WIFI_STORAGE_SET_ENABLED_REQ", { enabled = enabled })

    if not enabled then
        log.info("wifi_app", "关闭WiFi")
        stop_auto_connect()
        net_manager.on_wifi_disabled()
        wifi_state.connected = false
        wifi_state.ready = false
        wifi_state.current_ssid = ""
        wifi_state.connectivity_verified = false
        update_status(wifi_state)
        sys.publish("WIFI_DISCONNECTED", "用户关闭WiFi", -1)
        sys.publish("STATUS_WIFI_SIGNAL_UPDATED", 0)
    else
        -- 启动入口只留 on_storage_enabled_rsp 一处：这里再起一遍会与它抢，白等一轮超时还误标 FAILED
        log.info("wifi_app", "开启WiFi，等存储回执后启动自动连接")
    end
end

-- WIFI_SCAN_REQ
-- Airlink WiFi（Air1601/1602 外挂 6205）：wlan.scan() 通过 airlink 0x205 发给 6205。
-- 开机时 net_manager.init() 已完成 airlink 硬件初始化（有已保存WiFi则直连，否则用默认账号），
-- 扫描前只需给 6205 足够的处理时间即可，和 demo 里 sys.wait(5000) 后 scan 一致。
-- 原生 WiFi（Air8101/Air8000）：wlan.scan() 直接操作片上 WiFi，无需等待。
local function on_scan_req()
    log.info("wifi_app", "扫描请求")
    if scan_timer then return end

    local is_airlink = net_manager.get_wifi_hw_config() ~= nil

    sys.taskInit(function()
        if is_airlink then
            -- 轮询等待 airlink.ready() 确保 6205 真实就绪，避免 scan 命令发给未启动的模组。
            local deadline = tick_time.deadline(AIRLINK_SCAN_TIMEOUT)
            while not airlink.ready() do
                if tick_time.expired(deadline) then
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
        stop_auto_connect()
        user_connect = true

        if not ssid or ssid == "" then
            user_connect = false
            sys.publish("WIFI_DISCONNECTED", "SSID不能为空", -3)
            return
        end
        if not wifi_switch_on() then
            user_connect = false
            return
        end

        pending_connect = { ssid = ssid, password = password, advanced_config = adv, bssid = bssid }
        -- 用户连接也要有超时，否则 pending_connect / user_connect 会永久挂着
        if connect_timer then sys.timerStop(connect_timer) end
        connect_timer = sys.timerStart(on_connect_timeout, common.get_connect_timeout())

        sys.publish("WIFI_CONNECTING", ssid)
        net_manager.apply_wifi(ssid, password, bssid, adv)
    end)
end

-- WIFI_DISCONNECT_REQ
local function on_disconnect_req()
    log.info("wifi_app", "断开请求")
    stop_auto_connect()
    user_disconnect = true
    net_manager.on_wifi_disabled()
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
    -- 回执带的是网络设置页的真值，避免 WiFi 连接管理页误判「WiFi 未开启」
    wifi_switch_on()
    common.on_get_status_req(wifi_state, saved_config)
end

-- WIFI_GET_CONFIG_REQ
local function on_get_config()
    wifi_switch_on()
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

-- WIFI_STORAGE_SET_ENABLED_RSP：网络设置页开关 WiFi 后同步自动连接状态
-- 运行期刚打开开关时凭证尚未下发，走完整自动连接（含等 airlink 就绪）；
-- start_auto_watchdog 只适用于「凭证已由开机流程下发」的场景
local function on_storage_enabled_rsp(data)
    if data and data.enabled then
        sys.taskInit(run_auto_connect)
    else
        stop_auto_connect()
    end
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
sys.subscribe("WIFI_STORAGE_SET_ENABLED_RSP", on_storage_enabled_rsp)

log.info("wifi_app", "初始化")
sys.publish("WIFI_STORAGE_INIT_REQ")
