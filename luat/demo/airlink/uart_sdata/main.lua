
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "airlink_uart"
VERSION = "1.0.1"

dnsproxy = require("dnsproxy")

is_gw = true

sys.taskInit(function()
    sys.wait(500)
    log.info("airlink", "Starting airlink with UART task")
    -- 首先, 初始化uart1, 115200波特率 8N1
    uart.setup(1, 115200)
    -- 初始化airlink
    airlink.init()
    netdrv.setup(socket.LWIP_USER0, netdrv.WHALE) -- 初始化netdrv
    -- 启动airlink uart任务
    airlink.start(2)
    if is_gw then
        netdrv.ipv4(socket.LWIP_USER0, "192.168.111.1", "255.255.255.0", "192.168.111.2")
    else
        netdrv.ipv4(socket.LWIP_USER0, "192.168.111.2", "255.255.255.0", "192.168.111.1")
    end
    sys.wait(100)
    --等待IP_READY事件
    sys.waitUntil("IP_READY", 1000)
    -- netdrv.napt(socket.LWIP_GP)
    -- netdrv.debug(0, true)
    -- dnsproxy.setup(socket.LWIP_USER0,socket.LWIP_GP)
    -- while 1 do
    --     -- 发送给对端设备
    --     local data = rtos.bsp() .. " " .. os.date() .. " " .. (mobile and mobile.imei() or "")
    --     log.info("sever 发送数据给client设备", data, "当前airlink状态", airlink.ready())
    --     airlink.sdata(data)
    --     airlink.test(1000) -- 要测试高速连续发送的情况
    --     sys.wait(1000)
    -- end
end)

sys.taskInit(function()
    -- sys.waitUntil("IP_READY")
    sys.wait(3000)
    if is_gw then
        log.info("airlink", "Gateway mode")
        while netdrv.ready(socket.LWIP_GP) == false do
            sys.wait(100)
            log.info("airlink", "Waiting for netdrv_READY")
        end
        log.info("airlink", "netdrv_READY")
        netdrv.napt(socket.LWIP_GP)
        dnsproxy.setup(socket.LWIP_USER0,socket.LWIP_GP)
        return
    else
        log.info("airlink", "Client mode")
    end
    -- while 1 do
    --     sys.wait(500)
    --     local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil, {adapter=socket.LWIP_USER0,timeout=3000}).wait()
    --     log.info("http", code, body and #body)
    --     -- log.info("lua", rtos.meminfo())
    --     -- log.info("sys", rtos.meminfo("sys"))
    -- end
end)

--订阅IP_READY事件，打印收到的信息
sys.subscribe("IP_READY", function(id,ip)
    log.info("收到IP_READY!!", id,ip)
end)

sys.subscribe("AIRLINK_SDATA", function(data)
    log.info("sever 收到AIRLINK_SDATA!!", data)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
