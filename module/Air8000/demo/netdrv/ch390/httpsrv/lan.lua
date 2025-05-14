dhcps = require "dhcpsrv"
dnsproxy = require "dnsproxy"

local LEDA = gpio.setup(146, 0, gpio.PULLUP)
sys.taskInit(function()
    sys.wait(500)
    log.info("ch390", "打开LDO供电")
    gpio.setup(140, 1, gpio.PULLUP) -- 打开ch390供电
    sys.wait(6000)
    local result = spi.setup(1, -- spi_id
    nil, 0, -- CPHA
    0, -- CPOL
    8, -- 数据宽度
    25600000 -- ,--频率
    -- spi.MSB,--高低位顺序    可选，默认高位在前
    -- spi.master,--主模式     可选，默认主
    -- spi.full--全双工       可选，默认全双工
    )
    log.info("main", "open", result)
    if result ~= 0 then -- 返回值为0，表示打开成功
        log.info("main", "spi open error", result)
        return
    end

    -- 初始化指定netdrv设备,
    -- socket.LWIP_ETH 网络适配器编号
    -- netdrv.CH390外挂CH390
    -- SPI ID 1, 片选 GPIO12
    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {
        spi = 1,
        cs = 12
    })
    sys.wait(3000)
    local ipv4, mark, gw = netdrv.ipv4(socket.LWIP_ETH, "192.168.4.1", "255.255.255.0", "192.168.4.1")
    log.info("ipv4", ipv4, mark, gw)
    while netdrv.link(socket.LWIP_ETH) ~= true do
        sys.wait(100)
    end
    while netdrv.link(socket.LWIP_GP) ~= true do
        sys.wait(100)
    end
    sys.wait(2000)
    dhcps.create({
        adapter = socket.LWIP_ETH
    })
    dnsproxy.setup(socket.LWIP_ETH, socket.LWIP_GP)
    netdrv.napt(socket.LWIP_GP)
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
    if iperf then
        log.info("启动iperf服务器端")
        iperf.server(socket.LWIP_ETH)
    end
end)

sys.taskInit(function()
    while 1 do
        sys.wait(300000)
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
    end
end)
