local g_state = SP_T_NO_READY   --device状态
local g_mqttc = nil             --mqtt客户端
local g_local_id                  --本机ID
local g_remote_id                 --对端ID
local g_s_type                  --对讲的模式，字符串形式的
local g_s_topic                 --对讲用的topic
local g_s_mode                  --对讲的模式
local g_dev_list                --对讲列表




local function auth()
    if g_state == SP_T_NO_READY then
        g_mqttc:publish("ctrl/uplink/" .. g_local_id .."/0001", json.encode({["key"] = PRODUCT_KEY, ["device_type"] = 1}))
    end
end

local function heart()
    if g_state == SP_T_CONNECTED then
        g_mqttc:publish("ctrl/uplink/" .. g_local_id .."/0005", json.encode({["from"] = g_local_id, ["to"] = g_remote_id}))
    end
end

local function wait_speech_to()
    log.info("主动请求对讲超时无应答")
    speech_off(true, false)
end

--对讲开始，topic,ssrc,采样率(8K或者16K)这3个参数都有了之后就能进行对讲了，可以通过其他协议传入
local function speech_on(ssrc, sample)
    g_state = SP_T_CONNECTED
    g_mqttc:subscribe(g_s_topic)
    airtalk.set_topic(g_s_topic)
    airtalk.set_ssrc(ssrc)
    log.info("对讲模式", g_s_mode)
    airtalk.speech(true, g_s_mode, sample)
    sys.sendMsg(AIRTALK_TASK_NAME, MSG_SPEECH_ON_IND, true) 
    sys.timerLoopStart(heart, 150000)
    sys.timerStopAll(wait_speech_to)
    log.info("对讲接通，可以说话了")
end
--对讲结束
local function speech_off(need_upload, need_ind)
    if g_state ==  SP_T_CONNECTED then
        g_mqttc:unsubscribe(g_s_topic)
        airtalk.speech(false)
        g_s_topic = nil
    end
    g_state = SP_T_IDLE
    sys.timerStopAll(auth)
    sys.timerStopAll(heart)
    sys.timerStopAll(wait_speech_to)
    log.info("对讲断开了")
    if need_upload then
        g_mqttc:publish("ctrl/uplink/" .. g_local_id .."/0004", json.encode({["to"] = g_remote_id}))
    end
    if need_ind then
        sys.sendMsg(AIRTALK_TASK_NAME, MSG_SPEECH_OFF_IND, true)
    end
end


local function analyze_v1(cmd, topic, obj)
    if cmd == "8005" or cmd == "8004" then       -- 对讲心跳保持和结束对讲的应答不做处理
        return
    end
    if cmd == "8003" then       -- 请求对讲应答
        if g_state ~= SP_T_CONNECTING then  --没有发起对讲请求
            log.error("state", g_state, "need", SP_T_CONNECTING)
            return
        else
            if obj and obj["result"] == SUCC and g_s_topic == obj["topic"]then  --完全正确，开始对讲
                speech_on(obj["ssrc"], obj["audio_code"] == "amr-nb" and 8000 or 16000)
                return
            else
                log.info(obj["result"], obj["topic"], g_s_topic)
                sys.sendMsg(AIRTALK_TASK_NAME, MSG_SPEECH_ON_IND, false)   --有异常，无法对讲
            end
            
        end
        g_s_topic = nil
        g_state = SP_T_IDLE
        return
    end
    local new_obj = nil
    if cmd == "0102" then       -- 对端打过来
        if obj and obj["topic"] and obj["ssrc"] and obj["audio_code"] and obj["type"] then
            if g_state ~= SP_T_IDLE then    -- 空闲状态下才可以进入对讲状态
                log.error("state", g_state, "need", SP_T_IDLE)
                new_obj = {["result"] = "failed", ["topic"] = obj["topic"], ["info"] = "device is busy"}
            else
                if obj["type"] == "one-on-one" then -- 1对1对讲
                    local from = string.match(obj["topic"], "audio/.*/(.*)/.*")
                    if from then
                        log.info("remote id ", from)
                        g_s_topic = obj["topic"]
                        g_remote_id = from
                        new_obj = {["result"] = SUCC, ["topic"] = obj["topic"], ["info"] = ""}
                        g_s_type = "one-on-one"
                        g_s_mode = airtalk.MODE_PERSON
                        speech_on(obj["ssrc"], obj["audio_code"] == "amr-nb" and 8000 or 16000)
                    else
                        new_obj = {["result"] = "failed", ["topic"] = obj["topic"], ["info"] = "topic error"}
                    end
                elseif obj["type"] == "broadcast" then  -- 1对多对讲
                    g_s_topic = obj["topic"]
                    new_obj = {["result"] = SUCC, ["topic"] = obj["topic"], ["info"] = ""}
                    g_s_mode = airtalk.MODE_GROUP_LISTENER
                    g_s_type = "broadcast"
                    speech_on(obj["ssrc"], obj["audio_code"] == "amr-nb" and 8000 or 16000)
                end
            end
        else
            new_obj = {["result"] = "failed", ["topic"] = obj["topic"], ["info"] = "json info error"}
        end
        g_mqttc:publish("ctrl/uplink/" .. g_local_id .."/8102", json.encode(new_obj))
        return
    end

    if cmd == "0103" then   --对端挂断
        if g_state == SP_T_IDLE then
            new_obj = {["result"] = "failed", ["info"] = "no speech"}
        else
            if obj and obj["type"] == g_s_type then
                new_obj = {["result"] = SUCC, ["info"] = ""}
                speech_off(false, true)
            else
                new_obj = {["result"] = "failed", ["info"] = "type mismatch"}
            end
        end
        g_mqttc:publish("ctrl/uplink/" .. g_local_id .."/8103", json.encode(new_obj))
        return
    end

    if cmd == "0101" then                        --更新设备列表
        if obj then
            g_dev_list = obj["dev_list"]
            -- for i=1,#g_dev_list do
            --     log.info(g_dev_list[i]["id"],g_dev_list[i]["name"])
            -- end
            new_obj = {["result"] = SUCC, ["info"] = ""}
        else
            new_obj = {["result"] = "failed", ["info"] = "json info error"}
        end
        g_mqttc:publish("ctrl/uplink/" .. g_local_id .."/8101", json.encode(new_obj))
        return
    end
    if cmd == "8001" then
        if obj and obj["result"] == SUCC then
            g_mqttc:publish("ctrl/uplink/" .. g_local_id .."/0002","")  -- 更新列表
        else
            sys.sendMsg(AIRTALK_TASK_NAME, MSG_AUTH_IND, false, "鉴权失败" .. obj["info"]) 
        end
        return
    end
    if cmd == "8002" then
        if obj and obj["result"] == SUCC then   --收到设备列表更新应答，才能认为相关网络服务准备好了
            g_dev_list = obj["dev_list"]
            -- for i=1,#g_dev_list do
            --     log.info(g_dev_list[i]["id"],g_dev_list[i]["name"])
            -- end
            g_state = SP_T_IDLE
            sys.sendMsg(AIRTALK_TASK_NAME, MSG_AUTH_IND, true)  --完整登录流程结束
        else
            sys.sendMsg(AIRTALK_TASK_NAME, MSG_AUTH_IND, false, "更新设备列表失败") 
        end
        return
    end
end

local function mqtt_cb(mqttc, event, topic, payload)
    log.info(event, topic)
    local msg,data,obj
    if event == "conack" then
        sys.sendMsg(AIRTALK_TASK_NAME, MSG_CONNECT_ON_IND) --mqtt连上了，开始自定义的鉴权流程
        g_mqttc:subscribe("ctrl/downlink/" .. g_local_id .. "/#")--单主题订阅
    elseif event == "suback" then
        if g_state == SP_T_NO_READY then
            if topic then
                auth()
            else
                sys.sendMsg(AIRTALK_TASK_NAME, MSG_AUTH_IND, false, "订阅失败" .. "ctrl/downlink/" .. g_local_id .. "/#") 
            end
        elseif g_state == SP_T_CONNECTED then
            if not topic then
                speech_off(false, true)
            end
        end
    elseif event == "recv" then
        local result = string.match(topic, g_dl_topic)
        if result then 
            local obj,res,err = json.decode(payload)
            analyze_v1(result, topic, obj)
        end
        result = nil
        data = nil
        obj = nil
        
    elseif event == "sent" then
        -- log.info("mqtt", "sent", "pkgid", data)
    elseif event == "disconnect" then
        speech_off(false, true)
        g_state = SP_T_NO_READY
    elseif event == "error" then

    end
end

local function task_cb(msg)
    if msg[1] == MSG_SPEECH_CONNECT_TO then
        speech_off(true,false)
    else
        log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
    end
end

local function airtalk_event_cb(event, param)
    log.info("airtalk event", event, param)
    if event == airtalk.EVENT_ERROR then
        if param == airtalk.ERROR_NO_DATA then
            log.error("长时间没有收到音频数据")
            speech_off(true, true)
        end
    end
end

local function airtalk_mqtt_task()
    local msg,data,obj,online,num,res
    --g_local_id也可以自己设置
    g_local_id = mobile.imei()
    g_dl_topic = "ctrl/downlink/" .. g_local_id .. "/(%w%w%w%w)"
    sys.timerLoopStart(next_auth, 900000)

    g_mqttc = mqtt.create(nil, "mqtt.airtalk.luatos.com", 1883, false, {rxSize = 32768})
    airtalk.config(airtalk.PROTOCOL_MQTT, g_mqttc, 200) -- 缓冲至少200ms播放
    airtalk.on(airtalk_event_cb)
    airtalk.start()

    g_mqttc:auth(g_local_id,g_local_id,mobile.muid()) -- g_local_id必填,其余选填
    g_mqttc:keepalive(240) -- 默认值240s
    g_mqttc:autoreconn(true, 15000) -- 自动重连机制
    g_mqttc:debug(false)
    g_mqttc:on(mqtt_cb)
    log.info("设备信息", g_local_id, mobile.muid())
    -- mqttc自动处理重连, 除非自行关闭
    g_mqttc:connect()
    online = false
    while true do
        msg = sys.waitMsg(AIRTALK_TASK_NAME, MSG_CONNECT_ON_IND)   --等服务器连上
        log.info("connected")
        while not online do
            msg = sys.waitMsg(AIRTALK_TASK_NAME, MSG_AUTH_IND, 30000)   --登录流程不应该超过30秒
            if type(msg) == 'table' then
                online = msg[2]
                if online then
                    sys.timerLoopStart(auth, 3600000) --鉴权通过则60分钟后尝试重新鉴权
                else
                    log.info(msg[3])
                    sys.timerLoopStart(auth, 300000)       --5分钟后重新鉴权
                end
            else
                auth()  --30秒鉴权无效后重新鉴权
            end
        end
        log.info("对讲管理平台已连接")
        while online do
            msg = sys.waitMsg(AIRTALK_TASK_NAME)
            if type(msg) == 'table' and type(msg[1]) == "number" then
                if msg[1] == MSG_PERSON_SPEECH_TEST_START then
                    if g_state ~= SP_T_IDLE then
                        log.info("正在对讲无法开始")
                    else
                        log.info("测试一下主动1对1对讲功能，找一个有效的IMEI")

                        for i=1,#g_dev_list do
                            res = string.match(g_dev_list[i]["id"], "(%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w)")
                            if res and res ~= g_local_id then
                                break
                            end
                        end
                        if res then
                            log.info("向", res, "主动发起对讲")
                            g_state = SP_T_CONNECTING
                            g_remote_id = res
                            g_s_mode = airtalk.MODE_PERSON
                            g_s_type = "one-on-one"
                            g_s_topic = "audio/" .. g_local_id .. "/" .. g_remote_id .. "/" .. (string.sub(tostring(mcu.ticks()), -4, -1))
                            g_mqttc:publish("ctrl/uplink/" .. g_local_id .."/0003", json.encode({["topic"] = g_s_topic, ["type"] = g_s_type}))
                            sys.timerStart(wait_speech_to, 15000)
                        else
                            log.info("找不到有效的设备ID")
                        end
                    end
                elseif msg[1] == MSG_GROUP_SPEECH_TEST_START then
                    if g_state ~= SP_T_IDLE then
                        log.info("正在对讲无法开始")
                    else
                        log.info("测试一下1对多对讲功能")
                        g_remote_id = "all"
                        g_state = SP_T_CONNECTING
                        g_s_mode = airtalk.MODE_GROUP_SPEAKER
                        g_s_type = "broadcast"
                        g_s_topic = "audio/" .. g_local_id .. "/all/" .. (string.sub(tostring(mcu.ticks()), -4, -1))
                        g_mqttc:publish("ctrl/uplink/" .. g_local_id .."/0003", json.encode({["topic"] = g_s_topic, ["type"] = g_s_type}))
                        sys.timerStart(wait_speech_to, 15000)
                    end
                elseif msg[1] == MSG_SPEECH_STOP_TEST_END then
                    if g_state ~= SP_T_CONNECTING and g_state ~= SP_T_CONNECTED then
                        log.info("没有对讲", g_state)
                    else
                        log.info("主动断开对讲")
                        speech_off(true, false)
                    end
                elseif msg[1] == MSG_SPEECH_ON_IND then
                    if msg[2] then
                        log.info("对讲接通")
                    else
                        log.info("对讲断开")
                    end
                elseif msg[1] == MSG_CONNECT_OFF_IND then
                    log.info("connect", msg[2])
                    online = msg[2]
                end
                obj = nil
            else
                log.info(type(msg), type(msg[1]))
            end
            msg = nil
        end
        online = false
    end
end

function airtalk_mqtt_init()
    sys.taskInitEx(airtalk_mqtt_task, AIRTALK_TASK_NAME, task_cb)
end


