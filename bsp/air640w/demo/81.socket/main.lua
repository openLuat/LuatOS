--[[
demo说明:
wifi信息: 修改 wlan.connect
服务器信息, 修改 s:host s:port
可访问 http://tcplab.openluat.com 获取一个临时的tcp端口, 只适合测试ASCII字符
]]
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "socket2demo"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
local sys = require "sys"

log.info("main", "socket demo, tcp long connect")

log.info("mac", wlan.get_mac())
wlan.connect("uiot", "12345678") -- wifi信息在这里, 如果想用airkiss, 看app/playit/main.lua

sys.subscribe("WLAN_READY", function ()
    print("!!! wlan ready event !!! send ntp")
    socket.ntpSync()
end)

local PB7 = 27
gpio.setup(PB7, function(msg) log.info("IQR", "PB7/27", msg) end)

sys.taskInit(function()
    -- 等待联网成功
    sys.waitUntil("WLAN_READY", 30000)
    while 1 do
        log.info("main", "socket loop")
        if wlan.ready() then
            collectgarbage("collect")
            collectgarbage("collect")
            local s = socket.tcp()
            -- inews.gtimg.com/newsapp_bt/0/11443709755/1000
            s:host("tcplab.openluat.com") -- 改成服务器ip或者域名
            s:port(52501) -- 改成服务器端口
            s:on("connect", function(id, re)
                -- 连接成功后, 发注册包 {mac:"AABBCCDDEEFF"}
                log.info("netc", "connect result", re)
                if re then
                    local jdata = json.encode({mac=wlan.get_mac()})
                    s:send(jdata)
                end
            end)

            s:on("recv", function(id, re)
                print("recv", id, #re, re)
                if re then
                    -- 如果有数据就回显, 简单环路测试
                    s:send(re)
                end
            end)
            --log.info("netc", "info", s)
            -- 启动tcp独立线程(系统级的)
            if s:start() == 0 then
                -- 启动成功后, 连接中断时必然有NETC_END_XX事件
                -- 因为是长连接, 就这样等着就差不多了
                while s:closed() == 0 do
                    sys.waitUntil("NETC_END_" .. s:id(), 3000)
                    -- 定时发个心跳什么的
                    log.info("netc", "heartbeat ping")
                    s:send("ping")
                end
            else
                log.info("netc", "netc start fail!!")
            end
            -- 一定要清理好, 不然内存泄漏, 模块内存少啊!!!
            s:clean()
            collectgarbage("collect")
            collectgarbage("collect")
            --sys_memdump()
            sys.wait(2000) -- 没连上, 或者断开了? 等2秒重试
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
