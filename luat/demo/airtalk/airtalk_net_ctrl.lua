require "audio_config"


local mqttc = nil
local client_id
local downlink_topic
local topic_auth
local topic_list_update
local topic_talk_start
local topic_talk_stop
local topic_list_update_ack
local topic_talk_start_ack
local topic_talk_stop_ack
local dev_list

local function task_cb(msg)
    log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
end

local function airtalk_event_cb(event, param)
    log.info("airtalk event", event, param)
end

local function next_auth()
    sys.sendMsg(AIRTALK_TASK_NAME, MSG_NET_READY)
end

local function mqtt_cb(mqtt_client, event, data, payload)
    log.info(event)
    if event == "conack" then
        -- 联上了
        mqtt_client:subscribe("ctrl/downlink/" .. client_id .. "/#")--单主题订阅
    elseif event == "suback" then
        sys.sendMsg(AIRTALK_TASK_NAME, MSG_NET_READY)
    elseif event == "recv" then
        local result = string.match(data, downlink_topic)
        if result then
            log.info(data, payload)
            local obj,res,err = json.decode(payload)
            if result == "0102" then

            elseif result == "0103" then
            elseif result == "0101" then
            elseif result == "8003" then
            elseif result == "8004" then
            elseif result == "8001" then
                if res and obj["result"] then
                    sys.sendMsg(AIRTALK_TASK_NAME, MSG_AUTH_ACK, obj["result"], obj["version"])
                end
            elseif result == "8002" then
                if res and obj["result"] == SUCC then
                    dev_list = obj["dev_list"]
                    for i=1,#dev_list do
                        log.info(dev_list[i]["id"],dev_list[i]["name"])
                    end
                end
            else
            end
            decode_data = nil
        end
        result = nil
        
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
    downlink_topic = "ctrl/downlink/" .. client_id .. "/(%w%w%w%w)"
    topic_auth = "ctrl/uplink/" .. client_id .."/0001"
    topic_list_update = "ctrl/uplink/" .. client_id .."/0002"
    topic_talk_start = "ctrl/uplink/" .. client_id .."/0003" 
    topic_talk_stop = "ctrl/uplink/" .. client_id .."/0004"
    topic_list_update_ack = "ctrl/uplink/" .. client_id .."/8101"
    topic_talk_start_ack = "ctrl/uplink/" .. client_id .."/8102"
    topic_talk_stop_ack = "ctrl/uplink/" .. client_id .."/8103"
    sys.timerLoopStart(next_auth, 900000)

    audio_init()

    mqttc = mqtt.create(nil, "mqtt.airtalk.luatos.com", 1883, false, {rxSize = 32768})
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
        if type(msg) == 'table' and type(msg[1]) == "number" and msg[1] < MSG_QTY then
            if msg[1] == MSG_NET_READY then
                obj = {["key"] = PRODUCT_KEY, ["device_type"] = 1}
                data = json.encode(obj)
                log.info(topic_auth, data)
                mqttc:publish(topic_auth, data)
                sys.timerLoopStart(next_auth, 60000)    --1分钟就尝试重新鉴权
            elseif msg[1] == MSG_AUTH_ACK then
                if msg[2] == SUCC then
                    sys.timerLoopStart(next_auth, 3600000) --鉴权通过则60分钟后尝试重新鉴权
                    mqttc:publish(topic_list_update, "")
                else
                    log.info("auth", msg[2])
                end                
            end
            obj = nil
        end
    end
end

function airtalk_mqtt_init()
    sys.taskInitEx(airtalk_mqtt_task, AIRTALK_TASK_NAME, task_cb)
end