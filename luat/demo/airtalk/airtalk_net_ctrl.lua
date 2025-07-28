
local speech_state = SP_T_IDLE
local speech_mdoe
local g_mqttc = nil
local client_id
local downlink_topic
local topic_auth
local topic_list_update
local topic_talk_start
local topic_talk_stop
local topic_list_update_ack
local topic_talk_start_ack
local topic_talk_stop_ack
local speech_topic
local speech_sample
local dev_list

local function task_cb(msg)
    log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
end

local function airtalk_event_cb(event, param)
    log.info("airtalk event", event, param)
end

local function next_auth()
    if speech_state == SP_T_IDLE then
        obj = {["key"] = PRODUCT_KEY, ["device_type"] = 1}
        data = json.encode(obj)
        log.info(topic_auth, data)
        mqttc:publish(topic_auth, data)
    end
end

local function mqtt_cb(mqttc, event, topic, payload)
    -- log.info(event)
    local msg,data,obj,speech_topic,speech_sample
    if event == "conack" then
        -- 联上了
        mqttc:subscribe("ctrl/downlink/" .. client_id .. "/#")--单主题订阅
    elseif event == "suback" then
        if speech_state == SP_T_IDLE then
            obj = {["key"] = PRODUCT_KEY, ["device_type"] = 1}
            data = json.encode(obj)
            log.info(topic_auth, data)
            mqttc:publish(topic_auth, data)
            sys.timerLoopStart(next_auth, 60000)    --1分钟就尝试重新鉴权
        elseif speech_state == SP_T_CONNECTING then
            speech_state = SP_T_CONNECTED
            obj = {["result"] = SUCC, ["topic"] = msg[2], ["info"] = ""}
            data = json.encode(obj)
            log.info(topic_talk_start_ack, data)
            mqttc:publish(topic_talk_start_ack, data)
            airtalk.speech(true, speech_mdoe, speech_sample)
        else
            
        end 
        
    elseif event == "recv" then
        local result = string.match(topic, downlink_topic)
        if result then
            log.info(topic, payload)
            local obj,res,err = json.decode(payload)
            if result == "0102" then
                if res and obj["topic"] and obj["ssrc"] and obj["audio_code"] then
                    if speech_state == SP_T_CONNECTED then
                        obj = {["result"] = "failed", ["topic"] = msg[2], ["info"] = "last speech is running"}
                        data = json.encode(obj)
                        log.info(topic_talk_start_ack, data)
                        mqttc:publish(topic_talk_start_ack, data)
                        airtalk.speech(true, speech_mdoe, speech_sample)
                    elseif speech_state == SP_T_DISCONNECTING then
                        obj = {["result"] = "failed", ["topic"] = msg[2], ["info"] = "last speech not stop"}
                        data = json.encode(obj)
                        log.info(topic_talk_start_ack, data)
                        mqttc:publish(topic_talk_start_ack, data)
                        airtalk.speech(true, speech_mdoe, speech_sample)
                    else
                        speech_state = SP_T_CONNECTING
                        speech_topic = msg[2]
                        speech_sample = msg[4] == "amr-nb" and 8000 or 16000
                        mqttc:subscribe(speech_topic)
                        airtalk.set_topic(speech_topic)
                        airtalk.set_ssrc(msg[3])
                        speech_mdoe = airtalk.MODE_PERSON
                    end
                else
                    obj = {["result"] = "failed", ["info"] = "json info error"}
                    data = json.encode(obj)
                    log.info(topic_talk_start_ack, data)
                    mqttc:publish(topic_talk_start_ack, data)
                end
            elseif result == "0103" then
                if speech_state == SP_T_IDLE then
                    obj = {["result"] = "failed", ["info"] = "no speech"}
                else
                    obj = {["result"] = SUCC, ["info"] = ""}
                    speech_state = SP_T_IDLE
                    mqttc:unsubscribe(speech_topic)
                    airtalk.speech(false)
                    speech_topic = nil
                end
                data = json.encode(obj)
                mqttc:publish(topic_talk_stop_ack, data)
            elseif result == "0101" then
                if res then
                    dev_list = obj["dev_list"]
                    for i=1,#dev_list do
                        log.info(dev_list[i]["id"],dev_list[i]["name"])
                    end
                    obj = {["result"] = SUCC, ["info"] = ""}
                else
                    obj = {["result"] = "failed", ["info"] = "json info error"}
                end
                data = json.encode(obj)
                log.info(topic_list_update_ack, data)
                mqttc:publish(topic_list_update_ack, data)
            elseif result == "8003" then
            elseif result == "8004" then
            elseif result == "8001" then
                if res and obj["result"] then
                    sys.timerLoopStart(next_auth, 3600000) --鉴权通过则60分钟后尝试重新鉴权
                    mqttc:publish(topic_list_update, "")
                end
            elseif result == "8002" then
                if res and obj["result"] == SUCC then
                    dev_list = obj["dev_list"]
                    for i=1,#dev_list do
                        log.info(dev_list[i]["id"],dev_list[i]["name"])
                    end
                    sys.sendMsg(USER_TASK_NAME, MSG_READY)
                end
            else
            end
            decode_data = nil
        end
        result = nil
        data = nil
        obj = nil
        
    elseif event == "sent" then
        -- log.info("mqtt", "sent", "pkgid", data)
    elseif event == "disconnect" then
        speech_state = SP_T_IDLE
        -- 非自动重连时,按需重启mqttc
        -- mqttc:connect()
    else
    end
end

function airtalk_mqtt_task()
    local msg,data,obj,speech_topic,speech_sample
    --client_id也可以自己设置
    client_id = mobile.imei()
    downlink_topic = "ctrl/downlink/" .. client_id .. "/(%w%w%w%w)"
    topic_auth = "ctrl/uplink/" .. client_id .."/0001"
    topic_list_update = "ctrl/uplink/" .. client_id .."/0002"
    topic_talk_start = "ctrl/uplink/" .. client_id .."/0003" 
    topic_talk_stop = "ctrl/uplink/" .. client_id .."/0004"
    topic_list_update_ack = "ctrl/uplink/" .. client_id .."/8101"
    topic_talk_start_ack = "ctrl/uplink/" .. client_id .."/8102"
    topic_talk_stop_ack = "ctrl/uplink/" .. client_id .."/8103"
    sys.timerLoopStart(next_auth, 900000)

    g_mqttc = mqtt.create(nil, "mqtt.airtalk.luatos.com", 1883, false, {rxSize = 32768})
    airtalk.config(airtalk.PROTOCOL_MQTT, g_mqttc, 200) -- 缓冲至少200ms播放
    airtalk.on(airtalk_event_cb)
    airtalk.start()

    g_mqttc:auth(client_id,client_id,mobile.muid()) -- client_id必填,其余选填
    g_mqttc:keepalive(240) -- 默认值240s
    g_mqttc:autoreconn(true, 3000) -- 自动重连机制
    g_mqttc:debug(false)
    g_mqttc:on(mqtt_cb)

    -- mqttc自动处理重连, 除非自行关闭
    g_mqttc:connect()
    while true do
        msg = sys.waitMsg(AIRTALK_TASK_NAME)
        if type(msg) == 'table' and type(msg[1]) == "number" then
            if msg[1] == MSG_PERSON_SPEECH_REQ then
                -- if speech_state = 
                -- speech_state = SP_T_CONNECTING
                -- obj = {["to"] = msg[2]}
                -- data = json.encode(obj)
                -- log.info(topic_talk_start, data)
                -- mqttc:publish(topic_talk_start, data)
            elseif msg[1] == MSG_SPEECH_STOP_REQ then
                speech_state = SP_T_IDLE
                mqttc:unsubscribe(speech_topic)
                airtalk.speech(false)
                speech_topic = nil
                data = json.encode(obj)
                log.info(topic_talk_stop, data)
                mqttc:publish(topic_talk_stop, data)
            end
            obj = nil
        else
            log.info(type(msg), type(msg[1]))
        end
        msg = nil
    end
end

function airtalk_mqtt_init()
    sys.taskInitEx(airtalk_mqtt_task, AIRTALK_TASK_NAME, task_cb)
end