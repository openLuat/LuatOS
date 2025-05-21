-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "Air8000_AP_Config"
VERSION = "1.0.0"

-- 引入必要的库文件
sys = require("sys")
sysplus = require("sysplus")
dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")

-- 初始化LED灯, 这里演示控制Air8000核心板蓝灯，其他开发板请查看硬件原理图自行修改
local LEDA = gpio.setup(20, 0, gpio.PULLUP)

-- AP模式配置，如果未在WEB网页配置AP账号和密码，默认为如下ssid和passwd
local ap_config = {
    ssid = "Air8000_AP",
    passwd = "12345678",
    gateway = "192.168.4.1",
    netmask = "255.255.255.0",
    channel = 6
}

-- 保存的AP状态
local ap_status = "未启动"

sys.taskInit(function()
    sys.wait(1000)
    -- STA模式连接到路由器，此处修改为你的 STA SSID 和密码
    wlan.init()
    wlan.connect("luatos1234", "12341234", 1) -- 替换为你的 STA 配置
    log.info("wlan", "waiting for IP_READY in STA mode")

    while not wlan.ready() do
        local ret, ip = sys.waitUntil("IP_READY", 30000)
        log.info("ip", ret, ip)
        if ip then
            _G.wlan_ip = ip
        end
    end
    log.info("wlan", "STA mode ready !!", wlan.getMac())

    -- 启动HTTP服务器
    httpsrv.start(80, function(fd, method, uri, headers, body)
        log.info("httpsrv", method, uri, json.encode(headers), body)

        -- 控制LED
        if uri == "/led/1" then
            LEDA(1)
            return 200, {}, "LED on"
        elseif uri == "/led/0" then
            LEDA(0)
            return 200, {}, "LED off"
        -- 启动AP模式
        elseif uri == "/startap" then
            -- 创建AP
            wlan.createAP(ap_config.ssid, ap_config.passwd, ap_config.gateway, ap_config.netmask, ap_config.channel)
            
            -- 配置AP的IP地址和网关
            netdrv.ipv4(socket.LWIP_AP, ap_config.gateway, ap_config.netmask, ap_config.gateway)
            
            dnsproxy.setup(socket.LWIP_AP, socket.LWIP_GP)
            -- 创建DHCP服务器
            dhcpsrv.create({adapter=socket.LWIP_AP})

            -- 启用NAT
            while 1 do
                if netdrv.ready(socket.LWIP_GP) then
                    netdrv.napt(socket.LWIP_GP)
                    break
                end
                sys.wait(1000)
            end
            
            ap_status = "已启动"
            return 200, {}, "AP started"
        -- 获取AP状态
        elseif uri == "/apstatus" then
            return 200, {["Content-Type"]="application/json"}, json.encode({status = ap_status})
        -- 设置AP配置
        elseif uri == "/setap" then
            if method == "POST" and body then
                local jdata = json.decode(body)
                if jdata and jdata.ssid and jdata.passwd then
                    ap_config.ssid = jdata.ssid
                    ap_config.passwd = jdata.passwd
                    ap_status = "配置已更新，需重启AP"
                    return 200, {}, "AP config updated"
                end
            end
            return 400, {}, "Bad Request"
        end
        return 404, {}, "Not Found" .. uri
    end, socket.LWIP_STA)

    log.info("web", "please open url http://" .. _G.wlan_ip .. "/")
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!