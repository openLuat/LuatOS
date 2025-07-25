require "audio_config"

local mqttc = nil

local function task_cb(msg)
    log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
end

local function airtalk_event_cb(event, param)
    log.info("airtalk event", event, param)
end

local function mqtt_cb(mqtt_client, event, data, payload)
    log.info("mqtt", "event", event, mqtt_client, data, payload)
end

function airtalk_mqtt_task()
    local msg
    --client_id也可以自己设置
    local client_id = mobile.imei()
    local user = mobile.imei()
    local password = mobile.muid()
    audio_init()

    mqttc = mqtt.create(nil, mqtt.airtalk.luatos.com, 1883, false, {rxSize = 4096})
    airtalk.config(airtalk.PROTOCOL_MQTT, mqttc, 200) -- 缓冲至少200ms播放
    airtalk.on(airtalk_event_cb)
    airtalk.start()

    mqttc:auth(client_id,user_name,password) -- client_id必填,其余选填
    mqttc:keepalive(240) -- 默认值240s
    mqttc:autoreconn(true, 3000) -- 自动重连机制
    mqttc:debug(false)
    mqttc:on(mqtt_cb)

    -- mqttc自动处理重连, 除非自行关闭
    mqttc:connect()
    while true do
        msg = sys.waitMsg(AIRTALK_TASK_NAME)
        if type(result) == 'table' then

        end
    end
end

function airtalk_mqtt_init()
    sys.taskInitEx(airtalk_mqtt_task, AIRTALK_TASK_NAME, task_cb)
end