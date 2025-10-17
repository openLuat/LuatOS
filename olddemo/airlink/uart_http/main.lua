
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "airlink_uart_http"
VERSION = "1.0.1"

dnsproxy = require("dnsproxy")

-----------------------------------
-- 配置区域
-----------------------------------
is_gw = false -- 是否是网关模式, 要插卡, 要能联网
uart_id = 1   -- 按实际接到UART的ID来设置, 1或2
airlink.config(airlink.CONF_UART_ID, uart_id) -- 设置airlink使用的UART ID
uart.setup(uart_id, 115200) -- 初始化UART1, 波特率115200, 8N1
-- 注意, uart波特率的设置值,取决于两个设备的都支持的最高波特率, 例如2M也是可以的, 但要确保两个设备都支持2M波特率
-------------------------------------


sys.taskInit(function()
    sys.wait(500)
    log.info("airlink", "Starting airlink with UART task")
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
    -- netdrv.debug(0, true)

end)

sys.taskInit(function()
    sys.wait(1000)
    while 1 do
        -- 发送给对端设备
        local data = rtos.bsp() .. " " .. os.date() .. " " .. (mobile and mobile.imei() or "")
        log.info("client 发送数据给sever设备", data, "当前airlink状态", airlink.ready())
        airlink.sdata(data)
        -- airlink.test(1000) -- 要测试高速连续发送的情况
        sys.wait(1000)
    end
end)

sys.taskInit(function()
    -- sys.waitUntil("IP_READY")
    sys.wait(3000)
    if is_gw then
        log.info("airlink", "Gateway mode")
        -- while netdrv.ready(socket.LWIP_USER0) == false do
        while netdrv.ready(socket.LWIP_GP) == false do
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
