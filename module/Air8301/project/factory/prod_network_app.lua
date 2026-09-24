--[[
@module  prod_network_app
@summary 网络管理模块（产测模式），使用 exnetif 管理多网优先级
@version 1.0
@date    2026.08.04
@version_note 产测专属：双网口按需 DHCP（由 ETH_TEST 指令启动；业务模式为静态 IP + 网页 + TCP从站）
@usage
Air8000W 网络优先级：WiFi > 4G。
- 通过 exnetif.set_priority_order 只初始化 WiFi + 4G
  （双 CH390 网口与 Flash 共用 SPI1，同一时间只能一个设备用，故改为按需启动，见 prod_test.lua 的 ETH_TEST）
- 发布 STATUS_SIGNAL_UPDATED / STATUS_WIFI_UPDATED / STATUS_ETH_UPDATED 网络状态
- 响应 NETWORK_STATUS_QUERY 主动查询
- 初始化完成后发布 NETWORK_INIT_DONE
- require 即自初始化，无对外接口

产测用途：ETH_TEST,1/2# 检查对应网口能否通过 DHCP 拿到 IP
（由 prod_test.lua 按需 netdrv.setup 注册 + netdrv.dhcp 启动，启动前先停其他 SPI1 设备）。

硬件引脚对照：
  以太网1: CH390H, SPI1/CS=GPIO12, INT=GPIO20,   供电=GPIO32(ETH_3.3V)
  以太网2: CH390H, SPI1/CS=GPIO5,  INT=CHG_DET, 供电=GPIO33(ETH_3.3V)
]]

local exnetif = require "exnetif"

-- 默认WiFi配置（按实际环境修改）
local DEFAULT_WIFI_SSID = "机房-降功耗,找合宙!"
local DEFAULT_WIFI_PASSWORD = "Air123456"

-- 网络状态
local mobile_level = -1
local wifi_connected = false
local wifi_level = 0
local wifi_ssid = "" -- 当前连接的 WiFi SSID(由 WLAN_STA_INC 缓存)
local wifi_rssi = 0  -- 当前连接的 WiFi 信号强度缓存
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
@return number 等级：0=无信号, 1~4=信号由弱到强
]]
local function rssi_to_level(rssi)
    if not rssi then return 0 end
    if rssi > -50 then return 4 elseif rssi > -60 then return 3 elseif rssi > -70 then return 2 elseif rssi > -80 then return 1 end
    return 0
end

--[[
主动获取当前连接的 WiFi SSID
优先用 wlan.getSsid() 主动查询(部分平台支持, 如 ems 组件用法),
失败时回退到 WLAN_STA_INC 事件缓存的 ssid, 最后回退默认配置
]]
local function get_current_wifi_ssid()
    local ssid = ""
    local ok, s = pcall(wlan.getSsid)
    if ok and s and s ~= "" then
        ssid = s
    elseif wifi_ssid and wifi_ssid ~= "" then
        ssid = wifi_ssid -- 回退到事件缓存
    else
        ssid = DEFAULT_WIFI_SSID -- 最后回退默认配置
    end
    wifi_ssid = ssid
    return ssid
end

--[[
主动发布当前 WiFi 状态
消息: STATUS_WIFI_UPDATED(connected, ssid, level, rssi)
  connected: boolean 是否已连接
  ssid: string 当前连接的WiFi名称
  level: number 信号等级(0~4)
  rssi: number 信号强度dBm
]]
local function publish_wifi_status()
    local connected = wlan.ready()
    local info = connected and wlan.getInfo() or nil
    local rssi = info and info.rssi or 0
    wifi_connected = connected
    wifi_rssi = rssi
    wifi_level = rssi_to_level(rssi)
    if connected then
        get_current_wifi_ssid() -- 主动获取并缓存已连接 WiFi 名称
    else
        wifi_ssid = ""
    end
    sys.publish("STATUS_WIFI_UPDATED", wifi_connected, wifi_ssid, wifi_level, wifi_rssi)
    log.info("prod_network_app", "WiFi status:", wifi_connected, wifi_ssid, "level:", wifi_level, "rssi:", wifi_rssi)
end

-- 主动发布当前以太网状态
local function publish_eth_status()
    sys.publish("STATUS_ETH_UPDATED", eth1_connected and 1 or 0, eth1_ip, eth2_connected and 1 or 0, eth2_ip)
end

-- 主动发布当前4G信号等级
local function publish_signal_status()
    sys.publish("STATUS_SIGNAL_UPDATED", mobile_level)
end

-- 4G 信号轮询任务
local function mobile_poll_task()
    while true do
        sys.wait(MOBILE_POLL_INTERVAL)
        local csq = mobile.csq()
        if csq then
            mobile_level = csq_to_level(csq)
            sys.publish("STATUS_SIGNAL_UPDATED", mobile_level)
        end
    end
end

-- IP_READY 回调
local function on_ip_ready(ip, adapter)
    if adapter == socket.LWIP_ETH then
        eth1_connected = true
        eth1_ip = ip or ""
        log.info("prod_network_app", "ETH1 ready:", ip)
        publish_eth_status()
    elseif adapter == socket.LWIP_USER1 then
        eth2_connected = true
        eth2_ip = ip or ""
        log.info("prod_network_app", "ETH2 ready:", ip)
        publish_eth_status()
    elseif adapter == socket.LWIP_STA then
        wifi_connected = true
        log.info("prod_network_app", "WiFi ready:", ip)
        publish_wifi_status()
    elseif adapter == socket.LWIP_GP then
        log.info("prod_network_app", "4G ready:", ip)
        publish_signal_status()
    end
end

-- IP_LOSE 回调
local function on_ip_lose(adapter)
    if adapter == socket.LWIP_ETH then
        eth1_connected = false
        eth1_ip = ""
        publish_eth_status()
    elseif adapter == socket.LWIP_USER1 then
        eth2_connected = false
        eth2_ip = ""
        publish_eth_status()
    elseif adapter == socket.LWIP_STA then
        wifi_connected = false
        wifi_level = 0
        wifi_ssid = ""
        sys.publish("STATUS_WIFI_UPDATED", false, "", 0, 0)
    end
end

-- WLAN STA 状态回调
local function on_wlan_sta(evt, data)
    if evt == "CONNECTED" then
        if data then
            log.info("prod_network_app", "WiFi connected:", data)
            wifi_ssid = data
            wifi_connected = true
        end
        publish_wifi_status()
    elseif evt == "DISCONNECTED" then
        wifi_connected = false
        wifi_ssid = ""
        wifi_level = 0
        wifi_rssi = 0
        sys.publish("STATUS_WIFI_UPDATED", false, "", 0, 0)
    end
end

--[[
网络状态查询消息处理: 收到 NETWORK_STATUS_QUERY 时主动发布当前各网络状态,
供页面打开时刷新使用
]]
local function on_status_query()
    publish_signal_status()
    publish_wifi_status()
    publish_eth_status()
    log.info("prod_network_app", "已响应状态查询")
end

-- WiFi 状态兜底轮询: 每 5 秒主动刷新一次, 避免遗漏事件导致状态显示滞后
local function wifi_status_poll_task()
    while true do
        sys.wait(5000)
        publish_wifi_status()
    end
end

-- exnetif 网络状态回调
local function on_net_status(net_type, adapter)
    log.info("prod_network_app", "当前网络:", net_type or "无", "adapter:", adapter or -1)
end

-- 初始化并设置网络优先级
local function init_network()
    log.info("prod_network_app", "初始化网络优先级...")
    -- 网络优先级：WiFi > 4G
    -- 注意: 双 CH390 网口与 Flash 共用 SPI1，同一时间只能一个设备用，故开机不在此初始化 CH390，
    --       由 prod_test.lua 的 ETH_TEST,1/2# 指令按需 netdrv.setup 注册 + DHCP（启动前先停别的 SPI1 设备）
    -- 硬件引脚对照（ETH_TEST 内使用）：
    --   以太网1: CH390H, SPI1/CS=GPIO12, INT=GPIO20,   供电=GPIO32(ETH_3.3V)
    --   以太网2: CH390H, SPI1/CS=GPIO5,  INT=CHG_DET, 供电=GPIO33(ETH_3.3V)
    exnetif.set_priority_order({
        {
            WIFI = {
                ssid = DEFAULT_WIFI_SSID,
                password = DEFAULT_WIFI_PASSWORD,
                -- 如需纯内网/无外网环境使用, 可配置 need_ping = false 跳过连通性检测
            }
        },
        {
            LWIP_GP = true -- 4G 网卡 (最低优先级)
        }
    })

    exnetif.notify_status(on_net_status)
    log.info("prod_network_app", "网络初始化完成")

    -- 网络(WiFi/4G)初始化完成通知（原 flash_app 挂载时序依赖）
    -- 注: 产测模式下 Flash 不随开机自动挂载（改由 FLASH_TEST 指令按需挂载），本消息保留供其他模块监听
    sys.publish("NETWORK_INIT_DONE")
end

sys.taskInit(init_network)

sys.subscribe("IP_READY", on_ip_ready)
sys.subscribe("IP_LOSE", on_ip_lose)
sys.subscribe("WLAN_STA_INC", on_wlan_sta)
sys.subscribe("NETWORK_STATUS_QUERY", on_status_query)
sys.taskInit(mobile_poll_task)
sys.taskInit(wifi_status_poll_task)

log.info("prod_network_app", "init done")
