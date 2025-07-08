local talk = {}

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")
local run_state = false -- 判断本UI DEMO 是否运行
local airaudio  = require "airaudio"
local speech_topic = ""  --  填写手机号，需要保证所有对讲设备，网页都是同一个号码   
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

local function mqtt_cb(mqtt_client, event, data, payload)
    log.info("mqtt", "event", event, mqtt_client, data, payload)
end



local function init_talk()
    log.info("init_call")
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

local function stop_talk()
    talk_state = "语音停止采集"
    airtalk.uplink(false)
end


local function start_talk()
    talk_state = "语音采集上传中"
    airtalk.uplink(true)
end

function talk.run()
    log.info("talk.run")
    lcd.setFont(lcd.font_opposansm12_chinese) -- 设置中文字体
    run_state = true
    sys.taskInit(init_talk)


    while true do
        sys.wait(10)
        lcd.clear(_G.bkcolor)
        if speech_topic == "" then
            lcd.drawStr(0, 80, "请填入speech_topic,并保证所有终端topic 一致")
        else
            lcd.drawStr(0, 80, "对讲测试,测试topic:"..speech_topic )
            lcd.drawStr(0, 120, "所有终端或者网页都要使用同一个topic")

            lcd.drawStr(0, 140, talk_state)
            

            lcd.drawStr(0, 160, "事件:" .. event)
            lcd.showImage(130, 350, "/luadb/start.jpg") -- 对讲开始按钮
            lcd.showImage(130, 397, "/luadb/stop.jpg") -- 对讲停止按钮
            
            lcd.showImage(0, 448, "/luadb/Lbottom.jpg")
            
        end
        lcd.flush()

        if not run_state then -- 等待结束，返回主界面
            return true
        end
    end
end

function talk.tp_handal(x, y, event)
    if x > 20 and x < 100 and y > 360 and y < 440 then
        run_state = false
    elseif x > 130 and x < 230 and y > 350 and y < 397 then
        sysplus.taskInitEx(start_talk, "start_talk")
    elseif x > 130 and x < 230 and y > 397 and y < 444 then
        sysplus.taskInitEx(stop_talk, "stop_talk")
    end
end

return talk
