PROJECT = "ch390h"
VERSION = "1.0.0"

sys = require("sys")
sysplus = require("sysplus")
sys.taskInit(function ()
    log.info("ch390", "打开LDO供电")
    gpio.setup(140, 1, gpio.PULLUP)     --打开ch390供电
    sys.wait(6000)
    local result = spi.setup(
        1,--spi id
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

    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {spi=1,cs=12})
    netdrv.dhcp(socket.LWIP_ETH, true)
end)

LEDA = gpio.setup(146, 0, gpio.PULLUP)

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
        -- method 是字符串, 例如 GET POST PUT DELETE
        -- uri 也是字符串 例如 / /api/abc
        -- headers table类型
        -- body 字符串
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
        -- 返回值的约定 code, headers, body
        -- 若没有返回值, 则默认 404, {} ,""
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

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!