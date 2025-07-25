require "audio_config"


local mqttc = nil
local client_id
local topic_auth
local topic_list_update
local topic_talk_start
local topic_talk_stop
local topic_list_update_ack
local topic_talk_start_ack
local topic_talk_stop_ack

local function task_cb(msg)
    log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
end

local function airtalk_event_cb(event, param)
    log.info("airtalk event", event, param)
end

local function mqtt_cb(mqtt_client, event, data, payload)
    log.info(event)
    if event == "conack" then
        -- 联上了
        mqtt_client:subscribe("ctrl/downlink/" .. client_id .. "/#")--单主题订阅
    elseif event == "suback" then
        sys.sendMsg(AIRTALK_TASK_NAME, MSG_MQTT_READY)
    elseif event == "recv" then
        log.info("mqtt", "downlink", "topic", data, payload)
    elseif event == "sent" then
        -- log.info("mqtt", "sent", "pkgid", data)
    -- elseif event == "disconnect" then
        -- 非自动重连时,按需重启mqttc
        -- mqtt_client:connect()
    else
    end
end

function airtalk_mqtt_task()
    local msg,data,obj
    --client_id也可以自己设置
    client_id = mobile.imei()

    topic_auth = "ctrl/uplink/" .. client_id .."/0001"
    topic_list_update = "ctrl/uplink/" .. client_id .."/0002"
    topic_talk_start = "ctrl/uplink/" .. client_id .."/0003" 
    topic_talk_stop = "ctrl/uplink/" .. client_id .."/0004"
    topic_list_update_ack = "ctrl/uplink/" .. client_id .."/8101"
    topic_talk_start_ack = "ctrl/uplink/" .. client_id .."/8102"
    topic_talk_stop_ack = "ctrl/uplink/" .. client_id .."/8103"


    audio_init()

    mqttc = mqtt.create(nil, "mqtt.airtalk.luatos.com", 1883, false, {rxSize = 4096})
    airtalk.config(airtalk.PROTOCOL_MQTT, mqttc, 200) -- 缓冲至少200ms播放
    airtalk.on(airtalk_event_cb)
    airtalk.start()

    mqttc:auth(client_id,client_id,mobile.muid()) -- client_id必填,其余选填
    mqttc:keepalive(240) -- 默认值240s
    mqttc:autoreconn(true, 3000) -- 自动重连机制
    mqttc:debug(false)
    mqttc:on(mqtt_cb)

    -- mqttc自动处理重连, 除非自行关闭
    mqttc:connect()
    while true do
        msg = sys.waitMsg(AIRTALK_TASK_NAME)
        if type(msg) == 'table' and type(msg[1]) == "number" and msg[1] < 5 then
            if msg[1] == MSG_MQTT_READY then
                obj = {["key"] = PRODUCT_KEY, ["device_type"] = 1}
                data = json.encode(obj)
                log.info(topic_auth, data)
                mqttc:publish(topic_auth, data)
                obj = nil
            end
        end
    end
end

function airtalk_mqtt_init()
    sys.taskInitEx(airtalk_mqtt_task, AIRTALK_TASK_NAME, task_cb)
end