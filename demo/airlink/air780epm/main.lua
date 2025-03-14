
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "netdrv"
VERSION = "1.0.4"


-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用mqtt库需要下列语句]]
_G.sysplus = require("sysplus")

sys.taskInit(function()
    -- 设置电平, 关闭小核的供电
    pm.ioVol(pm.IOVOL_ALL_GPIO, 3300)
    gpio.setup(23, 0) -- 关闭Air8000S的LDO供电
    sys.wait(100)
    -- 初始化airlink
    airlink.init()
    log.info("注册STA和AP设备")
    netdrv.setup(socket.LWIP_STA)
    netdrv.setup(socket.LWIP_AP)
    -- 启动底层线程, 从机模式
    airlink.start(1)
    sys.wait(100)
    log.info("打开Air8000S的LDO供电")
    gpio.setup(23, 1) -- 打开Air8000S的LDO供电
    log.info("一切就绪了")
    sys.wait(5000)

    netdrv.ipv4(socket.LWIP_STA, "192.168.1.35", "255.255.255.0", "192.168.1.1")

    while 1 do
        -- log.info("MAC地址", netdrv.mac(socket.LWIP_STA))
        -- log.info("IP地址", netdrv.ipv4(socket.LWIP_STA))
        -- log.info("ready?", netdrv.ready(socket.LWIP_STA))
        sys.wait(5000)
        log.info("执行http请求")
        local code = http.request("GET", "http://192.168.1.15:8000/README.md", nil, nil, {adapter=socket.LWIP_STA,timeout=3000}).wait()
        -- local code = http.request("GET", "http://112.125.89.8:42376/get", nil, nil, {adapter=socket.LWIP_STA,timeout=3000}).wait()
        log.info("http执行结果", code, "=============================================")
    end
end)

sys.subscribe("IP_READY", function(id, ip)
    log.info("收到IP_READY!!", id, ip)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
