--[[
@module  lan
@summary lan功能测试模块
@version 1.0
@date    2025.07.01
@author  Jensen
@usage
使用Air780EGH核心板，插上sim卡，将4G网络转以太网功能，
通过网线将以太网模块CH390H与电脑以太网口连接，电脑可以4G网络访问互联网
]]

-- 加载dhcp server模块，用于动态ip地址分配
dhcps = require "dhcpsrv"
-- 加载dns模块，用于域名解析
dnsproxy = require "dnsproxy"

-- 网络配置，netdrv模块启动ch390h以太网模块和4g网络
function network_setup()
    -- 配置以太网模块ch390h的spi接口参数，使用SPI0
    -- sys.wait(3000)
    local result = spi.setup(
        0,--串口id
        nil,
        0,--CPHA
        0,--CPOL
        8,--数据宽度
        38400000--,--频率, 这里注意若通过杜邦线连接CH390H与核心板需调整总线速率，过大的速率会造成通信失败
        -- spi.MSB,--高低位顺序    可选，默认高位在前
        -- spi.master,--主模式     可选，默认主
        -- spi.full--全双工       可选，默认全双工
    )
    log.info("main", "open",result)
    if result ~= 0 then--返回值为0，表示打开成功
        log.info("main", "spi open error",result)
        return
    end
    -- 配置以太网网络,使用SPI0, CS为GPIO08
    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {spi=0,cs=8})
    sys.wait(3000)
    -- 配置以太网网络参数，包括静态IP，子网掩码，网关IP，
    -- 本测试需要将4G网络转以太网络相当于自身作为路由器，网关IP地址为自身静态IP地址
    local ipv4,mark, gw = netdrv.ipv4(socket.LWIP_ETH, "192.168.4.1", "255.255.255.0", "192.168.4.1")
    log.info("ipv4", ipv4,mark, gw)
    -- 等待以太网网口连接
    while netdrv.link(socket.LWIP_ETH) ~= true do
        sys.wait(100)
    end
    
    -- 插入sim卡，等待4G网络连接
    while netdrv.link(socket.LWIP_GP) ~= true do
        sys.wait(100)
    end
    
    -- 配置以太网络打开DHCP服务器
    dhcps.create({adapter=socket.LWIP_ETH})
    -- 配置DNS服务
    dnsproxy.setup(socket.LWIP_ETH, socket.LWIP_GP)
    -- 使用4G网络作为主网关出口
    netdrv.napt(socket.LWIP_GP)
    
    -- 若支持iper则建立iper服务器，用于吞吐测试
    if iperf then
        log.info("启动iperf服务器端")
        iperf.server(socket.LWIP_ETH)
    end    
    
end

-- 外部网络设备通过网线连接CH390H模块，通过4G网络进行http通信测试
function test_http_requet()
    -- sys.waitUntil("IP_READY")
    while 1 do
        sys.wait(300000)
        -- 注意这里会耗费sim卡4G网络流量，默认先屏蔽该功能，按需打开
        -- 定时通过http get请求来获取4K数据
        -- log.info("http", http.request("GET", "http://httpbin.air32.cn/bytes/4096", nil, nil, {adapter=socket.LWIP_ETH}).wait())
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
    end
end

-- 启动lan网络配置任务
sys.taskInit(network_setup)
-- 启动lan网络数据通信任务
sys.taskInit(test_http_requet)