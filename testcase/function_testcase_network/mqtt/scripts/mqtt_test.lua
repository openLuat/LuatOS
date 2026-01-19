local mqtt_test = {}

-- broker参数可按需改为自建环境
local mqtt_host = "lbsmqtt.airm2m.com"
local mqtt_port = 1884
local mqtt_ssl = false

local mqttc
local pub_topic
local sub_topic

-- 设备标识统一生成，优先使用蜂窝/网卡/芯片ID
local function get_device_id()
    if mobile and mobile.imei then
        return mobile.imei()
    end
    if wlan and wlan.getMac then
        return wlan.getMac()
    end
    if mcu and mcu.unique_id then
        return mcu.unique_id():toHex()
    end
    return "mqtt_test_" .. tostring(rtos and rtos.tick and rtos.tick() or os.time())
end

-- 清理上一次连接，避免跨用例残留
local function reset_client()
    if mqttc then
        pcall(mqttc.unsubscribe, mqttc, { pub_topic, sub_topic })
        pcall(mqttc.close, mqttc)
    end
    mqttc = nil
end

-- 每个用例前建立新连接并订阅
function mqtt_test.setUp()
    reset_client()

    local device_id = get_device_id()
    pub_topic = "/luatos/testcase/mqtt/" .. device_id .. "/pub"
    sub_topic = "/luatos/testcase/mqtt/" .. device_id .. "/sub"

    mqttc = mqtt.create(nil, mqtt_host, mqtt_port, mqtt_ssl)
    assert(mqttc, "mqtt.create failed")

    mqttc:auth(device_id, "user", "password")
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
        end
    end)

    mqttc:connect()
    local ok = sys.waitUntil("mqtt_conack", 30000)
    assert(ok, "mqtt connect timeout")

    local msg_id = mqttc:subscribe({ [pub_topic] = 1, [sub_topic] = 1 })
    assert(msg_id, "subscribe msg id missing")

    local sub_ok, result, err = sys.waitUntil("mqtt_suback", 20000)
    assert(sub_ok and result == true, "subscribe failed: " .. tostring(err))
end

-- 用例后关闭连接，释放资源
function mqtt_test.tearDown()
    reset_client()
    sys.wait(200)
end

function mqtt_test.test_ready_state()
    assert(mqttc and mqttc:ready(), "mqtt client not ready")
end

-- QoS1发布并回环校验payload一致性
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

-- QoS0发布到订阅topic，确认可达
function mqtt_test.test_publish_qos0_loopback()
    local payload = "qos0-" .. tostring(rtos and rtos.tick and rtos.tick() or os.time())
    mqttc:publish(sub_topic, payload, 0)

    local ok, topic, recv_payload = sys.waitUntil("mqtt_recv", 20000)
    assert(ok, "no message received")
    assert(topic == sub_topic, "unexpected topic: " .. tostring(topic))
    assert(recv_payload == payload, string.format("payload mismatch: expected %s got %s", payload, tostring(recv_payload)))
end

-- 负例: 未完成连接即发布应失败/返回nil
function mqtt_test.test_publish_before_connect()
    local temp = mqtt.create(nil, mqtt_host, mqtt_port, mqtt_ssl)
    assert(temp, "temp mqtt create failed")
    temp:auth(get_device_id(), "user", "password")
    local msg_id = temp:publish("/tmp/noconn", "payload", 0)
    assert(msg_id == nil, "publish should fail before connect")
    pcall(temp.close, temp)
end

-- 负例: 连接无效域名应超时且未ready
function mqtt_test.test_connect_invalid_host()
    local bad = mqtt.create(nil, "invalid.luat.host", mqtt_port, mqtt_ssl)
    assert(bad, "bad mqtt create failed")
    bad:auth(get_device_id(), "user", "password")
    bad:autoreconn(false, 1000)
    bad:on(function(_, event)
        if event == "conack" then
            sys.publish("mqtt_bad_conack")
        elseif event == "disconnect" then
            sys.publish("mqtt_bad_disconnect")
        end
    end)
    bad:connect()
    local ok = sys.waitUntil("mqtt_bad_conack", 8000)
    assert(not ok, "should not conack on invalid host")
    assert(not bad:ready(), "client should not be ready")
    pcall(bad.close, bad)
end

return mqtt_test
