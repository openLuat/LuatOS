--[[
本功能模块演示的内容为：
1. 初始化网络，使得Air8101可以外挂Air780EPM实现4G联网功能
2. Air8101发送数据信息给Air780EPM
3. HTTP GET请求任务，测试Air8101的网络连接情况
4. 订阅airlink的SDATA事件，打印收到的信息
]]

-- 初始化网络，使得Air8101可以外挂Air780EPM实现4G联网功能
sys.taskInit(function()
    -- sys.wait(500)
    -- 初始化airlink
    airlink.init()
    -- 创建桥接网络设备
    log.info("创建桥接网络设备")
    netdrv.setup(socket.LWIP_USER0, netdrv.WHALE)
    -- 启动底层线程, 主机模式
    airlink.start(0)
    -- 配置IPv4地址
    netdrv.ipv4(socket.LWIP_USER0, "192.168.111.1", "255.255.255.0", "192.168.111.2")
end)

-- Air8101发送数据信息给Air780EPM
sys.taskInit(function()
    socket.sntp() -- 设置网络时间同步
    while 1 do
        -- 发送给对端设备
        local data = rtos.bsp() .. " " .. os.date()
        log.info("发送数据给对端设备", data, "当前airlink状态", airlink.ready())
        airlink.sdata(data)
        sys.wait(1000)
    end
end)

-- HTTP GET请求任务，测试Air8101的网络连接情况
sys.taskInit(function()
    -- sys.waitUntil("IP_READY")
    --等待6000毫秒（6秒），确保网络连接已经建立，再执行后续操作
    sys.wait(6000)
    -- 创建一个无限循环，不断执行HTTP请求
    while 1 do
        sys.wait(500)
        -- 发起一个HTTP GET请求
        local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil, {adapter=socket.LWIP_USER0,timeout=3000}).wait()
        -- 打印HTTP请求的结果，包括响应码code和响应体长度#body
        log.info("http", code, body and #body)
    end
end)

-- 订阅airlink的SDATA事件，打印收到的信息
sys.subscribe("AIRLINK_SDATA", function(data)
    log.info("收到AIRLINK_SDATA!!", data)
end)
