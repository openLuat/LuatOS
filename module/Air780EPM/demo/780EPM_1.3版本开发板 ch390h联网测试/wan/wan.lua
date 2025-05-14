-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
sysplus = require("sysplus")

sys.taskInit(function()
    sys.wait(3000)
    local result = spi.setup(0, -- 串口id
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

    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {
        spiid = 0,
        cs = 8
    })
    netdrv.dhcp(socket.LWIP_ETH, true)
    -- sys.wait(3000)
    while 1 do
        local ipv4ip, aaa, bbb = netdrv.ipv4(socket.LWIP_ETH, "", "", "")
        log.info("ipv4地址,掩码,网关为", ipv4ip, aaa, bbb)
        local netdrv_start = netdrv.ready(socket.LWIP_ETH)
        if netdrv_start and ipv4ip and ipv4ip ~= "0.0.0.0" then
            log.info("条件都满足")
            sys.publish("CH390_IP_READY")
            return
        end
        sys.wait(1000)
    end

end)

-- sys.taskInit(function()
--     sys.waitUntil("CH390_IP_READY")
--     log.info("CH390 联网成功，开始测试")

--     -- 如果自带的DNS不好用，可以用下面的公用DNS,但是一定是要在CH390联网成功后使用
-- -- socket.setDNS(socket.LWIP_ETH,1,"223.5.5.5")	
-- -- socket.setDNS(nil,1,"114.114.114.114")

--     while 1 do
--         sys.wait(6000)
--         log.info("http", http.request("GET", "https://wiki.luatos.com/api/index.html", nil, nil, {
--             adapter = socket.LWIP_ETH
--         }).wait())
--         log.info("lua", rtos.meminfo())
--         log.info("sys", rtos.meminfo("sys"))
--     end
-- end)
