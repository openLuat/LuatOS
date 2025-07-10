--[[
@module libnetif
@summary libnetif 控制网络优先级（以太网->WIFI->4G）根据优先级选择上网的网卡。简化开启多网融合的操作，4G作为数据出口给WIFI,以太网设备上网，以太网作为数据出口给WIFI,Air8000上网，WIFI作为数据出口给Air8000,以太网上网。
@version 1.0
@date    2025.06.26
@author  wjq
]]
local libnetif = {}

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpdns = require("httpdns")
-- 设置pingip
local wifi_ping_ip
local eth_ping_ip


local ping_time = 10000
-- 连接状态
local connection_states = {
    DISCONNECTED = 0,
    CONNECTING = 1,
    CONNECTED = 2,
    OPENED = 3
}

-- 状态回调函数
local states_cbfnc = function(net_type) end
-- 当前优先级
local current_priority = { socket.LWIP_ETH, socket.LWIP_STA, socket.LWIP_GP }
-- 连接状态
local available = {
    [socket.LWIP_STA] = connection_states.DISCONNECTED,
    [socket.LWIP_ETH] = connection_states.DISCONNECTED,
    [socket.LWIP_GP] = connection_states.DISCONNECTED
}
-- 当前使用的网卡
local current_active = socket.LWIP_USER0

-- 网络类型转字符串
local function typeToString(net_type)
    local type_map = {
        [socket.LWIP_STA] = "WiFi",
        [socket.LWIP_ETH] = "Ethernet",
        [socket.LWIP_GP] = "4G"
    }
    return type_map[net_type] or "Unknown"
end

-- 状态更改后重新设置默认网卡
local function applyPriority()
    -- 查找优先级最高的可用网络
    for _, net_type in ipairs(current_priority) do
        -- log.info("网卡顺序",typeToString(net_type),available[net_type])
        if available[net_type] == connection_states.CONNECTED then
            -- 设置优先级高的网卡
            log.info("设置网卡", typeToString(net_type))
            if current_active ~= net_type then
                if current_active ~= socket.LWIP_USER0 then
                    states_cbfnc(typeToString(net_type)) -- 默认网卡改变的回调函数
                end
                socket.dft(net_type)
                current_active = net_type
            end
            break
        end
    end
end

--打开以太网Wan功能
local function setupETH(config)
    eth_ping_ip = config.ping_ip
    if type(config.ping_time) == "number" then
        ping_time = config.ping_time
    end
    log.info("初始化以太网")
    -- 打开CH390供电
    gpio.setup(config.pwrpin, 1, gpio.PULLUP)
    sys.wait(100)

    if config.mode == "Air8101" then
        log.info("8101以太网")
        netdrv.setup(socket.LWIP_ETH)
    else
        -- 配置SPI和初始化网络驱动
        local result = spi.setup(1, -- spi id
        nil, 0, -- CPHA
        0, -- CPOL
        8, -- 数据宽度
        51200000 -- ,--波特率
        )
        log.info("main", "open spi", result)
        if result ~= 0 then -- 返回值为0，表示打开成功
            log.info("main", "spi open error", result)
            gpio.close(config.pwrpin)
            return false
        end
        -- 初始化指定netdrv设备,
        -- socket.LWIP_ETH 网络适配器编号
        -- netdrv.CH390外挂CH390
        -- SPI ID 1, 片选 GPIO12
        netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {spi = 1, cs = 12})
    end
    netdrv.dhcp(socket.LWIP_ETH, true)
    available[socket.LWIP_ETH] = connection_states.OPENED
    log.info("以太网初始化完成")
    return true
end


--连接wifi(STA模式)
local function setWifiInfo(config)
    wifi_ping_ip = config.ping_ip
    if type(config.ping_time) == "number" then
        ping_time = config.ping_time
    end
    log.info("WiFi名称:", config.ssid)
    log.info("密码     :", config.password)
    log.info("ping_ip  :", config.ping_ip)
    wlan.init()

    -- 尝试连接Wi-Fi，并处理可能出现的错误
    local success = wlan.connect(config.ssid, config.password)
    if not success then
        log.error("WiFi连接失败")
        return false
    end
    available[socket.LWIP_STA] = connection_states.OPENED
    log.info("WiFi STA初始化完成")
    return true
end

--[[
设置网络优先级
@api libnetif.setPriorityOrder(new_priority)
@table 网络优先级列表
@return boolean 成功返回true，失败返回false
@usage
libnetif.setPriorityOrder({
    { -- 最高优先级网络
        WIFI = { -- WiFi配置
            ssid = "your_ssid",       -- WiFi名称(string)
            password = "your_pwd",    -- WiFi密码(string)
            ping_ip = "192.168.1.1",  -- 连通性检测IP(string),根据需要设置外网或局域网ip
            ping_time = 10000         -- 检测间隔(ms, 可选，默认为10秒)
        }
    },
    { -- 次优先级网络
        ETHERNET = { -- 以太网配置
            pwrpin = 140,             -- 供电使能引脚(number)
            ping_ip = "192.168.1.1",  -- 连通性检测IP(string)，根据需要设置外网或局域网ip
            ping_time = 10000         -- 检测间隔(ms, 可选,默认为10秒)
        }
    },
    { -- 最低优先级网络
        LWIP_GP = true  -- 启用4G网络
    }
})
]]
function libnetif.setPriorityOrder(networkConfigs)
    local new_priority = {}
    for _, config in ipairs(networkConfigs) do
        if type(config.WIFI) == "table" then
            --开启wifi
            local res = setWifiInfo(config.WIFI)
            if res == false then
                log.error("wifi连接失败")
                return false
            end
            table.insert(new_priority, socket.LWIP_STA)
        end
        if type(config.ETHERNET) == "table" then
            --开启以太网
            local res = setupETH(config.ETHERNET)
            if res == false then
                log.error("以太网打开失败")
                return false
            end
            table.insert(new_priority, socket.LWIP_ETH)
        end
        if config.LWIP_GP then
            --开启4G
            table.insert(new_priority, socket.LWIP_GP)
        end
    end

    -- 设置新优先级
    current_priority = new_priority
    applyPriority()

    return true
end

--[[
设置网络状态变化回调函数
@api libnetif.notifyStatus(cb_fnc)
@function 回调函数
@usage
    libnetif.notifyStatus(function(net_type)
    log.info("可以使用优先级更高的网络:", net_type)
    end)
]]
function libnetif.notifyStatus(cb_fnc)
    log.info("notifyStatus", type(cb_fnc))
    if type(cb_fnc) ~= "function" then
        log.error("notifyStatus设置错误，请传入一个函数")
        return
    end
    states_cbfnc = cb_fnc
end

--[[
设置多网融合模式，例如4G作为数据出口给WIFI或以太网设备上网
@api libnetif.setproxy(adapter, main_adapter, ssid, password, power_en)
@adapter 需要使用网络的网卡，例如socket.LWIP_ETH
@adapter 提供网络的网卡，例如socket.LWIP_GP
@string wifi名称，没有用到wifi可不填
@string wifi密码，没有用到wifi可不填
@int 以太网模块的供电使能引脚（gpio编号），没有用到以太网模块可不填
@usage
    libnetif.setproxy(socket.LWIP_AP,socket.LWIP_ETH,"test","HZ88888888",140)
]]
function libnetif.setproxy(adapter, main_adapter, ssid, password, power_en)
    if adapter == socket.LWIP_ETH then
        log.info("ch390", "打开LDO供电", power_en)
        gpio.setup(power_en, 1, gpio.PULLUP)
        -- 打开LAN功能
        -- sys.wait(3000)
        -- 配置 SPI 参数，Air8000 使用 SPI 接口与以太网模块进行通信。
        local result = spi.setup(1, -- spi id
            nil, 0,                 -- CPHA
            0,                      -- CPOL
            8,                      -- 数据宽度
            51200000                -- ,--波特率
        )
        log.info("main", "open spi", result)
        if result ~= 0 then -- 返回值为 0，表示打开成功
            log.error("main", "spi open error", result)
            gpio.close(power_en)
            return false
        end
        -- 初始化以太网，Air8000 指定使用 CH390 芯片。
        log.info("netdrv", "初始化以太网")
        netdrv.setup(socket.LWIP_ETH, netdrv.CH390, { spi = 1, cs = 12, irq = 255 })
        log.info("netdrv", "等待以太网就绪")
        sys.wait(1000)
        -- 设置以太网的 IP 地址、子网掩码、网关地址
        netdrv.ipv4(socket.LWIP_ETH, "192.168.5.1", "255.255.255.0", "0.0.0.0")
        -- 获取以太网网络状态，连接后返回 true，否则返回 false，如果不存在就返回 nil。
        local count = 1
        while netdrv.ready(socket.LWIP_ETH) ~= true do
            if count > 600 then
                log.error("以太网连接超时，请检查配置")
                gpio.close(power_en)
                return false
            end
            count = count + 1
            -- log.info("netdrv", "等待以太网就绪") -- 若以太网设备没有连上，可打开此处注释排查。
            sys.wait(100)
        end
        log.info("netdrv", "以太网就绪")
        -- 创建 DHCP 服务器，为连接到以太网的设备分配 IP 地址。
        log.info("netdrv", "创建dhcp服务器, 供以太网使用")
        dhcpsrv.create({ adapter = socket.LWIP_ETH, gw = { 192, 168, 5, 1 } })
        -- 创建 DNS 代理服务，使得以太网接口上的设备可以通过 4G 网络访问互联网。
        log.info("netdrv", "创建dns代理服务, 供以太网使用")
    elseif adapter == socket.LWIP_AP then
        wlan.setMode(wlan.APSTA)
        -- 打开AP功能，设置混合模式
        log.info("执行AP创建操作", airlink.ready(), "正常吗?")
        -- 设置 WiFi 热点的名称和密码
        if type(ssid)  then
            
        end
        wlan.createAP(ssid, password)
        -- 设置 AP 的 IP 地址、子网掩码、网关地址
        netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "0.0.0.0")
        -- 获取 WiFi AP 网络状态，连接后返回 true，否则返回 false，如果不存在就返回 nil。
        log.info("netdrv", "等待AP就绪")
        local count = 1
        while netdrv.ready(socket.LWIP_AP) ~= true do
            -- log.info("netdrv", "等待AP就绪")
            if count > 600 then
                log.error("AP创建超时，请检查配置")
                return false
            end
            sys.wait(100)
            count = count + 1
        end
        -- 创建 DHCP 服务器，为连接到 WiFi AP 的设备分配 IP 地址。
        log.info("netdrv", "创建dhcp服务器, 供AP使用")
        dhcpsrv.create({ adapter = socket.LWIP_AP })


        log.info("netdrv", "创建dns代理服务, 供AP使用")
    end


    if main_adapter == socket.LWIP_ETH and available[socket.LWIP_ETH] == connection_states.DISCONNECTED then
        -- 打开WAN功能
        log.info("ch390", "打开LDO供电", power_en)
        -- wlan.disconnect()
        gpio.setup(power_en, 1, gpio.PULLUP) -- 打开ch390供电
        sys.wait(100)
        local result = spi.setup(1,          -- spi_id
            nil, 0,                          -- CPHA
            0,                               -- CPOL
            8,                               -- 数据宽度
            25600000                         -- ,--频率
        -- spi.MSB,--高低位顺序    可选，默认高位在前
        -- spi.master,--主模式     可选，默认主
        -- spi.full--全双工       可选，默认全双工
        )
        log.info("main", "open", result)
        if result ~= 0 then -- 返回值为0，表示打开成功
            log.info("main", "spi open error", result)
            gpio.close(power_en)
            return false
        end
        local success = netdrv.setup(socket.LWIP_ETH, netdrv.CH390, { spi = 1, cs = 12 })
        if not success then
            log.error("以太网初始化失败")
            return false
        end
        netdrv.dhcp(socket.LWIP_ETH, true)
        local count = 1
        while 1 do
            local ip = netdrv.ipv4(socket.LWIP_ETH)
            if ip and ip ~= "0.0.0.0" then break end
            if count > 600 then
                log.error("以太网连接超时，请检查配置")
                gpio.close(power_en)
                return false
            end
            sys.wait(100)
            count = count + 1
        end
    elseif main_adapter == socket.LWIP_STA and available[socket.LWIP_STA] == connection_states.DISCONNECTED then
        -- 打开STA功能，设置混合模式
        wlan.init()
        wlan.setMode(wlan.APSTA)
        -- 尝试连接Wi-Fi，并处理可能出现的错误
        wlan.connect(ssid, password)
        -- 等待获取IP地址
        local count = 1
        while 1 do
            local ip = netdrv.ipv4(socket.LWIP_STA)
            if ip and ip ~= "0.0.0.0" then
                log.info("WiFi STA已连接，IP:", ip)
                return false
            end
            if count > 600 then
                log.error("WiFi STA连接超时，请检查配置")
                return false
            end
            sys.wait(100)
            count = count + 1
        end

        log.info("WiFi STA初始化完成")
    end
    dnsproxy.setup(adapter, main_adapter)
    netdrv.napt(main_adapter)
    return true
end

-- ping操作
local function ping_request(adaptertest)
    log.info("dns_request",typeToString(adaptertest))
    if adaptertest == socket.LWIP_ETH then
        if eth_ping_ip == nil then
            local ip = httpdns.ali("air32.cn", {adapter=adaptertest, timeout=3000})
            if ip ~= nil then
                available[adaptertest] = connection_states.CONNECTED
            end
            log.info("httpdns", "air32.cn", ip)
        else
            icmp.setup(adaptertest)
            icmp.ping(adaptertest, eth_ping_ip)
        end
    end
    if adaptertest == socket.LWIP_STA then
        if wifi_ping_ip == nil then
            local ip = httpdns.ali("air32.cn", {adapter=adaptertest, timeout=3000})
            if ip ~= nil then
                available[adaptertest] = connection_states.CONNECTED
            end
            log.info("httpdns", "air32.cn", ip)
        else
            icmp.setup(adaptertest)
            icmp.ping(adaptertest, wifi_ping_ip)
        end
    end
    if adaptertest == socket.LWIP_GP then
        available[socket.LWIP_GP] = connection_states.CONNECTED
    end
    applyPriority()
end
-- 网卡上线回调函数
local function ip_ready_handle(ip, adapter)
    log.info("ip_ready_handle", ip, typeToString(adapter))
    -- 需要ping操作，ping通后认为网络可用
    available[adapter] = connection_states.CONNECTING
    -- ping_request(adapter)
end
-- 网卡下线回调函数
local function ip_lose_handle(adapter)
    log.info("ip_lose_handle", typeToString(adapter))
    available[adapter] = connection_states.DISCONNECTED
    if current_active == adapter then
        log.info(typeToString(adapter) .. " 失效，切换到其他网络")
        applyPriority()
    end
end

--CONNECTING的网卡需要定时ping
sys.taskInit(function()
    while true do
        for _, net_type in ipairs(current_priority) do
            -- log.info("网卡顺序",typeToString(net_type),available[net_type])
            if available[net_type] == connection_states.CONNECTING then
                ping_request(net_type)
                log.info(typeToString(net_type) .. "网卡未ping通，需要定时ping")
                sys.wait(ping_time)
            end
        end
        sys.wait(1000)
    end
end)


sys.subscribe("PING_RESULT", function(id, time, dst)
    log.info("ping", typeToString(id), time, dst);
    available[id] = connection_states.CONNECTED
    applyPriority()
end)
-- 订阅网络状态变化的消息
sys.subscribe("IP_READY", ip_ready_handle)
sys.subscribe("IP_LOSE", ip_lose_handle)
return libnetif
