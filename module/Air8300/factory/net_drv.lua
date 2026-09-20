--[[
@module  net_drv
@summary 多网融合驱动（以太网 > WiFi > 4G，由 exnetif 统一管理优先级）
@version 1.1
@date    2026.09.18
@usage
本文件负责统一管理 以太网(CH390) / WiFi STA / 4G 的接入与优先级切换。


对外接口：
1、net_drv.get_wifi_ssid()  → 获取当前 WiFi SSID
2、net_drv.get_operator()   → 获取运营商名称
3、net_drv.wifi_scan()      → 触发 WiFi 扫描
]]

local exnetif = require "exnetif"
local net_config = require "net_config"
local M = {}

-- ============ 【硬件引脚定义】Air8300 开发板 ============
local ETH1_CS, ETH1_PWR = 21, 16   -- 网口1：SPI 片选 21，供电使能 16
local ETH2_CS, ETH2_PWR = 20, 17   -- 网口2：SPI 片选 20，供电使能 17
local RS485_PWR = 29               -- RS485 芯片电源脚（供 comm_core 两路 485 使用）

-- 硬件要求：两个网口使能脚必须同时拉高（否则 SPI 电平混乱导致通讯失败）
gpio.setup(ETH1_PWR, 1, gpio.PULLUP)
gpio.setup(ETH2_PWR, 1, gpio.PULLUP)
-- RS485 芯片电源脚：引脚复用 + 拉高（485 收发器供电）
-- 统一在此处初始化：temp_sensor / relay_ctrl 原先各自重复 setup 同一引脚，现统一收口到本模块
pins.setup(18, "GPIO29")
gpio.setup(RS485_PWR, 1, gpio.PULLUP)

-- 运营商映射表（MCC-MNC → 名称）
local OPERATOR_MAP = {
    ["46000"] = "中国移动", ["46002"] = "中国移动", ["46007"] = "中国移动",
    ["46001"] = "中国联通", ["46006"] = "中国联通",
    ["46003"] = "中国电信", ["46005"] = "中国电信", ["46011"] = "中国电信",
}

-- 时区字符串 → 偏移（单位：15 分钟，如 UTC+8 → 32）
local function tz_to_offset(tz)
    local h = tonumber(string.match(tz or "UTC+8", "([+-]?%d+)")) or 8
    return h * 4
end

-- ============ 【事件订阅】网卡就绪 / 断连日志 ============
-- 说明：exnetif 内部也订阅 IP_READY/IP_LOSE 做优先级切换，此处仅用于打印日志与设置 DNS，互不冲突。
local function ip_ready_func(ip, adapter)
    socket.setDNS(adapter, 1, "223.5.5.5")
    socket.setDNS(adapter, 2, "114.114.114.114")
    local name = adapter == socket.LWIP_STA and "WiFi STA"
        or adapter == socket.LWIP_ETH and "网口1"
        or adapter == socket.LWIP_USER1 and "网口2"
        or "4G"
    log.info("net_drv", name .. "就绪", socket.localIP(adapter))
end

local function ip_lose_func(adapter)
    log.warn("net_drv", "网卡断连", adapter)
end

sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)

-- ============ 【多网初始化任务】 ============
sys.taskInit(function()
    local c = net_config.load()

    -- 时区设置
    rtc.timezone(tz_to_offset(c.timezone))
    log.info("net_drv", "时区:", c.timezone or "UTC+8")

    -- ---------------- 【以太网】硬件初始化 ----------------
    -- 两个网口共用 SPI1；两个使能脚已在模块顶层拉高
    spi.setup(1, nil, 0, 0, 8, 25600000)

    local eth_sel = c.eth_enable or "eth1"
    if eth_sel == "eth1" then
        -- 未选中的网口2：仅做硬件初始化，不配 IP、不参与供网
        netdrv.setup(socket.LWIP_USER1, netdrv.CH390, { spi = 1, cs = ETH2_CS })
        log.info("net_drv", "网口2 已硬件初始化（未启用，不供网）")
    elseif eth_sel == "eth2" then
        -- 未选中的网口1：仅做硬件初始化，不配 IP、不参与供网
        netdrv.setup(socket.LWIP_ETH, netdrv.CH390, { spi = 1, cs = ETH1_CS })
        log.info("net_drv", "网口1 已硬件初始化（未启用，不供网）")
    else
        log.info("net_drv", "以太网已禁用（eth_enable = none）")
    end
    log.info("net_drv", "以太网供网口:", eth_sel, "IP 方式:", c.eth_mode or "dhcp")

    -- ---------------- 【多网融合】以太网 > WiFi > 4G ----------------
    -- 以太网条目构建（具体启用哪个网口由 eth_enable 决定）
    local function build_eth_entry()
        if eth_sel == "none" then
            return nil
        end
        local cfg
        if eth_sel == "eth1" then
            cfg = {
                pwrpin = ETH1_PWR,
                tp = netdrv.CH390,
                opts = { spi = 1, cs = ETH1_CS },
                need_ping = c.net_need_ping,
            }
            if c.eth_mode == "static" then
                cfg.static_ip = { ipv4 = c.eth1_ip, mark = c.eth1_mask, gw = c.eth1_gw }
            end
            return { ETHERNET = cfg }
        else
            cfg = {
                pwrpin = ETH2_PWR,
                tp = netdrv.CH390,
                opts = { spi = 1, cs = ETH2_CS },
                need_ping = c.net_need_ping,
            }
            if c.eth_mode == "static" then
                cfg.static_ip = { ipv4 = c.eth2_ip, mark = c.eth2_mask, gw = c.eth2_gw }
            end
            return { ETHUSER1 = cfg }
        end
    end

    -- 网卡条目构建器：eth（以太网）/ wifi（STA）/ 4g
    local builders = {
        eth = build_eth_entry,
        wifi = function()
            return {
                WIFI = {
                    ssid = c.wifi_ssid,
                    password = c.wifi_pwd,
                    need_ping = c.net_need_ping,
                }
            }
        end,
        ["4g"] = function()
            return { LWIP_GP = {} }
        end,
    }

    -- 按 net_config.priority 顺序构建优先级表（高 → 低）
    local priority_cfg = {}
    local seen = {}
    for _, key in ipairs(c.priority or { "eth1", "wifi", "4g" }) do
        local k = tostring(key):lower()
        -- 以太网：eth1/eth2 归为同一类，只取一次（用哪个口由 eth_enable 决定）
        if k == "eth1" or k == "eth2" then
            k = "eth"
        end
        if builders[k] and not seen[k] then
            seen[k] = true
            local entry = builders[k]()
            if entry then
                table.insert(priority_cfg, entry)
            end
        end
    end

    if #priority_cfg > 0 then
        exnetif.set_priority_order(priority_cfg)
        log.info("net_drv", "多网融合已启动：以太网 > WiFi > 4G（按 net_config.priority 排序）")
    else
        log.error("net_drv", "无可用网卡配置，多网融合未启动")
    end
end)

-- ============ 【网络重配】运行中更新 WiFi 凭证 / 时区 ============
-- 说明：放入 task 中执行，便于调用需要 sys.wait 的 exnetif.update_wifi()。
sys.taskInit(function()
    while true do
        sys.waitUntil("NET_CONFIG_UPDATED")
        local cfg = net_config.load()
        log.info("net_drv", "收到网络重配，更新 WiFi 凭证:", cfg.wifi_ssid)
        exnetif.update_wifi({
            ssid = cfg.wifi_ssid,
            password = cfg.wifi_pwd,
        })
        rtc.timezone(tz_to_offset(cfg.timezone))
    end
end)

-- 获取当前 WiFi SSID
function M.get_wifi_ssid() return net_config.load().wifi_ssid end

-- 获取运营商名称
function M.get_operator()
    local scell = mobile.scell()
    if scell and scell.mcc then
        local k = string.format("%d%02d", scell.mcc, scell.mnc or 0)
        return OPERATOR_MAP[k] or "未知"
    end
    return "--"
end

-- 触发 WiFi 扫描
function M.wifi_scan() wlan.scan() end

return M
