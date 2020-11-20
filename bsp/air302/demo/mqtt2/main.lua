
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air302_mqtt2"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require "sys"
mqtt = require "mqtt2"


log.info("version", _VERSION, VERSION)


sys.taskInit(function ()
    sys.wait(2000)
    while not socket.isReady() do
        log.info("net", "wait for network ready")
        sys.waitUntil("NET_READY", 1000)
    end
    local s = mqtt.new(nbiot.imei(), 300, "username", "password", 1, "lbsmqtt.airm2m.com", 1884,
    {
        ["/luatos/"..(nbiot.imei() or "no_imei")]=0,
        ["/luatos/"..(nbiot.imei() or "no_imei").."/+"]=0,
    },
    function (data)
        log.info("mqtt","receive",data.topic,data.payload,data.id,data.retain,data.qos,data.dup)
    end)
    sys.taskInit(function() s:run() end)

    while true do
        log.info("mqtt","pub start")
        local r,d = s:pub("/luatos/pub/"..(nbiot.imei() or "no_imei"), 0, tostring(os.time()))
        log.info("mqtt","pub sent",r,d)
        sys.wait(10000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
