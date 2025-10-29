-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air8000_ap_ping"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")
require "sysplus"
dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")

function create_ap()
    log.info("执行AP创建操作", "luatos8888")
    wlan.createAP("luatos8888", "12345678")
    sys.wait(1000)
    netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "0.0.0.0")
    dnsproxy.setup(socket.LWIP_AP, socket.LWIP_GP)
    dhcpsrv.create({adapter=socket.LWIP_AP})
    while 1 do
        if netdrv.ready(socket.LWIP_GP) then
            netdrv.napt(socket.LWIP_GP)
            break
        end
        sys.wait(1000)
    end
end

function wifi_networking()
   sys.wait(3000)
    -- AP的ssid和password
    wlan.scan()
    -- sys.wait(500)
    httpsrv.start(80, function(fd, method, uri, headers, body)
        log.info("httpsrv", method, uri, json.encode(headers), body)
    end, socket.LWIP_AP)
end


sys.subscribe("IP_READY", function()
    -- 联网成功后, 模拟上报到服务器
    log.info("wlan", "已联网", "通知服务器")

end)

sys.subscribe("PING_RESULT", function(id, time, dst)
    log.info("ping", id, time, dst);
end)

sys.taskInit(function()

    -- sys.wait(100)
    wlan.init()
    sys.wait(100)

    -- 启动AP测试
    create_ap()
    wifi_networking()

    icmp.setup(socket.LWIP_AP)
    while 1 do
        log.info("开始ping STA")

        for i = 0, 10, 1 do
            local ip = "192.168.4." .. (i+100)
            log.info("STA客户端", ip)
            icmp.ping(socket.LWIP_AP, ip)
            sys.waitUntil("PING_RESULT", 3000)
        end
        sys.wait(1000)
    end

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!