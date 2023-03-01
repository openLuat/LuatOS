-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "gnsstest"
VERSION = "1.0.1"

--[[
本demo需要很多流量!!!
注意: 室内无信号!! 无法定位!!!
]]

-- sys库是标配
local sys = require("sys")
require("sysplus")

local gps_uart_id = 2
local mqttc = nil

-- libgnss库初始化
libgnss.clear() -- 清空数据,兼初始化

-- LED和ADC初始化
LED_GNSS = 24
LED_VBAT = 26
gpio.setup(LED_GNSS, 0) -- GNSS定位成功灯
gpio.setup(LED_VBAT, 0) -- 低电压警告灯
adc.open(adc.CH_VBAT)
adc.open(adc.CH_CPU)

-- 串口初始化
uart.setup(gps_uart_id, 115200)

-- TODO 做成agnss.lua
function exec_agnss()
    local url = "http://download.openluat.com/9501-xingli/HXXT_GPS_BDS_AGNSS_DATA.dat"
    local dat_done = false
    sys.waitUntil("NTP_UPDATE", 1000)
    if io.fileSize("/6228.bin") > 1024 then
        local date = os.date("!*t")
        log.info("当前系统时间", os.date())
        if date.year < 2023 then
            date = os.date("!*t")
        end
        if date.year > 2022 then
            local tm = io.readFile("/6226_tm")
            if tm then
                local t = tonumber(tm)
                if t and (os.time() - t < 3600*2) then
                    log.info("agnss", "重用星历文件")
                    local body = io.readFile("/6228.bin")
                    for offset = 1, #body, 512 do
                        uart.write(gps_uart_id, body:sub(offset, offset + 511))
                        sys.wait(100)
                    end
                    dat_done = true
                else
                    log.info("星历过期了")
                end
            else
                log.info("星历时间有问题")
            end
        else
            log.info("时间有问题")
        end
    end
    if http and not dat_done then
        -- AGNSS 已调通
        while 1 do
            local code, headers, body = http.request("GET", url).wait()
            log.info("gnss", "AGNSS", code, body and #body or 0)
            if code == 200 and body and #body > 1024 then
                for offset = 1, #body, 512 do
                    log.info("gnss", "AGNSS", "write >>>", #body:sub(offset, offset + 511))
                    uart.write(gps_uart_id, body:sub(offset, offset + 511))
                    -- sys.waitUntil("UART2_SEND", 100)
                    sys.wait(100) -- 等100ms反而更成功
                end
                -- sys.waitUntil("UART2_SEND", 1000)
                io.writeFile("/6228.bin", body)
                local date = os.date("!*t")
                if date.year > 2022 then
                    io.writeFile("/6226_tm", tostring(os.time()))
                end
                break
            end
            sys.wait(60 * 1000)
        end
    end
    sys.wait(20)
    -- "$AIDTIME,year,month,day,hour,minute,second,millisecond"
    local date = os.date("!*t")
    if date.year > 2022 then
        local str = string.format("$AIDTIME,%d,%d,%d,%d,%d,%d,000", date["year"], date["month"], date["day"],
            date["hour"], date["min"], date["sec"])
        log.info("gnss", str)
        uart.write(gps_uart_id, str .. "\r\n")
        sys.wait(20)
    end
    -- 读取之前的位置信息
    local gnssloc = io.readFile("/gnssloc")
    if gnssloc then
        str = "$AIDPOS," .. gnssloc
        log.info("POS", str)
        uart.write(gps_uart_id, str .. "\r\n")
        str = nil
        gnssloc = nil
    else
        -- TODO 发起基站定位
        uart.write(gps_uart_id, "$AIDPOS,3432.70,N,10885.25,E,1.0\r\n")
    end
end

-- function upload_stat()
--     -- if mqttc == nil or not mqttc:ready() then return end
--     local stat = {
--         csq = mobile.csq(),
--         rssi = mobile.rssi(),
--         rsrq = mobile.rsrq(),
--         rsrp = mobile.rsrp(),
--         -- iccid = mobile.iccid(),
--         snr = mobile.snr(),
--         vbat = adc.get(adc.CH_VBAT),
--         temp = adc.get(adc.CH_CPU),
--         memsys = {rtos.meminfo("sys")},
--         memlua = {rtos.meminfo()},
--         fixed = libgnss.isFix()
--     }
--     sys.publish("uplink", "/gnss/" .. mobile.imei() .. "/up/stat", (json.encode(stat)), 1)
-- end

-- sys.timerLoopStart(upload_stat, 60 * 1000)

sys.taskInit(function()
    sys.waitUntil("IP_READY")
    -- Air780EG默认波特率是115200
    local nmea_topic = "/gnss/" .. mobile.imei() .. "/up/nmea"
    log.info("GPS", "start")
    pm.power(pm.GPS, true)
    libgnss.on("raw", function(data)
        sys.publish("uplink", nmea_topic, data, 1)
    end)
    -- 调试日志,可选
    libgnss.debug(true)
    sys.wait(200) -- GPNSS芯片启动需要时间,大概150ms
    -- 显示串口配置
    -- uart.write(gps_uart_id, "$CFGPRT,1\r\n")
    -- sys.wait(20)
    -- 增加显示的语句,可选
    uart.write(gps_uart_id, "$CFGMSG,0,1,1\r\n") -- GLL
    sys.wait(20)
    uart.write(gps_uart_id, "$CFGMSG,0,5,1\r\n") -- VTG
    sys.wait(20)
    uart.write(gps_uart_id, "$CFGMSG,0,6,1\r\n") -- ZDA
    sys.wait(20)
    -- 定位成功后,使用GNSS时间设置RTC, 暂不可用
    -- libgnss.rtcAuto(true)
    
    -- 绑定uart,底层自动处理GNSS数据
    -- 这里延后到设置命令发送完成后才开始处理数据,之前的数据就不上传了
    libgnss.bind(gps_uart_id)
    log.debug("提醒", "室内无GNSS信号,定位不会成功, 要到空旷的室外,起码要看得到天空")
    exec_agnss()
end)

sys.taskInit(function()
    while 1 do
        sys.wait(5000)
        -- 6228CI, 查询产品信息, 可选
        -- uart.write(gps_uart_id, "$PDTINFO,*62\r\n")
        -- uart.write(gps_uart_id, "$AIDINFO\r\n")
        -- sys.wait(100)

        -- uart.write(gps_uart_id, "$CFGSYS\r\n")
        -- uart.write(gps_uart_id, "$CFGMSG,6,4\r\n")
        log.info("RMC", json.encode(libgnss.getRmc(2) or {}))
        -- log.info("GGA", libgnss.getGga(3))
        -- log.info("GLL", json.encode(libgnss.getGll(2) or {}))
        -- log.info("GSA", json.encode(libgnss.getGsa(2) or {}))
        -- log.info("GSV", json.encode(libgnss.getGsv(2) or {}))
        -- log.info("VTG", json.encode(libgnss.getVtg(2) or {}))
        -- log.info("ZDA", json.encode(libgnss.getZda(2) or {}))
        -- log.info("date", os.date())
        log.info("sys", rtos.meminfo("sys"))
        log.info("lua", rtos.meminfo("lua"))
    end
end)

-- 订阅GNSS状态编码
sys.subscribe("GNSS_STATE", function(event, ticks)
    -- event取值有 
    -- FIXED 定位成功
    -- LOSE  定位丢失
    -- ticks是事件发生的时间,一般可以忽略
    local onoff = libgnss.isFix() and 1 or 0
    log.info("GNSS", "LED", onoff)
    gpio.set(LED_GNSS, onoff)
    log.info("gnss", "state", event, ticks)
    if event == "FIXED" then
        local locStr = libgnss.locStr()
        log.info("gnss", "locStr", locStr)
        if locStr then
            io.writeFile("/gnssloc", locStr)
        end
    end
end)

-- mqtt 上传任务
sys.taskInit(function()
    -- sys.waitUntil("IP_READY", 15000)
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

-- 适配GNSS测试设备的GPIO
sys.taskInit(function()
    while 1 do
        local vbat = adc.get(adc.CH_VBAT)
        log.info("vbat", vbat)
        if vbat < 3400 then
            gpio.set(LED_VBAT, 1)
            sys.wait(100)
            gpio.set(LED_VBAT, 0)
            sys.wait(900)
        else
            sys.wait(1000)
        end
    end
end)

sys.subscribe("NTP_UPDATE", function()
    if not libgnss.isFix() then
        -- "$AIDTIME,year,month,day,hour,minute,second,millisecond"
        local date = os.date("!*t")
        local str = string.format("$AIDTIME,%d,%d,%d,%d,%d,%d,000", 
                             date["year"], date["month"], date["day"], date["hour"], date["min"], date["sec"])
        log.info("gnss", str)
        uart.write(gps_uart_id, str .. "\r\n")
    end
end)

if socket.sntp then
    sys.subscribe("IP_READY", function()
        socket.sntp()
    end)
end

-- 休眠测试, V1103会有问题
-- mobile.flymode(0, false)
-- sys.taskInit(function()
--     while 1 do
--         sys.wait(60000)
--         if libgnss.isFix() then
--             pm.dtimerStart(0, 30000)
--             pm.request(pm.HIB)
--             pm.power(pm.USB, false)
--             mobile.flymode(0, true)
--         end
--     end
-- end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
