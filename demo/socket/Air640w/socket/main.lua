-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "socketdemo"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
local sys = require "sys"

log.info("main", "socket demo")

log.info("mac", wlan.get_mac())
wlan.connect("uiot", "12345678")

sys.subscribe("WLAN_READY", function ()
    print("!!! wlan ready event !!!")
    --socket.ntpSync()
end)

local PB7 = 27
gpio.setup(PB7, function(msg) log.info("IQR", "PB7/27", msg) end)

function dump_table(nm, t, level)
    log.info("dump", nm)
    local count = 0
    for k, v in pairs(t) do
        log.info("dump", nm, k)
        count = count + 1
        if k ~= "_G" and type(v) == "table" then
            count = count + dump_table(tostring(k), v, level + 1)
        end
    end
    log.info("dump", nm, "count", count, "level", level)
    return count
end

function sys_memdump()
    dump_table("_G", _G, 0)
end

sys.taskInit(function()
    sys.waitUntil("WLAN_READY", 30000)
    while 1 do
        log.info("main", "socket loop")
        if wlan.ready() then
            collectgarbage("collect")
            collectgarbage("collect")
            local s = socket.tcp()
            -- inews.gtimg.com/newsapp_bt/0/11443709755/1000
            s:host("inews.gtimg.com")
            s:port(80)
            s:on("connect", function(id, re)
                log.info("netc", "connect result", re)
                if re then
                    s:send("GET /newsapp_bt/0/11443709755/1000 HTTP/1.0\r\nHost: inews.gtimg.com\r\n\r\n")
                end
            end)

            s:on("recv", function(id, re)
                print("recv", id, #re)
            end)
            --log.info("netc", "info", s)
            if s:start() == 0 then
                sys.waitUntil("NETC_END_" .. s:id(), 30000)
                --sys.wait(1000)
                log.info("netc", "GET NETC_END or timeout")
            else
                log.info("netc", "netc start fail!!")
            end
            s:clean()
            collectgarbage("collect")
            collectgarbage("collect")
            --sys_memdump()
            sys.wait(100)
        else
            log.info("wifi", "wifi NOT ready yet")
            sys.waitUntil("WLAN_READY", 30000)
        end
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
