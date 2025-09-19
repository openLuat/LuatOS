--[[
@module  netif_app
@summary netif_app 网络管理模块,开启多网融合功能，wifi提供网络供wifi和以太网设备上网
@version 1.0
@date    2025.09.17
@author  魏健强
@usage
本文件为网络管理模块，核心业务逻辑为：
1.设置多网融合功能，wifi提供网络供wifi和以太网设备上网
2、http测试wifi网络
本文件没有对外接口，直接在main.lua中require "netif_app"就可以加载运行；
]] 
exnetif = require "exnetif"

function netif_app_task_func()
    local res
    --设置多网融合功能，wifi提供网络供以太网设备上网
    res = exnetif.setproxy(socket.LWIP_ETH, socket.LWIP_STA, {
        ethpower_en = 140,               -- 以太网模块的pwrpin引脚(gpio编号)
        tp = netdrv.CH390,               -- 网卡芯片型号(选填参数)，仅spi方式外挂以太网时需要填写。
        opts = { spi = 1, cs = 12 },     -- 外挂方式,需要额外的参数(选填参数)，仅spi方式外挂以太网时需要填写。
        main_adapter = {                 -- 提供网络的网卡开启参数
            ssid = "test",               
            password = "HZ88888888"
        }
    })
    -- 设置多网融合功能，wifi提供网络供wifi设备上网
    res = exnetif.setproxy(socket.LWIP_AP, socket.LWIP_STA, {
        ssid = "test2", -- AP热点名称(string)，网卡包含wifi时填写
        password = "HZ88888888", -- AP热点密码(string)，网卡包含wifi时填写
        -- ap_opts = {                      -- AP模式下配置项(选填参数)
        --     hidden = false,              -- 是否隐藏SSID, 默认false,不隐藏
        --     max_conn = 4 },              -- 最大客户端数量, 默认4
        -- channel = 6,                     -- AP建立的通道, 默认6
        main_adapter = {                    -- 提供网络的网卡开启参数
            ssid = "test",
            password = "HZ88888888"
        }
    })

    if res then
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
