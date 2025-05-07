
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air8000_wifi"
VERSION = "1.0.5"

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")

gpio.setup(140, 1, gpio.PULLUP)

-- 通过boot按键方便刷Air8000S
function PWR8000S(val)
    gpio.set(23, val)
end

gpio.debounce(0, 1000)
gpio.setup(0, function()
    sys.taskInit(function()
        log.info("复位Air8000S")
        PWR8000S(0)
        sys.wait(20)
        PWR8000S(1)
    end)
end, gpio.PULLDOWN)

function test_ap()
    log.info("执行AP创建操作")
    wlan.createAP("uiot5678", "12345678")
    netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "0.0.0.0")
    sys.wait(5000)
    dnsproxy.setup(socket.LWIP_AP, socket.LWIP_ETH)
    dhcpsrv.create({adapter=socket.LWIP_AP})
    while 1 do
        if netdrv.ready(socket.LWIP_ETH) then
            log.info("以太网作为网关")
            netdrv.napt(socket.LWIP_ETH)
            break
        end
        sys.wait(1000)
    end
    icmp.setup(socket.LWIP_ETH)
    while 1 do
        -- 持续ping网关
        local ip,mark,gw = netdrv.ipv4(socket.LWIP_ETH)
        if gw then
            log.info("ping", gw)
            icmp.ping(socket.LWIP_ETH, gw)
        end
        sys.wait(3000)
    end
end
function test_sta()
    log.info("执行STA连接操作")
    wlan.connect("Xiaomi 13", "15055190176")
    -- netdrv.dhcp(socket.LWIP_STA, true)
    sys.wait(8000)
    iperf.server(socket.LWIP_STA)
    -- iperf.client(socket.LWIP_STA, "47.94.236.172")
    dnsproxy.setup(socket.LWIP_ETH , socket.LWIP_STA)
    sys.wait(5000)
    while 1 do
        -- log.info("MAC地址", netdrv.mac(socket.LWIP_STA))
        -- log.info("IP地址", netdrv.ipv4(socket.LWIP_STA))
        -- log.info("ready?", netdrv.ready(socket.LWIP_STA))
        -- sys.wait(1000)
        -- log.info("执行http请求")
        -- local code = http.request("GET", "http://192.168.1.15:8000/README.md", nil, nil, {adapter=socket.LWIP_STA,timeout=3000}).wait()
        local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil, {adapter=socket.LWIP_STA,timeout=5000,debug=false}).wait()
        log.info("http执行结果", code, headers, body and #body)
        -- socket.sntp(nil, socket.LWIP_STA)
        sys.wait(2000)

        -- socket.sntp(nil)
        -- sys.wait(2000)
        -- log.info("执行ping操作")
        -- icmp.ping(socket.LWIP_STA, "183.2.172.177")
        -- sys.wait(2000)
    end
end
sys.subscribe("PING_RESULT", function(id, time, dst)
    log.info("ping.result", id, time, dst);
end)

-- wifi的AP相关事件
sys.subscribe("WLAN_AP_INC", function(evt, data)
    -- evt 可能的值有: "CONNECTED", "DISCONNECTED"
    -- 当evt=CONNECTED, data是连接的AP的新STA的MAC地址
    -- 当evt=DISCONNECTED, data是断开与AP连接的STA的MAC地址
    log.info("收到AP事件", evt, data and data:toHex())
end)

sys.subscribe("PING_RESULT", function(id, time, dst)
    log.info("ping", id, time, dst);
end)

--  每隔6秒打印一次airlink统计数据, 调试用
-- sys.taskInit(function()
--     while 1 do
--         sys.wait(6000)
--         airlink.statistics()
--     end
-- end)

function eth_lan()
    sys.wait(500)
    log.info("ch390", "打开LDO供电")
    gpio.setup(140, 1, gpio.PULLUP)     --打开ch390供电
    sys.wait(6000)
    local result = spi.setup(
        1,--spi_id
        nil,
        0,--CPHA
        0,--CPOL
        8,--数据宽度
        25600000--,--频率
        -- spi.MSB,--高低位顺序    可选，默认高位在前
        -- spi.master,--主模式     可选，默认主
        -- spi.full--全双工       可选，默认全双工
    )
    log.info("main", "open",result)
    if result ~= 0 then--返回值为0，表示打开成功
        log.info("main", "spi open error",result)
        return
    end

    -- 初始化指定netdrv设备,
    -- socket.LWIP_ETH 网络适配器编号
    -- netdrv.CH390外挂CH390
    -- SPI ID 1, 片选 GPIO12
    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {spi=1,cs=12})
    sys.wait(3000)
    local ipv4,mark, gw = netdrv.ipv4(socket.LWIP_ETH, "192.168.4.1", "255.255.255.0", "192.168.4.1")
    log.info("ipv4", ipv4,mark, gw)
    while netdrv.link(socket.LWIP_ETH) ~= true do
        sys.wait(100)
    end
    while netdrv.link(socket.LWIP_GP) ~= true do
        sys.wait(100)
    end
    sys.wait(2000)
    dhcps.create({adapter=socket.LWIP_ETH})
    dnsproxy.setup(socket.LWIP_ETH, socket.LWIP_GP)
    netdrv.napt(socket.LWIP_GP)
    if iperf then
        log.info("启动iperf服务器端")
        iperf.server(socket.LWIP_ETH)
    end
end

sys.taskInit(function()
    eth_lan()
    wlan.init()
    sys.wait(300)
    test_sta()
    while 1 do
        log.info("测试使用4G 给以太网和wifi 设备供应网络")
        sys.wait(1000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
