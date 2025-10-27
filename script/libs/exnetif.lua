--[[
@module exnetif
@summary exnetif 控制网络优先级（以太网->WIFI->4G）根据优先级选择上网的网卡。简化开启多网融合的操作，4G作为数据出口给WIFI,以太网设备上网，以太网作为数据出口给WIFI,Air8000上网，WIFI作为数据出口给Air8000,以太网上网。
@version 1.0
@date    2025.06.26
@author  wjq
@usage
本文件的对外接口有4个：
1、exnetif.set_priority_order(networkConfigs)：设置网络优先级顺序并初始化对应网络(需要在task中调用)
2、exnetif.notify_status(cb_fnc)：设置网络状态变化回调函数
3、exnetif.setproxy(adapter, main_adapter,other_configs)：配置网络代理实现多网融合(需要在task中调用)
4、exnetif.check_network_status(interval),检测间隔时间ms(选填)，不填时只检测一次，填写后将根据间隔时间循环检测，会提高模块功耗
]]
local exnetif = {}

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpdns = require("httpdns")
-- 设置pingip
local wifi_ping_ip
local eth_ping_ip
local local_network_mode
local need_ping = true
local single_network_mode = false
local auto_socket_switch = true

local ping_time = 10000
-- 连接状态
local connection_states = {
    DISCONNECTED = 0,
    CONNECTING = 1,
    CONNECTED = 2,
    OPENED = 3,
    SINGLE_NETWORK=4
}

-- 状态回调函数
local states_cbfnc = function(net_type) end
-- 当前优先级
local current_priority = { socket.LWIP_ETH, socket.LWIP_STA, socket.LWIP_GP }
-- 连接状态
local available = {
    [socket.LWIP_STA] = connection_states.DISCONNECTED,
    [socket.LWIP_ETH] = connection_states.DISCONNECTED,
    [socket.LWIP_GP] = connection_states.DISCONNECTED,
    [socket.LWIP_USER1] = connection_states.DISCONNECTED
}
-- 当前使用的网卡
local current_active = nil

-- 网络类型转字符串
local function type_to_string(net_type)
    local type_map = {
        [socket.LWIP_STA] = "WiFi",
        [socket.LWIP_ETH] = "Ethernet",
        [socket.LWIP_GP] = "4G",
        [socket.LWIP_USER1] = "8101SPIETH"
    }
    return type_map[net_type] or "Unknown"
end

local function socket_state_detection(adapter)
    if netdrv.on then
        log.info("netdrv", "订阅socket连接状态变化事件", type_to_string(adapter))
        -- 订阅socket连接状态变化事件
        netdrv.on(adapter, netdrv.EVT_SOCKET, function(id, event, params)
            if event == "timeout" or event == "error" then
                if available[adapter] == connection_states.CONNECTED then
                    available[adapter] = connection_states.CONNECTING
                end
            end
            -- log.info("netdrv", "socket event", id, event, json.encode(params or {}))
            -- if params then
            --     -- params里会有remote_ip, remote_port等信息, 可按需获取
            --     local remote_ip = params.remote_ip
            --     local remote_port = params.remote_port
            --     local domain_name = params.domain_name
            --     log.info("netdrv", "socket event", "remote_ip", remote_ip, "remote_port", remote_port, "domain_name", domain_name)
            -- end
        end)
    end
end

-- 状态更改后重新设置默认网卡
local function apply_priority()
    local usable = false
    -- 查找优先级最高的可用网络
    for _, net_type in ipairs(current_priority) do
        -- log.info("网卡顺序",type_to_string(net_type),available[net_type])
        if available[net_type] == connection_states.CONNECTED then
            usable = true
            -- 设置优先级高的网卡
            if current_active ~= net_type then
                log.info("设置网卡", type_to_string(net_type))
                states_cbfnc(type_to_string(net_type), net_type) -- 默认网卡改变的回调函数
                socket.dft(net_type)
                if auto_socket_switch and socket.close_all then
                    socket.close_all(current_active)
                end
                current_active = net_type
            end
            break
        end
    end

    -- 从存在可用网卡到没有可用网卡，才通知回调
    if usable == false and  current_active ~= nil then
        --避免重复通知
        current_active = nil
        states_cbfnc(nil, -1)
    end
end


--httpdns域名解析测试
local function http_dnstest(adaptertest)
    local ip = httpdns.ali("baidu.com", { adapter = adaptertest, timeout = 3000 })
    if ip ~= nil then
        available[adaptertest] = connection_states.CONNECTED
        log.info(type_to_string(adaptertest) .. "网卡httpdns域名解析成功")
    else
        log.info(type_to_string(adaptertest) .. "网卡httpdns域名解析失败")
    end
    log.info("httpdns", "baidu.com", ip)
end
-- ping操作
local function ping_request(adaptertest)
    log.info("dns_request",type_to_string(adaptertest),need_ping)
    if need_ping then
        if adaptertest == socket.LWIP_ETH or adaptertest == socket.LWIP_USER1 then
            if eth_ping_ip == nil then
            http_dnstest(adaptertest)
            else
                icmp.setup(adaptertest)
                icmp.ping(adaptertest, eth_ping_ip)
            end
        end
        if adaptertest == socket.LWIP_STA then
            if wifi_ping_ip == nil then
                http_dnstest(adaptertest)
            else
                icmp.setup(adaptertest)
                icmp.ping(adaptertest, wifi_ping_ip)
            end
        end
        if adaptertest == socket.LWIP_GP then
            if eth_ping_ip ~= nil then
                icmp.setup(adaptertest)
                icmp.ping(adaptertest, eth_ping_ip)
            elseif wifi_ping_ip ~= nil then
                icmp.setup(adaptertest)
                icmp.ping(adaptertest, wifi_ping_ip)
            else
                http_dnstest(adaptertest)
            end
        end
    else
        log.info(type_to_string(adaptertest) .. "配置了不需要ping，直接切换为CONNECTED状态")
        available[adaptertest] = connection_states.CONNECTED
    end
    apply_priority()
end
-- 网卡上线回调函数
local function ip_ready_handle(ip, adapter)
    local _, _, gw = socket.localIP(adapter)
    log.info("ip_ready_handle", ip, type_to_string(adapter), "state", available[adapter], "gw", gw)
    if local_network_mode then
        if adapter == socket.LWIP_ETH or adapter == socket.LWIP_USER1 then
            eth_ping_ip = gw
        elseif adapter == socket.LWIP_STA then
            wifi_ping_ip = gw
        end
    end
    log.info("eth_ping_ip", eth_ping_ip, "wifi_ping_ip", wifi_ping_ip)
    -- 需要ping操作，ping通后认为网络可用
    if available[adapter] == connection_states.OPENED then
        available[adapter] = connection_states.CONNECTING
    end
    -- ping_request(adapter)
end
-- 网卡下线回调函数
local function ip_lose_handle(adapter)
    log.info("ip_lose_handle", type_to_string(adapter))
    if available[adapter] == connection_states.CONNECTING or available[adapter] == connection_states.CONNECTED then
        available[adapter] = connection_states.OPENED
    end
    if current_active == adapter then
        log.info(type_to_string(adapter) .. " 失效，切换到其他网络")
        apply_priority()
    end
end

local interval_time = nil

--[[
对正常状态的网卡进行ping测试
@api exnetif.check_network_status(interval),
@int 检测间隔时间ms(选填)，不填时只检测一次，填写后将根据间隔时间循环检测，会提高模块功耗
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


--打开以太网Wan功能
local function setup_eth(config)
    if config.local_network_mode then
        local_network_mode = true
    end
    if config.need_ping~=nil then
        need_ping = config.need_ping
    end
    if config.auto_socket_switch ~=nil then
        auto_socket_switch = config.auto_socket_switch
        -- log.info("设置自动关闭非当前网卡socket连接", auto_socket_switch)
    end
    eth_ping_ip = config.ping_ip
    if type(config.ping_time) == "number" then
        ping_time = config.ping_time
    end
    log.info("初始化以太网")
    if not single_network_mode then
        available[socket.LWIP_ETH] = connection_states.OPENED
    else
        available[socket.LWIP_ETH] = connection_states.SINGLE_NETWORK
    end
    -- 打开CH390供电
    if config.pwrpin then
        gpio.setup(config.pwrpin, 1, gpio.PULLUP)
    end
    -- sys.wait(100) -- 等待以太网模块上电稳定
    if config.tp == nil then
        log.info("8101以太网")
        if netdrv.setup(socket.LWIP_ETH) == false then
            log.error("以太网初始化失败")
            if config.pwrpin then
                gpio.close(config.pwrpin)
            end
            return false
        end      
    else
        log.info("config.opts.spi",config.opts.spi,",config.type",config.tp)
        -- 配置SPI和初始化网络驱动
        local result = spi.setup(config.opts.spi, -- spi id
        nil, 0, -- CPHA
        0, -- CPOL
        8, -- 数据宽度
        25600000 -- ,--波特率
        )
        log.info("main", "open spi", result)
        if result ~= 0 then -- 返回值为0，表示打开成功
            log.info("main", "spi open error", result)
            if config.pwrpin then
                gpio.close(config.pwrpin)
            end
            return false
        end
        -- 初始化指定netdrv设备,
        -- socket.LWIP_ETH 网络适配器编号
        -- netdrv.CH390外挂CH390
        -- SPI ID 1, 片选 GPIO12
        if netdrv.setup(socket.LWIP_ETH, config.tp, config.opts) == false then
            log.error("以太网初始化失败")
            if config.pwrpin then
                gpio.close(config.pwrpin)
            end
            return false
        end    
    end
    if config.static_ip then
        sys.wait(1000) -- 等待以太网模块初始化完成,去掉会导致以太网初始化失败
        log.info("netdrv", "自定义以太网IP地址", config.static_ip.ipv4)
        log.info("静态ip",netdrv.ipv4(socket.LWIP_ETH, config.static_ip.ipv4,config.static_ip.mark,config.static_ip.gw))
    else
        netdrv.dhcp(socket.LWIP_ETH, true)
    end
    log.info("以太网初始化完成")
    socket_state_detection(socket.LWIP_ETH)
    return true
end

--打开8101spi以太网Wan功能
local function setup_eth_user1(config)
    if config.local_network_mode then
        local_network_mode = true
    end
    if config.need_ping~=nil then
        need_ping = config.need_ping
    end
    if config.auto_socket_switch ~=nil then
        auto_socket_switch = config.auto_socket_switch
        -- log.info("设置自动关闭非当前网卡socket连接", auto_socket_switch)
    end
    eth_ping_ip = config.ping_ip
    if type(config.ping_time) == "number" then
        ping_time = config.ping_time
    end
    log.info("初始化以太网")
    if not single_network_mode then
        available[socket.LWIP_USER1] = connection_states.OPENED
    else
        available[socket.LWIP_USER1] = connection_states.SINGLE_NETWORK
    end
    -- 打开CH390供电
    if config.pwrpin then
        gpio.setup(config.pwrpin, 1, gpio.PULLUP)        
    end
    -- sys.wait(100)-- 等待以太网模块上电稳定
    log.info("config.opts.spi", config.opts.spi, ",config.type", config.tp)
    -- 配置SPI和初始化网络驱动
    local result = spi.setup(config.opts.spi,     -- spi id
        nil, 0,                                   -- CPHA
        0,                                        -- CPOL
        8,                                        -- 数据宽度
        25600000                                  -- ,--波特率
    )
    log.info("main", "open spi", result)
    if result ~= 0 then     -- 返回值为0，表示打开成功
        log.info("main", "spi open error", result)
        if config.pwrpin then
                gpio.close(config.pwrpin)
            end
        return false
    end
    -- 初始化指定netdrv设备,
    -- socket.LWIP_ETH 网络适配器编号
    -- netdrv.CH390外挂CH390
    -- SPI ID 1, 片选 GPIO12
    if netdrv.setup(socket.LWIP_USER1, config.tp, config.opts) == false then
        log.error("以太网初始化失败")
        if config.pwrpin then
                gpio.close(config.pwrpin)
            end
        return false
    end
    if config.static_ip then
        sys.wait(1000) -- 等待以太网模块初始化完成,去掉会导致以太网初始化失败
        log.info("netdrv", "自定义以太网IP地址", config.static_ip.ipv4)
        log.info("静态ip",netdrv.ipv4(socket.LWIP_USER1, config.static_ip.ipv4, config.static_ip.mark, config.static_ip.gw))
    else
        netdrv.dhcp(socket.LWIP_USER1, true)
    end

    log.info("以太网初始化完成")
    socket_state_detection(socket.LWIP_USER1)
    return true
end

--连接wifi(STA模式)
local function set_wifi_info(config)
    if config.local_network_mode then
        local_network_mode = true
    end
    if config.need_ping~=nil then
        need_ping = config.need_ping
    end
    if config.auto_socket_switch ~=nil then
        auto_socket_switch = config.auto_socket_switch
        -- log.info("设置自动关闭非当前网卡socket连接", auto_socket_switch)
    end
    wifi_ping_ip = config.ping_ip
    if type(config.ping_time) == "number" then
        ping_time = config.ping_time
    end
    log.info("WiFi名称:", config.ssid)
    log.info("密码     :", config.password)
    log.info("ping_ip  :", config.ping_ip)
    wlan.init()
    if not single_network_mode then
        available[socket.LWIP_STA] = connection_states.OPENED
    else
        available[socket.LWIP_STA] = connection_states.SINGLE_NETWORK
    end
    -- 尝试连接Wi-Fi，并处理可能出现的错误
    local success = wlan.connect(config.ssid, config.password)
    if not success then
        log.error("WiFi连接失败")
        return false
    end
    log.info("WiFi STA初始化完成")
    socket_state_detection(socket.LWIP_STA)
    return true
end

--[[
设置网络优先级，相应网卡获取到ip且网络正常视为网卡可用，丢失ip视为网卡不可用.(需要在task中调用)
@api exnetif.set_priority_order(new_priority)
@table 网络优先级列表,优先级从高到低对应table中的第一个参数到最后一个参数
@return boolean 成功返回true，失败返回false
@usage
多网优先级模式：
exnetif.set_priority_order({
    { -- 最高优先级网络
        WIFI = { -- WiFi配置
            ssid = "your_ssid",       -- WiFi名称(string)
            password = "your_pwd",    -- WiFi密码(string)
            need_ping = true,         -- 是否需要通过ping来测试网络的连通性
                                      -- 在没有ping测试环境的项目中，需要将这个参数设置为false，表示不需要ping测试网络连通，
                                      -- 仅根据IP READY消息（即获取到了ip地址）来判断网络环境准备就绪，是否网络连通性则无法保证
                                      -- 如果没有设置此参数，默认为true
                                      -- 在有ping测试环境的项目中，建议不要将这个参数设置为true
            local_network_mode = true,-- 局域网模式(选填参数)，设置为true时，exnetif会自动将ping_ip设置为网卡的网关ip。
                                      -- 用户不需要传入ping_ip参数，即使传入了，也无效。
                                      -- 这个模式的使用场景，仅适用于局域网环境；可以访问外网时，不要使用
            ping_ip = "112.125.89.8", -- 连通性检测IP(选填参数),默认使用httpdns获取baidu.com的ip作为判断条件，
                                      -- 注：如果填写ip，则ping通作为判断网络是否可用的条件，
                                      -- 所以需要根据网络环境填写内网或者外网ip,
                                      -- 填写外网ip的话要保证外网ip始终可用，
                                      -- 填写局域网ip的话要确保相应ip固定且能够被ping通
            ping_time = 10000         -- 填写ping_ip且未ping通时的检测间隔(ms, 可选，默认为10秒)
                                      -- 定时ping将会影响模块功耗，使用低功耗模式的话可以适当延迟间隔时间
        }
    },
    { -- 次优先级网络
        ETHERNET = { -- 以太网配置
            pwrpin = 140,                   -- 供电使能引脚(number)
            need_ping = true,               -- 是否需要通过ping来测试网络的连通性
                                            -- 在没有ping测试环境的项目中，需要将这个参数设置为false，表示不需要ping测试网络连通，
                                            -- 仅根据IP READY消息（即获取到了ip地址）来判断网络环境准备就绪，是否网络连通性则无法保证
                                            -- 如果没有设置此参数，默认为true
                                            -- 在有ping测试环境的项目中，建议不要将这个参数设置为true
            local_network_mode = true,      -- 局域网模式(选填参数)，设置为true时，exnetif会自动将ping_ip设置为网卡的网关ip。
                                            -- 用户不需要传入ping_ip参数，即使传入了，也无效。
                                            -- 这个模式的使用场景，仅适用于局域网环境；可以访问外网时，不要使用
            ping_ip = "112.125.89.8",       -- 连通性检测IP(选填参数),默认使用httpdns获取baidu.com的ip作为判断条件，
                                            -- 注：如果填写ip，则ping通作为判断网络是否可用的条件，
                                            -- 所以需要根据网络环境填写内网或者外网ip,
                                            -- 填写外网ip的话要保证外网ip始终可用，
                                            -- 填写局域网ip的话要确保相应ip固定且能够被ping通
            ping_time = 10000,              -- 填写ping_ip且未ping通时的检测间隔(ms, 可选,默认为10秒)
                                            -- 定时ping将会影响模块功耗，使用低功耗模式的话可以适当延迟间隔时间
            tp = netdrv.CH390,              -- 网卡芯片型号(选填参数)，仅spi方式外挂以太网时需要填写。
            opts = { spi = 1, cs = 12 },    -- 外挂方式,需要额外的参数(选填参数)，仅spi方式外挂以太网时需要填写。
            static_ip = {                   -- 静态ip配置(选填参数)，不填写则使用dhcp获取ip
                ipv4 = "192.168.5.100",     -- ip地址(string)
                mark = "255.255.255.0",     -- 子网掩码(string)
                gw = "192.168.5.1"          -- 网关地址(string)
            }
        }
    },
    { -- 最低优先级网络
        LWIP_GP = true  -- 启用4G网络
    }
})
单网络模式：
-- 单网络模式下只使用WIFI网络
    exnetif.set_priority_order({
        { -- 单网络，打开wifi
            WIFI = { -- WiFi配置
                ssid = "test",       -- WiFi名称(string)
                password = "HZ88888888",    -- WiFi密码(string)
            }
        }
    })
-- Air8000系列和780EXX系列单网络模式下只使用SPI以太网网络
    exnetif.set_priority_order({
        {
            ETHERNET = { -- 以太网配置
                pwrpin = 140, -- 供电使能引脚(number)
                tp = netdrv.CH390, -- 网卡芯片型号(选填参数)，仅spi方式外挂以太网时需要填写。
                opts = {spi = 1, cs = 12}, -- 外挂方式,需要额外的参数(选填参数)，仅spi方式外挂以太网时需要填写。
            }
        }
    })
-- Air8101单网络模式下只使用SPI以太网网络
    exnetif.set_priority_order({
        {
            ETHUSER1 = { -- 以太网配置
                pwrpin = 13, -- 供电使能引脚(number)
                tp = netdrv.CH390, -- 网卡芯片型号(选填参数)，仅spi方式外挂以太网时需要填写。
                opts = {spi = 0, cs = 15}, -- 外挂方式,需要额外的参数(选填参数)，仅spi方式外挂以太网时需要填写。
                static_ip = {                   -- 静态ip配置(选填参数)，不填写则使用dhcp获取ip
                    ipv4 = "192.168.5.100",     -- ip地址(string)
                    mark = "255.255.255.0",     -- 子网掩码(string)
                    gw = "192.168.5.1"          -- 网关地址(string)
                }
            }
        }
    })
-- 单网络模式下只使用RMII以太网网络
    exnetif.set_priority_order({
        {
            ETHERNET = { -- 以太网配置
                pwrpin = 13, -- 供电使能引脚(number)
            }
        }
    })
-- 4G单网模式下，不需要require "exnetif"，减少不必要的功能模块加载
]]
function exnetif.set_priority_order(networkConfigs)
    -- 判断表中数据个数
    if #networkConfigs < 1 then
        log.error("网络配置为空")
        return false
    end
    if #networkConfigs == 1 then
        single_network_mode = true
    end

    if not single_network_mode then
        -- CONNECTING的网卡需要定时ping
        sys.taskInit(function()
            while true do
                for _, net_type in ipairs(current_priority) do
                    -- log.info("网卡顺序",type_to_string(net_type),available[net_type])
                    if available[net_type] == connection_states.CONNECTING then
                        log.info(type_to_string(net_type) .. "网卡开始PING")
                        ping_request(net_type)
                        sys.wait(ping_time)
                    end
                end
                sys.wait(1000)  -- 避免死循环
            end
        end)

        -- 循环ping检测任务，默认不启用
        sys.taskInit(function()
            while true do
                if interval_time ~= nil then
                    sys.wait(interval_time)
                    exnetif.check_network_status()
                end
                sys.wait(1000) -- 避免死循环
            end
        end)

        sys.subscribe("PING_RESULT", function(id, time, dst)
            log.info("ping", id, time, dst)
            log.info(type_to_string(id) .. "网卡PING测试成功")
            available[id] = connection_states.CONNECTED
            apply_priority()
        end)
        -- 订阅网络状态变化的消息
        sys.subscribe("IP_READY", ip_ready_handle)
        sys.subscribe("IP_LOSE", ip_lose_handle)

    end

    local new_priority = {}
    for _, config in ipairs(networkConfigs) do
        if type(config.WIFI) == "table" then
            -- 开启wifi
            local res = set_wifi_info(config.WIFI)
            if res == false then
                log.error("wifi连接失败")
                return false
            end
            table.insert(new_priority, socket.LWIP_STA)
        end
        if type(config.ETHUSER1) == "table" then
            -- 开启以太网
            local res = setup_eth_user1(config.ETHUSER1)
            if res == false then
                log.error("以太网打开失败")
                return false
            end
            table.insert(new_priority, socket.LWIP_USER1)
        end
        if type(config.ETHERNET) == "table" then
            -- 开启以太网
            local res = setup_eth(config.ETHERNET)
            if res == false then
                log.error("以太网打开失败")
                return false
            end
            table.insert(new_priority, socket.LWIP_ETH)
        end
        if config.LWIP_GP then
            -- 开启4G
            table.insert(new_priority, socket.LWIP_GP)
            available[socket.LWIP_GP] = connection_states.CONNECTING
            if config.auto_socket_switch ~=nil then
                auto_socket_switch = config.auto_socket_switch
                -- log.info("设置自动关闭非当前网卡socket连接", auto_socket_switch)
            end
        end
    end

    -- 设置新优先级
    current_priority = new_priority
    -- 此处按照用户期望的配置，先设置优先级最高的默认网卡
    -- 防止出现以下问题：
    -- 例如Air8000内核固件运行起来之后，默认网卡是socket.LWIP_GP，如果用户调用exnetif.set_priority_order接口配置最高优先级网卡为socket.LWIP_ETH
    -- 在socket.LWIP_ETH网卡准备就绪之前，socket.LWIP_GP可能已经准备就绪，此时默认网卡仍然是socket.LWIP_GP；
    -- 而网络应用层（例如socket，mqtt等）有关的demo，我们编写时，不关心具体网卡，直接使用默认网卡（这样符合正常逻辑）；
    -- 就可能会出现“网络应用在这段时间内直接使用socket.LWIP_GP，而不是用户期望的网卡socket.LWIP_ETH来上网”的问题；
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
            opts = {spi = 0, cs = 8}, -- 外挂方式,需要额外的参数(选填参数)，仅spi方式外挂以太网时需要填写。
            main_adapter = {
                ethpower_en = 21,-- 以太网模块的pwrpin引脚(gpio编号)
                tp = netdrv.CH390, -- 网卡芯片型号(选填参数)，仅spi方式外挂以太网时需要填写。
                opts = {spi = 1, cs = 12}
            }
        }) then
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
        opts = { spi = 1, cs = 12},      -- 外挂方式,需要额外的参数(选填参数)，仅spi方式外挂以太网时需要填写。
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
            opts = { spi = 1, cs = 12},      -- 外挂方式,需要额外的参数(选填参数)，仅spi方式外挂以太网时需要填写。
            ethpower_en = 140,               -- 以太网模块的pwrpin引脚(gpio编号)
        }
    })
    -- WIFI提供网络供以太网设备上网
    exnetif.setproxy(socket.LWIP_ETH, socket.LWIP_STA, {
        tp = netdrv.CH390,               -- 网卡芯片型号(选填参数)，仅spi方式外挂以太网时需要填写。
        opts = { spi = 1, cs = 12},      -- 外挂方式,需要额外的参数(选填参数)，仅spi方式外挂以太网时需要填写。
        ethpower_en = 140,               -- 以太网模块的pwrpin引脚(gpio编号)
        main_adapter = {
            ssid = "test",                -- 提供网络的网卡开启参数
            password = "HZ88888888"
        }
    })
]]
function exnetif.setproxy(adapter, main_adapter, other_configs)
    if main_adapter == socket.LWIP_ETH and available[socket.LWIP_ETH] == connection_states.DISCONNECTED then
        -- 打开WAN功能
        log.info("ch390", "打开LDO供电", other_configs.main_adapter.ethpower_en)
        available[socket.LWIP_ETH] = connection_states.OPENED
        -- 打开CH390供电
        if other_configs.main_adapter.ethpower_en then
            gpio.setup(other_configs.main_adapter.ethpower_en, 1, gpio.PULLUP)
        end
        -- sys.wait(100) -- 等待以太网模块上电稳定
        if other_configs.main_adapter.tp == nil then
            log.info("8101以太网")
            if netdrv.setup(socket.LWIP_ETH) == false then
            log.error("以太网初始化失败")
            if other_configs.main_adapter.ethpower_en then
                    gpio.close(other_configs.main_adapter.ethpower_en)
                end
            return false
        end  
        else
            log.info("config.opts.spi", other_configs.main_adapter.opts.spi, ",config.type", other_configs.main_adapter.tp)
            -- 配置SPI和初始化网络驱动
            local result = spi.setup(other_configs.main_adapter.opts.spi, -- spi id
                nil, 0,                                      -- CPHA
                0,                                           -- CPOL
                8,                                           -- 数据宽度
                25600000                                     -- ,--波特率
            )
            log.info("main", "open spi", result)
            if result ~= 0 then -- 返回值为0，表示打开成功
                log.info("main", "spi open error", result)
                if other_configs.main_adapter.ethpower_en then
                    gpio.close(other_configs.main_adapter.ethpower_en)
                end
                return false
            end
            -- 初始化指定netdrv设备,
            local success = netdrv.setup(socket.LWIP_ETH, other_configs.main_adapter.tp, other_configs.main_adapter.opts)
            if not success then
                log.error("以太网初始化失败")
                if other_configs.main_adapter.ethpower_en then
                    gpio.close(other_configs.main_adapter.ethpower_en)
                end
                return false
            end
        end
        netdrv.dhcp(socket.LWIP_ETH, true)
        local count = 1
        while 1 do
            local ip = netdrv.ipv4(socket.LWIP_ETH)
            if ip and ip ~= "0.0.0.0" then break end
            if count > 600 then
                log.error("以太网连接超时，请检查配置")
                if other_configs.main_adapter.ethpower_en then
                    gpio.close(other_configs.main_adapter.ethpower_en)
                end
                return false
            end
            sys.wait(100)
            count = count + 1
        end
    elseif main_adapter == socket.LWIP_USER1 and available[socket.LWIP_USER1] == connection_states.DISCONNECTED then
        log.info("初始化以太网")
        -- 打开CH390供电
        if other_configs.main_adapter.ethpower_en then
            gpio.setup(other_configs.main_adapter.ethpower_en, 1, gpio.PULLUP)
        end
        -- sys.wait(100) -- 等待以太网模块上电稳定
        log.info("config.opts.spi", other_configs.main_adapter.opts.spi, ",config.type", other_configs.main_adapter.tp)
        available[socket.LWIP_USER1] = connection_states.OPENED
        -- 配置SPI和初始化网络驱动
        local result = spi.setup(other_configs.main_adapter.opts.spi, -- spi id
            nil, 0,                               -- CPHA
            0,                                    -- CPOL
            8,                                    -- 数据宽度
            25600000                              -- ,--波特率
        )
        log.info("main", "open spi", result)
        if result ~= 0 then -- 返回值为0，表示打开成功
            log.info("main", "spi open error", result)
            if other_configs.main_adapter.ethpower_en then
                    gpio.close(other_configs.main_adapter.ethpower_en)
                end
            return false
        end
        -- 初始化指定netdrv设备,
        -- socket.LWIP_ETH 网络适配器编号
        -- netdrv.CH390外挂CH390
        -- SPI ID 1, 片选 GPIO12
        if netdrv.setup(socket.LWIP_USER1, other_configs.main_adapter.tp, other_configs.main_adapter.opts) == false then
            log.error("以太网初始化失败")
            if other_configs.main_adapter.ethpower_en then
                    gpio.close(other_configs.main_adapter.ethpower_en)
                end
            return false
        end
        netdrv.dhcp(socket.LWIP_USER1, true)
        log.info("以太网初始化完成")
        local count = 1
        while 1 do
            local ip = netdrv.ipv4(socket.LWIP_USER1)
            if ip and ip ~= "0.0.0.0" then break end
            if count > 600 then
                log.error("以太网连接超时，请检查配置")
                if other_configs.main_adapter.ethpower_en then
                    gpio.close(other_configs.main_adapter.ethpower_en)
                end
                return false
            end
            sys.wait(100)
            count = count + 1
        end
    elseif main_adapter == socket.LWIP_STA and available[socket.LWIP_STA] == connection_states.DISCONNECTED then
        -- 打开STA功能，设置混合模式
        wlan.init()
        wlan.setMode(wlan.APSTA)
        available[socket.LWIP_STA] = connection_states.OPENED
        -- 尝试连接Wi-Fi，并处理可能出现的错误
        wlan.connect(other_configs.main_adapter.ssid, other_configs.main_adapter.password)
        -- 等待获取IP地址
        local count = 1
        while 1 do
            local ip = netdrv.ipv4(socket.LWIP_STA)
            if ip and ip ~= "0.0.0.0" then
                log.info("WiFi STA已连接，IP:", ip)
                break
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

    if adapter == socket.LWIP_ETH then
        log.info("ch390", "打开LDO供电", other_configs.ethpower_en)
        if other_configs.ethpower_en then
            gpio.setup(other_configs.ethpower_en, 1, gpio.PULLUP)
        end
        -- 打开LAN功能
        -- 配置 SPI 参数，Air8000 使用 SPI 接口与以太网模块进行通信。
        if other_configs.tp then
            log.info("netdrv spi挂载以太网", "初始化LAN功能")
            local result = spi.setup(
                other_configs.opts.spi, -- spi id
                nil, 0,                 -- CPHA
                0,                      -- CPOL
                8,                      -- 数据宽度
                25600000                -- ,--波特率
            )
            log.info("main", "open spi", result)
            if result ~= 0 then -- 返回值为 0，表示打开成功
                log.error("main", "spi open error", result)
                if other_configs.ethpower_en then
                    gpio.close(other_configs.ethpower_en)
                end
                return false
            end
        end
        -- 初始化以太网，Air8000 指定使用 CH390 芯片。
        log.info("netdrv", "初始化以太网", other_configs.tp, other_configs.opts)
        if netdrv.setup(socket.LWIP_ETH, other_configs.tp, other_configs.opts) == false then
            log.error("初始化以太网失败")
            if other_configs.ethpower_en then
                    gpio.close(other_configs.ethpower_en)
                end
            return false
        end
        sys.wait(1000) -- 等待以太网模块初始化完成,去掉会导致以太网初始化失败
        -- 设置以太网的 IP 地址、子网掩码、网关地址
        log.info("netdrv", "自定义以太网IP地址", other_configs.adapter_addr, "网关地址", other_configs.adapter_gw)
        netdrv.ipv4(socket.LWIP_ETH, other_configs.adapter_addr or "192.168.5.1", "255.255.255.0", "0.0.0.0")
        -- 获取以太网网络状态，连接后返回 true，否则返回 false，如果不存在就返回 nil。
        local count = 1
        while netdrv.ready(socket.LWIP_ETH) ~= true do
            if count > 600 then
                log.error("以太网连接超时，请检查配置")
                if other_configs.ethpower_en then
                    gpio.close(other_configs.ethpower_en)
                end
                return false
            end
            count = count + 1
            -- log.info("netdrv", "等待以太网就绪") -- 若以太网设备没有连上，可打开此处注释排查。
            sys.wait(100)
        end
        log.info("netdrv", "以太网就绪")
        -- 创建 DHCP 服务器，为连接到以太网的设备分配 IP 地址。
        log.info("netdrv", "创建dhcp服务器, 供以太网使用")
        if other_configs.adapter_gw then
            dhcpsrv.create({ adapter = socket.LWIP_ETH, gw = other_configs.adapter_gw })
        else
            dhcpsrv.create({ adapter = socket.LWIP_ETH, gw = { 192, 168, 5, 1 } })
        end
        -- 创建 DNS 代理服务，使得以太网接口上的设备可以通过 4G 网络访问互联网。
        log.info("netdrv", "创建dns代理服务, 供以太网使用")
    elseif adapter == socket.LWIP_AP then
        wlan.setMode(wlan.APSTA)
        -- 打开AP功能，设置混合模式
        log.info("执行AP创建操作", airlink.ready(), "正常吗?")
        wlan.createAP(other_configs.ssid, other_configs.password, other_configs.adapter_addr or "192.168.4.1",
            "255.255.255.0",
            other_configs.channel, other_configs.ap_opts)
        -- 设置 AP 的 IP 地址、子网掩码、网关地址
        netdrv.ipv4(socket.LWIP_AP, other_configs.adapter_addr or "192.168.4.1", "255.255.255.0", "0.0.0.0")
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
        if other_configs.adapter_gw then
            dhcpsrv.create({ adapter = socket.LWIP_AP, gw = other_configs.adapter_gw })
        else
            dhcpsrv.create({ adapter = socket.LWIP_AP })
        end
    elseif adapter == socket.LWIP_USER1 then
        log.info("ch390", "打开LDO供电", other_configs.ethpower_en)
        if other_configs.ethpower_en then
            gpio.setup(other_configs.ethpower_en, 1, gpio.PULLUP)
        end
        -- 打开LAN功能
        -- 配置 SPI 参数，Air8101 使用 SPI 接口与以太网模块进行通信。
        log.info("netdrv spi挂载以太网", "初始化LAN功能")
        local result = spi.setup(
            other_configs.opts.spi,     -- spi id
            nil, 0,                     -- CPHA
            0,                          -- CPOL
            8,                          -- 数据宽度
            25600000                    -- ,--波特率
        )
        log.info("main", "open spi", result)
        if result ~= 0 then     -- 返回值为 0，表示打开成功
            log.error("main", "spi open error", result)
            if other_configs.ethpower_en then
                    gpio.close(other_configs.ethpower_en)
                end
            return false
        end
        -- 初始化以太网，Air8000 指定使用 CH390 芯片。
        log.info("netdrv", "初始化以太网", other_configs.tp, other_configs.opts)
        if netdrv.setup(socket.LWIP_USER1, other_configs.tp, other_configs.opts) == false then
            log.error("初始化以太网失败")
            if other_configs.ethpower_en then
                    gpio.close(other_configs.ethpower_en)
                end
            return false
        end
        sys.wait(1000) -- 等待以太网模块初始化完成,去掉会导致以太网初始化失败
        -- 设置以太网的 IP 地址、子网掩码、网关地址
        log.info("netdrv", "自定义以太网IP地址", other_configs.adapter_addr, "网关地址", other_configs.adapter_gw)
        netdrv.ipv4(socket.LWIP_USER1, other_configs.adapter_addr or "192.168.5.1", "255.255.255.0", "0.0.0.0")
        -- 获取以太网网络状态，连接后返回 true，否则返回 false，如果不存在就返回 nil。
        local count = 1
        while netdrv.ready(socket.LWIP_USER1) ~= true do
            if count > 600 then
                log.error("以太网连接超时，请检查配置")
                if other_configs.ethpower_en then
                    gpio.close(other_configs.ethpower_en)
                end
                return false
            end
            count = count + 1
            -- log.info("netdrv", "等待以太网就绪") -- 若以太网设备没有连上，可打开此处注释排查。
            sys.wait(100)
        end
        log.info("netdrv", "以太网就绪")
        -- 创建 DHCP 服务器，为连接到以太网的设备分配 IP 地址。
        log.info("netdrv", "创建dhcp服务器, 供以太网使用")
        if other_configs.adapter_gw then
            dhcpsrv.create({ adapter = socket.LWIP_USER1, gw = other_configs.adapter_gw })
        else
            dhcpsrv.create({ adapter = socket.LWIP_USER1, gw = { 192, 168, 5, 1 } })
        end
        -- 创建 DNS 代理服务，使得以太网接口上的设备可以通过 4G 网络访问互联网。
        log.info("netdrv", "创建dns代理服务, 供以太网使用")
    end

    dnsproxy.setup(adapter, main_adapter)
    netdrv.napt(main_adapter)
    return true
end
return exnetif
