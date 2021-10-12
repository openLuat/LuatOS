
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air302_mqtt2"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require "sys"
mqtt2 = require "mqtt2"

-- 打印一下项目的信息
log.info("version", _VERSION, VERSION, PROJECT) 


sys.taskInit(function ()
    sys.wait(2000)
    while not socket.isReady() do
        log.info("net", "wait for network ready")
        sys.waitUntil("NET_READY", 1000)
    end
    -- 与mqtt.lua传入的参数有所不同,注意区分
    -- 第一个参数是clientId, 通常就是用imei
    -- 第二个参数是用户
    -- 第三个参数是密码
    -- 第四个参数是cleanSession,当前强制为1
    -- 第5和第6个参数分别是服务器域名/ip, 及端口号
    -- 第7个参数, 必须是一个table, key-value形式, 代表默认订阅的topic
    -- 第8个参数是收到消息时的回调
    local s = mqtt2.new(nbiot.imei(), 300, "username", "password", 1, "lbsmqtt.airm2m.com", 1884,
    {
        ["/luatos/"..(nbiot.imei() or "no_imei")]=0,
        ["/luatos/"..(nbiot.imei() or "no_imei").."/+"]=0,
    },
    function (data) -- 回调,data肯定是table, 肯定不为null
        log.info("mqtt","receive",data.topic,data.payload,data.id,data.retain,data.qos,data.dup)
    end)
    -- s:run需要跑在协程里, 这里演示的是单独启动一个协程
    -- mqtt2的重要特性之一就是自动重连, s:run()会一直阻塞运行, 链接如果断开了, 会自动发起重连
    sys.taskInit(function() s:run() end)

    -- 毕竟这是个demo,所以加一段定时发送的代码
    -- 这段代码也可以在其他task里面执行
    while true do
        log.info("mqtt","pub start")
        -- s:pub的参数为 (topic, qos, payload),
        local r,d = s:pub("/luatos/pub/"..(nbiot.imei() or "no_imei"), 0, tostring(os.time()))
        log.info("mqtt","pub sent",r,d)
        sys.wait(10000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
