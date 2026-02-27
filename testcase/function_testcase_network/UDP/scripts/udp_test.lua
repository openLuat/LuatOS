-- UDP协议测试模块
local udp_test = {}

sys = require("sys")
_G.sysplus = require("sysplus")
local libnet = require "libnet" -- libnet库，支持tcp、udp协议所用的同步阻塞接口
local device_name = rtos.bsp()

-- ===========================================================================
local wifi_connection_condition = false
local ssl = false
local socket_clients = {}
-- 多个UDP服务器配置
local UDP_SERVERS_CONFIG = {{
    name = "UDP服务器1",
    host = "112.125.89.8",
    port = 33121,
    socket_client = nil,
    connected = false
}, {
    name = "UDP服务器2",
    host = "112.125.89.8", -- 示例IP，请替换为实际的服务器IP
    port = 33346, -- 示例端口，请替换为实际的服务器端口
    socket_client = nil,
    connected = false
}, {
    name = "UDP服务器3",
    host = "112.125.89.8", -- 示例IP，请替换为实际的服务器IP
    port = 34665, -- 示例端口，请替换为实际的服务器端口
    socket_client = nil,
    connected = false
}, {
    name = "UDP服务器4",
    host = "112.125.89.8", -- 示例IP，请替换为实际的服务器IP
    port = 34965, -- 示例端口，请替换为实际的服务器端口
    socket_client = nil,
    connected = false
}, {
    name = "UDP服务器5",
    host = "112.125.89.8", -- 示例IP，请替换为实际的服务器IP
    port = 33321, -- 示例端口，请替换为实际的服务器端口
    socket_client = nil,
    connected = false
}, {
    name = "UDP服务器6",
    host = "112.125.89.8", -- 示例IP，请替换为实际的服务器IP
    port = 32971, -- 示例端口，请替换为实际的服务器端口
    socket_client = nil,
    connected = false
}, {
    name = "UDP服务器7",
    host = "112.125.89.8", -- 示例IP，请替换为实际的服务器IP
    port = 32181, -- 示例端口，请替换为实际的服务器端口
    socket_client = nil,
    connected = false
}, {
    name = "UDP服务器8",
    host = "112.125.89.8", -- 示例IP，请替换为实际的服务器IP
    port = 32326, -- 示例端口，请替换为实际的服务器端口
    socket_client = nil,
    connected = false
}} -- 可以继续添加更多服务器配置

local taskName = "UDP_TASK" -- 测试任务名称
local ssid = "luatos1234"
local password = "12341234"
local ALL_ADAPTERS = {}
local send_buffs = {} -- 多个发送缓冲区
local recv_buffs = {} -- 多个接收缓冲区
local name
-- ===========================================================================

local function get_supported_adapters()
    if device_name == "Air8000" then
        -- 所有可用的网络适配器列表
        ALL_ADAPTERS = {{
            name = "默认(nil)",
            adapter = nil
        }, {
            name = "LWIP_GP",
            adapter = socket.LWIP_GP
        }, {
            name = "LWIP_STA",
            adapter = socket.LWIP_STA
        }}
    elseif device_name == "Air780EPM" or device_name == "Air780EHM" then
        -- 所有可用的网络适配器列表
        ALL_ADAPTERS = {{
            name = "默认(nil)",
            adapter = nil
        }, {
            name = "LWIP_GP",
            adapter = socket.LWIP_GP
        }}
    elseif device_name == "Air8101" then
        -- 所有可用的网络适配器列表
        ALL_ADAPTERS = {{
            name = "默认(nil)",
            adapter = nil
        }, {
            name = "LWIP_STA",
            adapter = socket.LWIP_STA
        }}
    else
        -- 所有可用的网络适配器列表
        ALL_ADAPTERS = {{
            name = "默认(nil)",
            adapter = nil
        }}
    end
end

local function wifi_connect_demo()
    wifi_connection_condition = wlan.ready()
    if not wifi_connection_condition then
        log.info("udp_test", "开始连接WiFi")

        -- 发起连接
        local wlan_result = wlan.connect(ssid, password, 1)
        if not wlan_result then
            log.info("udp_test", "WiFi连接发起失败")
            return false
        end

        -- 轮询检查连接状态，最多等待15秒
        local max_wait = 15
        for i = 1, max_wait do
            sys.wait(1000)

            -- 检查WiFi是否就绪
            if wlan.ready() then
                -- 再等待一下确保IP分配完成
                sys.wait(500)
                local ip = wlan.getIP()
                if ip and ip ~= "0.0.0.0" then
                    log.info("udp_test", string.format("WiFi连接成功, IP: %s", ip))
                    wifi_connection_condition = true
                    return true
                end
            end
        end

        log.info("udp_test", "WiFi连接超时")
        return false
    end
    return true
end

-- 为每个服务器创建独立的缓冲区
local function create_buffers_for_servers()
    for i, server_config in ipairs(UDP_SERVERS_CONFIG) do
        -- 创建发送缓冲区
        send_buffs[i] = zbuff.create(1024)
        assert(send_buffs[i] ~= nil,
            string.format("服务器[%s] 发送数据缓冲区创建失败！", server_config.name))
        log.info(string.format("服务器[%s] 发送数据缓冲区创建通过", server_config.name))

        -- 创建接收缓冲区
        recv_buffs[i] = zbuff.create(1024)
        assert(recv_buffs[i] ~= nil,
            string.format("服务器[%s] 接收数据缓冲区创建失败！", server_config.name))
        log.info(string.format("服务器[%s] 接收数据缓冲区创建通过", server_config.name))
    end
end

local function udp_date_callback()
    local test_count = 5 -- 总发送次数
    local interval = 3000 -- 间隔时间
    local server_count = #UDP_SERVERS_CONFIG

    -- 初始化每个服务器的测试计数
    local server_test_counts = {}
    for i = 1, server_count do
        server_test_counts[i] = 0
    end

    log.info("udp_echo", string.format("开始并行回环测试，服务器数量: %d", server_count))
    log.info("udp_echo", string.format("每个服务器测试次数: %d", test_count))

    -- 持续测试直到所有服务器都完成指定次数的测试
    local all_completed = false

    while not all_completed do
        all_completed = true

        -- 轮流为每个未完成的服务器发送一次数据
        for i, server_config in ipairs(UDP_SERVERS_CONFIG) do
            -- 只处理已连接且未完成测试次数的服务器
            if server_config.connected and server_test_counts[i] < test_count then
                all_completed = false

                local send_buff = send_buffs[i]
                local recv_buff = recv_buffs[i]
                local socket_client = server_config.socket_client

                    -- 生成测试数据
                    local current_time = os.time()
                    local date_table = os.date("*t", current_time)

                    local test_str = string.format(
                        '{"server":"%s","seq":%d,"time":%d,"date":"%04d-%02d-%02d %02d:%02d:%02d","data":"test_message_%d","hex":0x%X,"random":%d}',
                        server_config.name, server_test_counts[i] + 1, current_time, date_table.year, date_table.month,
                        date_table.day, date_table.hour, date_table.min, date_table.sec, server_test_counts[i] + 1,
                        math.random(0, 65535), math.random(1000, 9999))

                    log.info("udp_echo", string.format("服务器[%s] 第%d次发送数据: %s", server_config.name,
                        server_test_counts[i] + 1, test_str))

                    -- 清空发送缓冲区并写入新数据
                    send_buff:write(test_str)
                    assert(send_buff:used() > 0,
                        string.format("服务器[%s] 数据写入失败！", server_config.name))
                    log.info("udp_test", string.format("服务器[%s] 数据写入通过", server_config.name))

                    -- 发送数据
                    local succ, full = libnet.tx(taskName, 0, socket_client, send_buff)
                    assert(type(succ) == "boolean" and type(full) == "boolean",
                        string.format("服务器[%s] libnet.tx()返回的数据类型错误", server_config.name))
                    assert(succ == true, string.format("服务器[%s] 数据发送失败", server_config.name))
                    assert(full == false, string.format("服务器[%s] 发送缓冲区已满", server_config.name))

                    -- 保存发送数据用于后续比较
                    local send_data = send_buff:query()
                    assert(send_data ~= nil,
                        string.format("服务器[%s] 读取缓冲区数据失败", server_config.name))
                    send_buff:del()

                    -- 为当前服务器等待接收数据
                    local wait_result, event_param = libnet.wait(taskName, 5000, socket_client)

                    if wait_result then
                        -- 接收数据
                        local succ, param, _, _ = socket.rx(socket_client, recv_buff)
                        assert(succ == true, string.format("服务器[%s] 数据接收失败", server_config.name))
                        assert(param ~= 0,
                            string.format("服务器[%s] 接收到的数据长度为0", server_config.name))

                        local recive_data = recv_buff:query()
                        assert(recive_data ~= nil,
                            string.format("服务器[%s] 读取缓冲区数据失败", server_config.name))
                        recv_buff:del()

                        -- 验证数据一致性
                        assert(recive_data == send_data,
                            string.format(
                                "服务器[%s] 第%d次回环数据不匹配!\n发送数据: %s\n接收数据: %s",
                                server_config.name, server_test_counts[i] + 1, send_data, recive_data))

                        server_test_counts[i] = server_test_counts[i] + 1

                        log.info("udp_echo", string.format("服务器[%s] ✓ 第%d次回环成功", server_config.name,
                            server_test_counts[i]))
                        log.info("udp_echo",
                            string.format("服务器[%s] 接收数据: %s", server_config.name, recive_data))
                    else
                        -- 接收超时，记录日志但不中断测试
                        log.warn("udp_echo", string.format("服务器[%s] 第%d次接收超时", server_config.name,
                            server_test_counts[i] + 1))
                    end

                    -- 短暂延迟，避免同时发送造成拥塞
                    sys.wait(100)
            end
        end

        -- 如果还有未完成的测试，等待下一次轮询
        if not all_completed then
            sys.wait(interval)
        end

        log.info("udp_echo", "所有服务器回环测试完成")
    end

end

local function UDP_LIBNET_TASK()
    for _, adapt_result in ipairs(ALL_ADAPTERS) do
        local adapter = adapt_result.adapter
        name = adapt_result.name
        if name == "LWIP_STA" then
            local wifi_connect_result = wifi_connect_demo()
            if wifi_connect_result == false then
                log.info("适配器LWIP_STA初次连接wifi失败，开始重试...")
                local retry_count = 0
                local connected = false
                while retry_count < 3 and not connected do
                    retry_count = retry_count + 1
                    log.info(string.format("第%d次重试连接WiFi...", retry_count))
                    connected = wifi_connect_demo()
                    if connected then
                        log.info(string.format("第%d次重连成功！", retry_count))
                        break
                    end
                    if retry_count < 3 then
                        sys.wait(1000)
                    end

                    if not connected then
                        log.info("重连3次均失败，退出wifi测试")
                        assert(connected == true,
                            string.format("测试" .. device_name .. "LWIP_STA连接失败，暂停LWIP_STA测试"))
                        return
                    end
                end

                if not connected then
                    log.info("重连3次均失败，退出wifi测试")
                    assert(connected == true,
                        string.format("测试" .. device_name .. "LWIP_STA连接失败，暂停LWIP_STA测试"))
                    return
                end
            end
        end

        for i, server_config in ipairs(UDP_SERVERS_CONFIG) do
                log.info("udp_test",
                    string.format("适配器[%s] 创建到服务器[%s]的连接", name, server_config.name))

                -- 创建socket对象
                local socket_client = socket.create(adapter, taskName)
                assert(socket_client ~= nil,
                    string.format("适配器[%s] 服务器[%s] 创建socket对象失败", name, server_config.name))
                log.info("udp_test", string.format("适配器[%s] 服务器[%s] 创建socket对象测试通过", name,
                    server_config.name))

                -- 保存socket对象到配置中
                server_config.socket_client = socket_client

                -- 打开debug日志信息
                local success, err = pcall(function()
                    socket.debug(socket_client, true)
                end)
                assert(success == true,
                    string.format("适配器[%s] 服务器[%s] debug日志打开失败", name, server_config.name))
                log.info("udp_test", string.format("适配器[%s] 服务器[%s] debug日志信息打开测试通过",
                    name, server_config.name))

                -- 随机生成端口配置socket
                local config_port_table = {}
                -- 设置随机种子
                math.randomseed(os.time())
                for i = 1, 3 do
                    table.insert(config_port_table, math.random(0, 60000))
                end

                for _, number in ipairs(config_port_table) do

                    local config_port = number
                    local config_result = socket.config(socket_client, nil, true, ssl)
                    assert(type(config_result) == "boolean",
                        string.format(
                            "适配器[%s]端口[%s]配置socket对象的参数返回值类型测试失败,预期boolean，实际%s",
                            name, config_port, type(config_result)))
                    log.info("udp_test", string.format(
                        "适配器[%s]端口[%s]配置socket对象的参数返回值类型测试通过", name,
                        config_port))

                    assert(config_result == true,
                        string.format(
                            "适配器[%s]端口[%s]配置socket对象的参数测试失败,预期true，实际%s",
                            name, config_port, config_result))
                    log.info("udp_test", string.format("适配器[%s]端口[%s]配置socket对象的参数测试通过",
                        name, config_port))

                end

                local connect_result = libnet.connect(taskName, 15000, socket_client, server_config.host,
                    server_config.port)

                assert(type(connect_result) == "boolean",
                    "适配器[%s] 服务器[%s] libnet 连接对端返回的数据类型错误,实际是%s:", name,
                    server_config.name, type(connect_result))
                log.info("udp_test",
                    string.format("适配器[%s] libnet 连接对端返回的数据类型测试通过", name))
                assert(connect_result == true,
                    string.format("适配器[%s] 服务器[%s] libnet 连接对端测试失败,预期true，实际%s",
                        name, server_config.name, connect_result))
                log.info("udp_test", string.format("适配器[%s] 服务器[%s] libnet 连接对端测试通过", name,
                    server_config.name))

                if connect_result then
                    server_config.connected = true
                    log.info(string.format("适配器[%s] 连接服务器[%s] %s:%d 成功", name, server_config.name,
                        server_config.host, server_config.port))
                else
                    server_config.connected = false
                    log.error(string.format("适配器[%s] 连接服务器[%s] %s:%d 失败", name, server_config.name,
                        server_config.host, server_config.port))
                end

                -- 短暂延迟，避免同时连接造成问题
                sys.wait(500)
        end

        -- 所有服务器连接完成后，创建缓冲区
        create_buffers_for_servers()

        -- 开始并行回环测试
        log.info("udp_test", "所有服务器连接完成，开始并行回环测试")
        udp_date_callback()

        -- 测试完成后关闭所有连接
        for i, server_config in ipairs(UDP_SERVERS_CONFIG) do
            if server_config.connected and server_config.socket_client then
                pcall(function()
                    libnet.close(taskName, 5000, server_config.socket_client)
                    socket.release(server_config.socket_client)
                    end)
                server_config.socket_client = nil
                server_config.connected = false
                log.info(string.format("关闭服务器[%s]连接", server_config.name))
            end
        end
        sys.wait(1000)
    end
end

function udp_test.test_main_demo()
    -- 配置可用网络适配器
    get_supported_adapters()

    -- sysplus.taskInitEx(UDP_LIBNET_TASK, taskName)
    -- sys.wait(120000)

    pcall(function()
        sysplus.taskInitEx(UDP_LIBNET_TASK, taskName)
        sys.wait(120000)
    end)

end

return udp_test
