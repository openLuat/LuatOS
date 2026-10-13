--[[
@module  netdrv_wifi
@summary "WiFi网卡"驱动与网络管理模块（Air8301 双网卡：WiFi 优先于 4G）
@version 1.1
@date    2026.08.24
@author  嵌入式软件设计开发代理
@history
1.1  2026.09.04  修复"部分设备无法保存 WiFi 热点"：DISCONNECTED 事件不再清空待保存热点
                  （pending），IP_READY 保存/显示以 wlan 上报的真实连接（connected_ssid）为准
@usage
本模块为 WiFi 网络管理核心模块，核心业务逻辑为：
1、WiFi 初始化（wlan.init + wlan.setMode STATION）；
2、热点扫描（wlan.scan + WLAN_SCAN_DONE + wlan.scanResult）；
3、热点连接/断开（exnetif 优先级切换 + wlan 控制）；
4、保存"连接成功的最近三个 WiFi 热点信息"（fskv 持久化，最多 3 个，新连接在前）；
5、开机自动连接已保存热点（按保存列表顺序逐个尝试，每个超时 15s）；
6、WiFi 与 4G 优先级管理（exnetif.set_priority_order：WiFi > 4G，WiFi 不可用时自动降级 4G）；
7、统一发布网络状态 NET_STATUS（WiFi/4G 连接状态）供 UI 标题栏图标显示；
8、WiFi 已连接时每 10 秒查询一次 wlan.getInfo() 刷新信号强度（RSSI），随 NET_STATUS 发布
   （供标题栏 WiFi 信号格显示 + AirCloud 上报字段 782）。

对外接口（模块表）：
- netdrv_wifi.scan()                 -- 发起热点扫描（异步，完成后发布 WIFI_SCAN_RESULT）
- netdrv_wifi.connect(ssid, password) -- 连接指定热点
- netdrv_wifi.disconnect()           -- 断开 WiFi（保留保存列表）
- netdrv_wifi.forget(ssid)           -- 忘记热点（从保存列表删除）
- netdrv_wifi.get_status()           -- 获取网络状态
- netdrv_wifi.get_saved_list()       -- 获取已保存热点列表
- netdrv_wifi.get_wifi_enabled()     -- 获取 WiFi 开关状态（fskv 持久化，默认开启）
- netdrv_wifi.set_wifi_enabled(state)-- 设置 WiFi 开关状态并持久化到 fskv
- netdrv_wifi.enable_wifi()          -- 打开 WiFi 功能（持久化 + 扫描 + 自动连接已保存热点）
- netdrv_wifi.disable_wifi()         -- 关闭 WiFi 功能（持久化 + 断开 WiFi 连接）

订阅消息：
- "WIFI_SCAN_REQ"        -- 发起扫描请求（wifi_win 发布）
- "WIFI_CONNECT_REQ"     -- 连接热点请求 {ssid, password}
- "WIFI_DISCONNECT_REQ"  -- 断开 WiFi 请求
- "WIFI_FORGET_REQ"      -- 忘记热点请求 {ssid}
- "WIFI_GET_SAVED_REQ"   -- 获取保存列表请求
- "WIFI_GET_STATUS_REQ"  -- 查询网络状态请求（立即回复 NET_STATUS，wifi_win 打开窗口时主动查询）
- "WIFI_ENABLE_REQ"      -- 打开 WiFi 功能请求（持久化 + 扫描 + 自动连接）
- "WIFI_DISABLE_REQ"     -- 关闭 WiFi 功能请求（持久化 + 断开 WiFi）
- "WIFI_GET_STATE_REQ"   -- 查询 WiFi 开关状态请求（回复 WIFI_STATE_RSP）
- "NET_4G_STATUS"        -- 4G 状态 {connected}（netdrv_4g 发布）

发布消息：
- "WIFI_SCAN_RESULT"     -- 扫描结果 {list: [{ssid, rssi, bssid}]}
- "WIFI_SAVED_RSP"       -- 保存列表响应 {list: [{ssid, password}]}
- "WIFI_CONNECTED"       -- WiFi 连接成功 {ssid}
- "WIFI_DISCONNECTED"    -- WiFi 断开 {reason}
- "WIFI_STATE_RSP"       -- WiFi 开关状态响应 {enabled}
- "NET_STATUS"           -- 网络总状态 {wifi_connected, wifi_ssid, wifi_rssi, g4_connected, current_adapter}
]]

-- LuatOS 核心库（sys/log/json/wlan/socket/fskv）均内置在固件中，直接使用，无需 require
-- exnetif 为 LuatOS 扩展库，需要 require 加载
local exnetif = require "exnetif"

-- 常量定义
local SAVED_KEY = "wifi_saved_list"     -- fskv 保存键：已保存热点列表
local WIFI_ENABLED_KEY = "wifi_enabled" -- fskv 保存键：WiFi 开关状态（"1"开启/"0"关闭）
local MAX_SAVED = 3                     -- 最多保存 3 个热点（连接成功的最近三个）
local CONNECT_TIMEOUT = 15000           -- 自动连接每个热点超时（毫秒），用户确认 15s
local SCAN_TIMEOUT = 15000              -- 扫描超时（毫秒）

-- WiFi STA 网卡适配器（Air8000 系列上 WiFi 使用 socket.LWIP_STA）
local ADAPTER_WIFI = socket.LWIP_STA

-- 网络状态缓存
local net_state = {
    wifi_connected = false,   -- WiFi 是否已连接（STA 获取 IP）
    wifi_ssid = nil,          -- 当前连接的 SSID
    wifi_rssi = nil,          -- 当前信号强度
    g4_connected = false,     -- 4G 是否已连接
    current_adapter = nil,    -- 当前默认网卡
}

-- 已保存热点列表缓存 [{ssid=..., password=...}, ...]，新连接在前
local saved_list = {}

-- WiFi 功能开关（fskv 持久化，默认开启；关闭时不自动连接、可断开 WiFi）
local wifi_enabled = true

-- 自动连接任务是否正在运行（防止开关反复触发多个并发任务）
local auto_connecting = false

-- 前向声明：自动连接任务（enable_wifi 中引用，定义在文件后部）
local auto_connect_task

-- 当前尝试连接的热点（IP_READY 后用于保存）
local pending_ssid = nil
local pending_password = nil

-- wlan 事件上报的真实连接信息（WLAN_STA_INC CONNECTED 的 data 参数为 AP 的 ssid）
-- 修复记录（2026.09.04 第九十一次修改）：原实现中 DISCONNECTED 事件会清空
-- pending_ssid/pending_password，导致连接过程中夹带断开事件（原因 0，扫描切换/去关联
-- 重连）时，IP_READY 保存判断 pending_ssid 为假 → 热点保存静默失败（部分设备复现）。
-- 现改为：DISCONNECTED 不再清空 pending（清空责任收口到主动断开/超时切换/保存后消费），
-- 且 IP_READY 保存与 SSID 显示均以 wlan 上报的真实连接（connected_ssid）为准。
local connected_ssid = nil
-- 真实连接 SSID 对应的密码（CONNECTED 时确定：与连接目标一致 → 用目标密码；
-- 不一致（漫游/自动重连等异常场景）→ 从保存列表中按 SSID 匹配历史密码）
local connected_password = nil

-- 扫描请求标志（是否有 UI 等待扫描结果）
local scan_req_flag = false

--[[
从 fskv 加载已保存的热点列表

@local
@function load_saved_list
@return table 保存列表 [{ssid=..., password=...}, ...]，最多 MAX_SAVED 个
]]
local function load_saved_list()
    local data = fskv.get(SAVED_KEY)
    local list = {}
    if data and data ~= "" then
        local ok, tbl = pcall(json.decode, data)
        if ok and type(tbl) == "table" then
            list = tbl
        end
    end
    -- 校验格式并截断到 MAX_SAVED 个
    local valid = {}
    for _, item in ipairs(list) do
        if type(item) == "table" and type(item.ssid) == "string" and item.ssid ~= "" then
            valid[#valid + 1] = {ssid = item.ssid, password = item.password or ""}
            if #valid >= MAX_SAVED then
                break
            end
        end
    end
    return valid
end

--[[
保存热点列表到 fskv

@local
@function save_saved_list
@return nil
]]
local function save_saved_list()
    local ok, str = pcall(json.encode, saved_list)
    if ok and str then
        fskv.set(SAVED_KEY, str)
    end
end

--[[
从 fskv 加载 WiFi 开关状态（默认开启）

@local
@function load_wifi_enabled
@return boolean 开关状态
]]
local function load_wifi_enabled()
    local v = fskv.get(WIFI_ENABLED_KEY)
    if v == nil or v == "" then
        return true  -- 默认开启
    end
    return v == "1"
end

--[[
保存 WiFi 开关状态到 fskv

@local
@function save_wifi_enabled
@param state boolean 开关状态
@return nil
]]
local function save_wifi_enabled(state)
    fskv.set(WIFI_ENABLED_KEY, state and "1" or "0")
end

--[[
将连接成功的热点加入保存列表（去重、置顶、截断 MAX_SAVED 个）

@local
@function add_saved_hotspot
@param ssid string 热点名称
@param password string 密码
@return nil
]]
local function add_saved_hotspot(ssid, password)
    -- 去重：若已存在则先移除
    for i = #saved_list, 1, -1 do
        if saved_list[i].ssid == ssid then
            table.remove(saved_list, i)
        end
    end
    -- 置顶插入
    table.insert(saved_list, 1, {ssid = ssid, password = password or ""})
    -- 截断到 MAX_SAVED 个
    while #saved_list > MAX_SAVED do
        table.remove(saved_list)
    end
    save_saved_list()
    log.info("netdrv_wifi", "保存热点:", ssid, "数量:", #saved_list)
end

--[[
发布网络总状态 NET_STATUS（供 home_win 标题栏、wifi_win 界面显示）

@local
@function publish_net_status
@return nil
]]
local function publish_net_status()
    sys.publish("NET_STATUS",
        net_state.wifi_connected,
        net_state.wifi_ssid,
        net_state.wifi_rssi,
        net_state.g4_connected,
        net_state.current_adapter)
end

--[[
刷新 WiFi 信号强度（RSSI）：读取 wlan.getInfo().rssi 更新缓存并发布 NET_STATUS

用途：
1、标题栏 WiFi 信号格显示（home_win 订阅 NET_STATUS）；
2、AirCloud 上报字段 782（信号强度，protocol_app 订阅 NET_STATUS 缓存本次值）。

说明：wlan.getInfo() 仅在 STA 已连接后有效，故未连接时直接返回；
     读取失败时保留上一次有效值，不清空（避免信号格/上报值异常跳变）。

@local
@function update_wifi_rssi
@return nil
]]
local function update_wifi_rssi()
    if not net_state.wifi_connected then
        return
    end
    local ok, info = pcall(wlan.getInfo)
    if ok and type(info) == "table" and info.rssi then
        -- 仅当信号强度发生变化时才更新并发布：
        -- 避免每 10 秒无谓地触发 NET_STATUS 订阅方（home_win 会刷新界面）重绘
        if net_state.wifi_rssi ~= info.rssi then
            net_state.wifi_rssi = info.rssi
            publish_net_status()
        end
    else
        log.warn("netdrv_wifi", "读取 WiFi 信号强度失败:", tostring(info))
    end
end

--[[
应用 WiFi 优先级配置（WiFi > 4G）

用户已确认：本函数封装 exnetif.set_priority_order，放置在 netdrv_wifi.lua 中。
连接新热点（SSID 变化）时 exnetif 增量更新，自动断开旧连接并用新凭证连接。

注意：断开 WiFi 请使用 exnetif.close(false, socket.LWIP_STA)（见 disconnect），
不要用 apply_wifi(nil) 移除网卡——exnetif 增量更新不会重置 available[LWIP_STA] 状态，
会导致断开后重连同一热点时不发起连接。

@local
@function apply_wifi
@param ssid string 热点名称
@param password string 密码
@return nil
]]
local function apply_wifi(ssid, password)
    if ssid and password ~= nil then
        -- WiFi 优先于 4G
        exnetif.set_priority_order({
            {WIFI = {ssid = ssid, password = password, need_ping = false, auto_socket_switch = true}},
            {LWIP_GP = true}
        })
        log.info("netdrv_wifi", "已配置优先级: WiFi > 4G, ssid=", ssid)
    else
        -- 兼容调用（不推荐）：仅保留 4G 网卡
        exnetif.set_priority_order({{LWIP_GP = true}})
        log.warn("netdrv_wifi", "apply_wifi(nil) 已调用（建议改用 exnetif.close 断开 WiFi）")
    end
end

--[[
发起热点扫描（异步，完成后发布 WIFI_SCAN_RESULT）

@public
@function scan
@return nil
]]
local function scan()
    log.info("netdrv_wifi", "发起 WiFi 扫描")
    scan_req_flag = true
    wlan.scan()
    -- 扫描超时保护：15s 无结果则发布空列表
    sys.timerStart(function()
        if scan_req_flag then
            scan_req_flag = false
            log.warn("netdrv_wifi", "扫描超时")
            sys.publish("WIFI_SCAN_RESULT", {})
        end
    end, SCAN_TIMEOUT)
end

--[[
UI 连接热点任务（在协程中执行：exnetif.set_priority_order 的"WiFi凭证变化"分支内部含 sys.wait，
必须在协程上下文调用，否则报 attempt to yield from outside a coroutine）

@local
@function connect_task
@param ssid string 热点名称
@param password string 密码
@return nil
]]
local function connect_task(ssid, password)
    -- 等待任务调度稳定后执行（避免与 UI 消息回调竞争）
    sys.wait(50)
    -- 应用 WiFi 优先级（exnetif 自动断开旧连接并连接新热点；SSID 变化分支含 sys.wait，协程中安全）
    apply_wifi(ssid, password)
    -- 强制发起 wlan 连接（兜底修复：exnetif 增量更新仅在 available[LWIP_STA]==DISCONNECTED 或
    -- SSID 变化时才重新连接；断开后重连同一热点时两者都不满足，需显式 wlan.connect 确保真正发起连接）
    wlan.connect(ssid, password, 1)
    -- 记录当前尝试连接的热点（IP_READY 后保存到列表）
    pending_ssid = ssid
    pending_password = password
end

--[[
连接指定热点（UI 发起，放入协程任务执行）

@public
@function connect
@param ssid string 热点名称
@param password string 密码
@return nil
]]
local function connect(ssid, password)
    if not ssid or ssid == "" then
        return
    end
    log.info("netdrv_wifi", "UI 连接热点:", ssid)
    -- 放入协程任务执行（exnetif.set_priority_order 内部有 sys.wait，非协程上下文调用会崩溃）
    sys.taskInit(connect_task, ssid, password)
end

--[[
断开 WiFi 连接（保留保存列表）

@public
@function disconnect
@return nil
]]
local function disconnect()
    log.info("netdrv_wifi", "断开 WiFi 连接")
    -- 正确断开：exnetif.close(false, LWIP_STA) 会将 WiFi 网卡状态置为 DISCONNECTED 并断开 wlan 连接。
    -- 不能只用 apply_wifi(nil)+wlan.disconnect()：exnetif 不订阅 WLAN_STA_INC，无法感知 wlan 已断开，
    -- 导致 available[LWIP_STA] 仍为 CONNECTED；此时重新连接同一热点时，增量更新认为
    -- "网卡已初始化且 SSID 未变"而不发起连接（修复问题：断开后重连无反应）。
    exnetif.close(false, socket.LWIP_STA)
    -- 更新状态并通知 UI
    net_state.wifi_connected = false
    net_state.wifi_ssid = nil
    net_state.wifi_rssi = nil
    connected_ssid = nil
    connected_password = nil
    pending_ssid = nil
    pending_password = nil
    publish_net_status()
    sys.publish("WIFI_DISCONNECTED", "user_disconnect")
end

--[[
忘记热点（从保存列表删除）

@public
@function forget
@param ssid string 热点名称
@return nil
]]
local function forget(ssid)
    for i = #saved_list, 1, -1 do
        if saved_list[i].ssid == ssid then
            table.remove(saved_list, i)
            save_saved_list()
            log.info("netdrv_wifi", "忘记热点:", ssid)
            break
        end
    end
    -- 忘记的是当前连接的热点：断开 WiFi 连接（手机标准行为：忘记即断开）
    if ssid and net_state.wifi_connected and ssid == net_state.wifi_ssid then
        disconnect()
    end
end

--[[
获取 WiFi 开关状态

@public
@function get_wifi_enabled
@return boolean 开关状态（默认开启）
]]
local function get_wifi_enabled()
    return wifi_enabled
end

--[[
设置 WiFi 开关状态并持久化到 fskv

@public
@function set_wifi_enabled
@param state boolean 开关状态
@return nil
]]
local function set_wifi_enabled(state)
    wifi_enabled = state or false
    save_wifi_enabled(wifi_enabled)
    log.info("netdrv_wifi", "WiFi 开关状态:", wifi_enabled and "开启" or "关闭")
end

--[[
打开 WiFi 功能：持久化开启 + 发起热点扫描 + 自动连接已保存热点

@public
@function enable_wifi
@return nil
]]
local function enable_wifi()
    set_wifi_enabled(true)
    scan()
    -- 存在已保存热点且无自动连接任务在运行：启动自动连接（失败保留 WiFi 网卡）
    if #saved_list > 0 and not auto_connecting then
        sys.taskInit(auto_connect_task, true)
    end
end

--[[
关闭 WiFi 功能：持久化关闭 + 断开 WiFi 连接（保留保存列表）

@public
@function disable_wifi
@return nil
]]
local function disable_wifi()
    set_wifi_enabled(false)
    if net_state.wifi_connected or wlan.ready() then
        disconnect()
    end
end

--[[
获取网络状态

@public
@function get_status
@return table 状态表 {wifi_connected, wifi_ssid, wifi_rssi, g4_connected, current_adapter}
]]
local function get_status()
    return {
        wifi_connected = net_state.wifi_connected,
        wifi_ssid = net_state.wifi_ssid,
        wifi_rssi = net_state.wifi_rssi,
        g4_connected = net_state.g4_connected,
        current_adapter = net_state.current_adapter,
    }
end

--[[
获取已保存热点列表

@public
@function get_saved_list
@return table 保存列表 [{ssid=..., password=...}, ...]
]]
local function get_saved_list()
    return saved_list
end

-- WiFi 扫描完成事件：获取扫描结果并发布给 UI
sys.subscribe("WLAN_SCAN_DONE", function()
    log.info("netdrv_wifi", "扫描完成")
    if not scan_req_flag then
        return
    end
    scan_req_flag = false
    local results = wlan.scanResult()
    local list = {}
    if results then
        for _, ap in ipairs(results) do
            table.insert(list, {
                ssid = ap.ssid,
                rssi = ap.rssi,
                bssid = ap.bssid,
            })
        end
    end
    sys.publish("WIFI_SCAN_RESULT", list)
end)

-- WiFi STA 状态事件：CONNECTED（data=ssid）/ DISCONNECTED（data=原因）
sys.subscribe("WLAN_STA_INC", function(evt, data)
    if evt == "CONNECTED" then
        log.info("netdrv_wifi", "STA 已连接 AP:", data)
        -- 缓存 wlan 事件上报的真实 SSID（data 即 AP 的 ssid，Air8101 demo 注释确认）
        connected_ssid = data
        -- 记录该真实连接 SSID 对应的密码（IP_READY 保存时使用）：
        -- 与当前连接目标一致 → 用目标密码；不一致（漫游/自动重连等异常场景）→
        -- 从保存列表中按 SSID 匹配历史密码，避免把残留的旧尝试信息保存成错误热点
        if data == pending_ssid then
            connected_password = pending_password or ""
        else
            connected_password = nil
            for _, item in ipairs(saved_list) do
                if item.ssid == data then
                    connected_password = item.password or ""
                    break
                end
            end
        end
    elseif evt == "DISCONNECTED" then
        log.info("netdrv_wifi", "STA 已断开, 原因:", data)
        -- 更新状态并通知 UI（主动断开的重复通知无副作用）
        net_state.wifi_connected = false
        net_state.wifi_ssid = nil
        net_state.wifi_rssi = nil
        connected_ssid = nil
        connected_password = nil
        -- 注意：此处不再清空 pending_ssid/pending_password！
        -- 连接过程中驱动常上报多次"STA 已断开, 原因: 0"（扫描切换/去关联重连），
        -- 原实现把 pending 清空后，IP_READY 保存判断 pending_ssid 为假 → 热点保存静默失败
        -- （部分设备/路由器下连接过程夹带断开事件，表现为"有的设备能保存、有的不能"）。
        -- pending 的清空责任已收口到以下三处，保证连接成功后一定能保存：
        --   ① 主动断开 disconnect()（用户明确取消连接目标）
        --   ② 自动连接超时切换下一个热点（auto_connect_task 失败分支）
        --   ③ IP_READY 保存成功后消费（pending_ssid/pending_password = nil）
        publish_net_status()
        sys.publish("WIFI_DISCONNECTED", data)
    end
end)

-- IP_READY：WiFi（LWIP_STA）或 4G（LWIP_GP）获取 IP
sys.subscribe("IP_READY", function(ip, adapter)
    if adapter == ADAPTER_WIFI then
        -- WiFi 连接成功并获取 IP
        log.info("netdrv_wifi", "WiFi IP_READY:", ip)
        net_state.wifi_connected = true
        -- SSID 显示/保存以 wlan 上报的真实连接为准（connected_ssid 优先），
        -- pending_ssid 仅在驱动未上报 CONNECTED 事件时兜底，避免显示/保存与真实连接不一致
        net_state.wifi_ssid = connected_ssid or pending_ssid or "unknown"
        net_state.current_adapter = ADAPTER_WIFI
        -- 连接成功：保存热点到列表
        -- 修复记录（2026.09.04 第九十一次修改）：原实现仅在 pending_ssid 非空时保存，
        -- 且 DISCONNECTED 事件曾清空 pending，导致连接过程夹带断开事件（原因 0）时，
        -- 即使最终连接成功拿到 IP 也不保存热点（部分设备复现"无法保存 WiFi"）。
        -- 现改为：保存条件 = connected_ssid（真实连接）or pending_ssid（尝试目标）非空，
        -- 密码取 connected_password（CONNECTED 时按 SSID 匹配）or pending_password。
        local save_ssid = connected_ssid or pending_ssid
        local save_password = connected_password or pending_password
        if save_ssid and save_ssid ~= "unknown" then
            add_saved_hotspot(save_ssid, save_password or "")
        end
        -- 消费一次性连接凭证信息（防止重复保存/误存残留）
        pending_ssid = nil
        pending_password = nil
        connected_password = nil
        publish_net_status()
        -- 立即刷新一次 WiFi 信号强度（不等 10 秒轮询周期，保证连接后尽快有值）
        update_wifi_rssi()
        sys.publish("WIFI_CONNECTED", net_state.wifi_ssid)
    elseif adapter == socket.LWIP_GP then
        -- 4G 的 IP_READY（4G 状态由 netdrv_4g 发布，这里仅更新默认网卡）
        net_state.current_adapter = socket.LWIP_GP
    end
end)

-- IP_LOSE：WiFi 或 4G 失去 IP
sys.subscribe("IP_LOSE", function(adapter)
    if adapter == ADAPTER_WIFI then
        log.warn("netdrv_wifi", "WiFi IP_LOSE")
        net_state.wifi_connected = false
        net_state.wifi_ssid = nil
        net_state.wifi_rssi = nil
        connected_ssid = nil
        connected_password = nil
        publish_net_status()
    end
end)

-- 4G 状态汇总（netdrv_4g 发布 NET_4G_STATUS）
sys.subscribe("NET_4G_STATUS", function(connected)
    net_state.g4_connected = connected or false
    if not net_state.wifi_connected then
        -- WiFi 未连接时，默认网卡为 4G
        net_state.current_adapter = connected and socket.LWIP_GP or nil
    end
    publish_net_status()
end)

-- UI 请求消息订阅
sys.subscribe("WIFI_SCAN_REQ", function()
    scan()
end)

sys.subscribe("WIFI_CONNECT_REQ", function(ssid, password)
    connect(ssid, password)
end)

sys.subscribe("WIFI_DISCONNECT_REQ", function()
    disconnect()
end)

sys.subscribe("WIFI_FORGET_REQ", function(ssid)
    forget(ssid)
end)

sys.subscribe("WIFI_GET_SAVED_REQ", function()
    sys.publish("WIFI_SAVED_RSP", saved_list)
end)

sys.subscribe("WIFI_GET_STATUS_REQ", function()
    -- 立即用当前缓存状态回复 NET_STATUS（wifi_win 打开窗口时主动查询）
    publish_net_status()
end)

sys.subscribe("WIFI_ENABLE_REQ", function()
    enable_wifi()
end)

sys.subscribe("WIFI_DISABLE_REQ", function()
    disable_wifi()
end)

sys.subscribe("WIFI_GET_STATE_REQ", function()
    sys.publish("WIFI_STATE_RSP", wifi_enabled)
end)

--[[
自动连接任务：按保存列表顺序逐个尝试（每个超时 15s）

@local
@function auto_connect_task
@param keep_wifi boolean 全部失败后是否保留 WiFi 网卡
    - true ：开关打开场景，失败后保留 WiFi 网卡（用户可继续手动连接/扫描）
    - false/省略：开机场景，失败后降级 4G（apply_wifi(nil)）
@return nil
]]
auto_connect_task = function(keep_wifi)
    auto_connecting = true
    -- 等待 WiFi 硬件初始化完成
    sys.wait(500)
    if #saved_list == 0 then
        log.info("netdrv_wifi", "无已保存热点，使用 4G 网络")
        auto_connecting = false
        return
    end
    for _, item in ipairs(saved_list) do
        -- 自动连接过程中若用户关闭 WiFi 开关，立即中止
        if not wifi_enabled then
            log.info("netdrv_wifi", "WiFi 开关已关闭，中止自动连接")
            auto_connecting = false
            return
        end
        log.info("netdrv_wifi", "自动连接尝试:", item.ssid)
        apply_wifi(item.ssid, item.password)
        pending_ssid = item.ssid
        pending_password = item.password
        -- 等待 WiFi 连接成功（wlan.ready()），每个热点最多 15s
        local start_ticks = mcu.ticks()
        while not wlan.ready() do
            if not wifi_enabled then
                break
            end
            if mcu.ticks() - start_ticks >= CONNECT_TIMEOUT then
                break
            end
            -- 等待 IP_READY 消息（最多 1s），收到后循环检查 wlan.ready()
            sys.waitUntil("IP_READY", 1000)
        end
        if wlan.ready() then
            log.info("netdrv_wifi", "自动连接成功:", item.ssid)
            auto_connecting = false
            return
        end
        -- 超时或失败，尝试下一个
        log.warn("netdrv_wifi", "自动连接失败/超时:", item.ssid)
        pending_ssid = nil
        pending_password = nil
    end
    if keep_wifi then
        -- 开关打开场景：保留 WiFi 网卡（用户可在列表中手动连接）
        log.warn("netdrv_wifi", "已保存热点全部连接失败，保留 WiFi 网卡等待手动连接")
    else
        -- 开机场景：全部失败降级 4G（用 exnetif.close 确保 WiFi 状态为 DISCONNECTED，
        -- 避免 available[LWIP_STA] 残留为 CONNECTING/CONNECTED，导致后续手动连接同一热点不发起连接）
        log.warn("netdrv_wifi", "已保存热点全部连接失败，使用 4G 网络")
        exnetif.close(false, socket.LWIP_STA)
    end
    auto_connecting = false
end

-- WiFi 信号强度轮询：已连接时每 10 秒刷新一次
-- 用途：① 标题栏 WiFi 信号格显示；② AirCloud 上报字段 782（信号强度）
-- 说明：wlan.getInfo() 仅在 STA 已连接后有效，未连接时函数直接返回
sys.timerLoopStart(update_wifi_rssi, 10000)

-- 模块初始化
local function init()
    -- 加载已保存热点列表与 WiFi 开关状态
    saved_list = load_saved_list()
    wifi_enabled = load_wifi_enabled()
    log.info("netdrv_wifi", "已保存热点数量:", #saved_list, "WiFi 开关:", wifi_enabled and "开启" or "关闭")
    -- WiFi 初始化（STA 模式）
    wlan.init()
    wlan.setMode(wlan.STATION)
    -- 开关开启且存在已保存热点：启动自动连接任务
    if wifi_enabled and #saved_list > 0 then
        sys.taskInit(auto_connect_task, false)
    else
        -- 开关关闭或无保存热点：仅配置 4G 网卡优先级
        exnetif.set_priority_order({{LWIP_GP = true}})
    end
end

init()

-- 对外接口
return {
    scan = scan,
    connect = connect,
    disconnect = disconnect,
    forget = forget,
    get_status = get_status,
    get_saved_list = get_saved_list,
    get_wifi_enabled = get_wifi_enabled,
    set_wifi_enabled = set_wifi_enabled,
    enable_wifi = enable_wifi,
    disable_wifi = disable_wifi,
}
