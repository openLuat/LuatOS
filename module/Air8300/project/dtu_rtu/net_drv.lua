--[[
@module  net_drv
@summary 多网卡驱动（以太网手动 + 4G exnetif + WiFi 手动）
@version 2.0
@date    2026.06.10
]]

local exnetif = require "exnetif"
local net_config = require "net_config"
local M = {}

local OPERATOR_MAP = {
    ["46000"] = "中国移动", ["46002"] = "中国移动", ["46007"] = "中国移动",
    ["46001"] = "中国联通", ["46006"] = "中国联通",
    ["46003"] = "中国电信", ["46005"] = "中国电信", ["46011"] = "中国电信",
}

gpio.setup(16, 1, gpio.PULLUP)
gpio.setup(17, 1, gpio.PULLUP)

local function ip_ready_func(ip, adapter)
    socket.setDNS(adapter, 1, "223.5.5.5")
    socket.setDNS(adapter, 2, "114.114.114.114")
    local name = adapter == socket.LWIP_STA and "WiFi"
        or adapter == socket.LWIP_ETH and "网口1"
        or adapter == socket.LWIP_USER1 and "网口2" or "4G"
    log.info("net_drv", name .. "就绪", socket.localIP(adapter))
end
local function ip_lose_func(adapter)
    log.warn("net_drv", "网卡断连", adapter)
end
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)

sys.taskInit(function()
    local c = net_config.load()

    -- 设置时区
    local function tz_to_offset(tz)
        local h = tonumber(string.match(tz, "([+-]?%d+)")) or 8
        return h * 4
    end
    rtc.timezone(tz_to_offset(c.timezone or "UTC+8"))
    log.info("net_drv", "时区:", c.timezone or "UTC+8")

    -- 以太网：手动初始化，零 DHCP 窗口
    spi.setup(1, nil, 0, 0, 8, 25600000)

    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {spi = 1, cs = 21})
    netdrv.dhcp(socket.LWIP_ETH, false)
    netdrv.ipv4(socket.LWIP_ETH, c.eth1_ip, c.eth1_mask, c.eth1_gw)
    log.info("net_drv", "网口1静态IP:", c.eth1_ip)

    sys.wait(300)

    netdrv.setup(socket.LWIP_USER1, netdrv.CH390, {spi = 1, cs = 20})
    netdrv.dhcp(socket.LWIP_USER1, false)
    netdrv.ipv4(socket.LWIP_USER1, c.eth2_ip, c.eth2_mask, c.eth2_gw)
    log.info("net_drv", "网口2静态IP:", c.eth2_ip)

    -- 4G：exnetif 管（唯一一次 socket.dft 切换在此）
    exnetif.set_priority_order({{LWIP_GP = {}}})
    log.info("net_drv", "4G已启动")

    -- WiFi：最后手动连，此时无 socket.dft() 干扰 DHCP
    wlan.init()
    wlan.connect(c.wifi_ssid, c.wifi_pwd, 1)
    log.info("net_drv", "WiFi连接中 SSID:", c.wifi_ssid)
end)

sys.subscribe("NET_CONFIG_UPDATED", function(cfg)
    -- WiFi 重连
    wlan.disconnect()
    wlan.connect(cfg.wifi_ssid, cfg.wifi_pwd, 1)
    -- 立即应用时区
    local function tz_to_offset(tz)
        local h = tonumber(string.match(tz, "([+-]?%d+)")) or 8
        return h * 4
    end
    rtc.timezone(tz_to_offset(cfg.timezone or "UTC+8"))
end)

function M.get_wifi_ssid() return net_config.load().wifi_ssid end
function M.get_operator()
    local scell = mobile.scell()
    if scell and scell.mcc then
        local k = string.format("%d%02d", scell.mcc, scell.mnc or 0)
        return OPERATOR_MAP[k] or "未知"
    end
    return "--"
end
function M.wifi_scan() wlan.scan() end
function M.wifi_scan_result() return wlan.scanResult() or {} end

-- 低功耗控制（网口1 GPIO16 永不关闭，保证 httpsrv 可用）
function M.wifi_off() wlan.disconnect(); log.info("net_drv","WiFi关") end
function M.wifi_on()
    local c = net_config.load()
    wlan.init(); wlan.connect(c.wifi_ssid, c.wifi_pwd, 1)
    log.info("net_drv","WiFi开")
end
function M.eth2_off() gpio.setup(17, 0); log.info("net_drv","网口2关") end
function M.eth2_on() gpio.setup(17, 1, gpio.PULLUP); log.info("net_drv","网口2开") end
function M.rs485_off() gpio.setup(29, 0); log.info("net_drv","RS485关") end
function M.rs485_on() gpio.setup(29, 1, gpio.PULLUP); log.info("net_drv","RS485开") end

return M
