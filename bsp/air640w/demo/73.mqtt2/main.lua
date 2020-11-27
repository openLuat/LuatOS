--[[
demo说明:
1. 演示wifi联网操作
2. 演示长连接操作
3. 演示简易的网络状态灯
]]-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "mqtt2demo"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require

_G.sys = require("sys")
_G.mqtt2 = require("mqtt2")
_G.mine = require("my_demo")

log.info("main", "simple mqtt2 demo")

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
-- sys.subscribe("NET_READY", function ()
--     log.info("net", "!!! network ready event !!! send ntp")
--     sys.taskInit(function()
--         sys.wait(2000)
--         socket.ntpSync()
--     end)
-- end)

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
        --log.info("mem", rtos.meminfo())
    end
end)

-- 声明几个topic

local host, port, clientId = "lbsmqtt.airm2m.com", 1884, wlan.getMac():lower()

local topic_req = string.format("/device/%s/req", clientId)
local topic_report = string.format("/device/%s/report", clientId)
local topic_resp = string.format("/device/%s/resp", clientId)

uart.setup(1)
uart.on(1, "recv", function(id, len)
    local data = uart.read(1, 1024)
    if _G.mqttc and _G.mqttc.stat == 1 then
        sys.taskInit(function()
            _G.mqttc:pub(topic_resp, 1, data)
        end)
    end
end)

sys.taskInit(function()

    local sub_topics = {}
    sub_topics[topic_req] = 1
    sub_topics[topic_req .. "1"] = 1
    sub_topics[topic_req .. "2"] = 1
    sub_topics[topic_req .. "3"] = 1
    sub_topics[topic_req .. "4"] = 1
    sub_topics[topic_req .. "5"] = 1
    sub_topics[topic_req .. "6"] = 1
    sub_topics[topic_req .. "7"] = 1
    sub_topics[topic_req .. "8"] = 1

    _G.mqttc = mqtt2.new(clientId, 300, "wendal", "123456", 1, host, port, sub_topics, function(pkg)
        log.info("mqtt", "Oh", json.encode(pkg))
    end, "mqtt_airm2m")

    --log.info("mqtt", json.encode(mqttc))

    while not socket.isReady() do sys.waitUntil("NET_READY", 1000) end
    sys.wait(3000)
    log.info("go", "GoGoGo")
    mqttc:run() -- 会一直阻塞在这里
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
