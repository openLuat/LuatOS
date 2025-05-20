
-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
sysplus = require("sysplus")

sys.taskInit(function ()
    -- sys.wait(3000)
    local result = spi.setup(
        0,--spi id
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

    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {spi=0,cs=8})
    netdrv.dhcp(socket.LWIP_ETH, true)
end)

LEDA = gpio.setup(27, 0, gpio.PULLUP)

sys.taskInit(function()
    -- 等以太网就绪
    while 1 do
        local result, ip, adapter = sys.waitUntil("IP_READY", 3000)
        log.info("ready?", result, ip, adapter)
        if adapter and adapter ==  socket.LWIP_ETH then
            break
        end
    end
    
    sys.wait(200)
    httpsrv.start(80, function(client, method, uri, headers, body)
        log.info("httpsrv", method, uri, json.encode(headers), body)
        -- meminfo()
        if uri == "/led/1" then
            LEDA(1)
            return 200, {}, "ok"
        elseif uri == "/led/0" then
            LEDA(0)
            return 200, {}, "ok"
        end
        return 404, {}, "Not Found" .. uri
    end, socket.LWIP_ETH)
    iperf.server(socket.LWIP_ETH)
    while 1 do
        sys.wait(6000)
        local code, headers, body = http.request("GET", "http://httpbin.air32.cn/bytes/4096", nil, nil, {adapter=socket.LWIP_ETH}).wait()
        log.info("http", code, headers, body and #body)
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
    end
end)
