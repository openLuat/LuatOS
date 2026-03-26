local mqtt_test = {}

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

-- SSL双向认证服务器配置
local mqtt_mtls_host = "airtest.openluat.com"
local mqtt_mtls_port = 8886
local mqtt_mtls_username = "mqtt_hz_test_2"
local mqtt_mtls_password = "3bEKUb"

local mqttc
local pub_topic
local sub_topic
local will_topic

local function generate_fallback_id()
    local timestamp = os.time()
    local tick = rtos and rtos.tick and rtos.tick() or 0
    return string.format("mqtt_test_%d_%d", timestamp, tick)
end

local function get_device_id()
    if mobile and mobile.imei then
        local imei = mobile.imei()
        if imei and imei ~= "" then
            log.info("mqtt_test", "使用IMEI作为设备ID:", imei)
            return imei
        end
    end
    if wlan and wlan.getMac then
        local mac = wlan.getMac()
        if mac and mac ~= "" then
            log.info("mqtt_test", "使用MAC地址作为设备ID:", mac)
            return mac
        end
    end
    if mcu and mcu.unique_id then
        local unique_id = mcu.unique_id()
        if unique_id and type(unique_id) == "table" and unique_id.toHex then
            local hex_id = unique_id:toHex()
            if hex_id and hex_id ~= "" then
                log.info("mqtt_test", "使用MCU唯一ID作为设备ID:", hex_id)
                return hex_id
            end
        end
    end
    local fallback_id = generate_fallback_id()
    log.warn("mqtt_test", "无法获取硬件ID，使用生成的后备ID:", fallback_id)
    return fallback_id
end

local function reset_client()
    if mqttc then
        pcall(mqttc.unsubscribe, mqttc, { pub_topic, sub_topic, will_topic })
        pcall(mqttc.close, mqttc)
    end
    mqttc = nil
end

function mqtt_test.setUp()
    reset_client()

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
    reset_client()
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
    
    -- 使用SSL服务器
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
            sys.publish("qos2_sent", data)
        elseif event == "recv" then
            recv_ready = true
            received_topic = data
            received_payload = payload
            sys.publish("qos2_recv", data, payload, meta)
        end
    end)
    
    -- 连接
    local connect_result = qos2_client:connect()
    assert(connect_result == true, "qos2 connect failed")
    
    local ok = sys.waitUntil("qos2_conack", 30000)
    assert(ok, "qos2 connection timeout")
    assert(conack_received, "qos2 conack not received")
    
    -- 订阅自己的发布主题
    local sub_msg_id = qos2_client:subscribe(qos2_pub_topic, 2)
    assert(sub_msg_id, "qos2 subscribe msg id missing")
    
    local sub_ok = sys.waitUntil("qos2_suback", 20000)
    assert(sub_ok, "qos2 subscribe timeout")
    assert(sub_ready, "qos2 suback not received")
    
    -- 等待订阅完成
    sys.wait(500)
    
    -- 发布QoS2消息
    local payload = "qos2-" .. tostring(rtos and rtos.tick and rtos.tick() or os.time())
    local pub_msg_id = qos2_client:publish(qos2_pub_topic, payload, 2)
    assert(pub_msg_id, "qos2 publish msg id missing")
    
    -- 等待发送确认
    local sent_ok = sys.waitUntil("qos2_sent", 15000)
    assert(sent_ok, "qos2 publish sent timeout")
    assert(sent_ready, "qos2 sent not received")
    
    -- 等待接收消息
    local recv_ok = sys.waitUntil("qos2_recv", 30000)
    assert(recv_ok, "qos2 message not received")
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

function mqtt_test.test_ssl_connection()
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

-- 正确的遗嘱消息测试
function mqtt_test.test_will_message()
    local will_payload = "device_offline"
    local test_device_id = get_device_id() .. "_will_" .. tostring(os.time())
    
    -- 创建遗嘱客户端并设置遗嘱消息
    local will_client = mqtt.create(nil, mqtt_host, mqtt_port, mqtt_ssl)
    assert(will_client, "will mqtt create failed")
    
    local will_topic = "/luatos/testcase/mqtt/" .. test_device_id .. "/will"
    
    -- 设置遗嘱消息
    local will_result = will_client:will(will_topic, will_payload, 1, 0)
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
    
    -- 连接遗嘱客户端
    local connect_result = will_client:connect()
    assert(connect_result == true, "will connect failed")
    
    local ok = sys.waitUntil("will_conack", 30000)
    assert(ok, "will client connect timeout")
    assert(will_conack, "will client conack not received")
    
    -- 创建监控客户端来接收遗嘱消息
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
    
    -- 连接监控客户端
    local monitor_connect = monitor_client:connect()
    assert(monitor_connect == true, "monitor connect failed")
    
    local monitor_ok = sys.waitUntil("monitor_conack", 30000)
    assert(monitor_ok, "monitor client connect timeout")
    assert(monitor_conack, "monitor client conack not received")
    
    -- 订阅遗嘱主题
    local sub_msg_id = monitor_client:subscribe(will_topic, 1)
    assert(sub_msg_id, "monitor subscribe failed")
    
    local sub_ok = sys.waitUntil("monitor_suback", 20000)
    assert(sub_ok, "monitor subscribe timeout")
    assert(sub_ready, "monitor suback not received")
    
    -- 等待订阅完成
    sys.wait(1000)
    
    -- 模拟异常断开，触发遗嘱消息
    log.info("mqtt_test", "模拟异常断开，触发遗嘱消息")
    -- 直接关闭will_client（不发送DISCONNECT报文）
    -- 注意：close()会释放所有资源，但可能不会立即触发遗嘱
    -- 更好的方式是让底层socket异常断开
    will_client:close()
    will_client = nil
    
    -- 等待遗嘱消息
    local will_ok = sys.waitUntil("will_recv", 30000)
    
    -- 验证遗嘱消息
    assert(will_ok, "遗嘱消息未在30秒内收到")
    assert(will_received, "遗嘱消息未收到")
    assert(will_topic_received == will_topic,
        string.format("遗嘱主题不匹配: 期望 %s, 实际 %s", will_topic, tostring(will_topic_received)))
    assert(will_payload_received == will_payload,
        string.format("遗嘱内容不匹配: 期望 %s, 实际 %s", will_payload, tostring(will_payload_received)))
    
    log.info("mqtt_test", "遗嘱消息测试通过")
    
    -- 清理
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