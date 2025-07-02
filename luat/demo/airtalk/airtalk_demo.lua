local mqtt_host = "lbsmqtt.airm2m.com"
local mqtt_port = 1884
local mqtt_isssl = false
local client_id = nil
local user_name = "user"
local password = "password"
local mqttc = nil
require "audio_config"

local function airtalk_event_cb(event, param)
    log.info("airtalk event", event, param)
end

local function mqtt_cb(mqtt_client, event, data, payload)
    log.info("mqtt", "event", event, mqtt_client, data, payload)
end

function airtalk_demo_mqtt_8k()
    --client_id也可以自己设置
    client_id = mobile.imei()
    audio_init()

    mqttc = mqtt.create(nil, mqtt_host, mqtt_port, mqtt_isssl, {rxSize = 4096})
    airtalk.config(airtalk.PROTOCOL_DEMO_MQTT_8K, mqttc, 200) -- 缓冲至少200ms播放
    airtalk.on(airtalk_event_cb)
    airtalk.start(client_id)

    mqttc:auth(client_id,user_name,password) -- client_id必填,其余选填
    mqttc:keepalive(240) -- 默认值240s
    mqttc:autoreconn(true, 3000) -- 自动重连机制
    mqttc:debug(false)
    mqttc:on(mqtt_cb)

    -- mqttc自动处理重连, 除非自行关闭
    mqttc:connect()
    while true do
        --全是底层自动运行，到这里没什么可以演示的了
        sys.wait(60000000)
    end
end