
--[[
1.本demo可直接在Air8000整机开发板上运行，如有需要请luat.taobao.com 购买
2.演示如何使用以太网wan 功能，通过4G 转 以太网，给以太网终端设备上网
3.使用了如下的IO口
[41, "SPI1_CS", " PIN41脚, 用于控制SPI1 设备的以太网片选"],
[56, "GPIO140", " PIN56脚, 用于控制以太网使能"],
[40, "SPI1_MOSI", " PIN40脚, SPI1_MOSI"],
[39, "SPI1_MISO", " PIN39脚, SPI1_MISO"],
[38, "SPI_CLK", " PIN38脚, SPI 时钟"],
[24, "GPIO21", " PIN24脚, 以太网中断脚"],
4.程序运行逻辑为，4G 和 CH390 的IP 准备就绪，可以给下游的以太网设备提供网页服务
]]

local task_name = "ethernat_wan"
local ethernat_spi_id =  1   -- Air8000，air8000W 仅支持SPI1
local ethernat_spi_Frequency = 25600000
local ethernat_power = 140
local result = 0

local function setup_ethernat()
    gpio.setup(ethernat_power, 1) -- 打开以太网供电
    result = spi.setup(ethernat_spi_id, -- 串口id
    nil, 0, -- CPHA
    0, -- CPOL
    8, -- 数据宽度
    ethernat_spi_Frequency -- ,--频率
    -- spi.MSB,--高低位顺序    可选，默认高位在前
    -- spi.master,--主模式     可选，默认主
    -- spi.full--全双工       可选，默认全双工
    )
    log.info("main", "open", result)
    if result ~= 0 then -- 返回值为0，表示打开成功
        log.info("main", "spi open error", result)
    else
        return result 
    end
end

local function start_ch390()
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

end


local function ethernat_wan_task()
    sys.wait(3000)
    if setup_ethernat() ~= 0 then    -- 初始化以太网SPI
        return
    else
        start_ch390()                -- 初始化ch390
    end 
    sys.waitUntil("CH390_IP_READY")
    log.info("CH390 联网成功，开始测试")
    socket.dft(socket.LWIP_ETH)
    -- 如果自带的DNS不好用，可以用下面的公用DNS,但是一定是要在CH390联网成功后使用
    -- socket.setDNS(socket.LWIP_ETH,1,"223.5.5.5")	
    -- socket.setDNS(nil,1,"114.114.114.114")


    -- 这是个测试服务, 当发送的是json,且action=echo,就会回显所发送的内容
    -- wsc = websocket.create(nil, "ws://echo.airtun.air32.cn/ws/echo")
    -- 这是另外一个回环测试服务, 能响应websocket的二进制帧
    wsc = websocket.create(nil, "ws://airtest.openluat.com:2900/websocket")
    -- 以上两个测试服务是Java写的, 源码在 https://gitee.com/openLuat/luatos-airtun/tree/master/server/src/main/java/com/luatos/airtun/ws

    if wsc.headers then
        wsc:headers({Auth="Basic ABCDEGG"})
    end
    wsc:autoreconn(true, 3000) -- 自动重连机制
    wsc:on(function(wsc, event, data, fin, optcode)
        -- event 事件, 当前有conack和recv
        -- data 当事件为recv是有接收到的数据
        -- fin 是否为最后一个数据包, 0代表还有数据, 1代表是最后一个数据包
        -- optcode, 0 - 中间数据包, 1 - 文本数据包, 2 - 二进制数据包
        -- 因为lua并不区分文本和二进制数据, 所以optcode通常可以无视
        -- 若数据不多, 小于1400字节, 那么fid通常也是1, 同样可以忽略
        log.info("wsc", event, data, fin, optcode)
        -- 显示二进制数据
        -- log.info("wsc", event, data and data:toHex() or "", fin, optcode)
        if event == "conack" then -- 连接websocket服务后, 会有这个事件
            wsc:send((json.encode({action="echo", device_id=device_id})))
            sys.publish("wsc_conack")
        end
    end)
    wsc:connect()
    -- 等待conack是可选的
    --sys.waitUntil("wsc_conack", 15000)
    -- 定期发业务ping也是可选的, 但为了保存连接, 也为了继续持有wsc对象, 这里周期性发数据
    while true do
        sys.wait(15000)
        -- 发送文本帧
        wsc:send("{\"room\":\"topic:okfd7qcob2iujp1br83nn7lcg5\",\"action\":\"join\"}")
        sys.wait(2000)
        wsc:send((json.encode({action="echo", msg=os.date()})))
        sys.wait(2000)
        -- 发送二进制帧, 2023.06.21 之后编译的固件支持
        wsc:send(string.char(0xA5, 0x5A, 0xAA, 0xF2), 1, 1)
    end
    wsc:close()
    wsc = nil
end


sysplus.taskInitEx(ethernat_wan_task,task_name)  

