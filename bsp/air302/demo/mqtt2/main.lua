
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
        log.info("mqtt","=====cb start======")
        for i,j in pairs(data) do
            log.info("mqtt cb",i,j)
        end
        log.info("mqtt","======cb end======")
    end)

    s:run()

    sys.timerLoopStart(function()
        s:pub("/luatos/pub/"..(nbiot.imei() or "no_imei"), 0, tostring(os.time()))
    end,10000)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
