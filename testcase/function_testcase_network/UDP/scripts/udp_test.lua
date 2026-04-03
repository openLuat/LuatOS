-- UDP协议测试模块
local udp_test = {}

sys = require("sys")
_G.sysplus = require("sysplus")
local libnet = require "libnet"
local device_name = rtos.bsp()

-- ===========================================================================
-- 测试配置
local TEST_CONFIG = {
    enable_smart_switch = true,
    test_all_adapters = true,
    connect_timeout = 15000,
    send_timeout = 5000,
    recv_timeout = 5000,
    test_count = 3,
}

-- 记录每个适配器的测试结果
local adapter_test_results = {}

-- 网络适配器配置表 - 根据设备类型动态生成
local ALL_ADAPTERS = {}

-- WiFi配置（仅WiFi模块使用）
local ssid = "HHHHHHHHHHH"
local password = "huanghefm94.3"

-- UDP服务器配置
local UDP_SERVERS_CONFIG = {{
    name = "UDP服务器1",
    host = "115.120.239.161",
    port = 27639,
}}

-- 检查wlan库是否可用
local function is_wlan_available()
    return wlan ~= nil and type(wlan.ready) == "function"
end

-- 设备类型判断和适配器配置
if device_name == "Air8000" then
    -- Air8000: 支持4G和WiFi
    ALL_ADAPTERS = {
        {name = "4G网卡(LWIP_GP)", adapter = socket.LWIP_GP, type = "cellular", expected_supported = true},
        {name = "WiFi网卡(LWIP_STA)", adapter = socket.LWIP_STA, type = "wifi", expected_supported = true},
        {name = "默认(nil)", adapter = nil, type = "default", expected_supported = true}
    }
elseif device_name == "Air780EPM" or device_name == "Air780EHM" or device_name == "Air780EHV" or 
       device_name == "Air780EGH" or device_name == "Air780EGG" or device_name == "Air780EGP" then
    -- Air780系列: 仅支持4G，WiFi不支持（预期失败）
    ALL_ADAPTERS = {
        {name = "WiFi网卡(LWIP_STA)", adapter = socket.LWIP_STA, type = "wifi", expected_supported = false},
        {name = "4G网卡(LWIP_GP)", adapter = socket.LWIP_GP, type = "cellular", expected_supported = true},
        {name = "默认(nil)", adapter = nil, type = "default", expected_supported = true}
    }
elseif device_name == "Air8101" then
    -- Air8101: 仅支持WiFi，4G不支持（预期失败）
    ALL_ADAPTERS = {
        {name = "4G网卡(LWIP_GP)", adapter = socket.LWIP_GP, type = "cellular", expected_supported = false},
        {name = "WiFi网卡(LWIP_STA)", adapter = socket.LWIP_STA, type = "wifi", expected_supported = true},
        {name = "默认(nil)", adapter = nil, type = "default", expected_supported = true}
    }
else
    ALL_ADAPTERS = {
        {name = "默认(nil)", adapter = nil, type = "default", expected_supported = true}
    }
end

local taskName = "UDP_TASK"

-- 获取网卡IP地址
local function get_adapter_ip(adapter)
    local success, ip = pcall(socket.localIP, adapter)
    if success and ip and ip ~= "0.0.0.0" then
        return ip
    end
    return "未就绪"
end

-- 检查是否为网卡不支持的错误
local function is_adapter_not_supported_error(err_msg)
    if not err_msg then return false end
    local err_lower = string.lower(err_msg)
    return err_lower:find("adapter") ~= nil or
           err_lower:find("invalid") ~= nil or
           err_lower:find("not supported") ~= nil or
           err_lower:find("create fail") ~= nil or
           err_lower:find("alloc") ~= nil
end

-- WiFi连接函数（仅当wlan可用时）
local function wifi_connect_demo()
    if not is_wlan_available() then
        log.info("udp_test", "WiFi功能不可用，跳过WiFi连接")
        return false
    end
    
    if wlan.ready() then
        local ip = wlan.getIP()
        if ip and ip ~= "0.0.0.0" then
            log.info("udp_test", string.format("WiFi已连接, IP: %s", ip))
            return true
        end
    end

    log.info("udp_test", "开始连接WiFi: " .. ssid)

    local wlan_result = wlan.connect(ssid, password, 1)
    if not wlan_result then
        log.warn("udp_test", "WiFi连接发起失败")
        return false
    end

    for i = 1, 15 do
        sys.wait(1000)
        if wlan.ready() then
            sys.wait(500)
            local ip = wlan.getIP()
            if ip and ip ~= "0.0.0.0" then
                log.info("udp_test", string.format("WiFi连接成功, IP: %s", ip))
                return true
            end
        end
    end

    log.warn("udp_test", "WiFi连接超时")
    return false
end

-- 输出测试结果汇总
local function print_test_summary(test_name)
    log.info("udp_test", string.rep("=", 60))
    log.info("udp_test", string.format("测试[%s] 结果汇总:", test_name))
    
    local supported_count = 0
    local unsupported_count = 0
    local failed_count = 0
    local expected_success_count = 0
    local expected_fail_count = 0
    local unexpected_results = {}
    
    for name, result in pairs(adapter_test_results) do
        local expected = result.expected_supported
        local actual = result.actual_supported
        
        if result.connected then
            if expected then
                log.info("udp_test", string.format("  ✓ %s: 连接成功 (IP: %s) [符合预期]", name, result.ip or "未知"))
                expected_success_count = expected_success_count + 1
            else
                log.error("udp_test", string.format("  ✗ %s: 连接成功 [不符合预期！预期不支持但实际支持]", name))
                table.insert(unexpected_results, string.format("%s 预期不支持但连接成功", name))
            end
            supported_count = supported_count + 1
        elseif result.error_type == "adapter_not_supported" then
            if not expected then
                log.warn("udp_test", string.format("  ✗ %s: 网卡不支持 [符合预期]", name))
                expected_fail_count = expected_fail_count + 1
            else
                log.error("udp_test", string.format("  ✗ %s: 网卡不支持 [不符合预期！预期支持但实际不支持]", name))
                table.insert(unexpected_results, string.format("%s 预期支持但网卡不支持", name))
            end
            unsupported_count = unsupported_count + 1
        else
            log.error("udp_test", string.format("  ✗ %s: %s", name, tostring(result.error)))
            if expected then
                table.insert(unexpected_results, string.format("%s 预期支持但发生错误: %s", name, tostring(result.error)))
            end
            failed_count = failed_count + 1
        end
    end
    
    log.info("udp_test", "")
    log.info("udp_test", string.format("统计: 成功=%d, 不支持=%d, 失败=%d", supported_count, unsupported_count, failed_count))
    log.info("udp_test", string.format("预期验证: 预期成功=%d, 预期失败=%d", expected_success_count, expected_fail_count))
    
    if #unexpected_results > 0 then
        log.error("udp_test", "不符合预期的结果:")
        for _, msg in ipairs(unexpected_results) do
            log.error("udp_test", "  - " .. msg)
        end
    end
    
    if expected_success_count > 0 and expected_fail_count > 0 then
        log.info("udp_test", "✓ 自动适配功能验证通过: 不支持的网卡正确报错，支持的网卡成功连接")
    elseif expected_fail_count > 0 and expected_success_count == 0 then
        log.error("udp_test", "✗ 自动适配功能验证失败: 没有找到支持的网卡")
    elseif expected_fail_count == 0 and expected_success_count > 0 then
        if #unexpected_results == 0 then
            log.info("udp_test", "✓ 所有配置的网卡均支持")
        else
            log.error("udp_test", "✗ 部分网卡行为与预期不符")
        end
    end
    
    log.info("udp_test", string.rep("=", 60))
end

-- 尝试UDP连接指定适配器
local function try_connect_adapter(adapter, adapter_name, expected_supported)
    log.info("udp_test", string.format("尝试连接适配器 [%s] (预期支持: %s)...", adapter_name, tostring(expected_supported)))
    
    -- 对于WiFi网卡，尝试连接WiFi（仅当wlan可用时）
    if adapter_name:find("LWIP_STA") and is_wlan_available() then
        if not wlan.ready() then
            log.info("udp_test", "WiFi未连接，尝试连接...")
            local wifi_ok = wifi_connect_demo()
            if expected_supported == true and not wifi_ok then
                assert(false, string.format("适配器[%s] 预期支持但WiFi连接失败", adapter_name))
            end
        end
    elseif adapter_name:find("LWIP_STA") and not is_wlan_available() then
        log.info("udp_test", "WiFi网卡不可用（模块不支持WiFi）")
    end
    
    local server_config = UDP_SERVERS_CONFIG[1]
    local socket_client = nil
    local error_msg = nil
    local error_type = nil
    
    -- 创建socket对象
    local create_ok, create_result = pcall(socket.create, adapter, taskName)
    if not create_ok or create_result == nil then
        error_msg = "创建socket对象失败: " .. tostring(create_result)
        
        -- 判断是否为网卡不支持的错误
        if is_adapter_not_supported_error(error_msg) or tostring(create_result):find("adapter") then
            error_type = "adapter_not_supported"
            if expected_supported == true then
                assert(false, string.format("适配器[%s] 预期支持但创建socket失败（网卡不支持）", adapter_name))
            else
                log.warn("udp_test", string.format("✗ 适配器 [%s] 网卡不支持（符合预期）", adapter_name))
            end
        else
            error_type = "create_failed"
            if expected_supported == true then
                assert(false, string.format("适配器[%s] 预期支持但创建socket失败: %s", adapter_name, error_msg))
            end
        end
        
        adapter_test_results[adapter_name] = {
            connected = false,
            error = error_msg,
            error_type = error_type,
            expected_supported = expected_supported,
            actual_supported = (error_type ~= "adapter_not_supported"),
            ip = get_adapter_ip(adapter)
        }
        
        return false, error_msg, error_type, nil
    end
    
    socket_client = create_result
    assert(socket_client ~= nil, string.format("适配器[%s] socket对象创建失败", adapter_name))
    log.info("udp_test", string.format("适配器[%s] socket对象创建成功", adapter_name))
    
    -- 配置socket为UDP模式
    local config_result = socket.config(socket_client, nil, true, false)
    assert(config_result == true, string.format("适配器[%s] UDP模式配置失败", adapter_name))
    log.info("udp_test", string.format("适配器[%s] UDP模式配置成功", adapter_name))
    
    -- 连接UDP服务器
    local connect_result = libnet.connect(taskName, TEST_CONFIG.connect_timeout, socket_client, 
                                           server_config.host, server_config.port)
    
    if not connect_result then
        error_msg = string.format("连接服务器 %s:%d 失败", server_config.host, server_config.port)
        error_type = "connect_failed"
        
        if expected_supported == true then
            assert(false, string.format("适配器[%s] 预期支持但连接UDP服务器失败", adapter_name))
        end
        
        pcall(socket.release, socket_client)
        
        adapter_test_results[adapter_name] = {
            connected = false,
            error = error_msg,
            error_type = error_type,
            expected_supported = expected_supported,
            actual_supported = true,
            ip = get_adapter_ip(adapter)
        }
        
        return false, error_msg, error_type, nil
    end
    
    assert(connect_result == true, string.format("适配器[%s] UDP连接失败", adapter_name))
    log.info("udp_test", string.format("✓ 适配器 [%s] UDP连接成功", adapter_name))
    
    adapter_test_results[adapter_name] = {
        connected = true,
        error = nil,
        error_type = nil,
        expected_supported = expected_supported,
        actual_supported = true,
        ip = get_adapter_ip(adapter),
        socket_client = socket_client
    }
    
    return true, nil, nil, socket_client
end

-- UDP回环测试
local function udp_loopback_test(socket_client, adapter_name, server_config, test_seq)
    local send_buff = zbuff.create(1024)
    local recv_buff = zbuff.create(1024)
    
    assert(send_buff ~= nil, string.format("适配器[%s] 发送缓冲区创建失败", adapter_name))
    assert(recv_buff ~= nil, string.format("适配器[%s] 接收缓冲区创建失败", adapter_name))
    
    -- 生成测试数据
    local current_time = os.time()
    local date_table = os.date("*t", current_time)
    
    local test_str = string.format(
        '{"adapter":"%s","seq":%d,"time":%d,"date":"%04d-%02d-%02d %02d:%02d:%02d","data":"test_message_%d"}',
        adapter_name, test_seq, current_time, date_table.year, date_table.month,
        date_table.day, date_table.hour, date_table.min, date_table.sec, test_seq)
    
    log.info("udp_test", string.format("适配器[%s] 第%d次发送: %s", adapter_name, test_seq, test_str))
    
    -- 发送数据
    send_buff:write(test_str)
    assert(send_buff:used() > 0, string.format("适配器[%s] 数据写入失败", adapter_name))
    
    local succ, full = libnet.tx(taskName, 0, socket_client, send_buff)
    assert(type(succ) == "boolean" and type(full) == "boolean", 
           string.format("适配器[%s] libnet.tx返回值类型错误", adapter_name))
    assert(succ == true, string.format("适配器[%s] 数据发送失败", adapter_name))
    
    local send_data = send_buff:query()
    assert(send_data ~= nil, string.format("适配器[%s] 读取发送缓冲区失败", adapter_name))
    send_buff:del()
    
    -- 等待接收数据
    local wait_result, event_param = libnet.wait(taskName, TEST_CONFIG.recv_timeout, socket_client)
    
    if wait_result then
        local rx_succ, param, _, _ = socket.rx(socket_client, recv_buff)
        if rx_succ and param and param > 0 then
            local recv_data = recv_buff:query()
            assert(recv_data ~= nil, string.format("适配器[%s] 读取接收缓冲区失败", adapter_name))
            recv_buff:del()
            
            assert(recv_data == send_data,
                string.format("适配器[%s] 第%d次回环数据不匹配!\n发送: %s\n接收: %s", 
                    adapter_name, test_seq, send_data, recv_data))
            
            log.info("udp_test", string.format("适配器[%s] ✓ 第%d次回环成功", adapter_name, test_seq))
            return true
        else
            log.warn("udp_test", string.format("适配器[%s] 第%d次接收失败: rx_succ=%s, param=%s", 
                      adapter_name, test_seq, tostring(rx_succ), tostring(param)))
            return false
        end
    else
        log.warn("udp_test", string.format("适配器[%s] 第%d次接收超时", adapter_name, test_seq))
        return false
    end
end

-- 执行UDP测试
local function run_udp_test_on_adapter(adapter_name, socket_client)
    local server_config = UDP_SERVERS_CONFIG[1]
    local success_count = 0
    
    for i = 1, TEST_CONFIG.test_count do
        local ok = udp_loopback_test(socket_client, adapter_name, server_config, i)
        if ok then
            success_count = success_count + 1
        end
        sys.wait(500)
    end
    
    local success_rate = success_count / TEST_CONFIG.test_count
    log.info("udp_test", string.format("适配器[%s] 测试完成: 成功%d/%d (%.1f%%)", 
              adapter_name, success_count, TEST_CONFIG.test_count, success_rate * 100))
    
    assert(success_count > 0, string.format("适配器[%s] 所有测试均失败", adapter_name))
    
    return success_count == TEST_CONFIG.test_count
end

-- 执行测试的通用函数
local function run_test_on_adapters(test_name, test_func)
    local test_passed = false
    local last_error = nil
    local successful_adapter = nil
    
    log.info("udp_test", string.format("开始测试 [%s]，共 %d 个适配器", test_name, #ALL_ADAPTERS))
    
    for _, adapter_info in ipairs(ALL_ADAPTERS) do
        local adapter = adapter_info.adapter
        local name = adapter_info.name
        local expected_supported = adapter_info.expected_supported
        
        log.info("udp_test", string.format("测试[%s]: 尝试适配器 [%s] (预期支持: %s)", 
                  test_name, name, tostring(expected_supported)))
        
        -- 尝试连接
        local connect_ok, connect_err, error_type, socket_client = 
            try_connect_adapter(adapter, name, expected_supported)
        
        if connect_ok and socket_client then
            -- 执行具体测试
            local test_ok, test_err = pcall(test_func, name, socket_client)
            
            -- 关闭连接
            pcall(function()
                libnet.close(taskName, 5000, socket_client)
                socket.release(socket_client)
            end)
            
            if test_ok then
                log.info("udp_test", string.format("✓ 适配器 [%s] %s 测试通过", name, test_name))
                test_passed = true
                successful_adapter = name
                if not TEST_CONFIG.test_all_adapters and TEST_CONFIG.enable_smart_switch then
                    break
                end
            else
                log.error("udp_test", string.format("✗ 适配器 [%s] %s 测试失败: %s", name, test_name, test_err))
                last_error = test_err
                if adapter_test_results[name] then
                    adapter_test_results[name].error = test_err
                    adapter_test_results[name].error_type = "test_failed"
                end
                if expected_supported == true then
                    assert(false, string.format("适配器[%s] 预期支持但测试失败: %s", name, test_err))
                end
            end
        else
            log.warn("udp_test", string.format("适配器 [%s] 连接失败 (%s)，跳过测试", name, connect_err or "未知错误"))
            last_error = connect_err
        end
        
        sys.wait(200)
    end
    
    print_test_summary(test_name)
    
    if not test_passed then
        log.error("udp_test", string.format("测试[%s] 所有适配器均失败", test_name))
    else
        log.info("udp_test", string.format("测试[%s] 成功使用适配器: %s", test_name, successful_adapter))
    end
    
    return test_passed
end

-- ========== 以下为测试用例 ==========

function udp_test.test_udp_client_creation()
    local function do_creation_test(adapter_name, socket_client)
        assert(socket_client ~= nil, string.format("适配器[%s] socket对象为空", adapter_name))
        log.info("udp_test", string.format("适配器[%s] socket对象创建成功", adapter_name))
        return true
    end
    
    run_test_on_adapters("UDP客户端创建测试", do_creation_test)
end

function udp_test.test_udp_socket_config()
    local function do_config_test(adapter_name, socket_client)
        local config_result = socket.config(socket_client, nil, true, false)
        assert(config_result == true, string.format("适配器[%s] UDP模式配置失败", adapter_name))
        log.info("udp_test", string.format("适配器[%s] UDP模式配置成功", adapter_name))
        
        local config_port_result = socket.config(socket_client, 8888, true, false)
        assert(config_port_result == true, string.format("适配器[%s] 配置本地端口失败", adapter_name))
        log.info("udp_test", string.format("适配器[%s] 本地端口配置成功", adapter_name))
        
        return true
    end
    
    run_test_on_adapters("UDP配置测试", do_config_test)
end

function udp_test.test_udp_send_recv()
    local function do_send_recv_test(adapter_name, socket_client)
        local result = run_udp_test_on_adapter(adapter_name, socket_client)
        assert(result == true, string.format("适配器[%s] UDP发送接收测试失败", adapter_name))
        return true
    end
    
    run_test_on_adapters("UDP发送接收测试", do_send_recv_test)
end

function udp_test.test_udp_multi_packet()
    local function do_multi_packet_test(adapter_name, socket_client)
        local success_count = 0
        local total_count = 5
        
        for i = 1, total_count do
            local ok = udp_loopback_test(socket_client, adapter_name, UDP_SERVERS_CONFIG[1], i)
            if ok then
                success_count = success_count + 1
            end
            sys.wait(300)
        end
        
        assert(success_count >= total_count * 0.7, 
               string.format("适配器[%s] 多包测试成功率过低: %d/%d", adapter_name, success_count, total_count))
        
        log.info("udp_test", string.format("适配器[%s] 多包测试: 成功%d/%d", adapter_name, success_count, total_count))
        return true
    end
    
    run_test_on_adapters("UDP多包测试", do_multi_packet_test)
end

function udp_test.test_udp_invalid_server()
    local function do_invalid_server_test(adapter_name, socket_client)
        local test_buff = zbuff.create(1024)
        assert(test_buff ~= nil, "测试缓冲区创建失败")
        
        test_buff:write("test to invalid server")
        
        local succ, full = pcall(libnet.tx, taskName, 3000, socket_client, test_buff)
        log.info("udp_test", string.format("适配器[%s] 无效服务器测试完成, 发送结果: %s", adapter_name, tostring(succ)))
        return true
    end
    
    run_test_on_adapters("UDP无效服务器测试", do_invalid_server_test)
end

function udp_test.test_udp_state_check()
    local function do_state_check_test(adapter_name, socket_client)
        local state, str = socket.state(socket_client)
        log.info("udp_test", string.format("适配器[%s] socket状态: %d (%s)", adapter_name, state, str or "未知"))
        assert(state == 5 or state == 1, 
               string.format("适配器[%s] socket状态异常: state=%d", adapter_name, state))
        return true
    end
    
    run_test_on_adapters("UDP状态检查测试", do_state_check_test)
end

-- 获取完整测试状态报告
function udp_test.get_test_status()
    log.info("udp_test", "========== 完整测试状态报告 ==========")
    log.info("udp_test", "模块: " .. device_name)
    log.info("udp_test", "")
    
    local supported_adapters = {}
    local unsupported_adapters = {}
    
    for _, adapter_info in ipairs(ALL_ADAPTERS) do
        local name = adapter_info.name
        local result = adapter_test_results[name] or {}
        local expected = adapter_info.expected_supported
        
        if result.error_type == "adapter_not_supported" then
            table.insert(unsupported_adapters, name)
            if expected == false then
                log.warn("udp_test", string.format("✗ 适配器[%s]: 不支持 [符合预期]", name))
            else
                log.error("udp_test", string.format("✗ 适配器[%s]: 不支持 [不符合预期！]", name))
            end
        elseif result.connected == true then
            table.insert(supported_adapters, name)
            if expected == true then
                log.info("udp_test", string.format("✓ 适配器[%s]: 支持并连接成功 [符合预期] (IP: %s)", 
                          name, result.ip or "未知"))
            else
                log.warn("udp_test", string.format("? 适配器[%s]: 支持并连接成功 [不符合预期]", name))
            end
        else
            log.warn("udp_test", string.format("? 适配器[%s]: %s", name, tostring(result.error or "未测试")))
        end
    end
    
    log.info("udp_test", "")
    if #unsupported_adapters > 0 then
        log.info("udp_test", "【不支持的网卡】: " .. table.concat(unsupported_adapters, ", "))
    end
    if #supported_adapters > 0 then
        log.info("udp_test", "【支持的网卡】: " .. table.concat(supported_adapters, ", "))
    end
    
    if #unsupported_adapters > 0 and #supported_adapters > 0 then
        log.info("udp_test", "✓ 自动适配功能验证通过: 不支持的网卡正确报错后成功切换到支持的网卡")
    elseif #unsupported_adapters > 0 and #supported_adapters == 0 then
        log.error("udp_test", "✗ 自动适配功能验证失败: 所有网卡均不支持")
    elseif #unsupported_adapters == 0 and #supported_adapters > 0 then
        log.info("udp_test", "✓ 所有配置的网卡均支持")
    end
    
    log.info("udp_test", "==========================================")
end

function udp_test.setUp()
    log.info("udp_test", "setUp - 准备UDP测试环境")
end

function udp_test.tearDown()
    for name, result in pairs(adapter_test_results) do
        if result.socket_client then
            pcall(function()
                libnet.close(taskName, 5000, result.socket_client)
                socket.release(result.socket_client)
            end)
            result.socket_client = nil
        end
    end
    log.info("udp_test", "tearDown - 清理UDP测试环境")
end

return udp_test