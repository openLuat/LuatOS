--[[
@module  iperf_server
@summary iperf服务器模式测试模块
@version 1.0
@date    2025.10.29
@author  拓毅恒
@usage
本模块演示如何初始化CH390以太网并启动iperf服务器模式进行测试。
适用于路由器连接场景，设备通过DHCP从路由器获取IP地址。
使用步骤：
1、初始化SPI接口连接CH390
2、设置CH390驱动和网络参数
3、配置从路由器获取IP地址
4、启动iperf服务器并处理测试结果

本文件没有对外接口，直接在 main.lua 中 require "iperf_server" 即可加载运行。
]]

-- 引入必要的模块
local exnetif = require "exnetif"

-- 记录服务器IP
local server_ip = "0.0.0.0"

-- iperf测试报告处理函数
local function iperf_report_handler(bytes, ms_duration, bandwidth)
    -- 转换为Mbps显示
    local bandwidth_mbps = bandwidth / 1024 / 1024 * 8
    log.info("iperf报告", string.format("数据量: %d bytes, 持续时间: %d ms, 带宽: %.2f Mbps", bytes, ms_duration, bandwidth_mbps))
end

-- iperf服务器任务
local function iperf_server_task()
    log.info("iperf测试", "开始初始化网络...")
    -- 使用exnetif配置SPI外接以太网芯片CH390H
    exnetif.set_priority_order({
        {
            ETHERNET = {
                pwrpin = 140, 
                tp = netdrv.CH390,
                opts = {spi = 1, cs = 12}
            }
        }
    })
    -- 等待IP地址获取成功
    log.info("iperf测试", "等待获取IP地址...")
    local ip_wait_count = 60
    while true do
        local ipv4 = socket.localIP(socket.LWIP_ETH)
        if ipv4 and ipv4 ~= "0.0.0.0" then
            log.info("iperf测试", "IP获取成功:", ipv4)
            server_ip = ipv4
            break
        end
        
        -- 超时检查
        if ip_wait_count <= 0 then
            log.error("iperf测试", "获取IP地址超时")
            return
        end
        
        ip_wait_count = ip_wait_count - 1
        sys.wait(1000)
    end
    -- 等待以太网连接
    while not socket.adapter(socket.LWIP_ETH) do
        sys.wait(100)
    end
    log.info("iperf测试", "以太网连接状态: 已连接")
    
    -- 连接到路由器场景，不需要配置DHCP服务器
    log.info("iperf测试", "网络配置完成")
    
    -- 订阅iperf测试报告事件
    sys.subscribe("IPERF_REPORT", iperf_report_handler)
    
    -- 启动iperf服务器
    log.info("iperf测试", "启动服务器模式")
    log.info("iperf测试", "服务器IP地址:", server_ip, "端口: 5001")
    iperf.server(socket.LWIP_ETH)
    sys.wait(2000)
    log.info("iperf测试", "服务器已启动，等待客户端连接")
    log.info("iperf测试", "请在客户端设备上设置服务器IP地址为:", server_ip)
end

-- 执行iperf服务器模式测试
sys.taskInit(iperf_server_task)