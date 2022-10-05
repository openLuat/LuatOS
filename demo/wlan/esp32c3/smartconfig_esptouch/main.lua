-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "wifidemo"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
require("sysplus")

sys.subscribe("IP_READY", function(ip)
    log.info("wlan", "ip ready", ip)
    -- 联网成功, 可以发起http, mqtt, 等请求了.
end)

sys.taskInit(function()
    sys.wait(1000)
    wlan.init()
    --fdb.kvdb_init()
    --if fdb.kv_get("wlan_ssid") then
    --    wlan.connect(fdb.kv_get("wlan_ssid"), fdb.kv_get("wlan_passwd"))
    --    return -- 等联网就行了
    --end
    while 1 do
        wlan.smartconfig()
        local ret, ssid, passwd = sys.waitUntil("SC_RESULT", 180*1000) -- 等3分钟
        if ret == false then
            log.info("smartconfig", "timeout")
            wlan.smartconfig(wlan.STOP)
            sys.wait(1000)
        else
            log.info("smartconfig", ssid, passwd)
            --fdb.kv_set("wlan_ssid", ssid)
            --fdb.kv_set("wlan_passwd", passwd)
            --break
        end
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
