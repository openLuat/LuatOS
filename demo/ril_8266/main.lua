PROJECT = "adcdemo"
VERSION = "1.0.0"

sys = require 'sys'
local mqtt = require "mqtt"
_G.point = function(...)
    --local name = debug.getinfo(2).short_src
    --local line = debug.getinfo(2).currentline
    --print("[" .. name .. " : " .. line .. "]", ...)
end

require "wifi"
-- require "mqtt"
-- -- 这里请填写修改为自己的IP和端口
-- local host, port = "lbsmqtt.airm2m.com", 1884


sys.taskInit(function()
    -- 服务器配置信息
    local host, port, selfid = "1.15.81.195", 1883, "AIR105"
    sys.waitUntil("IP_READY_IND")
    -- 等待联网成功
    while true do
        while not socket.isReady() do 
            log.info("net", "wait for network ready")
            sys.waitUntil("IP_READY_IND", 1000)
        end
        log.info("main", "Airm2m mqtt loop")
        
        local mqttc = mqtt.client("clientid-123")
        while not mqttc:connect(host, port) do sys.wait(2000) end
        local topic_req = string.format("/device")
        local topic_report = string.format("/device")
        local topic_resp = string.format("/device/%s/resp", selfid)
        log.info("mqttc", "mqtt seem ok", "try subscribe", topic_req)
        if mqttc:subscribe(topic_req) then
            log.info("mqttc", "mqtt subscribe ok", "try publish")
            if mqttc:publish(topic_report, "test publish " .. os.date(), 1) then
                while true do
                    log.info("mqttc", "wait for new msg")
                    local r, data, param = mqttc:receive(120000, "pub_msg")
                    log.info("mqttc", "mqttc:receive", r, data, param)
                    if r then
                        log.info("mqttc", "get message from server", data.payload or "nil", data.topic)
                    elseif data == "pub_msg" then
                        log.info("mqttc", "send message to server", data, param)
                        mqttc:publish(topic_resp, "response " .. param)
                    elseif data == "timeout" then
                        log.info("mqttc", "wait timeout, send custom report")
                        mqttc:publish(topic_report, "test publish " .. os.date())
                    else
                        log.info("mqttc", "ok, something happen", "close connetion")
                        break
                    end
                end
            end
        end
        mqttc:disconnect()
        sys.wait(5000) -- 等待一小会, 免得疯狂重连
    end

end)
-- sys.taskInit(function()
--     sys.waitUntil("IP_READY_IND")
--     while true do
--         while not socket.isReady() do
--             sys.wait(1000)
--         end
--         local c = socket.tcp()
--         while not c:connect("112.125.89.8", 36091) do
--             sys.wait(2000)
--         end

--         while true do
--             c:send("1234567890")
--             r, s, p = c:recv(5000, "pub_msg")
--             if r then
--                 log.info("这是收到了服务器下发的消息:", s)
--             elseif s == "pub_msg" then
--                 log.info("这是收到了订阅的消息和参数显示:", s, p)
--                 if not c:send(p) then
--                     break
--                 end
--             elseif s == "timeout" then
--                 log.info("这是等待超时发送心跳包的显示!")
--                 if not c:send("\0") then
--                     break
--                 end
--             else
--                 log.info("这是socket连接错误的显示!")
--                 break
--             end
--             sys.wait(5000)
--         end
--         c:close()
--     end
-- end)


-- print(uart.setup(4,115200))

-- uart.on(4,"receive",function (id,len)
--     print(uart.read(id,len))
-- end)

-- sys.timerLoopStart(uart.write,1000,4,"ATE0\r\n")
sys.timerLoopStart(function()
    log.info("mem.lua", rtos.meminfo())
    -- log.info("mem.lua", rtos.meminfo("sys"))
    -- 打印占用的RAM
    collectgarbage("collect")
end, 3000)
sys.run()
sys.run()
