
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "airlink"
VERSION = "1.0.4"

-- Air724UG要用SPI1, CS选GPIO10, RDY选GPIO18

airlink.config(airlink.CONF_SPI_ID, 1) -- SPI1
airlink.config(airlink.CONF_SPI_CS, 10) -- GPIO10
airlink.config(airlink.CONF_SPI_RDY, 18) -- GPIO18
airlink.config(airlink.CONF_SPI_SPEED, 20*1000000) -- 20MHz速度

function test_ap()
    log.info("执行AP创建操作")
    wlan.createAP("uiot5678", "12345678")
    netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "0.0.0.0")
    sys.wait(5000)
    -- netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "0.0.0.0")
    -- log.info("创建dns代理", netdrv.ipv4(socket.LWIP_AP))
    dnsproxy.setup(socket.LWIP_AP, socket.LWIP_GP)
    -- log.info('创建DHCP服务器', netdrv.ipv4(socket.LWIP_AP))
    dhcpsrv.create({adapter=socket.LWIP_AP})
    while 1 do
        if netdrv.ready(socket.LWIP_GP) then
            netdrv.napt(socket.LWIP_GP)
            break
        end
        sys.wait(1000)
    end
end

-- wifi的STA相关事件
sys.subscribe("WLAN_STA_INC", function(evt, data)
    -- evt 可能的值有: "CONNECTED", "DISCONNECTED"
    -- 当evt=CONNECTED, data是连接的AP的ssid, 字符串类型
    -- 当evt=DISCONNECTED, data断开的原因, 整数类型
    log.info("收到STA事件", evt, data)
end)

-- wifi的AP相关事件
sys.subscribe("WLAN_AP_INC", function(evt, data)
    -- evt 可能的值有: "CONNECTED", "DISCONNECTED"
    -- 当evt=CONNECTED, data是连接的AP的新STA的MAC地址
    -- 当evt=DISCONNECTED, data是断开与AP连接的STA的MAC地址
    log.info("收到AP事件", evt, data and data:toHex())
end)

function test_sta()
    log.info("执行STA连接操作")
    -- netdrv.debug(0, true)
    wlan.connect("luatos1234", "12341234")
    -- airlink.debug(1)
    -- netdrv.dhcp(socket.LWIP_STA, true)
    while 1 do
        if wlan.ready() then
            break
        end
        sys.wait(100)
    end
    -- sys.wait(8000)
    -- iperf.server(socket.LWIP_STA)
    -- iperf.client(socket.LWIP_STA, "47.94.236.172")

    -- sys.wait(5000)
    while 1 do
        log.info("wlan", "info", json.encode(wlan.getInfo()))
        -- log.info("MAC地址", netdrv.mac(socket.LWIP_STA))
        -- log.info("IP地址", netdrv.ipv4(socket.LWIP_STA))
        -- log.info("ready?", netdrv.ready(socket.LWIP_STA))
        -- sys.wait(1000)
        -- log.info("执行http请求")
        -- local code = http.request("GET", "http://192.168.1.15:8000/README.md", nil, nil, {adapter=socket.LWIP_STA,timeout=3000}).wait()
        local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil, {adapter=socket.LWIP_STA,timeout=5000,debug=false}).wait()
        -- local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil).wait()
        log.info("http执行结果", code, headers, body and #body)
        -- socket.sntp(nil, socket.LWIP_STA)
        -- sys.wait(12000)

        -- socket.sntp(nil)
        -- sys.wait(2000)
        -- log.info("执行ping操作")
        -- icmp.ping(socket.LWIP_STA, "183.2.172.177")
        -- sys.wait(2000)
        local re_ip = httpdns.ali("air32.cn", {adapter=socket.LWIP_STA, timeout=3000})
        log.info("httpdns", re_ip)
        sys.wait(3000)
        -- pm.request(pm.LIGHT, 1)
    end
end

sys.subscribe("PING_RESULT", function(id, time, dst)
    log.info("ping", id, time, dst);
end)

function test_scan()
    while 1 do
        log.info("执行wifi扫描")
        wlan.scan()
        sys.wait(30 * 1000)
    end
end
sys.subscribe("WLAN_SCAN_DONE", function ()
    local results = wlan.scanResult()
    log.info("scan", "results", #results)
    for k,v in pairs(results) do
        log.info("scan", v["ssid"], v["rssi"], (v["bssid"]:toHex()))
    end
end)

--  每隔6秒打印一次airlink统计数据, 调试用
-- sys.taskInit(function()
--     while 1 do
--         sys.wait(6000)
--         airlink.statistics()
--     end
-- end)

sys.taskInit(function()
    log.info("新的Air7000脚本...")
    -- log.info("5秒后开始测试")
    -- sys.wait(5000)
    airlink.init()
    airlink.start(1)
    
    sys.wait(200) -- 稍微缓一下, Air8000S的启动大概需要300ms

    -- 等待初始化完成
    while not airlink.ready() do
        log.info("等待Airlink初始化完成")
        sys.wait(1000)
    end

    -- 启动AP测试
    netdrv.setup(socket.LWIP_STA, netdrv.WHALE)
    netdrv.setup(socket.LWIP_AP, netdrv.WHALE)
    wlan.init()
    -- sys.wait(5000)
    
    -- sys.wait(300)
    -- test_ap()

    -- 连接STA测试
    test_sta()

    -- wifi扫描测试
    -- sys.wait(2000)
    -- test_scan()
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
