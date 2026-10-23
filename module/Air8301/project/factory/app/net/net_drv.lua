--[[
@module  net_drv
@summary 多网卡驱动（多网融合：网口1 / 网口2 / WiFi / 4G + WiFi AP，Air8301 出厂固件）
@version 1.0
@date    2026.09.22
@author  江访
@usage
Air8301 网络硬件：
- 网口1：CH390H，SPI1 / CS=GPIO12，INT=GPIO20，供电 GPIO32（映射 socket.LWIP_ETH）
- 网口2：CH390H，SPI1 / CS=GPIO5， INT=CHG_DET(gpio.WAKEUP6)，供电 GPIO33（映射 socket.LWIP_USER1）
- 4G：映射 socket.LWIP_GP
- WiFi：STA 连接（映射 socket.LWIP_STA）+ AP 热点（供电脑直连访问内置网页）

多网融合（exnetif）：
- 四张网卡（网口1 / 网口2 / WiFi / 4G）统一交给 exnetif.set_priority_order 初始化与调度，
  配置表顺序即优先级顺序（取自 net_config.priority，可在屏幕「多网融合」页或内置网页调整）；
- 高优先级链路掉线时自动切换到下一档可用链路，全部断网才回调 (nil, -1)；
- WiFi AP 不参与多网融合调度，单独创建；
- 优先级调整 / WiFi 配网 / 网口 IP 变化 → 增量重下发（exnetif 自动跳过已初始化网卡）。

本模块职责：
1、按优先级初始化四张网卡（多网融合）并创建 WiFi AP
2、发布网络状态消息供 UI 显示：STATUS_SIGNAL_UPDATED / STATUS_WIFI_UPDATED / STATUS_ETH_UPDATED
3、发布当前生效网卡消息：NET_ACTIVE_UPDATED（多网融合调度结果）
4、响应 NETWORK_STATUS_QUERY 主动查询
5、初始化完成后发布 NETWORK_INIT_DONE（flash_app 依赖此消息挂载 Flash）
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

-- 当前生效网卡中文名（多网融合调度结果，由 exnetif.notify_status 回调更新）
local net_active = ""

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
    -- 多网融合：一并推送当前生效网卡，供页面打开时立即显示
    sys.publish("NET_ACTIVE_UPDATED", nil, -1, net_active ~= "" and net_active or "查询中")
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
网卡适配器编号 → 中文名（多网融合状态显示用）

@local
@function adapter_cn
@param adapter number 网卡编号（socket.LWIP_*）
@return string 中文名（无法识别时返回适配器号字符串）
]]
local function adapter_cn(adapter)
    if adapter == socket.LWIP_ETH then return "网口1" end
    if adapter == socket.LWIP_USER1 then return "网口2" end
    if socket.LWIP_STA and adapter == socket.LWIP_STA then return "WiFi" end
    if socket.LWIP_GP and adapter == socket.LWIP_GP then return "4G" end
    return tostring(adapter)
end

--[[
多网融合状态回调（exnetif.notify_status）

exnetif 在「当前生效网卡切换」或「全部网卡断网」时回调：
- 有可用网络：net_type = 网卡类型字符串（"WiFi"/"Ethernet"/"8101SPIETH"/"4G"），adapter = 网卡编号
- 全部断网：net_type = nil，adapter = -1
本回调只做状态缓存与消息转发，供 UI（多网融合页 / 通信分区页）显示当前生效链路。

@local
@function on_net_status_change
@param net_type string|nil 网卡类型字符串
@param adapter number 网卡编号（-1 表示全部断网）
]]
local function on_net_status_change(net_type, adapter)
    if net_type == nil or adapter == nil or adapter == -1 then
        net_active = "无可用网络"
        log.warn("net_drv", "多网融合: 全部网卡断网")
        sys.publish("NET_ACTIVE_UPDATED", nil, -1, net_active)
        return
    end
    net_active = adapter_cn(adapter)
    log.info("net_drv", "多网融合: 当前生效网卡", net_active, net_type, adapter)
    sys.publish("NET_ACTIVE_UPDATED", net_type, adapter, net_active)
end

--[[
按 net_config.priority 构造并下发 exnetif 多网卡优先级配置（多网融合核心）

四张网卡统一纳入 exnetif 调度，配置表顺序即优先级顺序：
  eth1 → ETHERNET（网口1，socket.LWIP_ETH）
  eth2 → ETHUSER1（网口2，socket.LWIP_USER1）
  wifi → WIFI    （WiFi STA，socket.LWIP_STA）
  4g   → LWIP_GP （4G，socket.LWIP_GP）
高优先级链路掉线时，exnetif 自动切换到下一档可用链路；全部断网才回调 (nil, -1)。

网口为局域网静态 IP 场景，配置 need_ping = false：
仅以「链路 + IP_READY/IP_LOSE」判定网卡可用，避免「内网无外网 → ping 失败 → 全链路被判死」。
（注：need_ping 在 exnetif 内部为单一变量，此处四张网卡统一传 false，语义一致。）

重复调用为增量更新：已初始化的网卡跳过初始化（网口不会重复 setup），
仅更新变化项，WiFi 凭证（ssid）变化时自动断开重连 —— 因此优先级调整与 WiFi 配网均走本函数。

@local
@function apply_priority_order
@param cfg table net_config 配置表
@return boolean 是否下发成功
]]
local function apply_priority_order(cfg)
    local priority = cfg.priority or { "wifi", "eth1", "eth2", "4g" }

    -- 各网卡的 exnetif 配置项（由闭包生成，保证改 IP / WiFi 后重建即生效）
    local builders = {
        eth1 = function()
            return {
                ETHERNET = {
                    pwrpin = 32,                            -- 网口1 供电使能 GPIO32
                    tp = netdrv.CH390,                      -- SPI 外挂 CH390H
                    opts = { spi = 1, cs = 12, irq = 20 },  -- SPI1 / CS=GPIO12 / INT=GPIO20（中断模式）
                    static_ip = {                           -- 局域网静态 IP
                        ipv4 = cfg.eth1_ip, mark = cfg.eth1_mask, gw = cfg.eth1_gw,
                    },
                    need_ping = false,                      -- 局域网场景：按 IP 判定可用
                },
            }
        end,
        eth2 = function()
            return {
                ETHUSER1 = {
                    pwrpin = 33,                             -- 网口2 供电使能 GPIO33
                    tp = netdrv.CH390,
                    opts = { spi = 1, cs = 5, irq = gpio.WAKEUP6 },  -- SPI1 / CS=GPIO5 / INT=CHG_DET
                    static_ip = {
                        ipv4 = cfg.eth2_ip, mark = cfg.eth2_mask, gw = cfg.eth2_gw,
                    },
                    need_ping = false,
                },
            }
        end,
        wifi = function()
            return {
                WIFI = {
                    ssid = cfg.wifi_ssid,
                    password = cfg.wifi_pwd,
                    need_ping = false,                      -- 与网口统一（need_ping 为 exnetif 全局开关）
                },
            }
        end,
        ["4g"] = function()
            return { LWIP_GP = true }                       -- 启用 4G
        end,
    }

    -- 按 priority 顺序装配配置表（去重；缺项补到末尾，保证四张网卡都在列表中）
    -- WiFi 凭证为空（未配置 / 已「忘记网络」）时不纳入本表：exnetif 仅当配置表含
    -- WIFI 条目时才处理 WiFi（exnetif.set_priority_order 内 type(config.WIFI)=="table" 判断），
    -- 跳过可避免其尝试连接空 SSID；用户重新配网（ssid 变化）后自动重新纳入。
    local wifi_on = (cfg.wifi_ssid ~= nil and cfg.wifi_ssid ~= "")
    local order, used = {}, {}
    for _, key in ipairs(priority) do
        if builders[key] and not used[key] and (key ~= "wifi" or wifi_on) then
            used[key] = true
            order[#order + 1] = builders[key]()
        end
    end
    for _, key in ipairs({ "wifi", "eth1", "eth2", "4g" }) do
        if not used[key] and (key ~= "wifi" or wifi_on) then
            used[key] = true
            order[#order + 1] = builders[key]()
        end
    end

    local ok = exnetif.set_priority_order(order)
    log.info("net_drv", "多网融合优先级下发:", table.concat(priority, ">"), ok and "成功" or "失败")
    return ok
end

--[[
网络初始化任务（多网融合）：
按 net_config.priority 统一初始化四张网卡（网口1 / 网口2 / WiFi STA / 4G） → WiFi AP(DHCP服务器)
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

    -- 多网融合：按优先级统一交给 exnetif 初始化并调度四张网卡
    -- exnetif 内部会完成 spi.setup + 供电使能 + netdrv.setup + 静态 IP 与 WiFi 连接，
    -- 故此处不再手动 netdrv.setup/ipv4（exnetif 无法感知外部的手动初始化，会重复初始化）。
    apply_priority_order(c)

    -- 通知其它模块: CH390 网卡已初始化完成
    -- Air8301 硬件上 Flash 与双 CH390 共用 SPI1 总线, CH390 在未初始化时会下拉共享的
    -- CLK/MISO/MOSI 信号导致 Flash 读 JEDEC ID 失败, 因此 flash_app 必须等待本消息。
    -- 本消息由「网口手动初始化之后」移到「apply_priority_order 之后」发布：
    -- exnetif 初始化网口时每个网口内含 sys.wait(1000)，返回时 CH390 已初始化完毕，
    -- 此时 SPI1 总线不再被下拉，挂载 Flash 才是安全的。
    sys.publish("NETWORK_INIT_DONE")

    -- WiFi AP 热点：让电脑直连设备访问 Web
    wlan.createAP(c.ap_ssid or "Air8301", c.ap_pwd or "12345678")
    netdrv.ipv4(socket.LWIP_AP, c.ap_ip or "192.168.4.1", c.ap_mask or "255.255.255.0", c.ap_gw or "192.168.4.1")
    while not netdrv.ready(socket.LWIP_AP) do sys.wait(100) end
    dhcpsrv.create({adapter = socket.LWIP_AP})
    log.info("net_drv", "WiFi AP就绪 SSID:", c.ap_ssid or "Air8301", "IP:", socket.localIP(socket.LWIP_AP))
end

-- 配置下发任务运行标志（单实例保护：连续调整优先级时合并为一次下发）
local cfg_task_running = false

--[[
多网融合配置下发任务（在 task 中调用 exnetif，满足其「需要在 task 中调用」的要求）

必须在协程中执行：exnetif 内部会调用 sys.wait（网口初始化 / WiFi 换凭证），
不能在消息回调、定时器回调等非协程上下文中直接调用。

@local
@function net_config_apply_task
]]
local function net_config_apply_task()
    -- 300ms 窗口：合并 UI 上连续点击「上移 / 下移」产生的多次 NET_CONFIG_UPDATED
    sys.wait(300)
    cfg_task_running = false
    local cfg = net_config.load()      -- 取最新配置，窗口内的中间态无需逐次下发
    apply_priority_order(cfg)
    rtc.timezone(tz_to_offset(cfg.timezone or "UTC+8"))
end

--[[
NET_CONFIG_UPDATED 回调：多网融合增量重排 + 应用时区

优先级顺序 / WiFi 凭证 / 网口 IP 变化时统一走本回调：
- 重新下发优先级配置表（exnetif 增量更新：已初始化网卡跳过，WiFi 凭证变化自动断连重连）
- 应用时区

@local
@function on_net_config_updated
@param cfg table 新的网络配置
]]
local function on_net_config_updated(cfg)
    -- 已有待执行任务时不再重复创建（任务执行时会读取最新配置）
    if cfg_task_running then return end
    cfg_task_running = true
    sys.taskInit(net_config_apply_task)
end

sys.taskInit(task_net_init)

sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)
sys.subscribe("WLAN_STA_INC", on_wlan_sta)
sys.subscribe("NETWORK_STATUS_QUERY", on_status_query)
sys.subscribe("NET_CONFIG_UPDATED", on_net_config_updated)
-- 注册多网融合状态回调（须在 set_priority_order 之前注册，避免漏掉首次切换通知）
exnetif.notify_status(on_net_status_change)
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

--[[
获取当前生效网卡中文名（多网融合调度结果）

@return string 网卡名（网口1 / 网口2 / WiFi / 4G / 无可用网络 / 查询中）
]]
function M.get_active_net() return net_active end

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
