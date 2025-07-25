
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "airlink_uart"
VERSION = "1.0.1"

is_gw = false -- 是否是网关模式

sys.taskInit(function()
    log.info("airlink", "Starting airlink with UART task")
    -- 首先, 初始化uart1, 115200波特率 8N1
    uart.setup(1, 115200)
    -- 初始化airlink
    airlink.init()
    -- 注册网卡
    netdrv.setup(socket.LWIP_USER0, netdrv.WHALE)
    -- 启动airlink uart任务
    airlink.start(2)

    -- 网关模式下, ip设置为.1, 对端设置为.2
    if is_gw then
        netdrv.ipv4(socket.LWIP_USER0, "192.168.111.1", "255.255.255.0", "192.168.111.2")
    else
        netdrv.ipv4(socket.LWIP_USER0, "192.168.111.2", "255.255.255.0", "192.168.111.1")
    end
end)

sys.taskInit(function()
    -- sys.waitUntil("IP_READY")
    sys.wait(3000)
    if is_gw then
        log.info("airlink", "Gateway mode")
        while netdrv.ready(socket.LWIP_USER0) == false do
            sys.wait(100)
        end
        netdrv.napt(socket.LWIP_GP)
        return
    else
        log.info("airlink", "Client mode")
    end
    while 1 do
        sys.wait(500)
        local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil, {adapter=socket.LWIP_USER0,timeout=3000}).wait()
        log.info("http", code, body and #body)
        -- log.info("lua", rtos.meminfo())
        -- log.info("sys", rtos.meminfo("sys"))
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
