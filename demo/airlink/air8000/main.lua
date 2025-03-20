
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "netdrv"
VERSION = "1.0.5"


-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用http库需要下列语句]]
_G.sysplus = require("sysplus")
dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")

gpio.setup(0, function()
    sys.publish("WIFI_RESET")
end, gpio.PULLDOWN, gpio.RISING)
gpio.debounce(0, 100)

gpio.setup(23, 0, gpio.PULLUP) -- 关闭Air8000S的LDO供电

sys.taskInit(function()
    sys.wait(100)
    while 1 do
        sys.waitUntil("WIFI_RESET")
        log.info("复位WIFI部分")
        gpio.set(23, 0)
        sys.wait(100)
        gpio.setup(23, 1)
    end
end)

sys.taskInit(function()
    -- 设置电平, 关闭小核的供电
    pm.ioVol(pm.IOVOL_ALL_GPIO, 3300)
    sys.wait(100)
    -- 初始化airlink
    airlink.init()
    log.info("注册STA和AP设备")
    netdrv.setup(socket.LWIP_STA, netdrv.WHALE)
    netdrv.setup(socket.LWIP_AP, netdrv.WHALE)
    -- 启动底层线程, 从机模式
    airlink.start(1)
    sys.wait(100)
    log.info("打开Air8000S的LDO供电")
    gpio.setup(23, 1) -- 打开Air8000S的LDO供电
    log.info("一切就绪了")
    sys.wait(5000)

    netdrv.ipv4(socket.LWIP_STA, "192.168.1.35", "255.255.255.0", "192.168.1.1")
    sys.wait(1000)
    -- while 1 do
    --     -- log.info("MAC地址", netdrv.mac(socket.LWIP_STA))
    --     -- log.info("IP地址", netdrv.ipv4(socket.LWIP_STA))
    --     -- log.info("ready?", netdrv.ready(socket.LWIP_STA))
    --     sys.wait(1000)
    --     log.info("执行http请求")
    --     -- local code = http.request("GET", "http://192.168.1.15:8000/README.md", nil, nil, {adapter=socket.LWIP_STA,timeout=3000}).wait()
    --     local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil, {adapter=socket.LWIP_STA,timeout=3000}).wait()
    --     log.info("http执行结果", code, code, headers, body)
    -- end
end)

sys.subscribe("IP_READY", function(ip, id)
    log.info("收到IP_READY!!", ip, id)
end)

sys.subscribe("IP_LOSE", function(id)
    log.info("收到IP_LOSE!!", id)
end)

sys.taskInit(function()
    while netdrv.ready(socket.LWIP_AP) == false do
        sys.wait(100)
    end
    sys.wait(100)
    netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "0.0.0.0")
    sys.wait(100)
    dnsproxy.setup(socket.LWIP_GP, socket.LWIP_AP)
    dhcpsrv.create({adapter=socket.LWIP_AP})
    while 1 do
        if netdrv.ready(socket.LWIP_GP) then
            netdrv.napt(socket.LWIP_GP)
            break
        end
        sys.wait(1000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
