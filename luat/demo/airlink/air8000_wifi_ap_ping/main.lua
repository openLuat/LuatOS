-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "WIFI_AP"
VERSION = "1.0.0"
--[[
本demo演示AP的配网实例
1. 启动后, 会创建一个 luatos_ + mac地址的热点
2. 热点密码是 12345678
3. 热点网关是 192.168.4.1, 同时也是配网网页的ip
4. http://192.168.4.1
]]

-- sys库是标配
_G.sys = require("sys")
require "sysplus"
dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")

function create_ap()
    log.info("执行AP创建操作", "luatos8888")
    wlan.createAP("luatos8888", "12345678")
    sys.wait(1000)
    netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "0.0.0.0")
    dnsproxy.setup(socket.LWIP_AP, socket.LWIP_GP)
    apdhcpd = dhcpsrv.create({adapter=socket.LWIP_AP})
    while 1 do
        if netdrv.ready(socket.LWIP_GP) then
            netdrv.napt(socket.LWIP_GP)
            break
        end
        sys.wait(1000)
    end

    icmp.setup(socket.LWIP_AP)
    while 1 do
        log.info("开始ping STA")
        -- for k, v in pairs(apdhcpd.clients) do
        --     local ip = "192.168.4." .. k
        --     log.info("STA客户端", ip, v.mac and v.mac:toHex())
        --     icmp.ping(socket.LWIP_AP, ip)
        --     sys.waitUntil("PING_RESULT", 3000)
        --     -- sys.wait(2000)
        -- end
        for i = 1, 10, 1 do
            local ip = "192.168.4." .. (i+100)
            log.info("STA客户端", ip)
            icmp.ping(socket.LWIP_AP, ip)
            sys.waitUntil("PING_RESULT", 3000)
            -- sys.wait(2000)
        end
        sys.wait(1000)
    end
end

sys.subscribe("PING_RESULT", function(id, time, dst)
    log.info("ping", id, time, dst);
end)

sys.taskInit(function()

    -- sys.wait(100)
    wlan.init()
    sys.wait(100)

    -- 启动AP测试
    create_ap()
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!