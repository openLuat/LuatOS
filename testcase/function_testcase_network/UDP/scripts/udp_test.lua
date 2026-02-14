-- UDP协议测试模块
local udp_test = {}

sys = require("sys")
_G.sysplus = require("sysplus")
local libnet = require "libnet" -- libnet库，支持tcp、udp协议所用的同步阻塞接口
local device_name = rtos.bsp()

-- ===========================================================================
local wifi_connection_condition = false
local ssl = false
local socket_client = nil
local UDP_SERVER_CONFIG = {
    host = "112.125.89.8",
    port = 34928
} -- UDP服务器配置
local taskName = "UDP_TASK" -- 测试任务名称
local ssid = "观看15秒广告解锁WiFi"
local password = "qwertYUIOP"
local ALL_ADAPTERS = {}
local send_buff
local recv_buff
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
                end

                if not connected then
                    log.info("重连3次均失败，退出wifi测试")
                    assert(connected == true,
                        string.format("测试" .. device_name .. "LWIP_STA连接失败，暂停LWIP_STA测试"))
                    return
                end
            end
        end

        socket_client = socket.create(adapter, taskName)
        assert(socket_client ~= nil,
            string.format("适配器[%s] 创建socket对象测试失败：预期是一个非nil值，实际是%s", name,
                socket_client))
        log.info("udp_test", string.format("适配器[%s] 创建socket对象测试通过", name))

        -- 打开debug日志信息
        local success, err = pcall(function()
            socket.debug(socket_client, true)
        end)
        assert(success == true, "debug日志信息打开失败，预期是true,错误原因是：", err)
        log.info("udp_test", string.format("适配器[%s] debug日志信息打开测试通过", name))

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
                "适配器[%s]端口[%s]配置socket对象的参数返回值类型测试通过", name, config_port))

            assert(config_result == true,
                string.format("适配器[%s]端口[%s]配置socket对象的参数测试失败,预期true，实际%s",
                    name, config_port, config_result))
            log.info("udp_test",
                string.format("适配器[%s]端口[%s]配置socket对象的参数测试通过", name, config_port))

        end

        local connect_result = libnet.connect(taskName, 15000, socket_client, UDP_SERVER_CONFIG.host,
            UDP_SERVER_CONFIG.port)
        assert(type(connect_result) == "boolean",
            "适配器[%s] libnet 连接对端返回的数据类型错误,实际是%s:", type(connect_result))
        log.info("udp_test", string.format("适配器[%s] libnet 连接对端返回的数据类型测试通过", name))
        assert(connect_result == true, string.format(
            "适配器[%s] libnet 连接对端测试失败,预期true，实际%s", name, connect_result))
        log.info("udp_test", string.format("适配器[%s] libnet 连接对端测试通过", name))

        if connect_result then
            log.info("connect ip:" .. UDP_SERVER_CONFIG.host .. "connect port:" .. UDP_SERVER_CONFIG.port ..
                         "连接成功")

            local tx_result, buff_result = libnet.tx(taskName, 0, socket_client, "UDP CONNECT")
            assert(type(tx_result) == "boolean" and tx_result == true, string.format(
                "发送数据到对端测试失败：预期发送结果为true,类型为boolean，实际发送结果为%s类型%s",
                tx_result, type(tx_result)))
            log.info("udp_test", "发送数据到对端测试通过")
            assert(buff_result == false, "发送缓冲区已满")
            log.info("发送缓冲区正常通过")
        end

        -- 服务器断开后的行动，由于while true的影响，所以会再次重新执行进行 重新连接。
        libnet.close(taskName, 5000, socket_client)
        socket.release(socket_client)
        -- send_buff:clear(0)
        -- recv_buff:clear(0)
        socket_client = nil
        sys.wait(1000)
    end
end

function udp_test.test_main_demo()
    -- 创建发送数据缓冲区
    send_buff = zbuff.create(1024)
    assert(send_buff ~= nil, "发送数据缓冲区创建失败！")
    log.info("发送数据缓冲区创建通过")

    -- 创建接收数据缓冲区
    recv_buff = zbuff.create(1024)
    assert(recv_buff ~= nil, "接收数据缓冲区创建失败！")
    log.info("接收数据缓冲区创建通过")

    -- 配置可用网络适配器
    get_supported_adapters()

    sysplus.taskInitEx(UDP_LIBNET_TASK, taskName)
    sys.wait(30000)
end

return udp_test
