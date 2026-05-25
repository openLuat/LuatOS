--[[
@module  net_init
@summary 统一网络初始化模块，基于 exnetif 多网融合框架管理所有网络适配器事件
@version 2.0
@date    2026.05.22
@author  江访

=== 模块职责 ===

本模块是所有网络事件的中央处理器，统一管理：

  1. DNS 配置：任何网卡获得 IP 后，自动设置阿里 DNS (223.5.5.5) 和 114 DNS (114.114.114.114)
  2. IP 事件日志：IP_READY（网卡上线）、IP_LOSE（网卡下线）统一日志
  3. WLAN STA 状态日志：WiFi 连接/断开/认证等中间状态的追踪日志
  4. 多网融合状态日志：exnetif 发布的当前活跃网络类型和适配器编号

=== 历史背景 ===

原先分散在三个独立模块中：
  - netdrv_4g_air8000w.lua   (Air8000W 4G)
  - netdrv_wifi_air8101.lua  (Air8101 WiFi)
  - netdrv_wifi_air1601.lua  (Air1601 WiFi)

重构后合并为此单文件，公共逻辑不再重复。

=== 网卡适配器映射 ===

LuatOS 使用数字标识不同类型的网络适配器：
  socket.LWIP_GP   (1) → 4G 蜂窝网络
  socket.LWIP_STA  (2) → WiFi STA 模式
  socket.LWIP_ETH  (3) → 以太网
  socket.LWIP_USER1 (?) → SPI 以太网（外挂）

=== 注意 ===

本模块只做日志和 DNS 配置，不控制网络连接状态。网络连接管理由 exnetif 扩展库统一负责，
各 wifi_app 模块通过 exnetif.set_priority_order() 配置优先级和连接参数。

本模块无对外 API，require 即自动运行。在 app_main.lua 中作为第一个模块被加载。
]]

--[[
网卡编号 → 中文名称映射
]]
local function adapter_name(adapter)
    if adapter == socket.LWIP_GP then return "4G"
    elseif adapter == socket.LWIP_STA then return "WiFi"
    elseif adapter == socket.LWIP_ETH then return "Ethernet"
    elseif adapter == socket.LWIP_USER1 then return "SPI_ETH"
    else return tostring(adapter) end
end

--[[
IP_READY 事件：某网卡获得 IP 地址
做两件事：1) 为该网卡设置两个 DNS 服务器  2) 记录日志
@param ip string  IP 地址（如 "192.168.0.46"）
@param adapter number  网卡适配器编号（1=4G, 2=WiFi, 3=ETH）
]]
sys.subscribe("IP_READY", function(ip, adapter)
    if not adapter then return end
    -- 设置 DNS：优先阿里 DNS (223.5.5.5)，备用 114 DNS
    -- 这是系统级 DNS 配置，所有后续 socket 连接都会使用
    socket.setDNS(adapter, 1, "223.5.5.5")
    socket.setDNS(adapter, 2, "114.114.114.114")
    log.info("net_init", adapter_name(adapter), "IP_READY", ip)
end)

--[[
IP_LOSE 事件：某网卡丢失 IP 地址
仅记录日志，不做状态清理（由各业务模块自行处理）
@param adapter number  网卡适配器编号
]]
sys.subscribe("IP_LOSE", function(adapter)
    if not adapter then return end
    log.warn("net_init", adapter_name(adapter), "IP_LOSE")
end)

--[[
WLAN_STA_INC 事件：WiFi STA 状态变化（连接中/已连接/断开/认证失败...）
由底层 WiFi 驱动发布，包含事件类型和附加数据
@param evt string  事件类型（如 "CONNECTED", "DISCONNECTED"）
@param data string  附加数据（如 SSID 名称）
]]
sys.subscribe("WLAN_STA_INC", function(evt, data)
    log.info("net_init", "WLAN_STA", evt, data)
end)

--[[
EXLIB_NETDRV_NETWORK_STATUS 事件：exnetif 多网融合框架发布的当前网络状态
当活动网卡切换时（如 WiFi→4G），exnetif 发布此事件通知所有模块
@param net_type string or nil  当前网络类型（"4G", "WiFi", "Ethernet"），nil=全部断开
@param net_adapter number or -1  当前适配器编号，-1=无可用适配器

注意：WiFi→4G 切换时 exnetif 可能短暂发布 (nil, -1)，业务模块不应仅据此判断断网
]]
sys.subscribe("EXLIB_NETDRV_NETWORK_STATUS", function(net_type, net_adapter)
    if net_type then
        log.info("net_init", "当前网络", net_type, "adapter", net_adapter)
    else
        log.warn("net_init", "所有网络已断开")
    end
end)
