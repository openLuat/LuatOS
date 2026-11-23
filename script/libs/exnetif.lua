--[[
@module exnetif
@summary exnetif 控制网络优先级（以太网->WIFI->4G）根据优先级选择上网的网卡。简化开启多网融合的操作，4G作为数据出口给WIFI,以太网设备上网，以太网作为数据出口给WIFI,Air8000上网，WIFI作为数据出口给Air8000,以太网上网。
@version 1.0
@date    2025.06.26
@author  王城钧
@usage
本文件的对外接口有8个：
1、exnetif.set_priority_order(networkConfigs)：设置网络优先级顺序并初始化对应网络，再次调用时增量更新变化项(需要在task中调用)
2、exnetif.notify_status(cb_fnc)：设置网络状态变化回调函数
3、exnetif.setproxy(adapter, main_adapter,other_configs)：配置网络代理实现多网融合，再次调用时自动切换上游WiFi无需重复初始化(需要在task中调用)
4、exnetif.check_network_status(interval),检测间隔时间ms(选填)，不填时只检测一次，填写后将根据间隔时间循环检测，会提高模块功耗
5、exnetif.close(type, adapter)：关闭网卡功能或多网融合,内核固件版本需为2026年1月后的固件
6、exnetif.version()：获取库文件版本信息
7、exnetif.airlink_provider(id, opts)：通过UART/SPI AirLink固定网卡供网，跟随本库出口策略
8、exnetif.airlink_client(id, opts)：创建UART/SPI AirLink固定网卡用网端

-- 版本更新说明
-- 202611181800：按能力兼容旧固件的网卡就绪查询、可选网卡及以太网启停。
-- 版本号：202611181800
-- 1、更新时间：2026-11-18 18:00
-- 2、更新内容
--    整理选路、探测和代理代码，共用 Wi-Fi 连接及旧式 AirLink 初始化流程。
--    隔离各网卡探测配置；修复关闭后的探测回写、初始化失败重试和代理WiFi重连。
--    AirLink固定网卡支持SPI主机/EC718M从机，传输主从独立于供网角色。
--    整合AirLink provider/client；代理库按需加载；
--    供网跟随set_priority_order，close(true)暂停，enable(true)恢复。

-- 版本号：202607211200
-- 1、更新时间：2026-07-21 12:00
-- 2、更新内容
--    setproxy：合并switch_upstream_wifi/disable_upstream_autoreconnect逻辑
--          再次对同一adapter+main_adapter调用setproxy时自动检测凭证变化并切换WiFi
--          STA代理模式下首次建立时自动启用IP_LOSE掉线重连
--    set_priority_order：合并update_wifi逻辑
--          再次调用时检测WiFi凭证变化(ssid)自动断开重连
--          增量更新：已初始化网卡保持不变，仅更新变化项
--    移除exnetif.switch_upstream_wifi/exnetif.disable_upstream_autoreconnect/exnetif.update_wifi公开API

-- 版本号：202607100900
-- 1、更新时间：2026-07-10 09:00
-- 2、更新内容
--    exnetif.close(true)：完整实现关闭多网融合功能（停止 DHCP 服务器→关闭 DNS 代理→禁用 NAPT→停止代理网卡服务）
--    exnetif.close(false, socket.LWIP_GP_GW)：支持关闭 airlink 4G 网卡（仅设置 DISCONNECTED 状态+apply_priority，无硬件操作）
--    setproxy：保存 DHCP 服务器引用和代理网卡列表，支持多次 setproxy 后的全部清理
--    修复 proxy_state 单值覆盖问题：多次 setproxy 的代理网卡改为数组累积，close(true) 遍历全部关闭

-- 版本号：202607022100
-- 1、更新时间：2026-07-02 21:00
-- 2、更新内容
--    新增exnetif.update_wifi(config)接口
--    修复： 1601 多网融合设置以太网 airlink over uart 4g顺序后，以太网断开后 4g网络连不上问题，ip_lose_handle 网卡掉线时遗漏恢复 OPENED 网卡
--    修复： 1601引擎主机的gpio设置与开发板不同，原airlink_wifi_hardware_init函数会导致引擎主机按键中断失效，airlink_wifi_hardware_init 支持 UART/SPI 双模式，目前改为了手动配置

-- 版本号：202607021200
-- 1、更新时间：2026-07-02 12:00
-- 2、更新内容
--    新增exnetif.version()接口
--    支持exnetif库文件版本号管理功能，版本号的格式为：yyyymmddhhmm，表示yyyy年mm月dd日hh时mm分发布的版本
]]
local exnetif = {}

-- 按需加载：AirLink client只需固定网卡，不需要代理/探测库。
local dnsproxy, dhcpsrv, httpdns
local priority_configured = false
local priority_monitor_started = false
local proxy_owner
local proxy_initializing = false
local proxy_generation = 0
local airlink_provider_controller, stop_airlink_provider
-- 只接受本轮探测结果；关闭、掉线和移出优先级时使旧任务失效。
local probe_options, pending_probe = {}, {}
local default_probe = {delay = 10000}
local function configure_probe(id, cfg)
    probe_options[id] = {
        skip = cfg.need_ping == false,
        gateway = cfg.local_network_mode,
        target = cfg.ping_ip,
        delay = type(cfg.ping_time) == "number" and cfg.ping_time > 0 and cfg.ping_time or default_probe.delay,
    }
    pending_probe[id] = nil
end
-- 使用单网卡模式
local single_network_mode = false
-- 是否自动关闭非当前网卡socket连接
local auto_socket_switch = true
-- 多网模式：OPENED 等 IP，CONNECTING 等探测，只有 CONNECTED 能成为出口。
-- SINGLE_NETWORK 跳过后台探测；STOPPED 表示驱动仍存在，可重新上电启用。
local connection_states = {
    DISCONNECTED = 0,
    CONNECTING = 1,
    CONNECTED = 2,
    OPENED = 3,
    SINGLE_NETWORK = 4,
    STOPPED = 5
}

-- 状态回调函数
local states_cbfnc = function(net_type)
end
-- 当前优先级
local current_priority = {socket.LWIP_ETH, socket.LWIP_STA, socket.LWIP_GP}
-- 连接状态
local available = {}
-- 当前WiFi凭证（供set_priority_order增量更新检测）
local current_wifi_ssid = nil
-- 当前使用的网卡
local current_active = nil

-- 裁剪固件可能没有 USER1 / GP_GW 等常量，不应影响其他网卡加载。
local adapter_names = {}
local names_by_constant = {
    LWIP_STA = "WiFi", LWIP_ETH = "Ethernet", LWIP_GP = "4G",
    LWIP_USER1 = "8101SPIETH", LWIP_GP_GW = "airlink_4G",
}
for key, name in pairs(names_by_constant) do
    local id = socket[key]
    if id ~= nil then
        adapter_names[id] = name
        available[id] = connection_states.DISCONNECTED
    end
end

local function adapter_ready(id)
    if id == nil then return false end
    if netdrv and netdrv.ready then
        local ready = netdrv.ready(id)
        if ready ~= nil then return ready end -- false 表示已查询且未就绪
    end
    if socket.adapter then
        local ready, checked = socket.adapter(id)
        return ready == true and (checked == nil or checked == id)
    end
    -- 仍可由 IP_READY 驱动普通多网选路；静态 IPv4 本身不能证明物理链路已通。
    return false
end

local function can_switch_phy()
    return netdrv and netdrv.ctrl and netdrv.CTRL_UPDOWN ~= nil
end

local function type_to_string(net_type)
    return adapter_names[net_type] or "Unknown"
end

-- 保存以太网网卡参数，用于关闭spi和供电使能
local eth_cfg = {}

-- 多网融合状态记录（供 close(true) 清理使用）
local proxy_state = {
    dhcp_servers = {},     -- DHCP 服务器对象列表，由 setproxy 创建
    proxy_adapters = {},   -- 使用网络的网卡列表 (如 {socket.LWIP_AP, socket.LWIP_ETH})
    main_adapter = nil,    -- 提供网络的网卡 (如 socket.LWIP_GP / socket.LWIP_STA)
    wifi_config = nil,     -- 上游WiFi凭证 {ssid=..., password=...}，供自动重连使用
}

-- 订阅socket连接状态变化事件，socket出现异常时修改网卡状态
local function socket_state_detection(adapter)
    if netdrv and netdrv.on and netdrv.EVT_SOCKET then
        log.info("netdrv", "订阅socket连接状态变化事件", type_to_string(adapter))
        netdrv.on(adapter, netdrv.EVT_SOCKET, function(_, event)
            if event == "timeout" or event == "error" then
                if available[adapter] == connection_states.CONNECTED then
                    available[adapter] = connection_states.CONNECTING
                end
            end
        end)
    end
end
-- 发布网络状态变化的全局消息
-- 当有可用网络时：net_type为网卡类型字符串，adapter为网卡id
-- 当所有网卡断开时：net_type为nil，adapter为-1
local function publish_network_status(net_type, adapter)
    if type(net_type) == "string" then
        log.info("exnetif", "publish network status", net_type, adapter)
    elseif type(net_type) == "nil" then
        log.warn("exnetif", "publish network status", "no available adapter", adapter)
    else
        log.warn("exnetif", "publish network status", "unknown status", net_type, adapter)
    end
    sys.publish("EXLIB_NETDRV_NETWORK_STATUS", net_type, adapter)
end

-- 状态更改后重新设置默认网卡
local function apply_priority()
    for _, net_type in ipairs(current_priority) do
        if available[net_type] == connection_states.CONNECTED then
            -- 更新优先级时可能先设置了尚未就绪的首选网卡，恢复实际选定出口。
            socket.dft(net_type)
            if current_active ~= net_type then
                local name = type_to_string(net_type)
                log.info("设置网卡", name)
                states_cbfnc(name, net_type)
                publish_network_status(name, net_type)
                if auto_socket_switch and socket.close_all and current_active ~= nil then
                    socket.close_all(current_active)
                end
                current_active = net_type
            end
            return
        end
    end

    -- 从存在可用网卡到没有可用网卡，才通知回调
    if current_active ~= nil then
        current_active = nil
        states_cbfnc(nil, -1)
        publish_network_status(nil, -1) -- 发布网络状态变化消息
    end
end

local function finish_probe(id, probe, ok)
    if pending_probe[id] ~= probe or available[id] ~= connection_states.CONNECTING then return end
    pending_probe[id] = nil
    available[id] = ok and connection_states.CONNECTED or connection_states.OPENED
    apply_priority()
end

local function ping_request(id, probe, options)
    if options.skip then
        finish_probe(id, probe, true)
        return
    end
    local target = options.target
    if options.gateway then
        local _, _, gateway = socket.localIP(id)
        target = gateway
    end
    if target then
        probe.target = target
        icmp.setup(id)
        icmp.ping(id, target)
        sys.timerStart(function() finish_probe(id, probe, false) end, options.delay)
    else
        httpdns = httpdns or require("httpdns")
        local ip = httpdns.ali("baidu.com", {adapter = id, timeout = 3000})
        finish_probe(id, probe, ip ~= nil)
    end
end
-- 网卡上线回调函数
local function ip_ready_handle(ip, adapter)
    local _, _, gw = socket.localIP(adapter)
    log.info("ip_ready_handle", ip, type_to_string(adapter), "state", available[adapter], "gw", gw)
    -- 这里只标记待探测；HTTPDNS 需要在任务中等待。
    if available[adapter] == connection_states.OPENED then
        available[adapter] = connection_states.CONNECTING
    end
end
-- 网卡下线回调函数
local function ip_lose_handle(adapter)
    pending_probe[adapter] = nil
    log.info("ip_lose_handle", type_to_string(adapter))
    if available[adapter] == connection_states.CONNECTING or available[adapter] == connection_states.CONNECTED then
        available[adapter] = connection_states.OPENED
    end
    if current_active == adapter then
        log.info(type_to_string(adapter) .. " 失效，切换到其他网络")
        -- 当前活跃网卡下线时，检查其他网卡是否物理连接还在
        -- 若其他网卡实际有IP但在OPENED状态，说明之前被IP_LOSE误标记，需触发重验证
        for _, net_type in ipairs(current_priority) do
            if net_type ~= adapter and available[net_type] == connection_states.OPENED and adapter_ready(net_type) then
                log.info(type_to_string(net_type) .. " 有IP但状态为OPENED，触发重验证")
                available[net_type] = connection_states.CONNECTING
            end
        end
        apply_priority()
    end
end

local interval_time = nil

--[[
将已连通的网卡标记为待复查，由多网模式的后台任务按各自的探测配置处理。
@api exnetif.check_network_status(interval)
@int interval 可选，周期复查间隔（毫秒）。省略时只触发本次复查，不改变已设置的周期。
]]
function exnetif.check_network_status(interval)
    if interval ~= nil then
        interval_time = interval
    end
    for _, net_type in ipairs(current_priority) do
        if available[net_type] == connection_states.CONNECTED then
            available[net_type] = connection_states.CONNECTING
        end
    end
end

-- 探测任务可能让出执行权；优先级被替换时，从新列表重新开始。
local function ping_test_loop()
    while true do
        local priority = current_priority
        for _, net_type in ipairs(priority) do
            if priority ~= current_priority or single_network_mode then break end
            if available[net_type] == connection_states.CONNECTING then
                log.info("exnetif", "检查网卡连通性", type_to_string(net_type))
                local options = probe_options[net_type] or default_probe
                local probe = {}
                pending_probe[net_type] = probe
                ping_request(net_type, probe, options)
                sys.wait(options.delay)
            end
        end
        sys.wait(1000) -- 避免死循环
    end
end

-- 正常状态网卡的检测任务
local function normal_network_test()
    while true do
        if interval_time ~= nil then
            sys.wait(interval_time)
            exnetif.check_network_status()
        end
        sys.wait(1000) -- 避免死循环
    end
end

-- PING结果处理函数
local function ping_res(id, time, dst)
    local probe = pending_probe[id]
    if probe and probe.target and probe.target == dst then finish_probe(id, probe, true) end
end

-- WAN 网卡初始化与恢复

local function connect_wifi(config)
    -- wlan.connect 接收二进制 BSSID，配置里使用十六进制文本。
    local bssid
    if config.bssid and #config.bssid >= 12 then bssid = string.fromHex(config.bssid) end
    return wlan.connect(config.ssid, config.password, 1, bssid)
end

local function open_eth_spi(id)
    return spi.setup(id, nil, 0, 0, 8, 25600000) == 0
end

-- 仅 ETH 支持内置网卡（不配置 SPI）；失败时回收本次打开的 SPI 和供电。
local function open_eth_driver(adapter, config, power)
    if power then gpio.setup(power, 1, gpio.PULLUP) end
    local external = adapter == socket.LWIP_USER1 or config.tp ~= nil
    if external and not open_eth_spi(config.opts.spi) then
        if power then gpio.close(power) end
        return false
    end
    if not netdrv.setup(adapter, config.tp, config.opts) then
        if external then spi.close(config.opts.spi) end
        if power then gpio.close(power) end
        return false
    end
    return true
end

local function setup_eth(adapter, config)
    if config.auto_socket_switch ~= nil then auto_socket_switch = config.auto_socket_switch end
    if not open_eth_driver(adapter, config, config.pwrpin) then return false end
    available[adapter] = single_network_mode and connection_states.SINGLE_NETWORK or connection_states.OPENED
    if config.static_ip then
        sys.wait(1000) -- 驱动初始化后才能设置静态地址
        local ip = config.static_ip
        netdrv.ipv4(adapter, ip.ipv4, ip.mark, ip.gw)
    else
        netdrv.dhcp(adapter, true)
    end
    socket_state_detection(adapter)
    return true
end

-- 连接wifi(STA模式)
local function set_wifi_info(config)
    if config.auto_socket_switch ~= nil then
        auto_socket_switch = config.auto_socket_switch
    end
    log.info("WiFi名称:", config.ssid)
    log.info("ping_ip  :", config.ping_ip)
    wlan.init()
    if not single_network_mode then
        available[socket.LWIP_STA] = connection_states.OPENED
    else
        available[socket.LWIP_STA] = connection_states.SINGLE_NETWORK
    end
    if not connect_wifi(config) then
        available[socket.LWIP_STA] = connection_states.DISCONNECTED
        log.error("WiFi连接失败")
        return false
    end
    log.info("WiFi STA初始化完成")
    socket_state_detection(socket.LWIP_STA)
    return true
end

-- STOPPED 保留了驱动，只需恢复供电和 SPI，再启用 PHY。
local function restart_eth(adapter, config)
    if not can_switch_phy() then return false end
    if config.pwrpin then gpio.setup(config.pwrpin, 1, gpio.PULLUP) end
    if config.tp ~= nil and not open_eth_spi(config.opts.spi) then
        if config.pwrpin then gpio.close(config.pwrpin) end
        return false
    end
    if not netdrv.ctrl(adapter, netdrv.CTRL_UPDOWN, 1) then
        if config.tp then spi.close(config.opts.spi) end
        if config.pwrpin then gpio.close(config.pwrpin) end
        return false
    end
    available[adapter] = single_network_mode and connection_states.SINGLE_NETWORK or connection_states.OPENED
    return true
end

local function configure_eth(adapter, config)
    configure_probe(adapter, config)
    eth_cfg[adapter] = config
    if available[adapter] == connection_states.DISCONNECTED then
        return setup_eth(adapter, config)
    elseif available[adapter] == connection_states.STOPPED then
        return restart_eth(adapter, config)
    end
    return true
end

-- 预检整个有序列表，后面的网卡不受支持时不要先改动前面的网卡。
local function unsupported_wan(cfg)
    if cfg.WIFI and not (socket.LWIP_STA and wlan and wlan.connect) then return "WIFI" end
    if cfg.LWIP_GP and not (socket.LWIP_GP and mobile and mobile.flymode) then return "LWIP_GP" end
    if cfg.ETHERNET and not (socket.LWIP_ETH and netdrv and netdrv.setup) then return "ETHERNET" end
    if cfg.ETHUSER1 and not (socket.LWIP_USER1 and netdrv and netdrv.setup) then return "ETHUSER1" end
    if cfg.airlink_wifi or cfg.airlink_4G then
        if not (airlink and airlink.init and airlink.start and netdrv and netdrv.setup and netdrv.WHALE) then
            return "AirLink WHALE"
        end
        if cfg.airlink_wifi and not (socket.LWIP_STA and wlan and wlan.connect) then return "airlink_wifi" end
        if cfg.airlink_4G and not socket.LWIP_GP_GW then
            local uart = cfg.airlink_4G.airlink_type == airlink.MODE_UART
            if not (uart and cfg.airlink_4G.airlink_adapter) then return "airlink_4G" end
        end
    end
end

-- 旧式单实例 WHALE 网卡使用 airlink.init/start；固定网卡实例另走 airlink.setup。
local function start_legacy_airlink(config, adapter)
    if config.auto_socket_switch ~= nil then
        auto_socket_switch = config.auto_socket_switch
    end
    local mode = config.airlink_type
    if mode == airlink.MODE_SPI_MASTER or mode == airlink.MODE_SPI_SLAVE or mode == airlink.MODE_HSPI_MASTER then
        if config.airlink_spi_id then
            airlink.config(airlink.CONF_SPI_ID, config.airlink_spi_id)
        end
        if config.airlink_cs_pin then
            airlink.config(airlink.CONF_SPI_CS, config.airlink_cs_pin)
        end
        if config.airlink_rdy_pin then
            airlink.config(airlink.CONF_SPI_RDY, config.airlink_rdy_pin)
        end
        if config.airlink_spi_speed then
            airlink.config(airlink.CONF_SPI_SPEED, config.airlink_spi_speed)
        end
    elseif mode == airlink.MODE_UART and config.airlink_uart_id then
        uart.setup(config.airlink_uart_id, config.airlink_uart_baud or 2000000, 8, 1)
        airlink.config(airlink.CONF_UART_ID, config.airlink_uart_id)
    end
    airlink.init()
    netdrv.setup(adapter, netdrv.WHALE)
    airlink.start(mode)
end

local function setup_airlink_4G(config)
    -- UART 外挂 4G 可以指定 USER 网卡；SPI 沿用固定的 GP_GW。
    local adapter_id = socket.LWIP_GP_GW
    if config.airlink_type == airlink.MODE_UART and config.airlink_adapter then
        adapter_id = config.airlink_adapter
    end
    start_legacy_airlink(config, adapter_id)
    netdrv.ipv4(adapter_id, "192.168.111.1", "255.255.255.0", "192.168.111.2")
    socket_state_detection(adapter_id)
    return adapter_id
end

-- Air1601 WiFi硬件初始化
-- UART模式：拉高使能GPIO，配置UART3引脚（GPIO22/23）
-- SPI模式：仅拉高使能GPIO，不操作UART引脚
local function airlink_wifi_hardware_init(config)
    -- WiFi使能GPIO（需通过config.airlink_wifi_en_pin显式传入，无默认值）
    local wifi_en = nil
    if type(config.airlink_wifi_en_pin) == "number" then
        wifi_en = gpio.setup(config.airlink_wifi_en_pin, 0)
    end

    -- UART模式：将串口对应的GPIO设置为输入拉低模式，初始化完成后关闭
    if config.airlink_type == airlink.MODE_UART then
        -- 串口RX引脚（可通过config.airlink_wifi_uart_rx_pin自定义，不传则默认GPIO22）
        local uart_rx_pin = 22
        if type(config.airlink_wifi_uart_rx_pin) == "number" then
            uart_rx_pin = config.airlink_wifi_uart_rx_pin
        end
        -- 串口TX引脚（可通过config.airlink_wifi_uart_tx_pin自定义，不传则默认GPIO23）
        local uart_tx_pin = 23
        if type(config.airlink_wifi_uart_tx_pin) == "number" then
            uart_tx_pin = config.airlink_wifi_uart_tx_pin
        end
        gpio.setup(uart_rx_pin, nil, gpio.PULLDOWN)
        gpio.setup(uart_tx_pin, nil, gpio.PULLDOWN)
        sys.wait(1000)
        if wifi_en then wifi_en(1) end -- 拉高WiFi使能GPIO
        sys.wait(1000)
        -- 关闭串口对应的GPIO引脚功能
        gpio.close(uart_rx_pin)
        gpio.close(uart_tx_pin)
    else
        -- SPI模式：仅延时后拉高使能
        sys.wait(1000)
        if wifi_en then wifi_en(1) end -- 拉高WiFi使能GPIO
        sys.wait(1000)
    end
    log.info("airlink_wifi_hardware_init", "6205模组硬件初始化完成")
end

-- airlink_wifi网卡开启（Air1601  WiFi方案）
local function setup_airlink_wifi(config)
    airlink_wifi_hardware_init(config)
    start_legacy_airlink(config, socket.LWIP_STA)

    if not single_network_mode then
        available[socket.LWIP_STA] = connection_states.OPENED
    else
        available[socket.LWIP_STA] = connection_states.SINGLE_NETWORK
    end

    -- 初始化WiFi并连接路由器
    wlan.init()
    sys.wait(1000)
    log.info("WiFi名称:", config.ssid)
    if not connect_wifi(config) then
        log.error("WiFi连接失败")
        return false
    end
    log.info("airlink_wifi初始化完成")
    socket_state_detection(socket.LWIP_STA)

    return socket.LWIP_STA
end


--[[
设置默认出口的优先级。请在 task 中调用，数组第一项优先级最高。
@api exnetif.set_priority_order(networkConfigs)
@table networkConfigs 有序数组，每项配置一种网络：WIFI、ETHERNET、ETHUSER1、LWIP_GP、airlink_4G 或 airlink_wifi。
@return boolean 初始化成功返回 true；不表示网卡已取得 IP 或通过连通性探测。
@usage
-- 多网模式：Wi-Fi 优先，其次是外挂 CH390，最后是 4G。
-- 单网模式只传其中一项，不启动后台探测。仅用内置 4G 时可以不加载本库。
exnetif.set_priority_order({
    {WIFI = {ssid = "your_ssid", password = "your_password"}},
    {ETHERNET = {pwrpin = 140, tp = netdrv.CH390, opts = {spi = 1, cs = 12, irq = 19}}},
    {LWIP_GP = true},
})

-- 探测按网卡配置：默认用 HTTPDNS 解析 baidu.com；指定 ping_ip 后用 ICMP。
-- local_network_mode = true 时探测本机网关；need_ping = false 则只根据 IP 就绪判断。
-- ping_time 默认 10000 ms，用于探测间隔及 ICMP 超时。4G 参数与 LWIP_GP 同级。
-- auto_socket_switch 控制切换时是否关闭旧出口的 socket，是全局选项，默认 true。

-- 以太网默认使用 DHCP。Air8101 的内置 RMII 使用 ETHERNET，不填 tp、opts；
-- 外挂 SPI 网卡使用 ETHUSER1。静态地址的掩码字段沿用 mark。
exnetif.set_priority_order({
    {ETHUSER1 = {pwrpin = 13, tp = netdrv.CH390, opts = {spi = 0, cs = 15, irq = 18},
        static_ip = {ipv4 = "192.168.5.100", mark = "255.255.255.0", gw = "192.168.5.1"}}},
})

-- 旧式 AirLink：Air1601 经 UART 外挂 4G，Air8101 经 SPI 外挂 4G（二选一）。
exnetif.set_priority_order({{airlink_4G = {airlink_type = airlink.MODE_UART,
    airlink_uart_id = 3, airlink_uart_baud = 2000000, airlink_adapter = socket.LWIP_USER0}}})
exnetif.set_priority_order({{airlink_4G = {airlink_type = airlink.MODE_SPI_MASTER,
    airlink_spi_id = 0, airlink_cs_pin = 15, airlink_rdy_pin = 48}}})
-- Air1601 外挂 Wi-Fi 使用 airlink_wifi，同样填写传输参数，并提供 ssid、password。
-- 使能引脚按板型填写 airlink_wifi_en_pin；UART 的 RX/TX 引脚默认 22/23，可单独配置。
]]
function exnetif.set_priority_order(networkConfigs)
    if #networkConfigs < 1 then
        log.error("网络配置为空")
        return false
    end
    -- 缺少目标网卡时在启动任务、操作硬件前返回，保留正在工作的路由。
    for _, cfg in ipairs(networkConfigs) do
        local unsupported = unsupported_wan(cfg)
        if unsupported then
            log.error("exnetif", "当前固件不支持配置的网卡", unsupported)
            return false
        end
    end
    -- 在任何硬件初始化之前排除供网LAN及旧单实例AirLink初始化。
    if airlink_provider_controller then
        local lan = airlink_provider_controller.adapter
        for _, config in ipairs(networkConfigs) do
            assert(not config.airlink_4G and not config.airlink_wifi,
                "legacy AirLink cannot be mixed with an AirLink provider")
            assert(not ((config.WIFI and lan == socket.LWIP_STA)
                or (config.ETHERNET and lan == socket.LWIP_ETH)
                or (config.ETHUSER1 and lan == socket.LWIP_USER1)
                or (config.LWIP_GP and lan == socket.LWIP_GP)), "LAN cannot be an uplink")
        end
    end
    single_network_mode = #networkConfigs == 1

    if not single_network_mode and not priority_monitor_started then
        priority_monitor_started = true
        -- CONNECTING的网卡需要定时ping
        sys.taskInit(ping_test_loop)

        -- 循环ping检测正常网卡的任务，默认不启用
        sys.taskInit(normal_network_test)

        sys.subscribe("PING_RESULT", ping_res)
        -- 订阅网络状态变化的消息
        sys.subscribe("IP_READY", ip_ready_handle)
        sys.subscribe("IP_LOSE", ip_lose_handle)

    end

    local new_priority = {}
    -- 只有关闭状态的网卡需要初始化
    for _, config in ipairs(networkConfigs) do
        if type(config.WIFI) == "table" then
            configure_probe(socket.LWIP_STA, config.WIFI)
            if available[socket.LWIP_STA] == connection_states.DISCONNECTED then
                -- 开启wifi
                local res = set_wifi_info(config.WIFI)
                if res == false then
                    log.error("wifi连接失败")
                    return false
                end
            elseif current_wifi_ssid and current_wifi_ssid ~= config.WIFI.ssid then
                -- 增量更新：WiFi凭证变化，断开重连
                log.info("set_priority_order", "WiFi凭证变化，切换中:", current_wifi_ssid, "->", config.WIFI.ssid)
                wlan.disconnect()
                sys.wait(500)
                connect_wifi(config.WIFI)
            else
                log.info("wifi不是关闭状态，跳过初始化")
            end
            current_wifi_ssid = config.WIFI.ssid
            table.insert(new_priority, socket.LWIP_STA)
        end
        if type(config.ETHUSER1) == "table" then
            if not configure_eth(socket.LWIP_USER1, config.ETHUSER1) then return false end
            table.insert(new_priority, socket.LWIP_USER1)
        end
        if type(config.ETHERNET) == "table" then
            if not configure_eth(socket.LWIP_ETH, config.ETHERNET) then return false end
            table.insert(new_priority, socket.LWIP_ETH)
        end
        if config.LWIP_GP then
            configure_probe(socket.LWIP_GP, config)
            -- 退出飞行模式
            mobile.flymode(nil, false)
            -- 开启4G
            table.insert(new_priority, socket.LWIP_GP)
            if available[socket.LWIP_GP] ~= connection_states.CONNECTED then
                available[socket.LWIP_GP] = adapter_ready(socket.LWIP_GP)
                    and connection_states.CONNECTING or connection_states.OPENED
            end
            if config.auto_socket_switch ~= nil then
                auto_socket_switch = config.auto_socket_switch
            end
        end
        if type(config.airlink_4G) == "table" then
            -- airlink_4G
            local adapter_id = setup_airlink_4G(config.airlink_4G)
            table.insert(new_priority, adapter_id)
            if config.auto_socket_switch ~= nil then
                auto_socket_switch = config.auto_socket_switch
            end
            available[adapter_id] = connection_states.CONNECTED
            log.info("airlink_4G网卡已开启", adapter_id)
        end
        if type(config.airlink_wifi) == "table" then
            -- airlink_wifi（Air1601 WHALE WiFi方案）
            local adapter_id = setup_airlink_wifi(config.airlink_wifi)
            if adapter_id == false then
                log.error("airlink_wifi开启失败")
                return false
            end
            table.insert(new_priority, adapter_id)
            if config.auto_socket_switch ~= nil then
                auto_socket_switch = config.auto_socket_switch
            end
            log.info("airlink_wifi网卡已开启", adapter_id)
        end
    end

    -- 设置新优先级
    pending_probe = {}
    current_priority = new_priority
    priority_configured = true
    if not single_network_mode then
        for _, wan in ipairs(current_priority) do
            if available[wan] == connection_states.SINGLE_NETWORK or available[wan] == connection_states.OPENED then
                available[wan] = adapter_ready(wan) and connection_states.CONNECTING or connection_states.OPENED
            end
        end
    end
    -- 尚无探测结果时，默认使用配置的首选网卡，避免应用意外走固件默认的 4G。
    -- 若已有就绪出口，apply_priority 会立即恢复到实际可用的最高优先级网卡。
    socket.dft(new_priority[1])
    apply_priority()

    return true
end

--[[
设置网络状态变化回调函数。触发条件：网卡切换或者所有网卡都断网。回调函数的输入参数: 1. 当有可用网络的时候，返回当前使用网卡、网卡id；2. 当没有可用网络的时候，返回 nil、-1 。
@api exnetif.notify_status(cb_fnc)
@function 回调函数
@usage
    exnetif.notify_status(function(net_type,adapter)
    log.info("可以使用优先级更高的网络:", net_type,adapter)
    end)
]]
function exnetif.notify_status(cb_fnc)
    log.info("notify_status", type(cb_fnc))
    if type(cb_fnc) ~= "function" then
        log.error("notify_status设置错误，请传入一个函数")
        return
    end
    states_cbfnc = cb_fnc
end

-- 多网融合：上游连接、下游服务与代理生命周期

-- 代理模式下切换上游WiFi（内部函数，由 setproxy 和 proxy_sta_reconnect_task 调用）
local function switch_upstream_wifi(config)
    if type(config) ~= "table" or not config.ssid then
        log.error("switch_upstream_wifi", "参数错误")
        return false
    end
    if proxy_state.main_adapter ~= socket.LWIP_STA then
        log.error("switch_upstream_wifi", "当前不在WiFi上游代理模式")
        return false
    end

    local generation = proxy_generation

    log.info("switch_upstream_wifi", "关闭NAPT, 断开当前WiFi")
    netdrv.napt(-1)
    wlan.disconnect()
    sys.wait(2000)
    if generation ~= proxy_generation then return false end

    log.info("switch_upstream_wifi", "正在连接新WiFi:", config.ssid)
    connect_wifi(config)

    local count = 1
    while true do
        if generation ~= proxy_generation then return false end
        local ip = netdrv.ipv4(socket.LWIP_STA)
        if ip and ip ~= "0.0.0.0" then
            log.info("switch_upstream_wifi", "新WiFi已连接, IP:", ip)
            break
        end
        if count > 600 then
            log.error("switch_upstream_wifi", "新WiFi连接超时:", config.ssid)
            return false
        end
        sys.wait(100)
        count = count + 1
    end

    netdrv.napt(socket.LWIP_STA)
    log.info("switch_upstream_wifi", "NAPT已重新打开, 切换完成")

    return true
end

-- 代理模式下WiFi异常掉线重连任务
local function proxy_sta_reconnect_task(config, generation)
    while true do
        if generation ~= proxy_generation then return end
        local ok = switch_upstream_wifi(config)
        if generation ~= proxy_generation then return end
        if ok then
            log.info("exnetif", "上游WiFi重连成功")
            proxy_state.reconnecting = false
            break
        end
        log.error("exnetif", "上游WiFi重连失败，3秒后重试:", config.ssid)
        sys.wait(3000)
    end
end

-- 代理模式下WiFi掉线回调
local function on_proxy_sta_ip_lose(adapter)
    if adapter ~= socket.LWIP_STA then
        return
    end
    if not proxy_state.wifi_config or proxy_state.wifi_config.auto_reconnect == false
        or proxy_state.reconnecting or proxy_initializing then
        return
    end
    log.warn("exnetif", "检测到上游WiFi STA异常掉线，自动重连:", proxy_state.wifi_config.ssid)
    proxy_state.reconnecting = true
    sys.taskInit(proxy_sta_reconnect_task, proxy_state.wifi_config, proxy_generation)
end

local function wait_for_network(id, require_ip)
    for attempt = 0, 600 do
        if require_ip then
            local ip = netdrv.ipv4(id)
            if ip and ip ~= "" and ip ~= "0.0.0.0" then return true end
        elseif adapter_ready(id) then
            return true
        end
        if attempt < 600 then sys.wait(100) end
    end
    log.error("setproxy", "等待网卡超时", id)
    return false
end

local function open_proxy_eth(id, config)
    if config.irq and config.opts then config.opts.irq = config.irq end
    return open_eth_driver(id, config, config.ethpower_en)
end

local function release_proxy_eth(id, config)
    if can_switch_phy() then netdrv.ctrl(id, netdrv.CTRL_UPDOWN, 0) end
    if config.opts and config.opts.spi then spi.close(config.opts.spi) end
    if config.ethpower_en then gpio.close(config.ethpower_en) end
end

local function prepare_proxy_wan(id, config)
    if available[id] ~= connection_states.DISCONNECTED then return true end
    if id == socket.LWIP_ETH or id == socket.LWIP_USER1 then
        if not open_proxy_eth(id, config) then return false end
        netdrv.dhcp(id, true)
        if not wait_for_network(id, true) then
            release_proxy_eth(id, config)
            return false
        end
    elseif id == socket.LWIP_STA then
        wlan.init()
        wlan.setMode(wlan.APSTA)
        wlan.connect(config.ssid, config.password)
        if not wait_for_network(id, true) then return false end
    else
        return true -- 蜂窝 WAN 由底层管理
    end
    available[id] = connection_states.OPENED
    return true
end

local function prepare_proxy_lan(id, config)
    local addr, gw
    if id == socket.LWIP_ETH or id == socket.LWIP_USER1 then
        if not open_proxy_eth(id, config) then return false end
        sys.wait(1000) -- 等待驱动初始化，再写入静态地址
        addr, gw = config.adapter_addr or "192.168.5.1", config.adapter_gw or {192,168,5,1}
    elseif id == socket.LWIP_AP then
        wlan.setMode(wlan.APSTA)
        addr, gw = config.adapter_addr or "192.168.4.1", config.adapter_gw
        wlan.createAP(config.ssid, config.password, addr, "255.255.255.0", config.channel, config.ap_opts)
    else
        return false
    end
    netdrv.ipv4(id, addr, "255.255.255.0", "0.0.0.0")
    local server
    if wait_for_network(id, false) then server = dhcpsrv.create({adapter=id, gw=gw}) end
    if not server then
        if id == socket.LWIP_AP then wlan.stopAP() else release_proxy_eth(id, config) end
        return false
    end
    table.insert(proxy_state.dhcp_servers, server)
    return true
end

local function setproxy(adapter, main_adapter, other_configs)
    -- 代理已存在检测：同一 adapter+main_adapter 组合再次调用时，跳过重复初始化
    if proxy_state.main_adapter == main_adapter then
        for _, a in ipairs(proxy_state.proxy_adapters) do
            if a == adapter then
                if main_adapter == socket.LWIP_STA and other_configs.main_adapter then
                    local old, new = proxy_state.wifi_config, other_configs.main_adapter
                    -- 保留主线语义：省略密码/自动重连选项时沿用旧配置。
                    new = {ssid = new.ssid, password = new.password,
                        bssid = new.bssid, auto_reconnect = new.auto_reconnect}
                    if old then
                        if new.password == nil then new.password = old.password end
                        if new.auto_reconnect == nil then new.auto_reconnect = old.auto_reconnect end
                    end
                    if not old or old.ssid ~= new.ssid or old.password ~= new.password or old.bssid ~= new.bssid then
                        log.info("setproxy", "检测到上游WiFi变化，切换中")
                        proxy_generation = proxy_generation + 1
                        proxy_state.wifi_config, proxy_state.reconnecting = nil, false
                        if not switch_upstream_wifi(new) then
                            -- 切换期间IP_LOSE被抑制，失败后主动恢复旧连接。
                            proxy_state.wifi_config = old
                            if old and old.auto_reconnect ~= false then
                                proxy_state.reconnecting = true
                                sys.taskInit(proxy_sta_reconnect_task, old, proxy_generation)
                            end
                            return false
                        end
                        proxy_state.wifi_config = {ssid = new.ssid, password = new.password,
                            bssid = new.bssid, auto_reconnect = new.auto_reconnect}
                    else
                        log.info("setproxy", "代理已存在且凭证未变，跳过")
                    end
                else
                    log.info("setproxy", "代理已存在，跳过")
                end
                return true
            end
        end
    end

    if not prepare_proxy_wan(main_adapter, other_configs.main_adapter) then return false end
    if not prepare_proxy_lan(adapter, other_configs) then return false end
    dnsproxy.setup(adapter, main_adapter)
    netdrv.napt(main_adapter)
    -- 保存多网融合状态，供 close(true) 清理
    proxy_state.proxy_adapters[#proxy_state.proxy_adapters + 1] = adapter
    proxy_state.main_adapter = main_adapter
    if main_adapter == socket.LWIP_STA then
        local wifi = other_configs.main_adapter
        proxy_state.wifi_config = {ssid = wifi.ssid, password = wifi.password, bssid = wifi.bssid,
            auto_reconnect = wifi.auto_reconnect}
        sys.subscribe("IP_LOSE", on_proxy_sta_ip_lose)
        log.info("exnetif", "已启用上游WiFi自动重连")
    end
    return true
end

--[[
设置多网融合模式，例如4G作为数据出口给WIFI或以太网设备上网(需要在task中调用)
@api exnetif.setproxy(adapter, main_adapter,other_configs)
@adapter 需要使用网络的网卡，例如socket.LWIP_ETH
@adapter 提供网络的网卡，例如socket.LWIP_GP
@table 其他设置参数(选填参数)，
@usage
    典型应用：
    -- 以太网WAN提供网络其他设备连接以太网LAN口上网
    exnetif.setproxy(socket.LWIP_ETH, socket.LWIP_USER1, {
            ethpower_en = 20,-- 以太网模块的pwrpin引脚(gpio编号)
            tp = netdrv.CH390, -- 网卡芯片型号(选填参数)，仅spi方式外挂以太网时需要填写。
            opts = {spi = 0, cs = 8, irq = 19}, -- 外挂方式,需要额外的参数(选填参数)，仅spi方式外挂以太网时需要填写。irq为中断引脚(选填参数)，配置后可使用中断模式提高响应速度
            main_adapter = {
                ethpower_en = 21,-- 以太网模块的pwrpin引脚(gpio编号)
                tp = netdrv.CH390, -- 网卡芯片型号(选填参数)，仅spi方式外挂以太网时需要填写。
                opts = {spi = 1, cs = 12, irq = 20} -- irq为中断引脚(选填参数)，配置后可使用中断模式提高响应速度
            }
        })
    -- wifi_sta提供网络开启wifi_ap热点供设备上网
    exnetif.setproxy(socket.LWIP_AP, socket.LWIP_STA, {
            ssid = "test2",                  -- AP热点名称(string)，网卡包含wifi时填写
            password = "HZ88888888",         -- AP热点密码(string)，网卡包含wifi时填写
            ap_opts = {                      -- AP模式下配置项(选填参数)
                hidden = false,              -- 是否隐藏SSID, 默认false,不隐藏
                max_conn = 4 },              -- 最大客户端数量, 默认4
            channel = 6,                     -- AP建立的通道, 默认6
            main_adapter = {
                ssid = "test",                -- 提供网络的网卡开启参数
                password = "HZ88888888"
            }
        })
    -- 4G提供网络开启wifi_ap热点供设备上网,其他设备连接以太网LAN口上网
    exnetif.setproxy(socket.LWIP_AP, socket.LWIP_GP, {
        ssid = "Hotspot",                -- WiFi名称(string)，网卡包含wifi时填写
        password = "password123",        -- WiFi密码(string)，网卡包含wifi时填写
        adapter_addr = "192.168.5.1",    -- adapter网卡的ip地址(选填),需要自定义ip和网关ip时填写
        adapter_gw= { 192, 168, 5, 1 },   -- adapter网卡的网关地址(选填),需要自定义ip和网关ip时填写
        ap_opts={                        -- AP模式下配置项(选填参数)
        hidden = false,                  -- 是否隐藏SSID, 默认false,不隐藏
        max_conn = 4 },                  -- 最大客户端数量, 默认4
        channel=6                        -- AP建立的通道, 默认6
    })
    exnetif.setproxy(socket.LWIP_ETH, socket.LWIP_GP, {
        tp = netdrv.CH390,               -- 网卡芯片型号(选填参数)，仅spi方式外挂以太网时需要填写。
        opts = { spi = 1, cs = 12, irq = 19}, -- 外挂方式,需要额外的参数(选填参数)，仅spi方式外挂以太网时需要填写。irq为中断引脚(选填参数)，配置后可使用中断模式提高响应速度
        ethpower_en = 140,               -- 以太网模块的pwrpin引脚(gpio编号)
        adapter_addr = "192.168.5.1",    -- adapter网卡的ip地址(选填),需要自定义ip和网关ip时填写
        adapter_gw= { 192, 168, 5, 1 },   -- adapter网卡的网关地址(选填),需要自定义ip和网关ip时填写
    })
    -- 以太网提供网络供WiFi设备上网
    exnetif.setproxy(socket.LWIP_AP, socket.LWIP_ETH, {
        ssid = "Hotspot",                -- WiFi名称(string)，网卡包含wifi时填写
        password = "password123",        -- WiFi密码(string)，网卡包含wifi时填写
        main_adapter={
            tp = netdrv.CH390,               -- 网卡芯片型号(选填参数)，仅spi方式外挂以太网时需要填写。
            opts = { spi = 1, cs = 12, irq = 20}, -- 外挂方式,需要额外的参数(选填参数)，仅spi方式外挂以太网时需要填写。irq为中断引脚(选填参数)，配置后可使用中断模式提高响应速度
            ethpower_en = 140,               -- 以太网模块的pwrpin引脚(gpio编号)
        }
    })
    -- WIFI提供网络供以太网设备上网
    exnetif.setproxy(socket.LWIP_ETH, socket.LWIP_STA, {
        tp = netdrv.CH390,               -- 网卡芯片型号(选填参数)，仅spi方式外挂以太网时需要填写。
        opts = { spi = 1, cs = 12, irq = 19}, -- 外挂方式,需要额外的参数(选填参数)，仅spi方式外挂以太网时需要填写。irq为中断引脚(选填参数)，配置后可使用中断模式提高响应速度
        ethpower_en = 140,               -- 以太网模块的pwrpin引脚(gpio编号)
        main_adapter = {
            ssid = "test",                -- 提供网络的网卡开启参数
            password = "HZ88888888"
        }
    })
]]
function exnetif.setproxy(adapter, main_adapter, other_configs)
    assert(proxy_owner ~= "airlink", "AirLink provider owns NAPT/DNS; use its controller")
    if adapter == nil or main_adapter == nil or not (netdrv and netdrv.ipv4 and netdrv.napt)
        or not (netdrv.ready or socket.adapter) then
        log.error("exnetif", "当前固件缺少代理网卡、NAPT 或网卡就绪接口")
        return false
    end
    if proxy_initializing then return false end
    -- 初始化可能yield，提前保留所有权；完成前不允许close释放给另一控制器。
    proxy_owner, proxy_initializing = "proxy", true
    local ok, result = pcall(function()
        dnsproxy = dnsproxy or require("dnsproxy")
        dhcpsrv = dhcpsrv or require("dhcpsrv")
        return setproxy(adapter, main_adapter, other_configs)
    end)
    proxy_initializing = false
    if not ok then error(result, 0) end
    return result
end

--[[
关闭网卡功能。(内核固件版本支持情况：Air8000系列模组对应V2022版本及以后版本，Air780/700 系列模组对应V2024及以后版本，Air1601/1602系列模组对应V1008版本及以后版本,Air8101 系列模组对应V2002及以后版本)
@api exnetif.close(type,adapter)
@param type boolean 是否为多网融合(true=关闭多网融合, false=关闭单个网卡)
AirLink provider模式下true表示同步暂停供网，使用返回控制器的enable(true)恢复。
setproxy初始化尚未结束时返回false，应在初始化结束后再关闭。
@param adapter number 需要关闭的网卡，可选值: socket.LWIP_ETH/LWIP_USER1/LWIP_STA/LWIP_AP/LWIP_GP/LWIP_GP_GW
     各网卡关闭行为:
       LWIP_ETH   -> 先停PHY，再按配置拉低供电、关闭SPI；停用失败保留网卡状态
       LWIP_USER1 -> 同LWIP_ETH
       LWIP_STA   -> wlan.disconnect() 断开WiFi连接
       LWIP_AP    -> wlan.stopAP() 停止热点
       LWIP_GP    -> mobile.flymode(nil,true) 进飞行模式
       LWIP_GP_GW -> 仅设状态 DISCONNECTED + apply_priority，无硬件操作（airlink无独立stop接口）
     关闭后恢复: 重新调用 set_priority_order 将网卡加入优先级列表
@return boolean 操作结果
@usage
    exnetif.close(true) --关闭多网融合功能（停止DHCP服务器、DNS代理、NAPT，恢复各网卡独立状态）
    exnetif.close(false,socket.LWIP_ETH)  --关闭以太网网卡
    exnetif.close(false,socket.LWIP_AP)   --关闭WiFi AP热点
    exnetif.close(false,socket.LWIP_STA)  --关闭WiFi STA
    exnetif.close(false,socket.LWIP_GP)   --关闭4G（飞行模式）
]]
function exnetif.close(type, adapter)
    if type == true then
        if airlink_provider_controller then
            return stop_airlink_provider()
        end
        if proxy_initializing then return false end
        -- 取消仍在等待WiFi的旧代理重连任务，防止其晚到后重开NAPT。
        proxy_generation = proxy_generation + 1
        -- 关闭多网融合：停止 DHCP 服务器、DNS 代理、NAPT，恢复各网卡独立状态
        log.info("exnetif", "关闭多网融合功能")

        -- 1. 停止所有 DHCP 服务器
        if #proxy_state.dhcp_servers > 0 then
            for _, srv in ipairs(proxy_state.dhcp_servers) do
                dhcpsrv.stop(srv)
            end
            proxy_state.dhcp_servers = {}
            log.info("exnetif", "DHCP 服务器已全部停止")
        end

        -- 2. 关闭 DNS 代理
        if dnsproxy then dnsproxy.close() end
        log.info("exnetif", "DNS 代理已关闭")

        -- 3. 禁用 NAPT
        if proxy_state.main_adapter then
            netdrv.napt(-1)
            log.info("exnetif", "NAPT 已禁用")
        end

        -- 4. 关闭所有使用网络的网卡服务（AP 停止热点，ETH/USER1 关闭 PHY）
        for _, adapter in ipairs(proxy_state.proxy_adapters) do
            if adapter == socket.LWIP_AP then
                wlan.stopAP()
                log.info("exnetif", "AP 热点已停止")
            elseif adapter == socket.LWIP_ETH or adapter == socket.LWIP_USER1 then
                if can_switch_phy() then
                    netdrv.ctrl(adapter, netdrv.CTRL_UPDOWN, 0)
                    log.info("exnetif", "以太网 PHY 已关闭 (adapter=" .. tostring(adapter) .. ")")
                end
            end
        end

        -- 5. 清理状态记录
        proxy_state.proxy_adapters = {}
        proxy_state.main_adapter = nil
        proxy_state.wifi_config = nil
        proxy_state.reconnecting = false
        proxy_owner = nil

        return true
    else
        if adapter == nil then
            log.error("请指定需要关闭的网卡")
            return false
        end
        local ethernet = adapter == socket.LWIP_ETH or adapter == socket.LWIP_USER1
        -- 有些固件提供 ctrl，但具体驱动未实现 UPDOWN；先确认 PHY 已停再释放 SPI。
        if ethernet and not (can_switch_phy() and netdrv.ctrl(adapter, netdrv.CTRL_UPDOWN, 0)) then
            log.error("exnetif", "以太网停用失败，检查固件和驱动是否支持 CTRL_UPDOWN")
            return false
        end
        -- 处理关闭操作，以太网关闭spi和供电使能。WLAN部分AP可以关闭，STA可以断开连接。4G的话就是进出飞行模式。并设置网卡为关闭状态。
        pending_probe[adapter] = nil
        available[adapter] = connection_states.DISCONNECTED
        if adapter == socket.LWIP_AP then
            wlan.stopAP()
        elseif ethernet then
            local cfg = eth_cfg[adapter] or {}
            if cfg.pwrpin then
                gpio.set(cfg.pwrpin, 0)
                gpio.close(cfg.pwrpin)
            end
            if cfg.opts and cfg.opts.spi then
                -- 关闭spi
                spi.close(cfg.opts.spi)
            end
            available[adapter] = connection_states.STOPPED
        elseif adapter == socket.LWIP_STA then
            wlan.disconnect()
        elseif adapter == socket.LWIP_GP then
            mobile.flymode(nil, true)
        elseif adapter == socket.LWIP_GP_GW then
            -- airlink 4G 网卡：无底层硬件关闭操作
            -- airlink 是共享 UART 桥梁，没有独立 stop 接口
            -- 仅通过 available[gp_gw]=DISCONNECTED + apply_priority() 实现网卡切换
        end
        log.info("exnetif", "关闭网卡功能", type_to_string(adapter))
        apply_priority()
        return true
    end
end

local function setup_airlink_netif(id, role, opts)
    assert(airlink and airlink.setup and netdrv and netdrv.ipv4, "firmware lacks AirLink netif setup")
    if role == "provider" then
        assert(airlink.netstate and netdrv.napt and (netdrv.ready or socket.adapter),
            "firmware lacks AirLink provider netstate/NAPT/readiness")
    else
        assert(socket.setDNS, "firmware lacks AirLink client DNS support")
    end
    local mode = opts.mode or airlink.MODE_UART
    assert(mode == airlink.MODE_UART or mode == airlink.MODE_SPI_MASTER or mode == airlink.MODE_SPI_SLAVE,
        "AirLink netif requires UART, SPI master or SPI slave")
    local adapter = opts.adapter or socket.LWIP_GP_GW
    assert(adapter ~= nil, "AirLink netif requires an available adapter")
    if mode ~= airlink.MODE_UART then
        assert(opts.spi_id ~= nil and opts.cs ~= nil and opts.rdy ~= nil,
            "SPI netif requires spi_id, cs and rdy")
    end
    local ok, rc = airlink.setup(id, {
        drv = "netif", role = role, mode = mode,
        uart_id = opts.uart_id or 1, baudrate = opts.baudrate or 2000000,
        spi_id = opts.spi_id, cs = opts.cs, rdy = opts.rdy, speed = opts.speed,
        network_adapter = adapter
    })
    assert(ok, "airlink netif setup failed: " .. tostring(rc))
    return adapter
end

--[[
创建AirLink用网端，固定地址在出口变化和断链时保留。支持UART和SPI。
@api exnetif.airlink_client(id, opts)
@param number 实例ID，Air1602通常为0
@param table 可选配置：uart_id=1, baudrate=2000000, adapter=socket.LWIP_GP_GW,
ip="192.168.111.1", mask="255.255.255.0", gateway="192.168.111.2", default=true
mode默认airlink.MODE_UART；SPI需配置mode、spi_id、cs、rdy，speed为1~20MHz。
SPI主机/从机与client/provider角色独立；当前SPI从机适配EC718M平台。
@return number 固定网卡adapter；gateway同时作为首选DNS
@usage
local adapter = exnetif.airlink_client(0, {uart_id=1})
]]
function exnetif.airlink_client(id, opts)
    opts = opts or {}
    local adapter = setup_airlink_netif(id, "client", opts)
    local gateway = opts.gateway or "192.168.111.2"
    netdrv.ipv4(adapter, opts.ip or "192.168.111.1", opts.mask or "255.255.255.0", gateway)
    socket.setDNS(adapter, 1, gateway)
    if opts.default ~= false then socket.dft(adapter) end
    return adapter
end

--[[
创建AirLink供网端，需要在task中调用。支持UART和SPI，独占全局NAPT/DNS。
@api exnetif.airlink_provider(id, opts)
@param number 实例ID，Air8000板内实例0保留，对外供网通常使用1
@param table 可选配置：uart_id=1, baudrate=2000000, adapter=socket.LWIP_GP_GW,
ip="192.168.111.2", mask="255.255.255.0", dns="119.29.29.29",
priority={socket.LWIP_STA,socket.LWIP_GP}
mode默认airlink.MODE_UART；SPI需配置mode、spi_id、cs、rdy，speed为1~20MHz。
Air8000保留板内SPI0，对外从机使用独立SPI1、硬件CS12和空闲RDY GPIO。
@return table 控制器：adapter、uplink（无出口为nil）、enable(false/true)暂停/恢复
@usage
-- WAN由应用初始化；调用过set_priority_order后，忽略opts.priority并跟随本库选路。
-- 未调用set_priority_order时，按opts.priority选择ready且IPv4有效的WAN，不检测公网。
local gateway = exnetif.airlink_provider(1, {uart_id=1})
-- exnetif.close(true)同步暂停供网；gateway.enable(true)恢复，无需重新setup。
-- 暂停期间仍保留NAPT/DNS所有权，不能再调用setproxy。
]]
function exnetif.airlink_provider(id, opts)
    assert(not proxy_owner, "NAPT/DNS is already owned by a proxy or AirLink provider")
    opts = opts or {}
    local priority = opts.priority or {socket.LWIP_STA, socket.LWIP_GP}
    local adapter = opts.adapter or socket.LWIP_GP_GW
    local candidates = priority_configured and current_priority or priority
    assert(#candidates > 0, "priority must contain an uplink")
    for _, wan in ipairs(candidates) do
        assert(wan ~= adapter, "LAN cannot be an uplink")
    end
    setup_airlink_netif(id, "provider", opts)
    proxy_owner = "airlink"
    local ip = opts.ip or "192.168.111.2"
    netdrv.ipv4(adapter, ip, opts.mask or "255.255.255.0", ip)
    dnsproxy = dnsproxy or require("dnsproxy")
    -- 由本控制器统一管理LAN/选定WAN，忽略其他网卡的IP_READY。
    sys.unsubscribe("IP_READY", dnsproxy.on_ip_ready)
    local controller = {adapter = adapter, uplink = nil}
    airlink_provider_controller = controller
    local enabled, changed = true, true
    local last_key
    -- socket.close没有Lua可见的完成屏障，保持引用并复用控件。
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
    local function withdraw()
        airlink.netstate(id, -1)
        local cleared = netdrv.napt(-1)
        close_dns()
        controller.uplink, last_key = nil, nil
        return cleared
    end
    stop_airlink_provider = function()
        controller.enable(false)
        local cleared = withdraw()
        changed = not cleared
        return cleared
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
            if enabled and adapter_ready(adapter) then
                local uplinks = priority
                if priority_configured then
                    -- 单网模式不启动探测任务；多网模式必须使用已探测选定的出口。
                    uplinks = single_network_mode and current_priority or {current_active}
                end
                for _, wan in ipairs(uplinks) do
                    local usable = not priority_configured
                        or (single_network_mode and available[wan] ~= connection_states.DISCONNECTED
                            and available[wan] ~= connection_states.STOPPED)
                        or (not single_network_mode and available[wan] == connection_states.CONNECTED)
                    if wan ~= adapter and usable and adapter_ready(wan) then
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
                -- 先撤销供网，再清理映射；同一WAN地址变化/断线也需要重建。
                local cleared = withdraw()
                if selected and cleared then
                    if not priority_configured then socket.dft(selected) end
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
                log.info("exnetif", "airlink uplink", controller.uplink or -1)
            end
            sys.wait(500)
        end
    end)
    return controller
end

--[[
获取库版本信息
@api exnetif.version()
@return string 年月日时分
@usage
exnetif.version()
]]
function exnetif.version()
    return "202611181800"
end

log.debug("exnetif", "version -> " .. exnetif.version())

return exnetif
