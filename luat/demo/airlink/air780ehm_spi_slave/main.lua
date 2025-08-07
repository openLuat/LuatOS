

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "airlink_spi_slave"
VERSION = "1.0.0"


-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用http库需要下列语句]]
_G.sysplus = require("sysplus")
dnsproxy = require ("dnsproxy")

local rtos_bsp = rtos.bsp()

local mode = "slave"

-- 订阅airlink的SDATA事件，打印收到的信息。
local function airlink_sdata(data)
    -- 打印收到的信息。
    log.info("收到AIRLINK_SDATA!!", data)
end

local function airlink_sdata_MOBILE()
    sys.waitUntil("IP_READY")
    -- 设置网络时间同步。
    socket.sntp()
    while 1 do
        -- rtos.bsp()：设备硬件bsp型号；os.date()：本地时间。
        local data = rtos_bsp .. " " .. os.date()
        log.info("发送数据给对端设备", data, "当前airlink状态", airlink.ready())
        airlink.sdata(data)
        sys.wait(200)
    end
end

-- 订阅airlink的SDATA事件，打印收到的信息。
sys.subscribe("AIRLINK_SDATA", airlink_sdata)

sys.subscribe("IP_READY", function(id, ip)
    log.info("收到IP_READY!!", id, ip)
end)

local function spi_slave_task()
    sys.wait(100)

    -- 初始化airlink
    airlink.init()
    -- 注册网卡
    netdrv.setup(socket.LWIP_USER0, netdrv.WHALE)
    sys.wait(100)
    -- 启动airlink从机模式
    airlink.start(0)

    -- 配置网关ip
    netdrv.ipv4(socket.LWIP_USER0, "192.168.111.1", "255.255.255.0", "192.168.111.2")
    -- sys.waitUntil("IP_READY")

    while 1 do
        sys.wait(1000)
        log.info("ticks", mcu.ticks(), hmeta.chip(), hmeta.model(), hmeta.hwver())
        airlink.statistics()
        log.info("执行http请求")
        local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil, {adapter=socket.LWIP_USER0,timeout=3000}).wait()
        log.info("http执行结果", code, code, headers, body)
    end
end

local function spi_master_task()
    sys.wait(100)
    -- 初始化airlink
    airlink.init()
    log.info("创建桥接网络设备")
    netdrv.setup(socket.LWIP_USER0, netdrv.WHALE)
    -- 启动底层线程, 主机模式
    airlink.start(1)

    netdrv.ipv4(socket.LWIP_USER0, "192.168.111.2", "255.255.255.0", "192.168.111.1")
    sys.wait(100)
    sys.waitUntil("IP_READY", 10000)
    netdrv.napt(socket.LWIP_GP)
    -- 设置DNS代理。
    dnsproxy.setup(socket.LWIP_USER0, socket.LWIP_GP)
    -- airlink.test(1000)
    while 1 do
        sys.wait(1000)
        log.info("ticks", mcu.ticks(), hmeta.chip(), hmeta.model(), hmeta.hwver())
        airlink.statistics()
        -- log.info("执行http请求")
        -- local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil, {adapter=socket.LWIP_GP,timeout=3000}).wait()
        -- log.info("http执行结果", code, code, headers, body)
    end
end

sys.taskInit(function()
    sys.wait(2000)
    log.info("main", rtos_bsp)
    -- 测试使用Air780EHM模块作为从机延时，如果使用其他模块测试，修改下面的代码。
    if string.find(rtos_bsp, "780EHM") then
        mode = "slave"
    else
        mode = "master"
    end

    if mode == "slave" then
        spi_slave_task()
    elseif mode == "master" then
        spi_master_task()
    else
        log.info("airlink_spi", "未知的通讯模式：", mode)
    end
end)

-- sys.taskInit(airlink_sdata_MOBILE)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
