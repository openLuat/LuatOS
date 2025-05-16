
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air8000_wifi"
VERSION = "1.0.5"

--[[
本demo演示的功能是:
1. 创建AP, 提供wifi设备, 通过4G上网
2. 创建以太网, 为局域网内的设备, 通过4G上网
]]

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
    log.info("执行AP创建操作", airlink.ready() , "正常吗?")
    wlan.createAP("uiot5678", "12345678")
    netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "0.0.0.0")
    log.info("netdrv", "等待AP就绪")
    while netdrv.ready(socket.LWIP_AP) ~= true do
        sys.wait(100)
    end
    log.info("netdrv", "创建dhcp服务器, 供AP使用")
    dhcpsrv.create({adapter=socket.LWIP_AP})
    log.info("netdrv", "等待4G就绪")
    while netdrv.ready(socket.LWIP_GP) ~= true do
        sys.wait(100)
    end
    log.info("netdrv", "创建dns代理服务, 供AP使用")
    dnsproxy.setup(socket.LWIP_AP, socket.LWIP_GP)
    while 1 do
        if netdrv.ready(socket.LWIP_GP) then
            log.info("netdrv", "4G作为网关")
            netdrv.napt(socket.LWIP_GP)
            break
        end
        sys.wait(1000)
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
    -- sys.wait(3000)
    local result = spi.setup(
        1,--spi id
        nil,
        0,--CPHA
        0,--CPOL
        8,--数据宽度
        51200000--,--波特率
    )
    log.info("main", "open spi",result)
    if result ~= 0 then--返回值为0，表示打开成功
        log.info("main", "spi open error",result)
        return
    end
    log.info("netdrv", "初始化以太网")
    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {spi=1,cs=12,irq=255})
    log.info("netdrv", "等待以太网就绪")
    sys.wait(1000)
    netdrv.ipv4(socket.LWIP_ETH, "192.168.5.1", "255.255.255.0", "0.0.0.0")
    while netdrv.ready(socket.LWIP_ETH) ~= true do
        -- log.info("netdrv", "等待以太网就绪")
        sys.wait(100)
    end
    log.info("netdrv", "以太网就绪")
    log.info("netdrv", "创建dhcp服务器, 供以太网使用")
    dhcpsrv.create({adapter=socket.LWIP_ETH, gw={192,168,5,1}})
    log.info("netdrv", "创建dns代理服务, 供以太网使用")
    dnsproxy.setup(socket.LWIP_ETH, socket.LWIP_GP)
end

sys.taskInit(function()
    while airlink.ready() ~= true do
        sys.wait(100)
    end
    eth_lan()
    wlan.init()
    sys.wait(300)
    test_ap()
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
