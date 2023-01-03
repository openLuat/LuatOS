-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "gnss"
VERSION = "1.0.0"

--[[
本demo是演示定位数据处理的
]]

-- sys库是标配
local sys = require("sys")
require("sysplus")

local gps_uart_id = 2
libgnss.clear() -- 清空数据,兼初始化

uart.setup(
    uart.VUART_0,-- USB虚拟串口id
    115200,--波特率
    8,--数据位
    1--停止位
)
uart.on(uart.VUART_0, "recv", function(id, len)
    log.info("uart", id, len);
    -- while 1 do
        -- local data = uart.read(uart.VUART_0, 1024)
        -- if data and #data > 0 then
        --     uart.write(gps_uart_id, data)
        -- else
        --     -- break
        -- end
    -- end
end)

uart.on(2, "sent", function(id, len)
    sys.publish("UART_SEND", 2)
end)

sys.taskInit(function()
    while 1 do
        local data = uart.read(uart.VUART_0, 1024)
        if data and #data > 0 then
            log.info("vuart", #data)
            log.info("vuart", data:toHex())
            uart.write(gps_uart_id, data)
        else
            sys.wait(30)
        end
    end
end)

sys.taskInit(function()
    -- Air780EG工程样品的GPS的默认波特率是9600, 量产版是115200,以下是临时代码
    log.info("GPS", "start")
    pm.power(pm.GPS, true)
    uart.setup(gps_uart_id, 115200)
    -- 绑定uart,底层自动处理GNSS数据
    -- 第二个参数是转发到虚拟UART, 方便上位机分析
    libgnss.bind(gps_uart_id, uart.VUART_0)
    libgnss.on("raw", function(data)
        sys.publish("mqtt_pub", "$gnss/" .. mobile.imei() .. "/up/nmea", data, 1)
    end)
    sys.wait(200) -- GPNSS芯片启动需要时间
    -- 调试日志,可选
    libgnss.debug(true)
    -- 显示串口配置
    uart.write(gps_uart_id, "$CFGPRT,1\r\n")
    sys.wait(20)
    -- 增加显示的语句
    uart.write(gps_uart_id, "$CFGMSG,0,1,1\r\n") -- GLL
    sys.wait(20)
    uart.write(gps_uart_id, "$CFGMSG,0,5,1\r\n") -- VTG
    sys.wait(20)
    -- 定位成功后,使用GNSS时间设置RTC, 暂不可用
    -- libgnss.rtcAuto(true)
    if http then
        -- AGNSS 已调通
        -- URL需要更新到3星座数据
        while 1 do
            local code, headers, body = http.request("GET", "http://download.openluat.com/9501-xingli/HXXT_GPS_BDS_AGNSS_DATA.dat").wait()
            -- local code, headers, body = http.request("GET", "http://nutzam.com/6228.bin").wait()
            log.info("gnss", "AGNSS", code, body and #body or 0)
            if code == 200 and body and #body > 1024 then
                -- uart.write(gps_uart_id, "$reset,0,h01\r\n")
                sys.wait(200)
                for offset=1,#body,512 do
                    log.info("gnss", "AGNSS", "write >>>", #body:sub(offset, offset + 511))
                    uart.write(gps_uart_id, body:sub(offset, offset + 511))
                    sys.waitUntil("UART_SEND", 100)
                end
                io.writeFile("/6228.bin", body)
                break
            end
            sys.wait(60*1000)
        end
    end
    sys.wait(100)
    -- "$AIDTIME,year,month,day,hour,minute,second,millisecond"
    local date = os.date("!*t")
    local str = string.format("$AIDTIME,%d,%d,%d,%d,%d,%d,000", 
                         date["year"], date["month"], date["day"], date["hour"], date["min"], date["sec"])
    log.info("gnss", str)
    uart.write(gps_uart_id, str .. "\r\n") 
    sys.wait(100)
    -- 读取之前的位置信息
    local gnssloc = io.readFile("/gnssloc")
    if gnssloc then
        str = "$AIDPOS," .. gnssloc
        log.info("POS", str)
        uart.write(gps_uart_id, str .. "\r\n")
        str = nil
        gnssloc = nil
    end
end)

sys.taskInit(function()
    while 1 do
        sys.wait(1000)
        -- 6228CI, 查询产品信息, 可选
        -- uart.write(gps_uart_id, "$PDTINFO,*62\r\n")
        uart.write(gps_uart_id, "$AIDINFO\r\n")
        -- sys.wait(100)
        
        -- uart.write(gps_uart_id, "$CFGSYS\r\n")
        -- uart.write(gps_uart_id, "$CFGMSG,6,4\r\n")
        log.info("RMC", json.encode(libgnss.getRmc(2) or {}))
        -- log.info("GGA", json.encode(libgnss.getGga(2) or {}))
        -- log.info("GLL", json.encode(libgnss.getGll(2) or {}))
        -- log.info("GSA", json.encode(libgnss.getGsa(2) or {}))
        -- log.info("GSV", json.encode(libgnss.getGsv(2) or {}))
        -- log.info("VTG", json.encode(libgnss.getVtg(2) or {}))
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

    mqttc = mqtt.create(nil, "mqtt.air32.cn", 1883)  --mqtt客户端创建

    mqttc:auth(mobile.imei(), mobile.imei(), mobile.imei()) --mqtt三元组配置
    mqttc:keepalive(30) -- 默认值240s
    mqttc:autoreconn(true, 3000) -- 自动重连机制

    mqttc:on(function(mqtt_client, event, data, payload)  --mqtt回调注册
        -- 用户自定义代码，按event处理
        --log.info("mqtt", "event", event, mqtt_client, data, payload)
        if event == "conack" then -- mqtt成功完成鉴权后的消息
            sys.publish("mqtt_conack") -- 小写字母的topic均为自定义topic
            -- 订阅不是必须的，但一般会有
            mqtt_client:subscribe("$gnss/" .. mobile.imei() .. "/down/#")
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
    while true do
        -- 业务演示。等待其他task发过来的待上报数据
        -- 这里的mqtt_pub字符串是自定义的，与mqtt库没有直接联系
        -- 若不需要异步关闭mqtt链接，while内的代码可以替换成sys.wait(13000
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

-- 定期重启GPS, 测试AGNSS
-- sys.taskInit(function()
--     while 1 do
--         sys.wait(120 * 1000)
--         log.info("GPS", "stop")
--         pm.power(pm.GPS, false)
--         pm.power(pm.GPS_ANT, false)
--         sys.wait(500)
--         log.info("GPS", "start")
--         pm.power(pm.GPS, true)
--         pm.power(pm.GPS_ANT, true)
--         sys.wait(300) -- 输出产品日志大概是150ms左右,这里延时一下
--         -- 写入时间
--         local date = os.date("!*t")
--         if date["year"] > 2021 then
--             local str = string.format("$AIDTIME,%d,%d,%d,%d,%d,%d,000", 
--                              date["year"], date["month"], date["day"], date["hour"], date["min"], date["sec"])
--             log.info("gnss", str)
--             uart.write(gps_uart_id, str .. "\r\n")
--         end
--         -- 读取并写入辅助坐标
--         local gnssloc = io.readFile("/gnssloc")
--         if gnssloc then
--             uart.write(gps_uart_id, "$AIDPOS," .. gnssloc .. "\r\n")
--             gnssloc = nil
--         end
--         -- 写入星历
--         local body = io.readFile("/6228.bin")
--         if body then
--             for offset=1,#body,1024 do
--                 log.info("gnss", "AGNSS", "write >>>")
--                 uart.write(gps_uart_id, body:sub(offset, 1024))
--                 sys.wait(5)
--             end
--         end
--         log.info("AGNSS", "write complete")
--         -- 查询一下辅助定位成功没
--         sys.wait(300)
--         uart.write(gps_uart_id, "$AIDINFO\r\n")
--     end

-- end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
