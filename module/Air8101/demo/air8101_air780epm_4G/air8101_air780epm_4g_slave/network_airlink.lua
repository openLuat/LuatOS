--[[
本功能模块演示的内容为：
1. 初始化网络，使得Air8101可以外挂Air780EPM实现4G联网功能
2. Air780EPM发送数据信息给Air8101
3. 订阅IP_READY事件，打印收到的信息
4. 订阅airlink的SDATA事件，打印收到的信息
]]

dnsproxy = require ("dnsproxy")

-- 初始化网络，使得Air8101可以外挂Air780EPM实现4G联网功能
sys.taskInit(function()
    sys.wait(100)
    -- 初始化airlink
    airlink.init()
    -- 创建桥接网络设备
    log.info("创建桥接网络设备")
    netdrv.setup(socket.LWIP_USER0, netdrv.WHALE)
    -- 启动底层线程, 从机模式
    airlink.start(1)

    -- 配置IPv4地址
    log.info("配置IPv4地址")
    netdrv.ipv4(socket.LWIP_USER0, "192.168.111.2", "255.255.255.0", "192.168.111.1")
    sys.wait(100)
    -- 等待IP_READY事件
    sys.waitUntil("IP_READY", 10000)
    -- 设置NAPT
    netdrv.napt(socket.LWIP_GP)
    -- 设置DNS代理
    dnsproxy.setup(socket.LWIP_USER0, socket.LWIP_GP)
end)

-- Air780EPM发送数据信息给Air8101
sys.taskInit(function()
    while 1 do
        -- 发送给对端设备
        local data = rtos.bsp() .. " " .. os.date()
        log.info("发送数据给对端设备", data, "当前airlink状态", airlink.ready())
        airlink.sdata(data)
        sys.wait(1000)
    end
end)

-- 订阅IP_READY事件，打印收到的信息
sys.subscribe("IP_READY", function(id, ip)
    log.info("收到IP_READY!!", id, ip)
end)

-- 订阅airlink的SDATA事件，打印收到的信息
sys.subscribe("AIRLINK_SDATA", function(data)
    log.info("收到AIRLINK_SDATA!!", data)
end)

