-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "gnss"
VERSION = "1.0.0"

--[[
本demo是演示定位数据处理的. script/turnkey目录有更完整的应用.
本demo需要V1103及以上的固件!!
注意: 室内无信号!! 无法定位!!! 到室外去, 起码天线要在室外.
窗口只有少许信号, 无法保证定位成功

这个demo需要的流量很多,可以注释这行
sys.publish("mqtt_pub", "/gnss/" .. mobile.imei() .. "/up/nmea", data, 1)
]]

-- sys库是标配
local sys = require("sys")
require("sysplus")

local gps_uart_id = 2
local mqttc = nil

libgnss.clear() -- 清空数据,兼初始化

uart.setup(gps_uart_id, 115200)

function exec_agnss()
    if http then
        -- AGNSS 已调通
        while 1 do
            local code, headers, body = http.request("GET", "http://download.openluat.com/9501-xingli/HXXT_GPS_BDS_AGNSS_DATA.dat").wait()
            -- local code, headers, body = http.request("GET", "http://nutzam.com/6228.bin").wait()
            log.info("gnss", "AGNSS", code, body and #body or 0)
            if code == 200 and body and #body > 1024 then
                -- uart.write(gps_uart_id, "$reset,0,h01\r\n")
                -- sys.wait(200)
                -- uart.write(gps_uart_id, body)
                for offset=1,#body,512 do
                    log.info("gnss", "AGNSS", "write >>>", #body:sub(offset, offset + 511))
                    uart.write(gps_uart_id, body:sub(offset, offset + 511))
                    -- sys.waitUntil("UART2_SEND", 100)
                    sys.wait(100) -- 等100ms反而更成功
                end
                -- sys.waitUntil("UART2_SEND", 1000)
                io.writeFile("/6228.bin", body)
                break
            end
            sys.wait(60*1000)
        end
    end
    sys.wait(20)
    -- "$AIDTIME,year,month,day,hour,minute,second,millisecond"
    local date = os.date("!*t")
    if date.year > 2022 then
        local str = string.format("$AIDTIME,%d,%d,%d,%d,%d,%d,000", 
                         date["year"], date["month"], date["day"], date["hour"], date["min"], date["sec"])
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

function upload_stat()
    if mqttc == nil or not mqttc:ready() then return end
    local stat = {
        csq = mobile.csq(),
        rssi = mobile.rssi(),
        rsrq = mobile.rsrq(),
        rsrp = mobile.rsrp(),
        --iccid = mobile.iccid(),
        snr = mobile.snr()
    }
    sys.publish("mqtt_pub", "/gnss/" .. mobile.imei() .. "/up/stat", (json.encode(stat)), 1)
end

sys.timerLoopStart(upload_stat, 60*1000)

sys.taskInit(function()
    -- Air780EG工程样品的GPS的默认波特率是9600, 量产版是115200,以下是临时代码
    log.info("GPS", "start")
    pm.power(pm.GPS, true)
    -- 绑定uart,底层自动处理GNSS数据
    -- 第二个参数是转发到虚拟UART, 方便上位机分析
    libgnss.bind(gps_uart_id, uart.VUART_0)
    libgnss.on("raw", function(data)
        -- 默认不上报, 需要的话自行打开
        data = data:split("\r\n")
        if data == nil then
            return
        end
        for k, v in pairs(data) do
            if v and v:startsWith("$GNRMC") then
                sys.publish("mqtt_pub", "/gnss/" .. mobile.imei() .. "/up/nmea", v, 0)
            end
        end
    end)
    sys.wait(200) -- GPNSS芯片启动需要时间
    -- 调试日志,可选
    libgnss.debug(true)
    -- 显示串口配置
    -- uart.write(gps_uart_id, "$CFGPRT,1\r\n")
    -- sys.wait(20)
    -- 增加显示的语句
    uart.write(gps_uart_id, "$CFGMSG,0,1,1\r\n") -- GLL
    sys.wait(20)
    uart.write(gps_uart_id, "$CFGMSG,0,5,1\r\n") -- VTG
    sys.wait(20)
    uart.write(gps_uart_id, "$CFGMSG,0,6,1\r\n") -- ZDA
    sys.wait(20)
    -- 定位成功后,使用GNSS时间设置RTC, 暂不可用
    -- libgnss.rtcAuto(true)
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
	sys.waitUntil("IP_READY", 15000)

    mqttc = mqtt.create(nil, "lbsmqtt.airm2m.com", 1886)  --mqtt客户端创建

    mqttc:auth(mobile.imei(), mobile.imei(), mobile.muid()) --mqtt三元组配置
    log.info("mqtt", mobile.imei(), mobile.imei(), mobile.muid())
    mqttc:keepalive(30) -- 默认值240s
    mqttc:autoreconn(true, 3000) -- 自动重连机制

    mqttc:on(function(mqtt_client, event, data, payload)  --mqtt回调注册
        -- 用户自定义代码，按event处理
        --log.info("mqtt", "event", event, mqtt_client, data, payload)
        if event == "conack" then -- mqtt成功完成鉴权后的消息
            sys.publish("mqtt_conack") -- 小写字母的topic均为自定义topic
            -- 订阅不是必须的，但一般会有
            mqtt_client:subscribe("/gnss/" .. mobile.imei() .. "/down/#")
        elseif event == "recv" then -- 服务器下发的数据
            log.info("mqtt", "downlink", "topic", data, "payload", payload)
            -- 这里继续加自定义的业务处理逻辑
        elseif event == "sent" then -- publish成功后的事件
            log.info("mqtt", "sent", "pkgid", data)
        end
    end)

    -- 发起连接之后，mqtt库会自动维护链接，若连接断开，默认会自动重连
    mqttc:connect()
	sys.waitUntil("mqtt_conack")
    log.info("mqtt连接成功")
    sys.timerStart(upload_stat, 1000) -- 一秒后主动上传一次
    while true do
        -- 业务演示。等待其他task发过来的待上报数据
        -- 这里的mqtt_pub字符串是自定义的，与mqtt库没有直接联系
        -- 若不需要异步关闭mqtt链接，while内的代码可以替换成sys.wait(30000)
        local ret, topic, data, qos = sys.waitUntil("mqtt_pub", 30000)
        if ret then
            if topic == "close" then break end
            log.info("mqtt", "publish", "topic", topic)
            mqttc:publish(topic, data, qos)
        end
    end
    mqttc:close()
    mqttc = nil
end)

sys.taskInit(function()
    while 1 do
        sys.wait(3600*1000) -- 一小时检查一次
        local fixed, time_fixed = libgnss.isFix()
        if not fixed then
            exec_agnss()
        end
    end
end)

sys.timerLoopStart(function()
    upload_stat()
end, 60000)

-- sys.subscribe("NTP_UPDATE", function()
--     if not libgnss.isFix() then
--         -- "$AIDTIME,year,month,day,hour,minute,second,millisecond"
--         local date = os.date("!*t")
--         local str = string.format("$AIDTIME,%d,%d,%d,%d,%d,%d,000", 
--                              date["year"], date["month"], date["day"], date["hour"], date["min"], date["sec"])
--         log.info("gnss", str)
--         uart.write(gps_uart_id, str .. "\r\n")
--     end
-- end)

-- if socket and socket.sntp then
--     sys.subscribe("IP_READY", function()
--         socket.sntp()
--     end)
-- end

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
