
local mqttc = nil

-- mqtt 上传任务
sys.taskInit(function()
    sys.waitUntil("IP_READY", 15000)
    mqttc = mqtt.create(nil, "lbsmqtt.airm2m.com", 1886) -- mqtt客户端创建

    mqttc:auth(mobile.imei(), mobile.imei(), mobile.muid()) -- mqtt三元组配置
    log.info("mqtt", mobile.imei(), mobile.imei(), mobile.muid())
    mqttc:keepalive(30) -- 默认值240s
    mqttc:autoreconn(true, 3000) -- 自动重连机制

    mqttc:on(function(mqtt_client, event, data, payload) -- mqtt回调注册
        -- 用户自定义代码，按event处理
        -- log.info("mqtt", "event", event, mqtt_client, data, payload)
        if event == "conack" then -- mqtt成功完成鉴权后的消息
            sys.publish("mqtt_conack") -- 小写字母的topic均为自定义topic
            -- 订阅不是必须的，但一般会有
            mqtt_client:subscribe("/gnss/" .. mobile.imei() .. "/down/#")
        elseif event == "recv" then -- 服务器下发的数据
            log.info("mqtt", "downlink", "topic", data, "payload", payload)
            local dl = json.decode(data)
            if dl then
                -- 检测命令
                if dl.cmd then
                    -- 直接写uart
                    if dl.cmd == "uart" and dl.data then
                        uart.write(gps_uart_id, dl.data)
                    -- 重启命令
                    elseif dl.cmd == "reboot" then
                        rtos.reboot()
                    elseif dl.cmd == "stat" then
                        upload_stat()
                    end
                end
            end
        elseif event == "sent" then -- publish成功后的事件
            log.info("mqtt", "sent", "pkgid", data)
        end
    end)

    -- 发起连接之后，mqtt库会自动维护链接，若连接断开，默认会自动重连
    mqttc:connect()
    -- sys.waitUntil("mqtt_conack")
    -- log.info("mqtt连接成功")
    sys.timerStart(upload_stat, 3000) -- 一秒后主动上传一次
    while true do
        sys.wait(60*1000)
    end
    mqttc:close()
    mqttc = nil
end)

sys.taskInit(function()
    while 1 do
        sys.wait(3600 * 1000) -- 一小时检查一次
        local fixed, time_fixed = libgnss.isFix()
        if not fixed then
            exec_agnss()
        end
    end
end)

sys.timerLoopStart(upload_stat, 60000)

sys.taskInit(function()
    local msgs = {}
    while 1 do
        local ret, topic, data, qos = sys.waitUntil("uplink", 30000)
        if ret then
            if topic == "close" then
                break
            end
            log.info("mqtt", "publish", "topic", topic)
            -- if #data > 512 then
            --     local start = mcu.ticks()
            --     local cdata = miniz.compress(data)
            --     local endt = mcu.ticks() - start
            --     if cdata then
            --         log.info("miniz", #data, #cdata, endt)
            --     end
            -- end
            if mqttc:ready() then
                local tmp = msgs
                if #tmp > 0 then
                    log.info("mqtt", "ready, send buff", #tmp)
                    msgs = {}
                    for k, msg in pairs(tmp) do
                        mqttc:publish(msg.topic, msg.data, 0)
                    end
                end
                mqttc:publish(topic, data, qos)
            else
                log.info("mqtt", "not ready, insert into buff")
                if #msgs > 60 then
                    table.remove(msgs, 1)
                end
                table.insert(msgs, {
                    topic = topic,
                    data = data
                })
            end
        end
    end
end)

function upload_stat()
    if mqttc == nil or not mqttc:ready() then return end
    local stat = {
        csq = mobile.csq(),
        rssi = mobile.rssi(),
        rsrq = mobile.rsrq(),
        rsrp = mobile.rsrp(),
        -- iccid = mobile.iccid(),
        snr = mobile.snr(),
        vbat = adc.get(adc.CH_VBAT),
        temp = adc.get(adc.CH_CPU),
        memsys = {rtos.meminfo("sys")},
        memlua = {rtos.meminfo()},
        fixed = libgnss.isFix()
    }
    sys.publish("uplink", "/gnss/" .. mobile.imei() .. "/up/stat", (json.encode(stat)), 1)
end

sys.timerLoopStart(upload_stat, 60 * 1000)

