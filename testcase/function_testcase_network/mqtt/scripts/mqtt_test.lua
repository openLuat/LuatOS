local mqtt_test = {}
local device_name = rtos.bsp()

-- ===========================================================================
-- 测试配置
local TEST_CONFIG = {
    test_all_adapters = true,
    connect_timeout = 30000,
}

-- 记录每个适配器的测试结果
local adapter_test_results = {}

-- 网络适配器配置表
local ALL_ADAPTERS = {}

-- WiFi配置
local ssid = "luatos1234"
local password = "12341234"

-- broker参数
local mqtt_host = "lbsmqtt.airm2m.com"
local mqtt_port = 1884
local mqtt_ssl = false
local mqtt_username = ""
local mqtt_password = ""

-- SSL单向认证服务器配置
local mqtts_host = "airtest.openluat.com"
local mqtts_port = 8888
local mqtts_username = "mqtt_hz_test_2"
local mqtts_password = "3bEKUb"

-- 检查wlan库是否可用
local function is_wlan_available()
    return wlan ~= nil and type(wlan.ready) == "function"
end

-- 设备类型判断和适配器配置
if device_name == "Air8000" then
    ALL_ADAPTERS = {
        {name = "4G网卡(LWIP_GP)", adapter = socket.LWIP_GP, expected = true},
        {name = "WiFi网卡(LWIP_STA)", adapter = socket.LWIP_STA, expected = true},
        {name = "默认网卡", adapter = nil, expected = true}
    }
elseif device_name == "Air780EPM" or device_name == "Air780EHM" or device_name == "Air780EHV" or 
       device_name == "Air780EGH" or device_name == "Air780EGG" or device_name == "Air780EGP" then
    ALL_ADAPTERS = {
        {name = "WiFi网卡(LWIP_STA)", adapter = socket.LWIP_STA, expected = false},
        {name = "4G网卡(LWIP_GP)", adapter = socket.LWIP_GP, expected = true},
        {name = "默认网卡", adapter = nil, expected = true}
    }
elseif device_name == "Air8101" then
    ALL_ADAPTERS = {
        {name = "4G网卡(LWIP_GP)", adapter = socket.LWIP_GP, expected = false},
        {name = "WiFi网卡(LWIP_STA)", adapter = socket.LWIP_STA, expected = true},
        {name = "默认网卡", adapter = nil, expected = true}
    }
else
    ALL_ADAPTERS = {{name = "默认网卡", adapter = nil, expected = true}}
end

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
    local err_lower = string.lower(tostring(err_msg))
    return err_lower:find("adapter") ~= nil or
           err_lower:find("invalid") ~= nil or
           err_lower:find("index") ~= nil or
           err_lower:find("faid") ~= nil or
           err_lower:find("ret -1") ~= nil or
           err_lower:find("network_alloc_ctrl") ~= nil
end

-- WiFi连接函数
local function wifi_connect_demo()
    if not is_wlan_available() then
        return false
    end
    
    if wlan.ready() then
        local ip = wlan.getIP()
        if ip and ip ~= "0.0.0.0" then
            return true
        end
    end

    local wlan_result = wlan.connect(ssid, password, 1)
    if not wlan_result then
        return false
    end

    for i = 1, 15 do
        sys.wait(1000)
        if wlan.ready() then
            sys.wait(500)
            local ip = wlan.getIP()
            if ip and ip ~= "0.0.0.0" then
                return true
            end
        end
    end
    return false
end

-- 生成设备ID
local function generate_fallback_id()
    local timestamp = os.time()
    local tick = rtos and rtos.tick and rtos.tick() or 0
    return string.format("mqtt_test_%d_%d", timestamp, tick)
end

local function get_device_id()
    if mobile and mobile.imei then
        local imei = mobile.imei()
        if imei and imei ~= "" then
            return imei
        end
    end
    if wlan and wlan.getMac then
        local mac = wlan.getMac()
        if mac and mac ~= "" then
            return mac
        end
    end
    if mcu and mcu.unique_id then
        local unique_id = mcu.unique_id()
        if unique_id and type(unique_id) == "table" and unique_id.toHex then
            local hex_id = unique_id:toHex()
            if hex_id and hex_id ~= "" then
                return hex_id
            end
        end
    end
    return generate_fallback_id()
end

-- 输出测试结果汇总
local function print_test_summary(test_name)
    log.info("mqtt_test", string.rep("=", 60))
    log.info("mqtt_test", string.format("测试[%s] 结果汇总:", test_name))
    
    local success_count = 0
    local expected_success = 0
    local expected_fail = 0
    local unexpected = {}
    
    for name, result in pairs(adapter_test_results) do
        if result.test_name == test_name then
            local expected = result.expected
            if result.connected then
                if expected then
                    log.info("mqtt_test", string.format("  ✓ %s: 连接成功 [符合预期]", name))
                    expected_success = expected_success + 1
                else
                    log.error("mqtt_test", string.format("  ✗ %s: 连接成功 [不符合预期]", name))
                    table.insert(unexpected, name)
                end
                success_count = success_count + 1
            elseif result.error_type == "adapter_not_supported" then
                if not expected then
                    log.info("mqtt_test", string.format("  ○ %s: 网卡不支持 [符合预期]", name))
                    expected_fail = expected_fail + 1
                else
                    log.error("mqtt_test", string.format("  ✗ %s: 网卡不支持 [不符合预期]", name))
                    table.insert(unexpected, name)
                end
            else
                if not expected then
                    log.info("mqtt_test", string.format("  ○ %s: %s [符合预期]", name, tostring(result.error or "失败")))
                    expected_fail = expected_fail + 1
                else
                    log.error("mqtt_test", string.format("  ✗ %s: %s [不符合预期]", name, tostring(result.error)))
                    table.insert(unexpected, name)
                end
            end
        end
    end
    
    log.info("mqtt_test", "")
    log.info("mqtt_test", string.format("统计: 连接成功=%d, 预期成功=%d, 预期失败=%d", 
              success_count, expected_success, expected_fail))
    
    if #unexpected > 0 then
        log.error("mqtt_test", "不符合预期的结果:")
        for _, msg in ipairs(unexpected) do
            log.error("mqtt_test", "  - " .. msg)
        end
    end
    
    if expected_success > 0 and expected_fail > 0 then
        log.info("mqtt_test", "✓ 自动适配功能验证通过: 不支持的网卡正确报错，支持的网卡成功连接")
    elseif expected_fail > 0 and expected_success == 0 then
        log.error("mqtt_test", "✗ 自动适配功能验证失败: 没有找到支持的网卡")
    elseif expected_fail == 0 and expected_success > 0 then
        if #unexpected == 0 then
            log.info("mqtt_test", "✓ 所有配置的网卡均支持")
        else
            log.error("mqtt_test", "✗ 部分网卡行为与预期不符")
        end
    end
    
    log.info("mqtt_test", string.rep("=", 60))
end

-- 尝试MQTT连接指定适配器（只测试连接，不测试发布订阅）
local function try_connect_adapter(adapter, adapter_name, expected, test_name, use_ssl)
    log.info("mqtt_test", string.format("尝试连接 [%s] (预期支持: %s)...", adapter_name, tostring(expected)))
    
    local host = use_ssl and mqtts_host or mqtt_host
    local port = use_ssl and mqtts_port or mqtt_port
    local username = use_ssl and mqtts_username or mqtt_username
    local password = use_ssl and mqtts_password or mqtt_password
    
    if adapter_name:find("WiFi") and is_wlan_available() then
        if not wlan.ready() then
            wifi_connect_demo()
        end
    end
    
    local device_id = get_device_id() .. "_" .. test_name .. "_" .. adapter_name:gsub("[^%w]", "")
    local client = nil
    
    -- 创建客户端
    local create_ok, create_result = pcall(mqtt.create, adapter, host, port, use_ssl)
    if not create_ok or create_result == nil then
        local err_detail = tostring(create_result)
        if is_adapter_not_supported_error(err_detail) then
            if expected == true then
                assert(false, string.format("适配器[%s] 预期支持但创建失败（网卡不支持）", adapter_name))
            else
                log.info("mqtt_test", string.format("适配器 [%s] 网卡不支持（符合预期）", adapter_name))
            end
            adapter_test_results[adapter_name .. "_" .. test_name] = {
                connected = false, error_type = "adapter_not_supported",
                expected = expected, test_name = test_name
            }
            return false, nil
        else
            if expected == true then
                assert(false, string.format("适配器[%s] 创建客户端失败: %s", adapter_name, err_detail))
            else
                log.info("mqtt_test", string.format("适配器 [%s] 创建失败（符合预期）", adapter_name))
                adapter_test_results[adapter_name .. "_" .. test_name] = {
                    connected = false, error_type = "create_failed",
                    expected = expected, test_name = test_name, error = err_detail
                }
            end
            return false, nil
        end
    end
    
    client = create_result
    assert(client ~= nil, string.format("适配器[%s] 客户端创建失败", adapter_name))
    
    -- 认证
    local auth_result = client:auth(device_id, username, password, true)
    assert(auth_result == true, string.format("适配器[%s] 认证失败", adapter_name))
    
    client:keepalive(60)
    client:autoreconn(false, 3000)
    
    -- 连接等待
    local conack_received = false
    client:on(function(cl, event, data, payload, meta)
        if event == "conack" then
            conack_received = true
        end
    end)
    
    local conn_result = client:connect()
    assert(conn_result == true, string.format("适配器[%s] 连接请求失败", adapter_name))
    
    -- 等待CONACK
    local ok = false
    for i = 1, 30 do
        sys.wait(1000)
        if conack_received then
            ok = true
            break
        end
    end
    
    if not ok then
        if expected == true then
            assert(false, string.format("适配器[%s] 连接超时", adapter_name))
        else
            log.info("mqtt_test", string.format("适配器 [%s] 连接超时（符合预期）", adapter_name))
            client:close()
            adapter_test_results[adapter_name .. "_" .. test_name] = {
                connected = false, error_type = "timeout",
                expected = expected, test_name = test_name
            }
            return false, nil
        end
    end
    
    log.info("mqtt_test", string.format("✓ 适配器 [%s] MQTT连接成功", adapter_name))
    
    adapter_test_results[adapter_name .. "_" .. test_name] = {
        connected = true, expected = expected, test_name = test_name,
        client = client
    }
    
    client:close()
    return true, nil
end

-- 执行适配器连接测试
local function run_adapter_test(test_name, use_ssl)
    local any_success = false
    local success_adapter = nil
    
    log.info("mqtt_test", string.format("开始测试 [%s]，共 %d 个适配器", test_name, #ALL_ADAPTERS))
    
    for _, adp in ipairs(ALL_ADAPTERS) do
        log.info("mqtt_test", string.format("测试[%s]: 尝试适配器 [%s] (预期支持: %s)", 
                  test_name, adp.name, tostring(adp.expected)))
        
        local ok = try_connect_adapter(adp.adapter, adp.name, adp.expected, test_name, use_ssl)
        
        if ok then
            any_success = true
            success_adapter = adp.name
            log.info("mqtt_test", string.format("✓ 适配器 [%s] %s 通过", adp.name, test_name))
        end
        sys.wait(200)
    end
    
    print_test_summary(test_name)
    
    if any_success then
        log.info("mqtt_test", string.format("测试[%s] 成功使用适配器: %s", test_name, success_adapter))
    else
        log.error("mqtt_test", string.format("测试[%s] 所有适配器均失败", test_name))
    end
    
    return any_success
end

-- ========== 以下为测试用例 ==========

-- 测试1: 基础MQTT连接测试（测试网卡适配器）
function mqtt_test.test_basic_connection()
    run_adapter_test("基础连接测试", false)
end

-- 测试2: SSL连接测试（测试网卡适配器）
function mqtt_test.test_ssl_connection()
    run_adapter_test("SSL连接测试", true)
end

-- 以下为原始MQTT功能测试（使用默认网卡，不测试多适配器）
-- 这些测试保持原有逻辑，确保功能正常

local mqttc
local pub_topic
local sub_topic
local will_topic

function mqtt_test.setUp()
    if mqttc then
        pcall(mqttc.close, mqttc)
    end
    
    local device_id = get_device_id()
    pub_topic = "/luatos/testcase/mqtt/" .. device_id .. "/pub"
    sub_topic = "/luatos/testcase/mqtt/" .. device_id .. "/sub"
    will_topic = "/luatos/testcase/mqtt/" .. device_id .. "/will"
    
    log.info("mqtt_test", "pub_topic:", pub_topic)
    log.info("mqtt_test", "sub_topic:", sub_topic)

    mqttc = mqtt.create(nil, mqtt_host, mqtt_port, mqtt_ssl)
    assert(mqttc, "mqtt.create failed")

    local auth_result = mqttc:auth(device_id, mqtt_username, mqtt_password, true)
    assert(auth_result == true, "auth配置失败")

    mqttc:keepalive(60)
    mqttc:autoreconn(false, 3000)

    mqttc:on(function(client, event, data, payload, meta)
        if event == "conack" then
            sys.publish("mqtt_conack")
        elseif event == "suback" then
            sys.publish("mqtt_suback", data, payload)
        elseif event == "sent" then
            sys.publish("mqtt_sent", data)
        elseif event == "recv" then
            sys.publish("mqtt_recv", data, payload, meta)
        elseif event == "disconnect" then
            sys.publish("mqtt_disconnect", data)
        elseif event == "pong" then
            sys.publish("mqtt_pong")
        end
    end)

    local connect = mqttc:connect()
    assert(connect == true, "mqtt connect failed")

    local ok = sys.waitUntil("mqtt_conack", 30000)
    assert(ok, "mqtt connect timeout")

    local msg_id = mqttc:subscribe({ [pub_topic] = 1, [sub_topic] = 1 })
    assert(msg_id, "subscribe msg id missing")

    local sub_ok, result, err = sys.waitUntil("mqtt_suback", 20000)
    assert(sub_ok and result == true, "subscribe failed: " .. tostring(err))
end

function mqtt_test.tearDown()
    if mqttc then
        pcall(mqttc.close, mqttc)
    end
    mqttc = nil
    sys.wait(200)
end

function mqtt_test.test_ready_state()
    assert(mqttc and mqttc:ready(), "mqtt client not ready")
end

function mqtt_test.test_publish_qos1_echo()
    local payload = "qos1-" .. tostring(rtos and rtos.tick and rtos.tick() or os.time())
    local msg_id = mqttc:publish(pub_topic, payload, 1)
    assert(msg_id, "publish msg id missing")

    sys.waitUntil("mqtt_sent", 10000)
    local ok, topic, recv_payload = sys.waitUntil("mqtt_recv", 20000)
    assert(ok, "no message received")
    assert(topic == pub_topic, "unexpected topic: " .. tostring(topic))
    assert(recv_payload == payload, string.format("payload mismatch: expected %s got %s", payload, tostring(recv_payload)))
end

function mqtt_test.test_publish_qos0_loopback()
    local payload = "qos0-" .. tostring(rtos and rtos.tick and rtos.tick() or os.time())
    mqttc:publish(sub_topic, payload, 0)

    local ok, topic, recv_payload = sys.waitUntil("mqtt_recv", 20000)
    assert(ok, "no message received")
    assert(topic == sub_topic, "unexpected topic: " .. tostring(topic))
    assert(recv_payload == payload, string.format("payload mismatch: expected %s got %s", payload, tostring(recv_payload)))
end

-- QoS2测试
function mqtt_test.test_publish_qos2()
    local qos2_client = nil
    local cleanup = function()
        if qos2_client then
            pcall(qos2_client.close, qos2_client)
            qos2_client = nil
        end
    end
    
    local device_id = get_device_id() .. "_qos2_" .. tostring(os.time())
    local qos2_pub_topic = "/luatos/testcase/mqtt/" .. device_id .. "/qos2_pub"
    
    qos2_client = mqtt.create(nil, mqtts_host, mqtts_port, true)
    assert(qos2_client, "qos2 mqtt create failed")
    
    local auth_result = qos2_client:auth(device_id, mqtts_username, mqtts_password, true)
    assert(auth_result == true, "qos2 auth配置失败")
    
    qos2_client:keepalive(60)
    
    local conack_received = false
    local sub_ready = false
    local sent_ready = false
    local recv_ready = false
    local received_payload = nil
    local received_topic = nil
    
    qos2_client:on(function(client, event, data, payload, meta)
        if event == "conack" then
            conack_received = true
            sys.publish("qos2_conack")
        elseif event == "suback" then
            sub_ready = true
            sys.publish("qos2_suback", data, payload)
        elseif event == "sent" then
            sent_ready = true
            -- sys.publish("qos2_sent", data)
        elseif event == "recv" then
            recv_ready = true
            received_topic = data
            received_payload = payload
            -- sys.publish("qos2_recv", data, payload, meta)
        end
    end)
    
    local connect_result = qos2_client:connect()
    assert(connect_result == true, "qos2 connect failed")
    
    local ok = sys.waitUntil("qos2_conack", 30000)
    assert(ok, "qos2 connection timeout")
    assert(conack_received, "qos2 conack not received")
    
    local sub_msg_id = qos2_client:subscribe(qos2_pub_topic, 2)
    assert(sub_msg_id, "qos2 subscribe msg id missing")
    
    local sub_ok = sys.waitUntil("qos2_suback", 20000)
    assert(sub_ok, "qos2 subscribe timeout")
    assert(sub_ready, "qos2 suback not received")
    
    sys.wait(500)
    
    local payload = "qos2-" .. tostring(rtos and rtos.tick and rtos.tick() or os.time())
    local pub_msg_id = qos2_client:publish(qos2_pub_topic, payload, 2)
    assert(pub_msg_id, "qos2 publish msg id missing")
    
    local num = 0
    while sent_ready == false do
        sys.wait(100)
        num = num + 1
        if num > 100 then
            break
        end
    end
    assert(sent_ready, "qos2 sent not received")

    num = 0
    while recv_ready == false do
        sys.wait(100)
        num = num + 1
        if num > 100 then
            break
        end
    end
    assert(recv_ready, "qos2 recv not received")
    assert(received_topic == qos2_pub_topic, 
        string.format("topic mismatch: expected %s got %s", qos2_pub_topic, tostring(received_topic)))
    assert(received_payload == payload,
        string.format("payload mismatch: expected %s got %s", payload, tostring(received_payload)))
    
    log.info("mqtt_test", "QoS2测试通过")
    cleanup()
end

function mqtt_test.test_publish_before_connect()
    local temp = mqtt.create(nil, mqtt_host, mqtt_port, mqtt_ssl)
    assert(temp, "temp mqtt create failed")
    local auth_result = temp:auth(get_device_id(), mqtt_username, mqtt_password)
    assert(auth_result == true, "auth配置失败")
    local msg_id = temp:publish("/tmp/noconn", "payload", 0)
    assert(msg_id == nil, "publish should fail before connect")
    pcall(temp.close, temp)
end

function mqtt_test.test_connect_invalid_host()
    local bad = mqtt.create(nil, "invalid.luat.host", mqtt_port, mqtt_ssl)
    assert(bad, "bad mqtt create failed")
    local auth_result = bad:auth(get_device_id(), mqtt_username, mqtt_password)
    assert(auth_result == true, "auth配置失败")
    bad:autoreconn(false, 1000)
    bad:on(function(_, event)
        if event == "conack" then
            sys.publish("mqtt_bad_conack")
        end
    end)
    bad:connect()
    local ok = sys.waitUntil("mqtt_bad_conack", 8000)
    assert(not ok, "should not conack on invalid host")
    assert(not bad:ready(), "client should not be ready")
    pcall(bad.close, bad)
end

-- SSL连接测试（使用默认网卡的功能测试）
function mqtt_test.test_ssl_connection_function()
    local ssl_client = nil
    local cleanup = function()
        if ssl_client then
            pcall(ssl_client.close, ssl_client)
            ssl_client = nil
        end
    end
    
    local device_id = get_device_id() .. "_ssl"
    ssl_client = mqtt.create(nil, mqtts_host, mqtts_port, true)
    assert(ssl_client, "ssl mqtt create failed")
    
    local auth_result = ssl_client:auth(device_id, mqtts_username, mqtts_password, true)
    assert(auth_result == true, "ssl auth配置失败")
    
    ssl_client:keepalive(60)
    
    local conack_received = false
    local error_occurred = false
    
    ssl_client:on(function(client, event, data, payload, meta)
        if event == "conack" then
            conack_received = true
            sys.publish("ssl_conack")
        elseif event == "error" then
            error_occurred = true
            sys.publish("ssl_error", data, payload)
        end
    end)
    
    local connect_result = ssl_client:connect()
    assert(connect_result == true, "ssl connect failed")
    
    local ok = sys.waitUntil("ssl_conack", 30000)
    assert(ok, "ssl connection timeout")
    assert(conack_received, "ssl conack not received")
    assert(not error_occurred, "ssl error occurred")
    
    local ready_state = ssl_client:ready()
    assert(ready_state, "ssl client should be ready")
    
    cleanup()
end

-- 遗嘱消息测试
function mqtt_test.test_will_message()
    local will_payload = "device_offline"
    local test_device_id = get_device_id() .. "_will_" .. tostring(os.time())
    
    local will_client = mqtt.create(nil, mqtt_host, mqtt_port, mqtt_ssl)
    assert(will_client, "will mqtt create failed")
    
    local will_topic = "/luatos/testcase/mqtt/" .. test_device_id .. "/will"
    
    local will_result = will_client:will(will_topic, will_payload, 1, 1)
    assert(will_result == true, "遗嘱消息设置失败")
    
    local auth_result = will_client:auth(test_device_id, mqtt_username, mqtt_password, true)
    assert(auth_result == true, "will auth配置失败")
    
    will_client:keepalive(10)
    
    local will_conack = false
    will_client:on(function(client, event, data, payload, meta)
        if event == "conack" then
            will_conack = true
            sys.publish("will_conack")
        end
    end)
    
    local connect_result = will_client:connect()
    assert(connect_result == true, "will connect failed")
    
    local ok = sys.waitUntil("will_conack", 30000)
    assert(ok, "will client connect timeout")
    assert(will_conack, "will client conack not received")
    
    sys.wait(1000)
    socket.close_all(socket.dft())

    local monitor_client = mqtt.create(nil, mqtt_host, mqtt_port, mqtt_ssl)
    assert(monitor_client, "monitor mqtt create failed")
    
    local monitor_device_id = get_device_id() .. "_monitor_" .. tostring(os.time())
    local monitor_auth = monitor_client:auth(monitor_device_id, mqtt_username, mqtt_password, true)
    assert(monitor_auth == true, "monitor auth配置失败")
    
    monitor_client:keepalive(30)
    
    local monitor_conack = false
    local will_received = false
    local will_topic_received = nil
    local will_payload_received = nil
    local sub_ready = false
    
    monitor_client:on(function(client, event, data, payload, meta)
        if event == "conack" then
            monitor_conack = true
            sys.publish("monitor_conack")
        elseif event == "suback" then
            sub_ready = true
            sys.publish("monitor_suback", data, payload)
        elseif event == "recv" then
            will_received = true
            will_topic_received = data
            will_payload_received = payload
            sys.publish("will_recv", data, payload)
        end
    end)
    
    local monitor_connect = monitor_client:connect()
    assert(monitor_connect == true, "monitor connect failed")
    
    local monitor_ok = sys.waitUntil("monitor_conack", 30000)
    assert(monitor_ok, "monitor client connect timeout")
    assert(monitor_conack, "monitor client conack not received")
    
    local sub_msg_id = monitor_client:subscribe(will_topic, 1)
    assert(sub_msg_id, "monitor subscribe failed")
    
    local sub_ok = sys.waitUntil("monitor_suback", 20000)
    assert(sub_ok, "monitor subscribe timeout")
    assert(sub_ready, "monitor suback not received")
    
    sys.wait(5000)
    
    log.info("mqtt_test", "模拟异常断开，触发遗嘱消息")

    -- will_client:close()
    -- will_client = nil
    
    assert(will_received, "遗嘱消息未收到")
    assert(will_topic_received == will_topic,
        string.format("遗嘱主题不匹配: 期望 %s, 实际 %s", will_topic, tostring(will_topic_received)))
    assert(will_payload_received == will_payload,
        string.format("遗嘱内容不匹配: 期望 %s, 实际 %s", will_payload, tostring(will_payload_received)))
    
    log.info("mqtt_test", "遗嘱消息测试通过")
    
    pcall(monitor_client.close, monitor_client)
end

function mqtt_test.test_keepalive()
    local device_id = get_device_id() .. "_ka"
    local ka_client = mqtt.create(nil, mqtt_host, mqtt_port, mqtt_ssl)
    assert(ka_client, "keepalive mqtt create failed")
    
    local auth_result = ka_client:auth(device_id, mqtt_username, mqtt_password, true)
    assert(auth_result == true, "keepalive auth配置失败")
    
    ka_client:keepalive(15)
    
    local pong_count = 0
    
    ka_client:on(function(client, event, data, payload, meta)
        if event == "conack" then
            sys.publish("ka_conack")
        elseif event == "pong" then
            pong_count = pong_count + 1
            sys.publish("ka_pong", pong_count)
        end
    end)
    
    local connect_result = ka_client:connect()
    assert(connect_result == true, "keepalive connect failed")
    
    local ok = sys.waitUntil("ka_conack", 30000)
    assert(ok, "keepalive client connect timeout")
    
    local pong_ok = sys.waitUntil("ka_pong", 30000)
    assert(pong_ok, "pong not received within timeout")
    assert(pong_count >= 1, string.format("expected at least 1 pong, got %d", pong_count))
    
    local ready_state = ka_client:ready()
    assert(ready_state, "client should be ready after keepalive")
    
    pcall(ka_client.close, ka_client)
end

function mqtt_test.test_auto_reconnect()
    local device_id = get_device_id() .. "_reconn"
    local reconn_client = nil
    
    local cleanup = function()
        if reconn_client then
            pcall(reconn_client.close, reconn_client)
            reconn_client = nil
        end
    end
    
    reconn_client = mqtt.create(nil, mqtt_host, mqtt_port, mqtt_ssl)
    assert(reconn_client, "auto reconnect mqtt create failed")
    
    local auth_result = reconn_client:auth(device_id, mqtt_username, mqtt_password, true)
    assert(auth_result == true, "auto reconnect auth配置失败")
    
    reconn_client:keepalive(30)
    reconn_client:autoreconn(true, 5000)
    
    local disconnect_received = false
    local reconnect_conack_received = false
    
    reconn_client:on(function(client, event, data, payload, meta)
        if event == "conack" then
            if disconnect_received then
                reconnect_conack_received = true
                sys.publish("reconn_conack")
            else
                sys.publish("first_conack")
            end
        elseif event == "disconnect" then
            disconnect_received = true
            sys.publish("reconn_disconnect")
        end
    end)
    
    local connect_result = reconn_client:connect()
    assert(connect_result == true, "auto reconnect connect failed")
    
    local first_ok = sys.waitUntil("first_conack", 30000)
    assert(first_ok, "first connection timeout")
    
    reconn_client:disconnect()
    local disconnect_ok = sys.waitUntil("reconn_disconnect", 10000)
    assert(disconnect_ok, "disconnect event not received")
    
    local reconnect_ok = sys.waitUntil("reconn_conack", 20000)
    assert(reconnect_ok, "auto reconnect failed")
    assert(reconnect_conack_received, "reconnect conack not received")
    
    local ready_state = reconn_client:ready()
    assert(ready_state, "client should be ready after auto reconnect")
    
    cleanup()
end

function mqtt_test.test_disconnect_interface()
    local device_id = get_device_id() .. "_disc"
    local disc_client = mqtt.create(nil, mqtt_host, mqtt_port, mqtt_ssl)
    assert(disc_client, "disconnect test mqtt create failed")
    
    local auth_result = disc_client:auth(device_id, mqtt_username, mqtt_password, true)
    assert(auth_result == true, "disconnect auth配置失败")
    
    disc_client:keepalive(30)
    
    local conack_received = false
    local disconnect_received = false
    
    disc_client:on(function(client, event, data, payload, meta)
        if event == "conack" then
            conack_received = true
            sys.publish("disc_conack")
        elseif event == "disconnect" then
            disconnect_received = true
            sys.publish("disc_disconnect")
        end
    end)
    
    local connect_result = disc_client:connect()
    assert(connect_result == true, "disconnect connect failed")
    
    local ok = sys.waitUntil("disc_conack", 30000)
    assert(ok, "disconnect test connect timeout")
    assert(conack_received, "conack not received")
    
    local ready_before = disc_client:ready()
    assert(ready_before, "client should be ready before disconnect")
    
    disc_client:disconnect()
    
    local disc_ok = sys.waitUntil("disc_disconnect", 10000)
    assert(disc_ok, "disconnect event not received")
    assert(disconnect_received, "disconnect not received")
    
    local ready_after = disc_client:ready()
    assert(not ready_after, "client should not be ready after disconnect")
    
    pcall(disc_client.close, disc_client)
end

function mqtt_test.test_state_interface()
    local device_id = get_device_id() .. "_state"
    local state_client = mqtt.create(nil, mqtt_host, mqtt_port, mqtt_ssl)
    assert(state_client, "state test mqtt create failed")
    
    local initial_state = state_client:state()
    assert(initial_state == mqtt.STATE_DISCONNECT,
        string.format("initial state should be DISCONNECT(%d), got %d", mqtt.STATE_DISCONNECT, initial_state))
    
    local auth_result = state_client:auth(device_id, mqtt_username, mqtt_password, true)
    assert(auth_result == true, "state auth配置失败")
    
    state_client:keepalive(30)
    
    local conack_received = false
    state_client:on(function(client, event, data, payload, meta)
        if event == "conack" then
            conack_received = true
            sys.publish("state_conack")
        end
    end)
    
    local connect_result = state_client:connect()
    assert(connect_result == true, "state connect failed")
    
    local ok = sys.waitUntil("state_conack", 30000)
    assert(ok, "state test connect timeout")
    assert(conack_received, "conack not received")
    
    local connected_state = state_client:state()
    assert(connected_state == mqtt.STATE_READY,
        string.format("connected state should be READY(%d), got %d", mqtt.STATE_READY, connected_state))
    
    local ready_result = state_client:ready()
    assert(ready_result == (connected_state == mqtt.STATE_READY), "state() and ready() should be consistent")
    
    state_client:disconnect()
    sys.wait(1000)
    
    local disconnected_state = state_client:state()
    assert(disconnected_state == mqtt.STATE_DISCONNECT,
        string.format("after disconnect state should be DISCONNECT(%d), got %d", mqtt.STATE_DISCONNECT, disconnected_state))
    
    pcall(state_client.close, state_client)
end

return mqtt_test