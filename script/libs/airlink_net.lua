--[[
@module airlink_net
@summary UART AirLink固定网卡供网（IPv4）
@version 1.0
@usage
-- Air8000: 板内Wi-Fi实例0自动启动；先初始化所需WAN，再启动供网。
-- local gateway = require("airlink_net").provider(1, {
--     uart_id=1, priority={socket.LWIP_STA, socket.LWIP_GP, socket.ETH0}
-- })
-- Air1602:
-- require("airlink_net").client(0, {uart_id=1})
-- 本库独占全局NAPT及dnsproxy；不能同时使用exnetif.setproxy。
]]
local M = {}
local provider_started = false

local function setup(id, role, opts)
    local adapter = opts.adapter or socket.LWIP_GP_GW
    local ok, rc = airlink.setup(id, {
        drv = "netif", role = role, mode = airlink.MODE_UART,
        uart_id = opts.uart_id or 1, baudrate = opts.baudrate or 2000000,
        network_adapter = adapter
    })
    assert(ok, "airlink netif setup failed: " .. tostring(rc))
    return adapter
end

-- 固定地址在出口变化和断链时保留，应用始终使用同一个adapter。
function M.client(id, opts)
    opts = opts or {}
    local adapter = setup(id, "client", opts)
    local gateway = opts.gateway or "192.168.111.2"
    netdrv.ipv4(adapter, opts.ip or "192.168.111.1", opts.mask or "255.255.255.0", gateway)
    socket.setDNS(adapter, 1, gateway)
    if opts.default ~= false then socket.dft(adapter) end
    return adapter
end

-- WAN由应用初始化；priority按顺序选择已就绪的网卡。
-- 返回控制器：enable(false/true)暂停/恢复供网，uplink为当前出口或nil。
function M.provider(id, opts)
    assert(not provider_started, "only one NAPT provider is supported")
    opts = opts or {}
    local priority = opts.priority or {socket.LWIP_STA, socket.LWIP_GP}
    assert(#priority > 0, "priority must contain an uplink")
    local adapter = setup(id, "provider", opts)
    for _, wan in ipairs(priority) do
        assert(wan ~= adapter, "LAN cannot be an uplink")
    end
    provider_started = true
    local ip = opts.ip or "192.168.111.2"
    netdrv.ipv4(adapter, ip, opts.mask or "255.255.255.0", ip)
    local dnsproxy = require "dnsproxy"
    -- The controller restarts DNS only for this LAN/selected WAN, not every
    -- unrelated IP_READY event (including the onboard Wi-Fi instance).
    sys.unsubscribe("IP_READY", dnsproxy.on_ip_ready)
    local controller = {adapter = adapter, uplink = nil}
    local enabled, changed = true, true
    local last_key
    -- Keep controls rooted and reuse them. The socket API has no Lua-visible
    -- close-completion barrier; release/recreate on every switch is unsafe.
    local upstreams, listener = {}, nil
    function controller.enable(value)
        value = not not value
        if enabled ~= value then enabled, changed = value, true end
    end
    local function close_dns()
        local txid = dnsproxy.txid
        dnsproxy.close()
        dnsproxy.txid = txid
    end
    local function start_dns(wan)
        if not upstreams[wan] then
            upstreams[wan] = socket.create(wan, function(sc, event)
                if upstreams[wan] == dnsproxy.main_sc then dnsproxy.on_response(sc, event) end
            end)
            if not upstreams[wan] then return false end
            socket.config(upstreams[wan], 1053, true)
        end
        if not listener then
            listener = socket.create(adapter, function(sc, event)
                if dnsproxy.main_sc and dnsproxy.srvs[adapter] == listener then
                    dnsproxy.on_request(sc, event, adapter)
                end
            end)
            if not listener then return false end
            socket.config(listener, 53, true)
        end
        dnsproxy.main_sc = upstreams[wan]
        dnsproxy.srvs[adapter] = listener
        dnsproxy.on_ip_ready()
        return true
    end
    sys.subscribe("IP_LOSE", function(lost)
        if lost == adapter or lost == controller.uplink then changed = true end
    end)
    sys.taskInit(function()
        while true do
            local selected, key
            if enabled and netdrv.ready(adapter) then
                for _, wan in ipairs(priority) do
                    if netdrv.ready(wan) then
                        local addr, mask, gateway = netdrv.ipv4(wan)
                        if addr and addr ~= "" and addr ~= "0.0.0.0" then
                            selected = wan
                            key = table.concat({wan, addr, mask or "", gateway or ""}, "/")
                            break
                        end
                    end
                end
            end
            if changed or key ~= last_key then
                -- Withdraw first; resetting even the same WAN clears stale
                -- mappings after DHCP/PDP changes or a down/up cycle.
                airlink.netstate(id, -1)
                local cleared = netdrv.napt(-1)
                close_dns()
                controller.uplink, last_key = nil, nil
                if selected and cleared then
                    socket.dft(selected)
                    dnsproxy.server = opts.dns or "119.29.29.29"
                    local dns_ok = start_dns(selected)
                    if dns_ok and netdrv.napt(selected) then
                        airlink.netstate(id, selected)
                        controller.uplink, last_key = selected, key
                    else
                        close_dns()
                    end
                end
                changed = not cleared
                log.info("airlink_net", "uplink", controller.uplink or -1)
            end
            sys.wait(500)
        end
    end)
    return controller
end

return M
