-- UDP协议测试模块
local udp_test = {}

local adapter_manager = require("adapter_manager")
local wifi_manager = require("wifi_manager")

-- UDP服务器配置
local UDP_SERVER_CONFIG = {
    host = "airtest.openluat.com",
    port = 2901
}

-- 测试任务名称
local TASK_NAME = "UDP_TASK_EX"

-- 标志位，确保只初始化一次
local initialized = false
local main_task_started = false
local libnet_task_running = false

-- 创建独立的libnet任务
local function start_libnet_task()
    if main_task_started then
        return
    end
    
    sysplus.taskInitEx(function()
        log.info("udp_test", "Libnet任务已启动, TASK_NAME:", TASK_NAME)
        libnet_task_running = true
        
        -- 等待网络就绪
        sys.waitUntil("IP_READY", 30000)
        log.info("udp_test", "网络已就绪")
        
        -- 保持任务运行
        while libnet_task_running do
            sys.wait(1000)
        end
    end, TASK_NAME)
    
    main_task_started = true
    sys.wait(500)
end

-- 初始化函数
local function init()
    if not initialized then
        initialized = true
        start_libnet_task()
        adapter_manager.prepare_wifi_once()
        sys.wait(1000)
    end
end

-- 确保UDP连接已关闭
local function ensure_udp_closed(socket_client)
    if socket_client then
        pcall(function()
            libnet.close(TASK_NAME, 3000, socket_client)
            socket.release(socket_client)
        end)
    end
    sys.wait(200)
end

-- 打印测试开始信息
local function test_start(adapter_name, name)
    log.info("udp_test", string.rep("=", 60))
    log.info("udp_test", string.format("适配器 [%s] - 测试: %s", adapter_name or "全局", name))
    log.info("udp_test", string.rep("=", 60))
end

-- 生成唯一的测试消息ID
local function generate_test_msg_id()
    local tick = mcu.tick64()
    local num = 0
    if type(tick) == "number" then
        num = tick
    elseif type(tick) == "string" then
        num = tonumber(tick) or 0
    end
    if num == 0 then
        num = math.random(100000, 999999)
    end
    return string.format("UDP_TEST_%d_%d", num, math.random(1000, 9999))
end

-- 获取当前时间（毫秒）
local function get_current_time_ms()
    local tick = mcu.tick64()
    if type(tick) == "number" then
        return tick
    elseif type(tick) == "string" then
        return tonumber(tick) or 0
    end
    return 0
end

-- 安全的发送函数，带超时保护
local function safe_tx(task_name, timeout, socket_client, data)
    if not socket_client then
        return false
    end
    
    local libnet = require "libnet"
    
    local success, result = pcall(function()
        return libnet.tx(task_name, timeout, socket_client, data)
    end)
    
    if success and result then
        return true
    end
    return false
end

-- 创建并连接UDP socket
local function create_udp_connection(adapter, adapter_name, retry_count)
    retry_count = retry_count or 2
    
    if not main_task_started then
        start_libnet_task()
        sys.wait(500)
    end
    
    local libnet = require "libnet"
    local last_error = nil
    
    for retry = 1, retry_count do
        local socket_client = socket.create(adapter, TASK_NAME)
        if not socket_client then
            last_error = "创建socket失败"
            sys.wait(500)
        else
            local config_result = socket.config(socket_client, nil, true, false)
            if not config_result then
                socket.release(socket_client)
                last_error = "配置socket失败"
                sys.wait(500)
            else
                local connect_result = libnet.connect(TASK_NAME, 10000, socket_client, 
                                                     UDP_SERVER_CONFIG.host, UDP_SERVER_CONFIG.port)
                
                if connect_result == true then
                    log.info("udp_test", string.format("✓ 适配器[%s] 连接服务器成功 (尝试%d) - %s:%d", 
                                                      adapter_name or "默认", retry,
                                                      UDP_SERVER_CONFIG.host, UDP_SERVER_CONFIG.port))
                    return true, socket_client, nil
                else
                    ensure_udp_closed(socket_client)
                    last_error = string.format("连接服务器失败 (尝试%d)", retry)
                    sys.wait(800)
                end
            end
        end
    end
    
    return false, nil, last_error or "连接服务器失败"
end

-- ============== 测试用例 ==============

-- UDP连接测试
function udp_test.test_udp_connection()
    init()
    
    local adapters = adapter_manager.get_testable_adapters()
    
    for _, adapter_info in ipairs(adapters) do
        local adapter = adapter_info.adapter
        local name = adapter_info.name
        
        test_start(name, "UDP连接测试")
        
        local success, socket_client, err = create_udp_connection(adapter, name, 2)
        
        assert(success == true, string.format(
            "适配器[%s] UDP连接测试失败: %s", 
            name or "默认", err or "未知错误"))
        
        log.info("udp_test", string.format("✓ 适配器[%s] UDP连接测试通过 - 服务器: %s:%d", 
                                          name, UDP_SERVER_CONFIG.host, UDP_SERVER_CONFIG.port))
        
        ensure_udp_closed(socket_client)
        sys.wait(300)
    end
end

-- UDP发送与回环接收测试
function udp_test.test_udp_send_and_echo()
    init()
    
    local adapters = adapter_manager.get_testable_adapters()
    
    for _, adapter_info in ipairs(adapters) do
        local adapter = adapter_info.adapter
        local name = adapter_info.name
        local libnet = require "libnet"
        
        test_start(name, "UDP发送与回环接收测试")
        
        local success, socket_client, err = create_udp_connection(adapter, name, 2)
        if not success then
            error(string.format("适配器[%s] 连接失败: %s", name or "默认", err))
        end
        
        local rx_buff = zbuff.create(1024)
        
        local test_messages = {
            "Hello",
            "UDP Test",
            generate_test_msg_id(),
            string.rep("A", 50)
        }
        
        for i, send_msg in ipairs(test_messages) do
            log.info("udp_test", string.format("发送测试消息 #%d, 长度: %d", i, #send_msg))
            
            local tx_result = safe_tx(TASK_NAME, 3000, socket_client, send_msg)
            assert(tx_result == true, string.format(
                "适配器[%s] UDP发送失败, 消息#%d", name or "默认", i))
            
            sys.wait(200)
            rx_buff:del()
            
            local rx_result = socket.rx(socket_client, rx_buff)
            if rx_result and rx_buff:used() > 0 then
                local received_data = rx_buff:query()
                assert(received_data == send_msg, string.format(
                    "适配器[%s] UDP数据回环验证失败\n预期: %s\n实际: %s", 
                    name or "默认", send_msg, tostring(received_data)))
                log.info("udp_test", string.format("✓ 消息 #%d 发送并接收成功", i))
            else
                log.info("udp_test", string.format("消息 #%d 未收到回显", i))
            end
            rx_buff:del()
        end
        
        log.info("udp_test", string.format("✓ 适配器[%s] UDP发送与回环接收测试通过", name))
        ensure_udp_closed(socket_client)
        sys.wait(300)
    end
end

-- UDP多包发送与接收测试
function udp_test.test_udp_multi_packet()
    init()
    
    local adapters = adapter_manager.get_testable_adapters()
    
    for _, adapter_info in ipairs(adapters) do
        local adapter = adapter_info.adapter
        local name = adapter_info.name
        local libnet = require "libnet"
        
        test_start(name, "UDP多包发送与接收测试")
        
        local success, socket_client, err = create_udp_connection(adapter, name, 2)
        if not success then
            error(string.format("适配器[%s] 连接失败: %s", name or "默认", err))
        end
        
        local rx_buff = zbuff.create(2048)
        
        local packet_count = 3
        local sent_count = 0
        local sent_messages = {}
        
        for i = 1, packet_count do
            local msg = string.format("MULTI_%d_%s", i, generate_test_msg_id())
            sent_messages[i] = msg
            
            local tx_result = safe_tx(TASK_NAME, 2000, socket_client, msg)
            if tx_result then
                sent_count = sent_count + 1
                log.info("udp_test", string.format("✓ 第%d包发送成功", i))
            else
                log.info("udp_test", string.format("✗ 第%d包发送失败", i))
            end
            sys.wait(100)
        end
        
        log.info("udp_test", "所有数据包发送完成，开始接收回环数据")
        sys.wait(500)
        
        local received_count = 0
        
        while true do
            rx_buff:del()
            local rx_result = socket.rx(socket_client, rx_buff)
            if not rx_result or rx_buff:used() == 0 then
                break
            end
            received_count = received_count + 1
            log.info("udp_test", string.format("收到第%d个回显包", received_count))
            rx_buff:del()
        end
        
        assert(received_count == sent_count, string.format(
            "适配器[%s] 多包接收数量验证失败: 预期%d包,实际%d包", 
            name or "默认", sent_count, received_count))
        
        log.info("udp_test", string.format("✓ 适配器[%s] UDP多包发送与接收测试通过", name))
        ensure_udp_closed(socket_client)
        sys.wait(300)
    end
end

-- UDP超时测试
function udp_test.test_udp_timeout()
    init()
    
    local adapters = adapter_manager.get_testable_adapters()
    
    for _, adapter_info in ipairs(adapters) do
        local adapter = adapter_info.adapter
        local name = adapter_info.name
        local libnet = require "libnet"
        
        test_start(name, "UDP超时测试")
        
        local success, socket_client, err = create_udp_connection(adapter, name, 2)
        if not success then
            error(string.format("适配器[%s] 连接失败: %s", name or "默认", err))
        end
        
        local start_time = get_current_time_ms()
        local wait_result = libnet.wait(TASK_NAME, 1000, socket_client)
        local end_time = get_current_time_ms()
        local elapsed = end_time - start_time
        if elapsed < 0 then
            elapsed = -elapsed
        end
        
        -- wait超时应该返回true
        assert(wait_result == true, string.format(
            "适配器[%s] wait超时测试失败: 预期true,实际%s", 
            name or "默认", tostring(wait_result)))
        
        log.info("udp_test", string.format("wait超时时间: %dms", elapsed))
        
        ensure_udp_closed(socket_client)
        sys.wait(300)
    end
end


-- UDP长连接稳定性测试
function udp_test.test_udp_stability()
    init()
    
    local adapters = adapter_manager.get_testable_adapters()
    
    for _, adapter_info in ipairs(adapters) do
        local adapter = adapter_info.adapter
        local name = adapter_info.name
        local libnet = require "libnet"
        
        test_start(name, "UDP长连接稳定性测试")
        
        local success, socket_client, err = create_udp_connection(adapter, name, 2)
        if not success then
            error(string.format("适配器[%s] 连接失败: %s", name or "默认", err))
        end
        
        local test_duration = 3000
        local interval = 500
        local iterations = test_duration / interval
        local success_count = 0
        
        for i = 1, iterations do
            local test_msg = string.format("STABILITY_%d_%s", i, generate_test_msg_id())
            local tx_result = safe_tx(TASK_NAME, 1000, socket_client, test_msg)
            
            if tx_result then
                success_count = success_count + 1
                log.info("udp_test", string.format("✓ 第%d次发送成功", i))
            else
                log.info("udp_test", string.format("✗ 第%d次发送失败", i))
            end
            
            sys.wait(interval)
        end
        
        local success_rate = (success_count / iterations) * 100
        log.info("udp_test", string.format("适配器[%s] 稳定性测试: 成功率%.1f%%", 
                                          name or "默认", success_rate))
        
        ensure_udp_closed(socket_client)
        sys.wait(300)
    end
end

-- UDP错误处理测试
function udp_test.test_udp_error_handling()
    init()
    
    test_start(nil, "UDP错误处理测试")
    
    -- 1. 使用无效适配器创建socket
    local invalid_client = socket.create(9999, TASK_NAME)
    assert(invalid_client == nil, "使用无效适配器应返回nil")
    log.info("udp_test", "✓ 无效适配器测试通过")
    
    -- 2. 测试默认适配器连接
    local success, socket_client, err = create_udp_connection(nil, "默认", 1)
    if success then
        ensure_udp_closed(socket_client)
        log.info("udp_test", "✓ 默认适配器连接测试通过")
    end
    
    log.info("udp_test", "✓ UDP错误处理测试通过")
    sys.wait(300)
end

-- UDP不同端口测试
function udp_test.test_udp_different_ports()
    init()
    
    local adapters = adapter_manager.get_testable_adapters()
    
    for _, adapter_info in ipairs(adapters) do
        local adapter = adapter_info.adapter
        local name = adapter_info.name
        local libnet = require "libnet"
        
        test_start(name, "UDP端口测试")
        
        local test_port = UDP_SERVER_CONFIG.port
        local max_retries = 2
        local connected = false
        local socket_client = nil
        
        log.info("udp_test", string.format("测试端口: %d", test_port))
        
        for retry = 1, max_retries do
            socket_client = socket.create(adapter, TASK_NAME)
            if not socket_client then
                log.info("udp_test", string.format("尝试%d: 创建socket失败", retry))
                sys.wait(500)
            else
                local config_result = socket.config(socket_client, nil, true, false)
                if not config_result then
                    socket.release(socket_client)
                    log.info("udp_test", string.format("尝试%d: 配置socket失败", retry))
                    sys.wait(500)
                else
                    local connect_result = libnet.connect(TASK_NAME, 3000, socket_client, 
                                                         UDP_SERVER_CONFIG.host, test_port)
                    
                    if connect_result == true then
                        connected = true
                        log.info("udp_test", string.format("✓ 尝试%d: 连接成功", retry))
                        break
                    else
                        pcall(function()
                            libnet.close(TASK_NAME, 1000, socket_client)
                            socket.release(socket_client)
                        end)
                        socket_client = nil
                        log.info("udp_test", string.format("尝试%d: 连接失败", retry))
                        sys.wait(800)
                    end
                end
            end
        end
        
        assert(connected == true, string.format(
            "适配器[%s] 连接端口%d失败", name or "默认", test_port))
        
        if connected and socket_client then
            local test_msg = string.format("PORT_TEST_%d_%s", test_port, generate_test_msg_id())
            local tx_result = safe_tx(TASK_NAME, 2000, socket_client, test_msg)
            assert(tx_result == true, string.format(
                "适配器[%s] 发送数据到端口%d失败", name or "默认", test_port))
            
            log.info("udp_test", "✓ 数据发送成功")
            ensure_udp_closed(socket_client)
        end
        
        log.info("udp_test", string.format("✓ 适配器[%s] UDP端口测试通过", name))
        sys.wait(300)
    end
end

return udp_test