--[[
@module  net_drv
@summary 多网卡驱动（以太网静态IP + 4G + WiFi + WiFi AP，Air8301 出厂固件）
@version 1.1
@date    2026.09.22
@author  江访
@usage
Air8301 网络硬件：
- 网口1：CH390H，SPI1 / CS=GPIO12，INT=GPIO20，供电 GPIO32（映射 socket.LWIP_ETH）
- 网口2：CH390H，SPI1 / CS=GPIO5， INT=CHG_DET(gpio.WAKEUP6)，供电 GPIO33（映射 socket.LWIP_USER1）
- 4G：exnetif 管理（最低优先级）
- WiFi：手动 STA 连接 + AP 热点（供电脑直连访问内置网页）

本模块职责：
1、初始化双 CH390H 网口静态 IP、4G、WiFi、WiFi AP
2、发布网络状态消息供 UI 显示：STATUS_SIGNAL_UPDATED / STATUS_WIFI_UPDATED / STATUS_ETH_UPDATED
3、响应 NETWORK_STATUS_QUERY 主动查询
4、初始化完成后发布 NETWORK_INIT_DONE（flash_app 依赖此消息挂载 Flash）
]]

local exnetif = require "exnetif"
local net_config = require "net_config"
local dhcpsrv = require "dhcpsrv"
local M = {}

local OPERATOR_MAP = {
    ["46000"] = "中国移动", ["46002"] = "中国移动", ["46007"] = "中国移动",
    ["46001"] = "中国联通", ["46006"] = "中国联通",
    ["46003"] = "中国电信", ["46005"] = "中国电信", ["46011"] = "中国电信",
}

-- ==================== 网络状态缓存 ====================
local mobile_level = -1      -- 4G 信号等级：-1=无信号, 1~5=由弱到强
local wifi_connected = false
local wifi_level = 0
local wifi_ssid = ""
local eth1_connected = false
local eth1_ip = ""
local eth2_connected = false
local eth2_ip = ""

-- 4G CSQ 轮询间隔
local MOBILE_POLL_INTERVAL = 3000

--[[
CSQ 转信号等级（4G）

@local
@function csq_to_level
@param csq number CSQ值（0~31，99=无信号）
@return number 等级：-1=无信号, 1~5=信号由弱到强
]]
local function csq_to_level(csq)
    if not csq or csq == 99 then return -1 end
    if csq <= 5 then return 1 elseif csq <= 10 then return 2 elseif csq <= 15 then return 3 elseif csq <= 20 then return 4 elseif csq <= 31 then return 5 end
    return -1
end

--[[
RSSI 转信号等级（WiFi）

@local
@function rssi_to_level
@param rssi number 信号强度dBm（负数，越大越强）
@return number 等级：0=无信号, 1~4=由弱到强
]]
local function rssi_to_level(rssi)
    if not rssi then return 0 end
    if rssi > -50 then return 4 elseif rssi > -60 then return 3 elseif rssi > -70 then return 2 elseif rssi > -80 then return 1 end
    return 0
end

-- 双网口供电使能并置高（GPIO32=网口1，GPIO33=网口2）
-- 注意：gpio.setup 仅配置引脚方向，必须再 gpio.set 置高才真正对外供电，
--       否则 CH390H 无电，会打印“读取vid/pid持续失败!请检查接线!!”
gpio.setup(32, 1, gpio.PULLUP)
gpio.set(32, 1)
gpio.setup(33, 1, gpio.PULLUP)
gpio.set(33, 1)

--[[
发布 WiFi 状态：STATUS_WIFI_UPDATED(connected, ssid, level, rssi)

@local
@function publish_wifi_status
]]
local function publish_wifi_status()
    local connected = wlan.ready()
    local info = connected and wlan.getInfo() or nil
    local rssi = info and info.rssi or 0
    wifi_connected = connected
    wifi_level = rssi_to_level(rssi)
    if connected then
        local ok, s = pcall(wlan.getSsid)
        if ok and s and s ~= "" then
            wifi_ssid = s
        end
    else
        wifi_ssid = ""
    end
    sys.publish("STATUS_WIFI_UPDATED", wifi_connected, wifi_ssid, wifi_level, rssi)
end

-- 发布以太网状态：STATUS_ETH_UPDATED(eth1_state, eth1_ip, eth2_state, eth2_ip)
local function publish_eth_status()
    sys.publish("STATUS_ETH_UPDATED", eth1_connected and 1 or 0, eth1_ip, eth2_connected and 1 or 0, eth2_ip)
end

-- 发布 4G 信号等级：STATUS_SIGNAL_UPDATED(level)
local function publish_signal_status()
    sys.publish("STATUS_SIGNAL_UPDATED", mobile_level)
end

--[[
IP_READY 回调：更新对应网卡状态并发布 UI 消息

@local
@function ip_ready_func
@param ip string 获取到的IP地址
@param adapter number 网卡编号
]]
local function ip_ready_func(ip, adapter)
    socket.setDNS(adapter, 1, "223.5.5.5")
    socket.setDNS(adapter, 2, "114.114.114.114")
    if adapter == socket.LWIP_ETH then
        eth1_connected = true
        eth1_ip = ip or ""
        publish_eth_status()
    elseif adapter == socket.LWIP_USER1 then
        eth2_connected = true
        eth2_ip = ip or ""
        publish_eth_status()
    elseif adapter == socket.LWIP_STA then
        publish_wifi_status()
    end
    local name = adapter == socket.LWIP_STA and "WiFi"
        or adapter == socket.LWIP_ETH and "网口1"
        or adapter == socket.LWIP_USER1 and "网口2" or "4G"
    log.info("net_drv", name .. "就绪", socket.localIP(adapter))
end

--[[
IP_LOSE 回调：更新对应网卡状态

@local
@function ip_lose_func
@param adapter number 网卡编号
]]
local function ip_lose_func(adapter)
    if adapter == socket.LWIP_ETH then
        eth1_connected = false
        eth1_ip = ""
        publish_eth_status()
    elseif adapter == socket.LWIP_USER1 then
        eth2_connected = false
        eth2_ip = ""
        publish_eth_status()
    elseif adapter == socket.LWIP_STA then
        sys.publish("STATUS_WIFI_UPDATED", false, "", 0, 0)
    end
    log.warn("net_drv", "网卡断连", adapter)
end

--[[
WLAN STA 状态回调

@local
@function on_wlan_sta
@param evt string 事件名
@param data string 事件数据（SSID）
]]
local function on_wlan_sta(evt, data)
    if evt == "CONNECTED" then
        if data then wifi_ssid = data end
        publish_wifi_status()
    elseif evt == "DISCONNECTED" then
        wifi_ssid = ""
        sys.publish("STATUS_WIFI_UPDATED", false, "", 0, 0)
    end
end

--[[
NETWORK_STATUS_QUERY 回调：UI 页面打开时主动拉取最新网络状态

@local
@function on_status_query
]]
local function on_status_query()
    publish_signal_status()
    publish_wifi_status()
    publish_eth_status()
end

-- 4G 信号轮询任务
local function mobile_poll_task()
    while true do
        sys.wait(MOBILE_POLL_INTERVAL)
        local csq = mobile.csq()
        if csq then
            mobile_level = csq_to_level(csq)
            publish_signal_status()
        end
    end
end

-- WiFi 状态兜底轮询（5 秒），避免遗漏事件导致显示滞后
local function wifi_status_poll_task()
    while true do
        sys.wait(5000)
        publish_wifi_status()
    end
end

--[[
时区字符串转 rtc.timezone 偏移值

@local
@function tz_to_offset
@param tz string 如 "UTC+8"
@return number 偏移值
]]
local function tz_to_offset(tz)
    local h = tonumber(string.match(tz, "([+-]?%d+)")) or 8
    return h * 4
end

--[[
网络初始化任务：
以太网静态IP（网口1/网口2） → 4G → WiFi STA → WiFi AP(DHCP服务器)
完成后发布 NETWORK_INIT_DONE

@local
@function task_net_init
]]
local function task_net_init()
    local c = net_config.load()

    -- 设置时区
    rtc.timezone(tz_to_offset(c.timezone or "UTC+8"))
    log.info("net_drv", "时区:", c.timezone or "UTC+8")

    -- 确保双网口供电已上电，并等待 CH390H 上电稳定
    -- （不上电或上电瞬间即读寄存器，会导致 vid/pid 持续读取失败，网口延迟很久才 link up）
    gpio.set(32, 1)
    gpio.set(33, 1)
    sys.wait(200)

    -- 以太网：手动初始化，零 DHCP 窗口
    spi.setup(1, nil, 0, 0, 8, 25600000)

    -- 补中断引脚 INT=GPIO20：CH390H 走中断模式（MCP 核实 opts.irq），
    -- 避免驱动周期性轮询 SPI1，降低与同总线 SPI NAND / 另一片 CH390H 的总线争用
    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {spi = 1, cs = 12, irq = 20})
    netdrv.dhcp(socket.LWIP_ETH, false)
    netdrv.ipv4(socket.LWIP_ETH, c.eth1_ip, c.eth1_mask, c.eth1_gw)
    log.info("net_drv", "网口1静态IP:", c.eth1_ip)

    sys.wait(300)

    -- 补中断引脚 INT=CHG_DET（gpio.WAKEUP6，MCP 核实仅 Air8000 系列支持），同上网口1 的理由
    netdrv.setup(socket.LWIP_USER1, netdrv.CH390, {spi = 1, cs = 5, irq = gpio.WAKEUP6})
    netdrv.dhcp(socket.LWIP_USER1, false)
    netdrv.ipv4(socket.LWIP_USER1, c.eth2_ip, c.eth2_mask, c.eth2_gw)
    log.info("net_drv", "网口2静态IP:", c.eth2_ip)

    -- 通知其它模块: CH390 网卡已初始化完成
    -- Air8301 硬件上 Flash 与双 CH390 共用 SPI1 总线, CH390 在未初始化时会下拉共享的
    -- CLK/MISO/MOSI 信号导致 Flash 读 JEDEC ID 失败, 因此 flash_app 必须等待本消息
    sys.publish("NETWORK_INIT_DONE")

    -- 4G：exnetif 管（唯一一次 socket.dft 切换在此）
    exnetif.set_priority_order({{LWIP_GP = {}}})
    log.info("net_drv", "4G已启动")

    -- WiFi：最后手动连，此时无 socket.dft() 干扰 DHCP
    wlan.init()
    wlan.connect(c.wifi_ssid, c.wifi_pwd, 1)
    log.info("net_drv", "WiFi连接中 SSID:", c.wifi_ssid)

    -- WiFi AP 热点：让电脑直连设备访问 Web
    wlan.createAP(c.ap_ssid or "Air8301", c.ap_pwd or "12345678")
    netdrv.ipv4(socket.LWIP_AP, c.ap_ip or "192.168.4.1", c.ap_mask or "255.255.255.0", c.ap_gw or "192.168.4.1")
    while not netdrv.ready(socket.LWIP_AP) do sys.wait(100) end
    dhcpsrv.create({adapter = socket.LWIP_AP})
    log.info("net_drv", "WiFi AP就绪 SSID:", c.ap_ssid or "Air8301", "IP:", socket.localIP(socket.LWIP_AP))
end

--[[
NET_CONFIG_UPDATED 回调：WiFi 重连 + 应用时区

@local
@function on_net_config_updated
@param cfg table 新的网络配置
]]
local function on_net_config_updated(cfg)
    wlan.disconnect()
    wlan.connect(cfg.wifi_ssid, cfg.wifi_pwd, 1)
    rtc.timezone(tz_to_offset(cfg.timezone or "UTC+8"))
end

sys.taskInit(task_net_init)

sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)
sys.subscribe("WLAN_STA_INC", on_wlan_sta)
sys.subscribe("NETWORK_STATUS_QUERY", on_status_query)
sys.subscribe("NET_CONFIG_UPDATED", on_net_config_updated)
sys.taskInit(mobile_poll_task)
sys.taskInit(wifi_status_poll_task)

-- ==================== 对外接口 ====================

--[[
获取当前 WiFi SSID

@return string SSID
]]
function M.get_wifi_ssid() return net_config.load().wifi_ssid end

--[[
获取当前运营商名称（4G）

@return string 运营商名称
]]
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
-- 获取 WiFi 扫描结果
function M.wifi_scan_result() return wlan.scanResult() or {} end

-- ==================== 低功耗控制 ====================

-- 关闭 WiFi
function M.wifi_off() wlan.disconnect(); log.info("net_drv", "WiFi关") end
-- 打开 WiFi 并连接
function M.wifi_on()
    local c = net_config.load()
    wlan.init(); wlan.connect(c.wifi_ssid, c.wifi_pwd, 1)
    log.info("net_drv", "WiFi开")
end

-- 关闭 RS485 供电
function M.rs485_off() gpio.setup(29, 0); log.info("net_drv", "RS485关") end
-- 打开 RS485 供电
function M.rs485_on() gpio.setup(29, 1, gpio.PULLUP); log.info("net_drv", "RS485开") end

return M
