--[[
@module  netif_app
@summary netif_app 网络管理模块,开启多网融合功能，wifi提供网络供wifi和以太网设备上网
@version 1.0
@date    2026.07.02
@author  王城钧
@usage
本文件为网络管理模块，核心业务逻辑为：
1.设置多网融合功能，演示动态切换WiFi上游网络（WiFi A → 以太网 → WiFi B → 以太网）
2、http测试以太网网络
本文件没有对外接口，直接在main.lua中require "netif_app"就可以加载运行；
]]
exnetif = require "exnetif"

-- 记录当前使用的WiFi配置，用于掉线重连
local current_wifi_config = nil

--[[
连接WiFi STA
@param ssid string WiFi SSID
@param password string WiFi密码
@return boolean 是否连接成功
]]
local function connect_wifi_sta(ssid, password)
    wlan.connect(ssid, password)
    local count = 1
    while true do
        local ip = netdrv.ipv4(socket.LWIP_STA)
        if ip and ip ~= "0.0.0.0" then
            log.info("wifi", "已连接", ssid, "IP:", ip)
            return true
        end
        if count > 600 then
            log.error("wifi", "连接超时:", ssid)
            return false
        end
        sys.wait(100)
        count = count + 1
    end
end

--[[
切换WiFi STA上游网络
切换前先关闭NAPT(-1)，拿到新IP后再重新打开NAPT，避免NAPT状态残留导致CH390异常。
@param ssid string 新的WiFi SSID
@param password string 新的WiFi密码
@return boolean 是否切换成功
]]
local function switch_wifi_sta(ssid, password)
    log.info("switch_wifi", "关闭NAPT, 断开当前WiFi")
    current_wifi_config = nil   -- 先置空，避免 disconnect 触发的 IP_LOSE 回调抢连旧 WiFi
    netdrv.napt(-1)
    wlan.disconnect()
    sys.wait(2000)

    log.info("switch_wifi", "正在连接新WiFi:", ssid)
    if not connect_wifi_sta(ssid, password) then
        return false
    end

    -- 拿到新IP后重新打开NAPT
    netdrv.napt(socket.LWIP_STA)
    current_wifi_config = {ssid = ssid, password = password}
    log.info("switch_wifi", "NAPT已重新打开, 切换完成, 当前上游:", ssid)
    return true
end

--[[
WiFi STA 异常掉线时的重连回调
订阅 IP_LOSE 事件，当 STA 非主动断开时自动重连
]]
local function on_sta_ip_lose(adapter)
    if adapter ~= socket.LWIP_STA then
        return
    end
    if not current_wifi_config then
        return
    end
    sys.taskInit(function()
        log.warn("wifi", "检测到WiFi STA异常掉线，重连:", current_wifi_config.ssid)

        local ssid = current_wifi_config.ssid
        local pwd = current_wifi_config.password
        while true do
            -- 关闭所有网络适配器的napt功能
            netdrv.napt(-1)
            if connect_wifi_sta(ssid, pwd) then
                netdrv.napt(socket.LWIP_STA)
                log.info("wifi", "重连成功, NAPT已恢复")
                break
            end
            log.error("wifi", "重连失败，3秒后重试:", ssid)
            sys.wait(3000)
        end
    end)
end

function netif_app_task_func()
    -- WiFi A 和 WiFi B 的配置（请替换为实际SSID和密码）
    local wifi_a_config = {
        ssid = "116",
        password = "hezhou88888888"
    }
    local wifi_b_config = {
        ssid = "hezhou",
        password = "hezhou88888888"
    }

    -- 切换到WiFi A后等待多长时间再切到WiFi B（单位：毫秒）
    local switch_interval = 30000  -- 30秒，按需修改

    -- 以太网公共配置
    local eth_config = {
        ethpower_en = 140,                          -- 以太网模块的pwrpin引脚(gpio编号)
        tp = netdrv.CH390,                          -- 网卡芯片型号
        opts = { spi = 1, cs = 12, irq = 21 },      -- SPI参数
    }

    -- 第一阶段：WiFi A → 以太网
    local eth_params = {}
    for k, v in pairs(eth_config) do
        eth_params[k] = v
    end
    eth_params.main_adapter = wifi_a_config

    local res = exnetif.setproxy(socket.LWIP_ETH, socket.LWIP_STA, eth_params)
    if not res then
        log.error("第一阶段失败：WiFi A → 以太网 代理建立失败")
        return
    end
    current_wifi_config = wifi_a_config
    -- 订阅WiFi STA异常掉线事件，自动重连
    sys.subscribe("IP_LOSE", on_sta_ip_lose)
    log.info("第一阶段成功", "WiFi A → 以太网 代理已建立")

    -- WiFi A 工作一段时间
    log.info("WiFi A 将工作", switch_interval / 1000, "秒后切换到 WiFi B")
    sys.wait(switch_interval)


    -- 第二阶段：切换到 WiFi B → 以太网
    res = switch_wifi_sta(wifi_b_config.ssid, wifi_b_config.password)
    if not res then
        log.error("第二阶段失败：无法切换到 WiFi B")
        return
    end
    log.info("第二阶段成功", "WiFi B → 以太网 代理已建立")

    -- WiFi B 持续工作中
    -- 如需切回 WiFi A，再次调用 switch_wifi_sta 即可
    log.info( "WiFi 切换演示完成，当前使用 WiFi B 提供网络")

    -- 每5秒进行HTTP连接测试，实时监测WIFI网络连接状态，仅供测试需要，量产不需要
    -- while 1 do
    --     local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil, {adapter = socket.LWIP_STA, timeout = 5000, debug = false}).wait()
    --     log.info("http执行结果", code, headers, body and #body)
    --     sys.wait(5000)
    -- end
end

sys.taskInit(netif_app_task_func)
