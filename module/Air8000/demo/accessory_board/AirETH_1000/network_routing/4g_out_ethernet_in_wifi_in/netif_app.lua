--[[
@module  netif_app
@summary netif_app 网络管理模块，开启多网融合功能，4G提供网络供wifi和以太网设备上网
@version 1.0
@date    2025.08.05
@author  魏健强
@usage
本文件为网络管理模块，核心业务逻辑为：
1、设置多网融合功能，4G提供网络供wifi和以太网设备上网
2、http测试4G网络
本文件没有对外接口，直接在main.lua中require "netif_app"就可以加载运行；
]]

exnetif = require "exnetif"

function netif_app_task_func()
    local res
    -- 等待4G网络连接成功
    while not socket.adapter() do
        -- 在此处阻塞等待4G网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        sys.waitUntil("IP_READY", 1000)
    end
    --设置多网融合功能，4G提供网络供wifi设备上网
    res = exnetif.setproxy(socket.LWIP_AP, socket.LWIP_GP, {
            ssid = "test2",                  -- AP热点名称(string)，网卡包含wifi时填写
            password = "HZ88888888",         -- AP热点密码(string)，网卡包含wifi时填写
            -- ap_opts = {                      -- AP模式下配置项(选填参数)
            --     hidden = false,              -- 是否隐藏SSID, 默认false,不隐藏
            --     max_conn = 4 },              -- 最大客户端数量, 默认4
            -- channel = 6,                     -- AP建立的通道, 默认6
            -- adapter_addr = "192.168.5.1",    -- 自定义LWIP_AP网卡的ip地址(选填),需要自定义ip和网关ip时填写
            -- adapter_gw = { 192, 168, 5, 1 }, -- 自定义LWIP_AP网卡的网关地址(选填),需要自定义ip和网关ip时填写
        })
    if res then
        log.info("exnetif", "setproxy success")
    else
        log.info("开启失败，请检查配置项是否正确，日志中是否打印了错误信息")
    end
    --设置多网融合功能，4G提供网络供以太网设备上网
    res = exnetif.setproxy(socket.LWIP_ETH, socket.LWIP_GP, {
            ethpower_en = 140,              -- 以太网模块的pwrpin引脚(gpio编号)
            tp = netdrv.CH390,              -- 网卡芯片型号(选填参数)，仅spi方式外挂以太网时需要填写。
            opts = { spi = 1, cs = 12 },    -- 外挂方式,需要额外的参数(选填参数)，仅spi方式外挂以太网时需要填写。
            -- adapter_addr = "192.168.2.1",   -- 自定义LWIP_ETH网卡的ip地址(选填),需要自定义ip和网关ip时填写
            -- adapter_gw = { 192, 168, 2, 1 } -- 自定义LWIP_ETH网卡的网关地址(选填),需要自定义ip和网关ip时填写
        })
    if res then
        log.info("exnetif", "setproxy success")
    else
        log.info("开启失败，请检查配置项是否正确，日志中是否打印了错误信息")
    end    
    -- 每5秒进行HTTPS连接测试，实时监测4G网络连接状态, 仅供测试需要，量产不需要，用来判断当前网络是否可用，需要的话可以打开注释
    -- while 1 do
    --     local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil,
    --         { adapter = socket.LWIP_GP, timeout = 5000, debug = false }).wait()
    --     log.info("http执行结果", code, headers, body and #body)
    --     sys.wait(5000)
    -- end
end

sys.taskInit(netif_app_task_func)
