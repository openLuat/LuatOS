--[[
@module  netdrv_4g
@summary "4G网卡"驱动模块 
@version 1.0
@date    2025.07.01
@author  朱天华
@usage
本文件为4G网卡驱动模块，核心业务逻辑为：
1、监听"IP_READY"和"IP_LOSE"，在日志中进行打印；
2、监听"SIM_IND"，检测 SIM 卡在位状态，发布 NET_4G_SIM_STATUS 供 UI 更新图标；

本文件没有对外接口，直接在main.lua中require "netdrv_device"就可以加载运行；

发布消息：
- "NET_4G_STATUS"          -- 4G 连接状态 {connected}
- "NET_4G_SIM_STATUS"      -- SIM 卡在位状态 {present}（false=未识别 SIM 卡）
- "NET_4G_SIGNAL_STATUS"   -- 4G 信号状态（csq_level, csq，每 2 秒更新）
                              csq_level：-1=无卡/无信号，1-5=信号等级（供标题栏 4G 图标）
                              csq：原始 CSQ，0~31（99=无信号/不可测），供 AirCloud 上报字段 782
]]

-- 4G 连接状态缓存（供 netdrv_wifi 汇总发布 NET_STATUS）
local g4_connected = false

-- SIM 卡在位标志（初始 false=未知/无卡，参考官方 status_provider_app；SIM_IND 事件到达后纠正）
local sim_present = false

-- 4G 信号等级（-1=无 SIM 卡/无信号，1-5=信号等级，每 2 秒由 mobile.csq() 更新）
local csq_level = -1

-- 4G 信号原始值（CSQ：0~31，越大越好；99=无信号/不可测）
-- 供 AirCloud 上报字段 782（信号强度）使用
local csq_raw = 99

local function ip_ready_func(ip, adapter)    
    if adapter == socket.LWIP_GP then
        -- 在位置1和2设置自定义的DNS服务器ip地址：
        -- "223.5.5.5"，这个DNS服务器IP地址是阿里云提供的DNS服务器IP地址；
        -- "114.114.114.114"，这个DNS服务器IP地址是国内通用的DNS服务器IP地址；
        -- 可以加上以下两行代码，在自动获取的DNS服务器工作不稳定的情况下，这两个新增的DNS服务器会使DNS服务更加稳定可靠；
        -- 如果使用专网卡，不要使用这两行代码；
        -- 如果使用国外的网络，不要使用这两行代码；
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")
        
        log.info("netdrv_4g.ip_ready_func", "IP_READY", socket.localIP(socket.LWIP_GP))
        -- 更新 4G 连接状态并通知网络管理模块（netdrv_wifi 汇总发布 NET_STATUS）
        if not g4_connected then
            g4_connected = true
            sys.publish("NET_4G_STATUS", true)
        end
    end
end

local function ip_lose_func(adapter)    
    if adapter == socket.LWIP_GP then
        log.warn("netdrv_4g.ip_lose_func", "IP_LOSE")
        -- 更新 4G 连接状态并通知网络管理模块
        if g4_connected then
            g4_connected = false
            sys.publish("NET_4G_STATUS", false)
        end
    end
end



--此处订阅"IP_READY"和"IP_LOSE"两种消息
--在消息的处理函数中，仅仅打印了一些信息，便于实时观察4G网络的连接状态
--也可以根据自己的项目需求，在消息处理函数中增加自己的业务逻辑控制，例如可以在联网状态发生改变时更新网络图标
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)

-- SIM 卡状态检测（参考官方 Air8000A turnkey 固件 status_provider_app）
-- SIM_IND 事件：RDY=SIM卡就绪，NORDY=无SIM卡；底层约30秒周期检测SIM卡在位
sys.subscribe("SIM_IND", function(status, value)
    if status == "RDY" then
        sim_present = true
        log.info("netdrv_4g.sim_ind", "SIM 卡就绪")
    elseif status == "NORDY" then
        sim_present = false
        log.warn("netdrv_4g.sim_ind", "未识别到 SIM 卡")
    end
    -- 通知 UI 更新 4G 状态图标（home_win 订阅）
    sys.publish("NET_4G_SIM_STATUS", sim_present)
end)

-- 4G 信号等级更新（参考官方 Air8000A status_provider_app：每 2 秒查询 mobile.csq() 映射等级 1-5）
-- csq 范围 0-31，99=未知；csq==99 或 <=5 → 1（最弱）... csq>20 → 5（最强）
local function update_signal()
    if not sim_present then
        csq_level = -1
        -- 无 SIM 卡：CSQ 不可测，按 99 上报
        csq_raw = 99
    else
        -- mobile.csq() 失败时可能返回 nil，兜底为 99（无信号/不可测）
        local csq = mobile.csq() or 99
        -- 缓存原始 CSQ（0~31，99=无信号/不可测），供上报字段 782 使用
        csq_raw = csq
        if csq == 99 or csq <= 5 then
            csq_level = 1
        elseif csq <= 10 then
            csq_level = 2
        elseif csq <= 15 then
            csq_level = 3
        elseif csq <= 20 then
            csq_level = 4
        else
            csq_level = 5
        end
    end
    -- 通知 UI 更新 4G 信号图标（home_win 订阅，只取第一个参数 csq_level）；
    -- 第二个参数 csq_raw 为原始 CSQ，供 protocol_app 上报字段 782 使用
    sys.publish("NET_4G_SIGNAL_STATUS", csq_level, csq_raw)
end
-- 每 2 秒更新一次 4G 信号等级
sys.timerLoopStart(update_signal, 2000)

-- 在Air8000系列上，内核固件运行起来之后，默认网卡就是socket.LWIP_GP
