--[[
@module  app_net
@summary 用户模式网络管理：以太网 / WiFi(STA) / 4G(AirLink UART) 三张网卡统一调度
@version 1.0
@date    2026.10.16
@usage
    local app_net = require "app_net"
    app_net.init()                     -- 必须在 task 中调用（exnetif 要求）
    app_net.get_all()                  -- 三张网卡的 {name, adapter, ip, ready}
    app_net.get_active()               -- 当前默认出口
    app_net.scan_wifi()                -- 扫描热点，返回 { {ssid=.., rssi=..}, ... }
    app_net.set_wifi(ssid, pwd)        -- 保存凭据并重连（立即生效，无需重启）
    app_net.sntp()                     -- 网络就绪后对时

设计说明
1. 三张网卡交给 exnetif 统一按优先级调度，默认优先级：以太网 → WiFi → 4G。
   理由：以太网插网线即通、不耗流量；WiFi 次之；4G 走板载 Air780ER2，
   需要 VBAT_4G 拨码 + SIM 卡，只能当兜底出口，不能当唯一出口。
   现场可在「网络优先级」应用里上移 / 下移，改完立即重排，不用重启。
2. WiFi 凭据不写死在代码里，存 fskv（wifi_ssid / wifi_pwd），首次由配网页面写入，
   之后每次开机自动连。凭据为空时 WiFi 网卡不参与调度。
3. 4G 这张网卡的 adapter 是 socket.LWIP_GP_GW（exnetif UART 模式的默认值），
   不是 socket.LWIP_GP；并且它会常驻占用 UART1，用户模式下不要再碰 UART1。
4. 任何网卡状态变化都发布 "APP_NET_CHANGED"，UI 订阅即可，不用轮询。
5. 优先级可在运行时改（net_config.save → NET_CONFIG_UPDATED）：app_net 收到后
   合并 300ms 内多次改动，再调 exnetif.set_priority_order 增量重排，不用重启。
   顺序没变（签名相同）时直接跳过，避免无谓地重建 4G / 以太网。
]]

local M = {}

local exnetif  = require "exnetif"
local net_config = require "net_config"

-- 三张网卡的固定顺序与显示名（adapter 编号来自 socket 核心库）
M.ORDER = {
    { adapter = socket.LWIP_ETH,   name = "以太网" },
    { adapter = socket.LWIP_STA,   name = "WiFi"   },
    { adapter = socket.LWIP_GP_GW, name = "4G"     },
}

local state = {}

function M.supported(key)
    local hw = (_G.project_config or {}).hw or {}
    if key == "eth"  then return hw.eth ~= nil end
    if key == "wifi" then return true end
    if key == "4g"   then return hw.g4  ~= nil end
    return false
end

local function reset_state()
    for _, item in ipairs(M.ORDER) do
        state[item.adapter] = { name = item.name, ip = nil, ready = false }
    end
end
reset_state()

local function on_ip_ready(ip, adapter)
    local s = state[adapter]
    if not s then return end
    s.ip, s.ready = ip, true
    log.info("app_net", s.name, "IP_READY", tostring(ip))
    sys.publish("APP_NET_CHANGED")
end

local function on_ip_lose(adapter)
    local s = state[adapter]
    if not s then return end
    s.ip, s.ready = nil, false
    log.warn("app_net", s.name, "IP_LOSE")
    sys.publish("APP_NET_CHANGED")
end

sys.subscribe("IP_READY", on_ip_ready)
sys.subscribe("IP_LOSE", on_ip_lose)

-- ===== 查询接口 =====

function M.get(adapter)
    return state[adapter]
end

function M.get_all()
    local list = {}
    for _, item in ipairs(M.ORDER) do
        list[#list + 1] = state[item.adapter]
    end
    return list
end

--- 当前默认出口（内核选定的网卡），返回 adapter 与显示名
function M.get_active()
    local adapter = socket.dft()
    local s = state[adapter]
    return adapter, (s and s.name) or "无"
end

function M.is_online()
    return socket.adapter(socket.dft()) and true or false
end

-- ===== WiFi 凭据（存 fskv，不写死代码）=====

function M.get_wifi_cred()
    return fskv.get("wifi_ssid"), fskv.get("wifi_pwd")
end

function M.clear_wifi_cred()
    fskv.del("wifi_ssid")
    fskv.del("wifi_pwd")
    log.info("app_net", "已清除 WiFi 凭据")
    -- 凭据清空后 WiFi 不再参与调度，重排一次（exnetif 只能在 task 里调）
    sys.taskInit(function()
        sys.wait(50)
        M.apply()
        sys.publish("APP_NET_CHANGED")
    end)
end

function M.set_wifi(ssid, pwd)
    if not ssid or ssid == "" then return false end
    fskv.set("wifi_ssid", ssid)
    if pwd and pwd ~= "" then
        fskv.set("wifi_pwd", pwd)
    else
        fskv.del("wifi_pwd")
    end
    -- exnetif 必须在 task 中调用，配网页的点击回调不是 task，这里单独起一个
    sys.taskInit(function()
        sys.wait(50)
        M.apply()
        sys.publish("APP_NET_CHANGED")
    end)
    log.info("app_net", "已保存 WiFi 凭据并重连:", ssid)
    return true
end

-- ===== 网卡配置 =====

local function build_order()
    local hw = (_G.project_config or {}).hw or {}
    local ssid, pwd = M.get_wifi_cred()
    local list = {}

    for _, key in ipairs(net_config.load()) do
        if key == "eth" and M.supported("eth") then
            list[#list + 1] = {
                ETHERNET = {
                    pwrpin = hw.eth.en,
                    tp     = netdrv.CH390,
                    opts   = { spi = 0, cs = hw.eth.cs, irq = hw.eth.irq },
                }
            }
        elseif key == "wifi" then
            if ssid and ssid ~= "" then
                list[#list + 1] = { WIFI = { ssid = ssid, password = pwd } }
            else
                log.info("app_net", "未保存 WiFi 凭据，本次跳过 WiFi 网卡")
            end
        elseif key == "4g" and M.supported("4g") then
            list[#list + 1] = {
                airlink_4G = {
                    auto_socket_switch = false,
                    airlink_type       = airlink.MODE_UART,
                    airlink_uart_id    = hw.g4.uart_id,   -- UART1（与产测口同路，用户模式独占）
                    airlink_uart_baud  = 2000000,
                }
            }
        end
    end

    return list
end

local function build_signature(list)
    local parts = {}
    for _, item in ipairs(list) do
        for key, cfg in pairs(item) do
            parts[#parts + 1] = key
            if key == "WIFI" then
                parts[#parts + 1] = tostring(cfg.ssid or "")
                parts[#parts + 1] = tostring(cfg.password or "")
            end
        end
    end
    return table.concat(parts, "|")
end

local applied_sig

function M.apply(force)
    local list = build_order()
    if #list == 0 then
        log.warn("app_net", "没有可用的网卡配置")
        return false
    end

    local sig = build_signature(list)
    if not force and sig == applied_sig then
        log.info("app_net", "网卡配置无变化，跳过重排")
        return true
    end

    local ok = exnetif.set_priority_order(list)
    if ok then
        applied_sig = sig
        log.info("app_net", "网卡调度已生效，数量:", #list)
    else
        log.warn("app_net", "网卡调度下发失败，保留上次配置")
    end
    return ok and true or false
end

-- ===== 优先级配置（动态，改完立即生效）=====

local net_inited = false

--- 当前优先级（key 列表，第一项最高）
function M.priority()
    return net_config.load()
end

--- 保存优先级并立即重排（net_config.save 内部会广播，订阅处统一 apply）
function M.set_priority(list)
    return net_config.save(list)
end

--- 恢复默认优先级（以太网 > WiFi > 4G）
function M.reset_priority()
    return net_config.save(net_config.DEFAULT)
end

local APPLY_DEBOUNCE_MS = 300
local apply_timer

local function schedule_apply()
    if apply_timer then sys.timerStop(apply_timer) end
    apply_timer = sys.timerStart(function()
        apply_timer = nil
        sys.taskInit(function()
            M.apply()
            sys.publish("APP_NET_CHANGED")
        end)
    end, APPLY_DEBOUNCE_MS)
end

sys.subscribe("NET_CONFIG_UPDATED", function()
    if not net_inited then return end
    schedule_apply()
end)

function M.init()
    -- 设置网络状态变化通知：切换出口或全部断网时打印，便于产线排查
    exnetif.notify_status(function(net_type, adapter)
        if type(net_type) == "string" then
            log.info("app_net", "当前出口切换到", net_type, adapter)
        else
            log.warn("app_net", "所有网卡均不可用")
        end
        sys.publish("APP_NET_CHANGED")
    end)

    M.apply()

    -- 连上后给「路由器下发 DNS」的网卡补公共 DNS，避免个别路由器 DNS 不稳导致解析失败。
    -- 注意：千万别改 4G（airlink）网卡的 DNS —— 它的 DNS 是模块侧的 192.168.111.2
    -- （4G 模块自带 DNS 代理 + NAPT），改成 223.5.5.5 后查询发不出去（实测 DNS 无响应），
    -- 表现就是 airlbs / 云平台 / FOTA 等所有走域名的业务都"连接失败"。
    sys.subscribe("IP_READY", function(_, adapter)
        if adapter == socket.LWIP_ETH or adapter == socket.LWIP_STA then
            pcall(socket.setDNS, adapter, 1, "223.5.5.5")
            pcall(socket.setDNS, adapter, 2, "114.114.114.114")
        end
    end)

    net_inited = true
end

-- ===== WiFi 扫描 =====

function M.scan_wifi(timeout_ms)
    timeout_ms = timeout_ms or 15000

    wlan.init()
    sys.wait(300)

    wlan.scan()
    if not sys.waitUntil("WLAN_SCAN_DONE", timeout_ms) then
        log.warn("app_net", "WiFi 扫描超时")
        return {}
    end

    local result = wlan.scanResult() or {}
    local list = {}
    for k, v in pairs(result) do
        local ssid, rssi
        if type(k) == "number" and type(v) == "table" then
            ssid, rssi = v.ssid, v.rssi
        else
            ssid = k
            rssi = (type(v) == "table") and v.rssi or nil
        end
        if type(ssid) == "string" and ssid ~= "" then
            list[#list + 1] = { ssid = ssid, rssi = tonumber(rssi) or -127 }
        end
    end
    -- 信号强的排前面，页面上先看到能连的
    table.sort(list, function(a, b) return (a.rssi or -127) > (b.rssi or -127) end)

    log.info("app_net", "扫描到", #list, "个热点")
    return list
end

-- ===== 时间同步 =====

-- 网络就绪后对时；同步成功后系统时间自动变为本地时区时间，无需手动设置
function M.sntp()
    while not socket.adapter(socket.dft()) do
        sys.waitUntil("IP_READY", 1000)
    end

    while true do
        socket.sntp()
        if sys.waitUntil("NTP_UPDATE", 5000) then
            log.info("app_net", "时间同步成功:", os.date("%Y-%m-%d %H:%M:%S"))
            sys.publish("APP_TIME_SYNCED")
            break
        end
        log.warn("app_net", "时间同步失败，10 秒后重试")
        sys.wait(10000)
    end
end

return M
