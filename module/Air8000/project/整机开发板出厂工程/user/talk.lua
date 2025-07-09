-- talk.lua
local talk = {}

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")

local run_state = false
local airaudio  = require "airaudio"
local input_method = require "InputMethod" 
local input_active = false
local prev_fun = "main" 
local input_key = false

-- 初始化fskv

local speech_topic = nil  --  填写对讲号码，需要保证所有对讲设备，网页都是同一个号码   
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
local mqttc = nil

local function airtalk_event_cb(event, param)
    log.info("talk event", event, param)
    event  = event
end


-- MQTT回调函数
local function mqtt_cb(mqtt_client, event, data, payload)
    log.info("mqtt", "event", event, mqtt_client, data, payload)
    -- 连接成功时订阅主题
end


local function init_talk()
    log.info("init_call")
    airaudio.init() 

    speech_topic = fskv.get("talk")
    log.info("get  speech_topic",speech_topic)
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

-- 输入法回调函数
local function submit_callback(input_text)
    if input_text and #input_text > 0 then
        speech_topic = input_text
        fskv.set("talk_channel", input_text)  -- 保存频道名称到fskv
        log.info("fskv", "频道名称保存成功:", input_text)
        fskv.set("talk_channel", speech_topic)
        log.info("talk", "使用默认频道:", speech_topic)
        input_key = false
   
        -- 重新初始化对讲
        sys.taskInit(reinit_talk)
    end
end


function talk.run()
    log.info("talk.run")
    lcd.setFont(lcd.font_opposansm12_chinese)
    run_state = true
    
    if not mqttc then
        sys.taskInit(init_talk)
    end

    while run_state do
        sys.wait(100)
        if input_method.is_active() then
            input_method.periodic_refresh()
        else
            lcd.clear(_G.bkcolor) 
            if  speech_topic  == nil then
                lcd.drawStr(0, 80, "请填入speech_topic,并保证所有终端topic 一致")
            else
                lcd.drawStr(0, 80, "对讲测试,测试topic:"..speech_topic )
                lcd.drawStr(0, 120, "所有终端或者网页都要使用同一个topic")
                lcd.drawStr(0, 140, talk_state)
                lcd.drawStr(0, 160, "事件:" .. event)
                
                -- 显示输入法入口按钮
                lcd.showImage(130, 250, "/luadb/input_topic.jpg")
                lcd.showImage(130, 350, "/luadb/start.jpg")
                lcd.showImage(130, 397, "/luadb/stop.jpg")
                lcd.showImage(0, 448, "/luadb/Lbottom.jpg")
                -- log.info("flush ui") 
            end
            lcd.flush()
        end


        if not run_state then
            return true
        end
    end
end


local function stop_talk()
    talk_state = "语音停止采集"
    airtalk.uplink(false)
end


local function start_talk()
    talk_state = "语音采集上传中"
    airtalk.uplink(true)
end


local function start_input()
    input_key = true
    input_method.init(false, "talk", submit_callback)  -- 直接传递函数
end



function talk.tp_handal(x, y, event)
    if input_key then
        input_method.process_touch(x, y)
    end

    if x > 20 and x < 100 and y > 360 and y < 440 then
        run_state = false
    elseif x > 130 and x < 230 and y > 350 and y < 397 then
        sysplus.taskInitEx(start_talk, "start_talk")
    elseif x > 130 and x < 230 and y > 397 and y < 444 then
        sysplus.taskInitEx(stop_talk, "stop_talk")
    elseif x > 130 and x < 230 and y > 250 and y < 300 then
        sysplus.taskInitEx(start_input,"start_input")
    end
end



return talk