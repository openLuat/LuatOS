--[[
@module  iperf_client
@summary iperf客户端模式测试模块
@version 1.0
@date    2025.10.29
@author  拓毅恒
@usage
本模块演示如何初始化CH390以太网并启动iperf客户端模式进行测试。
适用于路由器连接场景，设备通过DHCP从路由器获取IP地址。
1、初始化SPI接口连接CH390
2、设置CH390驱动和网络参数
3、配置从路由器获取IP地址
4、连接到指定的iperf服务器并进行测试

本文件没有对外接口，直接在 main.lua 中 require "iperf_client" 即可加载运行。
]]

-- 引入必要的模块
local exnetif = require "exnetif"

-- 配置服务器IP地址（需要根据实际服务器IP进行修改）
local SERVER_IP = "192.168.1.3"  -- 这里需要修改为实际的服务器IP地址

-- iperf测试报告处理函数
local function iperf_report_handler(bytes, ms_duration, bandwidth)
    -- 转换为Mbps显示
    local bandwidth_mbps = bandwidth / 1024 / 1024 * 8
    log.info("iperf报告", string.format("数据量: %d bytes, 持续时间: %d ms, 带宽: %.2f Mbps", bytes, ms_duration, bandwidth_mbps))
end

-- iperf客户端任务
local function iperf_client_task()
    log.info("iperf测试", "开始初始化网络...")
    -- 使用exnetif配置SPI外接以太网芯片CH390H
    exnetif.set_priority_order({
        {
            ETHERNET = {
                pwrpin = 20, 
                tp = netdrv.CH390,
                opts = {spi = 0, cs = 8}
            }
        }
    })
    -- 等待IP地址获取成功
    log.info("iperf测试", "等待获取IP地址...")
    -- 设置IP获取超时
    local ip_wait_count = 60
    while true do
        local ipv4 = socket.localIP(socket.LWIP_ETH)
        if ipv4 and ipv4 ~= "0.0.0.0" then
            log.info("iperf测试", "IP获取成功:", ipv4)
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

    -- 启动客户端模式，连接到指定服务器
    log.info("iperf测试", "启动客户端模式")
    log.info("iperf测试", "连接到服务器IP:", SERVER_IP, "端口: 5001")
    
    -- 连接服务器
    iperf.client(socket.LWIP_ETH, SERVER_IP, 5001)
    
    -- 订阅iperf测试报告事件
    sys.subscribe("IPERF_REPORT", iperf_report_handler)
    
    log.info("iperf测试", "测试开始")
    
        -- 设置测试循环次数，共测试2分钟
    local test_count = 24
    while test_count > 0 do
        -- 等待IPERF_REPORT事件，超时时间5秒
        local report_received = sys.waitUntil("IPERF_REPORT", 5000)
        if report_received then
            -- 如果收到报告事件，退出循环
            log.info("iperf测试", "收到报告，结束测试")
            break
        else
            -- 如果超时，继续测试
            test_count = test_count - 1
            log.info("iperf测试", "测试进行中...")
        end
    end
    
    -- 测试结束
    log.info("iperf测试", "测试结束，关闭客户端")
    iperf.abort()
end

-- 执行iperf客户端模式测试
sys.taskInit(iperf_client_task)