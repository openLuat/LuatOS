--[[
本功能模块演示的内容有：
1. 初始化4G和WiFi网络连接。
2. Air8101与对端设备进行数据交互。
3. 自动切换网络连接模式。
4. 通过HTTP GET请求测试网络连接情况。
]]

-- 联网模式标志位，1: WiFi联网模式， 2: 4G联网模式
local connect_mode = 1

-- 初始化网络，使得Air8101可以外挂Air780EPM实现4G联网功能。
local function init_airlink_net()
    -- sys.wait(500)
    -- 初始化airlink。
    airlink.init()
    -- 创建桥接网络设备。
    log.info("创建桥接网络设备")
    netdrv.setup(socket.LWIP_USER0, netdrv.WHALE)
    -- 启动airlink，配置Air8101作为SPI从机模式。
    airlink.start(airlink.MODE_SPI_SLAVE)

    -- 配置IPv4地址。
    log.info("配置IPv4地址", "192.168.111.1", "255.255.255.0", "192.168.111.2")
    netdrv.ipv4(socket.LWIP_USER0, "192.168.111.1", "255.255.255.0", "192.168.111.2")
end

-- 初始化Air8101 WiFi联网配置程序。（WiFi联网功能需要用户自行配置WiFi热点名称和密码）
local function init_wifi_net()
    -- 输入需要连接对应WiFi热点的名称（ssid）和密码（password）
    local ssid = "HONOR_100_Pro" -- 热点名称
    local password = "12356789"  -- 热点密码
    log.info("热点信息：", "热点名称：", ssid, "热点密码：", password)

    -- wlan库的判断和WiFi连接。
    if wlan and wlan.connect then
        -- 初始化wlan库。
        wlan.init()
        -- 设置为WiFi STA模式。
        wlan.setMode(wlan.STATION)
        -- 连接WiFi热点。
        local result = wlan.connect(ssid, password, 1)
        if result then
            log.info("发起连接成功")
        else
            log.info("发起连接失败")
        end
    else
        log.info("wlan库不存在")
    end
end

-- Air8101发送数据信息给Air780EPM。
local function airlink_sdata_Air780EPM()
    -- 设置网络时间同步。
    socket.sntp()
    while 1 do
        -- rtos.bsp()：设备硬件bsp型号；os.date()：本地时间。
        local data = rtos.bsp() .. " " .. os.date()
        log.info("发送数据给对端设备", data, "当前airlink状态", airlink.ready())
        airlink.sdata(data)
        sys.wait(1000)
    end
end

-- 一个简单的HTTP GET请求测试程序，用于判断Air8101的网络连接情况。
local function http_get_test(mode)
    -- 发起一个HTTP GET请求。
    log.info(mode, "发起HTTP GET请求", "https://httpbin.air32.cn/bytes/2048")
    local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil, {timeout=3000}).wait()

    -- 打印HTTP请求的结果，包括响应码code和响应体长度#body。
    if code == 200 then
        log.info(mode, "HTTP请求成功", "响应码", code, "响应体长度", body and #body)
        sys.publish("打印网卡信息", mode, "succeeded")
    else
        log.error(mode, "HTTP请求失败", "错误码", code)
        sys.publish("打印网卡信息", mode, "failed")
    end
end

-- 订阅airlink的SDATA事件，打印收到的信息。
local function airlink_sdata(data)
    -- 针对对端网络状态，发布不同事件主题。
    if data == "Air780EPM_IP_READY!!" then
        log.info("对端设备已联网")
        -- 可在此处添加对端设备联网后的处理逻辑。
        -- sys.publish("Air780EPM_IP_READY")
    elseif data == "Air780EPM_IP_LOSE!!" then
        log.info("对端设备已断网")
        -- 可在此处添加对端设备断网后的处理逻辑。
        -- sys.publish("Air780EPM_IP_LOSE")
    end

    -- 打印收到的信息。
    log.info("收到AIRLINK_SDATA!!", data)
end

-- 切换默认网络适配器。
local function switch_default_net_adapter(netAdapter)
    -- 切换默认网络适配器。
    if netAdapter == "4G" then
        -- 切换到4G网络适配器。
        socket.dft(socket.LWIP_USER0)
        -- 设置DNS服务器地址。
        socket.setDNS(socket.LWIP_USER0, 1, "192.168.111.2")
    elseif netAdapter == "WiFi" then
        -- 切换到WiFi网络适配器。
        socket.dft(socket.LWIP_STA)
        -- 设置DNS服务器地址。
        socket.setDNS(socket.LWIP_STA, 1, "114.114.114.114")
    end
end

-- 网络模式切换测试程序。
local function net_mode_switch()
    -- 30秒够4G和WiFi初始化完成了。
    log.info("30秒后开始Air8101网络模式切换测试")
    sys.wait(30000)
    log.info("开始Air8101网络模式切换测试")

    while 1 do
        if connect_mode == 2 then
            log.info("当前为4G联网模式，进行一次http请求")
            switch_default_net_adapter("4G")
            http_get_test("4G网络模式")
        else
            log.info("当前为WiFi联网模式，进行一次http请求")
            switch_default_net_adapter("WiFi")
            http_get_test("WiFi网络模式")
        end

        log.info("35秒后切换为另一种网络模式")
        sys.wait(35000)

        if connect_mode == 1 then
            log.info("切换为4G联网模式")
            connect_mode = 2
            sys.publish("4G联网模式")
        else
            log.info("切换为WiFi联网模式")
            connect_mode = 1
            sys.publish("WiFi联网模式")
        end
    end
end

-- 网卡信息获取程序。
local function net_card_info(mode, result)
    if mode == "4G网络模式" then
        if result == "succeeded" then
            log.info("4G网络模式连接成功")
        else
            log.error("4G网络模式连接失败")
        end
        log.info("当前网络适配器编号：", socket.dft())
        log.info("当前本地IP地址：", netdrv.ipv4(socket.LWIP_USER0))
    elseif mode == "WiFi网络模式" then
        if result == "succeeded" then
            log.info("WiFi网络模式连接成功")
        else
            log.error("WiFi网络模式连接失败")
        end
        log.info("当前网络适配器编号：", socket.dft())
        log.info("当前本地IP地址：", netdrv.ipv4(socket.LWIP_STA))
        log.info("当前MAC地址：", wlan.getMac())
        log.info("其他信息", json.encode(wlan.getInfo()))
    end
end

-- 初始化网络，使得Air8101可以外挂Air780EPM实现4G联网功能。
sys.taskInit(init_airlink_net)

-- 初始化Air8101 WiFi联网配置程序。（WiFi联网功能需要用户自行配置WiFi热点名称和密码）
sys.taskInit(init_wifi_net)

-- Air8101发送数据信息给Air780EPM。
sys.taskInit(airlink_sdata_Air780EPM)

-- 网络模式切换测试程序。
sys.taskInit(net_mode_switch)

-- 订阅airlink的SDATA事件，打印收到的信息。
sys.subscribe("AIRLINK_SDATA", airlink_sdata)

-- 订阅打印网卡信息事件，打印网卡信息。
sys.subscribe("打印网卡信息", net_card_info)