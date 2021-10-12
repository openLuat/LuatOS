--[[
demo说明:
1. 演示wifi联网操作
2. 演示长连接操作
3. 演示简易的网络状态灯
]]
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "mqttdemo"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
_G.sys = require("sys")
_G.mqtt = require("mqtt")
_G.mine = require("my_demo")

log.info("main", "simple mqtt demo")

-- //////////////////////////////////////////////////////////////////////////////////////
-- wifi 相关的代码
if wlan ~= nil then
    log.info("mac", wlan.get_mac())
    local ssid = mine.wifi_ssid
    local password = mine.wifi_passwd
    -- 方式1 直接连接, 简单快捷
    wlan.connect(ssid, password) -- 直接连
    -- 方式2 先扫描,再连接. 例如根据rssi(信号强度)的不同, 择优选择ssid
    -- sys.taskInit(function()
    --     wlan.scan()
    --     sys.waitUntil("WLAN_SCAN_DONE", 30000)
    --     local re = wlan.scan_get_info()
    --     log.info("wlan", "scan done", #re)
    --     for i in ipairs(re) do
    --         log.info("wlan", "info", re[i].ssid, re[i].rssi)
    --     end
    --     log.info("wlan", "try connect to wifi")
    --     wlan.connect(ssid, password)
    --     sys.waitUntil("WLAN_READY", 15000)
    --     log.info("wifi", "self ip", socket.ip())
    -- end)
    -- 方法3 airkiss配网, 可参考 app/playit/main.lua
end

-- airkiss.auto(27) -- 预留的功能,未完成 
-- //////////////////////////////////////////////////////////////////////////////////////

--- 从这里开始, 代码与具体网络无关

-- 联网后自动同步时间
sys.subscribe("NET_READY", function ()
    log.info("net", "!!! network ready event !!! send ntp")
    sys.taskInit(function()
        sys.wait(2000)
        socket.ntpSync()
    end)
end)

gpio.setup(21, 0)
_G.use_netled = 1 -- 启用1, 关闭0
sys.taskInit(function()
    while 1 do
        --log.info("wlan", "ready?", wlan.ready())
        if socket.isReady() then
            --log.info("netled", "net ready, slow")
            gpio.set(21, 1 * use_netled)
            sys.wait(1900)
            gpio.set(21, 0)
            sys.wait(100)
        else
            --log.info("netled", "net not ready, fast")
            gpio.set(21, 1 * use_netled)
            sys.wait(100)
            gpio.set(21, 0)
            sys.wait(100)
        end
    end
end)

sys.taskInit(function()
    local host, port, selfid = "lbsmqtt.airm2m.com", 1884, wlan.getMac():lower()
    -- 等待联网成功
    while true do
        while not socket.isReady() do 
            log.info("net", "wait for network ready")
            sys.waitUntil("NET_READY", 1000)
        end
        log.info("main", "mqtt loop")
        
        collectgarbage("collect")
        collectgarbage("collect")
        local mqttc = mqtt.client(wlan.getMac(), nil, nil, false)
        while not mqttc:connect(host, port) do sys.wait(2000) end
        local topic_req = string.format("/device/%s/req", selfid)
        local topic_report = string.format("/device/%s/report", selfid)
        local topic_resp = string.format("/device/%s/resp", selfid)
        log.info("mqttc", "mqtt seem ok", "try subscribe", topic_req)
        if mqttc:subscribe(topic_req) then
            log.info("mqttc", "mqtt subscribe ok", "try publish")
            if mqttc:publish(topic_report, "test publish " .. os.time(), 1) then
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
                        mqttc:publish(topic_report, "test publish " .. os.time() .. wlan.getMac())
                    else
                        log.info("mqttc", "ok, something happen", "close connetion")
                        break
                    end
                end
            end
        end
        mqttc:disconnect()
        sys.wait(5000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
