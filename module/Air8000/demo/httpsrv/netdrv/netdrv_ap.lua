--[[
@module  netdrv_ap
@summary "WIFI AP网卡"驱动模块
@version 1.0
@date    2025.11.4
@author  拓毅恒
@usage
本文件为WIFI AP网卡驱动模块，核心业务逻辑为：
1、初始化网络；
2、创建WIFI AP热点；
3、配置IP地址和DHCP服务器；
4、发布AP创建完成事件；

本文件没有对外接口，直接在其他功能模块中require "netdrv_ap"就可以加载运行；
]]

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")

-- AP热点创建完成回调函数
local function ap_ready_func()
    log.info("netdrv_ap", "AP热点创建成功，IP地址为: 192.168.4.1")
    -- 发布AP创建完成事件
    sys.publish("CREATE_OK")
end

-- 创建并启动AP热点初始化任务
local function netdrv_ap_init_task()
    -- 初始化WIFI
    wlan.init()
    log.info("netdrv_ap", "执行AP创建操作", "luatos8888")
    sys.wait(100)
    -- 创建AP热点，名称为luatos8888，密码为12345678
    wlan.createAP("luatos8888", "12345678")
    -- AP启动成功后，设置IP地址和DHCP服务器
    netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "0.0.0.0")
    -- 等待网络准备就绪
    while netdrv.ready(socket.LWIP_AP) ~= true do
        sys.wait(100)
    end
    -- 设置DNS代理
    dnsproxy.setup(socket.LWIP_AP, socket.LWIP_GP)
    -- 创建DHCP服务器
    dhcpsrv.create({adapter=socket.LWIP_AP})
    -- 调用AP就绪回调
    ap_ready_func()
end

-- 启动AP初始化任务
sys.taskInit(netdrv_ap_init_task)