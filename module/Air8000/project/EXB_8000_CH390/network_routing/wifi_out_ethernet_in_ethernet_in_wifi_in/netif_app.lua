--[[
@module  netif_app
@summary netif_app 网络管理模块,开启多网融合功能，wifi提供网络供wifi和以太网设备上网
@version 1.0
@date    2025.08.05
@author  魏健强
@usage
本文件为网络管理模块，核心业务逻辑为：
1.设置多网融合功能，wifi提供网络供wifi和以太网设备上网
2、http测试wifi网络
本文件没有对外接口，直接在main.lua中require "netif_app"就可以加载运行；
]]
exnetif = require "exnetif"

local function ip_ready_func(ip, adapter)
    if adapter == socket.LWIP_STA then
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")
        log.info("netif_app.ip_ready_func", "IP_READY", socket.localIP(socket.LWIP_STA))
    elseif adapter == socket.LWIP_ETH then
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")
        log.info("netif_app.ip_ready_func", "以太网1 IP_READY", ip)
    elseif adapter == socket.LWIP_USER1 then
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")
        log.info("netif_app.ip_ready_func", "以太网2 IP_READY", ip)
    elseif adapter == socket.LWIP_AP then
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")
        log.info("netif_app.ip_ready_func", "WiFi AP IP_READY", ip)
    end
end

local function ip_lose_func(adapter)
    if adapter == socket.LWIP_STA then
        log.warn("netif_app.ip_lose_func", "WiFi STA IP_LOSE")
    elseif adapter == socket.LWIP_ETH then
        log.warn("netif_app.ip_lose_func", "以太网1 IP_LOSE")
    elseif adapter == socket.LWIP_USER1 then
        log.warn("netif_app.ip_lose_func", "以太网2 IP_LOSE")
    elseif adapter == socket.LWIP_AP then
        log.warn("netif_app.ip_lose_func", "WiFi AP IP_LOSE")
    end
end

sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)

function netif_app_task_func()
    --  需同时拉高两个网口的使能脚，若不同时开启SPI信号的逻辑电平会混乱，导致通讯失败
    gpio.setup(16, 1, gpio.PULLUP) -- 打开ch390 1的供电
    gpio.setup(17, 1, gpio.PULLUP) -- 打开ch390 2的供电
    local res, res1
    --设置多网融合功能，wifi提供网络供以太网设备上网
    res = exnetif.setproxy(socket.LWIP_ETH, socket.LWIP_STA, {
        -- 网口1
        ethpower_en = 16,            -- 以太网模块的pwrpin引脚(gpio编号)
        tp = netdrv.CH390,           -- 网卡芯片型号(选填参数)，仅spi方式外挂以太网时需要填写。
        opts = { spi = 1, cs = 21 }, -- 外挂方式,需要额外的参数(选填参数)，仅spi方式外挂以太网时需要填写。
        main_adapter = { -- 提供网络的网卡开启参数
            ssid = "116",
            password = "wangshuai123"
        }
    })
    -- 设置多网融合功能，wifi提供网络供wifi设备上网
    res = exnetif.setproxy(socket.LWIP_AP, socket.LWIP_STA, {
        ssid = "test2",          -- AP热点名称(string)，网卡包含wifi时填写
        password = "HZ88888888", -- AP热点密码(string)，网卡包含wifi时填写
        -- ap_opts = {                      -- AP模式下配置项(选填参数)
        --     hidden = false,              -- 是否隐藏SSID, 默认false,不隐藏
        --     max_conn = 4 },              -- 最大客户端数量, 默认4
        -- channel = 6,                     -- AP建立的通道, 默认6
        main_adapter = { -- 提供网络的网卡开启参数
            ssid = "116",
            password = "wangshuai123"
        }
    })
    if res then
        log.info("exnetif", "setproxy success")
    else
        log.info("开启失败，请检查配置项是否正确，日志中是否打印了错误信息")
    end

    sys.wait(2000)
    --设置多网融合功能，wifi提供网络供以太网设备上网
    res1 = exnetif.setproxy(socket.LWIP_USER1, socket.LWIP_STA, {
        -- 网口2
        ethpower_en = 17,            -- 以太网模块的pwrpin引脚(gpio编号)
        tp = netdrv.CH390,           -- 网卡芯片型号(选填参数)，仅spi方式外挂以太网时需要填写。
        opts = { spi = 1, cs = 20 }, -- 外挂方式,需要额外的参数(选填参数)，仅spi方式外挂以太网时需要填写。
        main_adapter = {             -- 提供网络的网卡开启参数
            ssid = "116",
            password = "wangshuai123"
        }
    })
    if res1 then
        log.info("exnetif", "setproxy success")
    else
        log.info("开启失败，请检查配置项是否正确，日志中是否打印了错误信息")
    end
    
    -- 每5秒进行HTTPS连接测试，实时监测wifi网络连接状态, 仅供测试需要，量产不需要，用来判断当前网络是否可用，需要的话可以打开注释
    -- while 1 do
    --     local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil, {
    --         adapter = socket.LWIP_STA,
    --         timeout = 5000,
    --         debug = false
    --     }).wait()
    --     log.info("http执行结果", code, headers, body and #body)
    --     sys.wait(5000)
    -- end
end

sys.taskInit(netif_app_task_func)
