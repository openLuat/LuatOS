--[[
@module  talk
@summary airtalk测试功能模块
@version 001.000.000
@date    2025.07.11
@author  李源龙
@usage
使用Air8000整机板,连接MQTT服务器，订阅对应的主题和平台进行对讲功能，还支持使用powerkey按键进行对讲功能
]]
local talk = {}

local run_state = false
local airaudio  = require "airaudio"
local input_key = false

-- 初始化fskv
--speech_topic是topic，自己设定，需要和平台的topic一致，mqtt_host是mqtt服务器地址，mqtt_port是mqtt服务器端口，
--mqtt_isssl是是否使用ssl连接，client_id是mqtt客户端id，user_name是mqtt用户名，password是mqtt密码
local speech_topic = "12345678910"
local mqtt_host = "lbsmqtt.openluat.com"
local mqtt_port = 1886
local mqtt_isssl = false
local client_id = nil
local user_name = "mqtt_hz_test_1"
local password = "Ck8WpNCp"
local mqttc = nil
local message = ""
local event = ""
local talk_state = ""

local function airtalk_event_cb(event, param)
    log.info("talk event", event, param)
    event  = event
end


-- MQTT回调函数
local function mqtt_cb(mqtt_client, event, data, payload)
    log.info("mqtt", "event", event, mqtt_client, data, payload)
    -- 连接成功时订阅主题
end


--初始化airtalk，连接MQTT
local function init_talk()
    log.info("init_call")
    --初始化codec
    airaudio.init() 
    client_id = mobile.imei()

    mqttc = mqtt.create(nil, mqtt_host, mqtt_port, mqtt_isssl, {rxSize = 4096})
    airtalk.config(airtalk.PROTOCOL_DEMO_MQTT_8K, mqttc, 200) -- 缓冲至少200ms播放
    airtalk.on(airtalk_event_cb)
    airtalk.start(client_id, speech_topic)

    mqttc:auth(client_id,user_name,password) -- client_id必填,其余选填
    mqttc:keepalive(240) -- 默认值240s
    mqttc:autoreconn(true, 3000) -- 自动重连机制
    mqttc:debug(false)
    mqttc:on(mqtt_cb)

    -- mqttc自动处理重连, 除非自行关闭
    mqttc:connect()

end

-- 重新初始化对讲函数
local function reinit_talk()
    log.info("talk", "重新初始化对讲")
    
    -- 安全停止对讲
    if airtalk and airtalk.stop then
        airtalk.stop()
    end
    if mqttc then
        mqttc:close()
    end
    
    -- 重新初始化对讲
    sys.taskInit(init_talk)
end

--初始化airtalk
function talk.run()
    log.info("talk.run")
    -- lcd.setFont(lcd.font_opposansm12_chinese)
    run_state = true
    init_talk()
    speech_topic = fskv.get("talk_channel")
    log.info("get  speech_topic",speech_topic)
end

--停止语音采集
local function stop_talk()
    talk_state = "语音停止采集"
    airtalk.uplink(false)
    log.info("STATE", talk_state)
end

--开启语音采集
local function start_talk()
    talk_state = "语音采集上传中"
    airtalk.uplink(true)
    log.info("STATE", talk_state)
end


--设置防抖
gpio.debounce(gpio.PWR_KEY,1000)
gpio.setup(gpio.PWR_KEY,function(val)
    if val == 1 then
        log.info("talk", "暂停",val)
        stop_talk()
    else
        log.info("talk2", "录音上传",val)
        start_talk()

    end
end,gpio.PULLUP)



return talk