-- J24 belongs to the Air1602. On M boards SPI2 also carries J15 traffic from the EX2.
local M = {}
local p, radio, enabled
local registered, powered, running = false, false, false
local active, active_ip
local transit_ready = false
local shared_ip, shared_mask, cell_allowed
local WAKE = "AIR8606_WAN_UPDATE"

local function wake()
    sys.publish(WAKE)
end

local function stop_j24()
    if running and not netdrv.ctrl(socket.LWIP_ETH, netdrv.CTRL_UPDOWN, 0) then
        return false
    end
    running = false
    if powered then
        if registered then netdrv.dhcp(socket.LWIP_ETH, false) end
        spi.close(p.spi_id)
        for _, pin in ipairs({p.cs_pin, p.sck_pin, p.mosi_pin, p.miso_pin, p.irq_pin}) do
            gpio.setup(pin, nil, 0)
        end
        gpio.setup(p.pwr_pin, 0)
        powered = false
    end
    return true
end

local function start_j24()
    gpio.setup(p.pwr_pin, 1)
    powered = true
    sys.wait(2)
    gpio.setup(p.cs_pin, 1, gpio.PULLUP)
    sys.wait(50) -- allow the CH390H supply and oscillator to settle before SPI
    if not enabled("eth_spi") then return false end
    if spi.setup(p.spi_id, nil, 0, 0, 8, p.speed) ~= 0 then return false end
    local id = socket.LWIP_ETH
    if registered then
        if not netdrv.ctrl(id, netdrv.CTRL_UPDOWN, 1) then return false end
    else
        registered = netdrv.setup(id, netdrv.CH390, {spi=p.spi_id, cs=p.cs_pin, irq=p.irq_pin}) == true
        if not registered then return false end
    end
    running = true
    return netdrv.dhcp(id, true) == true
end

local function ready_ip(id)
    if netdrv.link(id) and netdrv.ready(id) then
        local ip, mask = netdrv.ipv4(id)
        if type(ip) == "string" and ip ~= "" and ip ~= "0.0.0.0" then return ip, mask end
    end
end

local function update_share(ip, mask)
    local allow = enabled("4g_airlink_spi")
    if not transit_ready then ip, mask = nil, nil end
    if ip == shared_ip and mask == shared_mask and allow == cell_allowed then return end
    if shared_ip and (ip ~= shared_ip or mask ~= shared_mask) then
        if not netdrv.napt(-1) then return end
        shared_ip, shared_mask = nil, nil
    end
    if ip and not shared_ip and netdrv.napt(socket.LWIP_ETH) then
        shared_ip, shared_mask = ip, mask
    end
    cell_allowed = allow
    sys.publish("AIR8606_SHARE_CHANGED")
end

-- Only advertise a wired uplink after its physical interface, DHCP and NAPT are ready.
function M.policy()
    if radio ~= "4g" or cell_allowed == nil then return nil end
    return {j24=shared_ip or "", mask=shared_mask or "", cell=cell_allowed}
end

local function select_route()
    local eth = socket.LWIP_ETH
    local ip, mask
    if running and enabled("eth_spi") then ip, mask = ready_ip(eth) end
    M.j24_ip = ip
    local id, name = eth, "Ethernet"
    if radio == "4g" then update_share(ip, mask) end
    if not ip then
        if radio == "4g" and enabled("4g_airlink_spi") then
            id, name = socket.LWIP_GP_GW, "airlink_4G"
            ip = ready_ip(id)
        elseif radio == "wifi" and enabled("wifi_airlink_spi") then
            id, name = socket.LWIP_STA, "WiFi"
            ip = ready_ip(id)
        end
    end
    if not ip then id, name = nil, nil end
    -- With no uplink leave sockets on the disconnected WAN, never on the transit network.
    if socket.dft() ~= (id or eth) then socket.dft(id or eth) end
    if id ~= active or ip ~= active_ip then
        active, active_ip = id, ip
        log.info("air8606_wan", "uplink", name or "offline", ip or "")
        sys.publish("EXLIB_NETDRV_NETWORK_STATUS", name, id or -1)
    end
end

local function start_ex2(link)
    airlink.init()
    airlink.config(airlink.CONF_SPI_ID, link.spi_id)
    airlink.config(airlink.CONF_SPI_CS, link.cs_pin)
    airlink.config(airlink.CONF_SPI_RDY, link.rdy_pin)
    airlink.config(airlink.CONF_SPI_SPEED, link.speed)
    netdrv.setup(socket.LWIP_GP_GW, netdrv.WHALE)
    -- Registering USER0 must never make the private backhaul the implicit default.
    socket.dft(socket.LWIP_ETH)
    netdrv.ipv4(socket.LWIP_GP_GW, "192.168.111.1", "255.255.255.0", "192.168.111.2")
    airlink.start(airlink.MODE_SPI_MASTER)
end

local function start_transit()
    local id = socket.LWIP_USER0
    -- Both ends carry Ethernet frames, including ARP, across the private SPI link.
    local opts = {flags=0x0a, mtu=1500, mac=string.char(0x02,0xa1,0x60,0x86,0x06,0x01)}
    if netdrv.setup(id, netdrv.WHALE, opts) then
        transit_ready = netdrv.ipv4(id, "169.254.86.1", "255.255.255.252", "169.254.86.2") == "169.254.86.1"
    end
end

function M.start(cfg, wan, radio_config, is_enabled)
    p, radio, enabled = wan, cfg.radio, is_enabled
    if radio == "4g" then start_ex2(radio_config) end
    sys.subscribe("IP_READY", wake)
    sys.subscribe("IP_LOSE", wake)
    sys.subscribe("NET_CONFIG_CHANGED", wake)
    sys.taskInit(function()
        while true do
            if radio == "4g" and not transit_ready then start_transit() end
            if enabled("eth_spi") then
                if not running and not start_j24() then
                    log.warn("air8606_wan", "J24 初始化未完成")
                    stop_j24()
                end
            elseif powered then
                stop_j24()
            end
            select_route()
            sys.waitUntil(WAKE, 1000)
        end
    end)
end

function M.refresh()
    if p then select_route(); wake() end
end

function M.online()
    return active ~= nil
end

return M
