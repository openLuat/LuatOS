

sys = require("sys")

log.info("sys", "from win32")

sys.taskInit(function ()
    log.info("lwip", "wait for ready")
    sys.wait(10000)
    log.info("lwip", "mqtt_new")
    local mqttc = lwip.mqtt_new()
    log.info("lwip", "mqtt_arg")
    local cbs = {}
    cbs.conn = function(status)
        log.info("mqtt", "conn_cb", "status", status)
        if status == lwip.MQTT_CONNECT_ACCEPTED then
            lwip.mqtt_subscribe(mqttc, "/sys/req/XXXYYYZZZ", 0)
            lwip.mqtt_subscribe(mqttc, "/sys/req/XXXYYYZZZ", 1)
            lwip.mqtt_subscribe(mqttc, "/sys/ota/XXXYYYZZZ", 0)
        else
            log.info("mqtt", "error or closed")
        end
        sys.publish("MQTT_INC")
    end
    cbs.inpub = function(topic, data)
        log.info("mqtt", topic, data)
    end
    cbs.req = function(result)
        log.info("mqtt", "req", result)
    end
    lwip.mqtt_arg(mqttc, cbs)
    while 1 do
        log.info("lwip", "mqtt_connect")
        local ret, err = lwip.mqtt_connect(mqttc, "120.55.137.106", 1884, {
            id = "XXXYYYZZZ",
            user = "test",
            pass = "test",
            keep_alive = 300,
            will_topic = "/sys/will/XXXYYYZZZ",
            will_data = "offline",
            will_qos = 0,
            will_retain = 0
            })
        log.info("mqtt", "conn", ret, err)
        if ret then
            --lwip.mqtt_publish(mqttc, "/sys/ping/XXXYYYZZZ", "{}")
            sys.waitUntil("MQTT_INC", 60000)
            while lwip.mqtt_is_connected(mqttc) do
                lwip.mqtt_publish(mqttc, "/sys/ping/XXXYYYZZZ", "{}")
                sys.waitUntil("MQTT_INC", 60000)
            end
            log.info("mqtt", "mqtt disconnect?")
        end
        sys.wait(5000)
    end

end)

sys.run()
