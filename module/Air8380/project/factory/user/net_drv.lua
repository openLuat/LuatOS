--[[
@module  net_drv
@summary 多网融合：网口(CH390H) / WiFi(STA) / 4G
@version 1.0
@date    2026.10.20

行为：
1. 按 app_config.priority 的意图组织 exnetif 优先级（默认 网口 > WiFi > 4G）；
2. 网口用静态 IP（现场固定地址），WiFi 未配网时不进优先级表，避免连接失败拖垮 4G；
3. 不开 AP 热点、不做内置网页：本板无网页与本地配置界面，配置入口为源码默认值 + AirCloud 下行 set_wifi；
4. 网卡切换/全断由 exnetif 发布 EXLIB_NETDRV_NETWORK_STATUS，这里转发成统一状态。
]]

local board = require "board"
local app_config = require "app_config"
local exnetif = require "exnetif"

local M = {}

-- 对外状态：给 AirCloud / 网络看门狗看
M.state = {
    active = nil,        -- "Ethernet" / "WiFi" / "4G" / nil
    active_adapter = -1,
    eth_ready = false,
    wifi_ready = false,
    gprs_ready = false,
}

-- 组装优先级表；WiFi 未配置时跳过，保证 4G 一定能起来
local function build_priority(c)
    local list = {}
    local allow_wifi = (c.wifi_ssid and #tostring(c.wifi_ssid) > 0)

    for _, name in ipairs(c.priority or { "eth", "wifi", "4g" }) do
        if name == "eth" and board.eth and board.eth.enabled then
            local eth_cfg = {
                pwrpin = board.ldo.eth.pin,           -- P4 U401 网口 LDO 使能
                tp = netdrv.CH390,
                opts = { spi = board.spi.id, cs = board.eth.cs, irq = board.eth.irq },
                need_ping = false,                     -- 工业现场常无外网，按 IP 就绪判定
                -- 切网时不断开已有 socket：否则 excloud 长连接在 4G 上刚建立就被强杀，
                -- 会导致 libnet 内部状态错乱（实测出现过 C 层死机）
                auto_socket_switch = false,
            }
            if c.eth_mode == "dhcp" then
                eth_cfg.need_ping = false
            else
                eth_cfg.static_ip = {
                    ipv4 = c.eth_ip,
                    mark = c.eth_mask,
                    gw = c.eth_gw,
                }
            end
            table.insert(list, { ETHERNET = eth_cfg })
        elseif name == "wifi" and board.wifi and board.wifi.enabled and allow_wifi then
            table.insert(list, {
                WIFI = {
                    ssid = c.wifi_ssid,
                    password = c.wifi_pwd or "",
                    need_ping = false,
                    auto_socket_switch = false,
                }
            })
        elseif name == "4g" then
            table.insert(list, { LWIP_GP = true, auto_socket_switch = false })
        end
    end

    -- 兜底：至少要有一条链路
    if #list == 0 then
        table.insert(list, { LWIP_GP = true })
    end
    return list
end

-- 应用网络配置（首次启动与配置变更都走这里）
local function apply_network()
    local c = app_config.load()
    rtc.timezone(app_config.tz_offset(c.timezone))
    log.info("net_drv", "应用网络配置，优先级:", table.concat(c.priority or {}, ">"))

    local list = build_priority(c)
    -- 最多降级两次：失败时去掉 WiFi 再试，仍失败则只剩 4G
    for attempt = 1, 3 do
        local ok = exnetif.set_priority_order(list)
        if ok then
            log.info("net_drv", "多网融合启动成功，链路数:", #list)
            break
        end
        log.warn("net_drv", "多网融合启动失败，降级重试，attempt:", attempt)
        -- 去掉 WiFi 项
        local trimmed = {}
        for _, item in ipairs(list) do
            if not item.WIFI then table.insert(trimmed, item) end
        end
        if #trimmed == #list then
            list = { { LWIP_GP = true } }
        else
            list = trimmed
        end
        sys.wait(1000)
    end
end

-- 统一状态回调
local function on_net_status(net_type, adapter)
    M.state.active = net_type
    M.state.active_adapter = adapter or -1
    log.info("net_drv", "当前生效链路:", tostring(net_type), adapter)
    sys.publish("NET_ACTIVE_CHANGED", net_type, adapter)
end
exnetif.notify_status(on_net_status)

sys.subscribe("IP_READY", function(ip, adapter)
    if adapter == socket.LWIP_ETH then
        M.state.eth_ready = true
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")
    elseif adapter == socket.LWIP_STA then
        M.state.wifi_ready = true
    elseif adapter == socket.LWIP_GP then
        M.state.gprs_ready = true
    end
    log.info("net_drv", "IP 就绪", tostring(adapter), ip)
end)

sys.subscribe("IP_LOSE", function(adapter)
    if adapter == socket.LWIP_ETH then
        M.state.eth_ready = false
    elseif adapter == socket.LWIP_STA then
        M.state.wifi_ready = false
    elseif adapter == socket.LWIP_GP then
        M.state.gprs_ready = false
    end
    log.warn("net_drv", "IP 丢失", tostring(adapter))
end)

-- 配置变更：WiFi 凭据/静态 IP 变化后重新应用
sys.subscribe("APP_CONFIG_UPDATED", function()
    sys.taskInit(function()
        sys.wait(500)
        log.info("net_drv", "配置变更，重新应用网络")
        apply_network()
    end)
end)

-- 4G 运营商名称
local OPERATOR_MAP = {
    ["46000"] = "中国移动", ["46002"] = "中国移动", ["46007"] = "中国移动",
    ["46001"] = "中国联通", ["46006"] = "中国联通",
    ["46003"] = "中国电信", ["46005"] = "中国电信", ["46011"] = "中国电信",
}
function M.get_operator()
    local scell = mobile.scell()
    if scell and scell.mcc then
        local k = string.format("%d%02d", scell.mcc, scell.mnc or 0)
        return OPERATOR_MAP[k] or "未知"
    end
    return "--"
end

function M.wifi_scan()
    wlan.scan()
    return wlan.scanResult() or {}
end

function M.reconnect_wifi(ssid, pwd)
    app_config.save({ wifi_ssid = ssid, wifi_pwd = pwd })
end

sys.taskInit(apply_network)
return M
