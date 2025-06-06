
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air8000_wifi"
VERSION = "1.0.5"

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")


function test_ap()
    log.info("执行AP创建操作")
    wlan.createAP("uiot5678", "12345678")
    netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "0.0.0.0")
    sys.wait(5000)
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


-- wifi的AP相关事件
sys.subscribe("WLAN_AP_INC", function(evt, data)
    log.info("收到AP事件", evt, data and data:toHex())
end)

sys.subscribe("PING_RESULT", function(id, time, dst)
    log.info("ping", id, time, dst);
end)



sys.taskInit(function()
    log.info("新的Air8000脚本1...")
 
    wlan.init()

    test_ap()
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
