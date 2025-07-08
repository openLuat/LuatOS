--[[
@module  low_power
@summary 低功耗模式主应用功能模块 
@version 1.0
@date    2025.07.01
@author  陈取德
@usage
本文件为低功耗模式主应用功能模块，核心业务逻辑为：
1、进入低功耗模式
2、判断是否在低功耗模式下连接网络和发送平台心跳包
使用前请根据需要，变更功能变量。条件不同，功耗体现不同。
本文件没有对外接口，直接在main.lua中require "low_power"就可以加载运行；
]] --
----是否需要连接WIFI，测试连接网络状态下功耗--------------------------------------
local wifi_mode = true -- true 需要   --false 不需要
-------------------------------------------------------------------------------

-----是否需要保持服务器心跳------------------------------------------------------
local tcp_mode = true -- true 需要，设置下方心跳包。    --false 不需要，不需要设置心跳包。
local tcp_heartbeat = 5 -- 常规模式和低功耗模式心跳包，单位（分钟），输入 1 为 一分钟一次心跳包。
local heart_data = string.rep("1234567890", 3) -- 心跳包数据内容，可自定义。
-------------------------------------------------------------------------------

function low_power_func()
    log.info("开始测试低功耗模式功耗。")
    -- 判断是否连接WIFI，请注意WIFI账号密码是否正确。
    if wifi_mode then
        -- 导入WIFI_app功能，自动运行连接WIFI。
        require "wifi_app"
        -- 进入低功耗 MODE 1 模式
        pm.power(pm.WORK_MODE, 1)
        -- 判断是否连接TCP平台
        if tcp_mode then
            -- 导入tcp客户端收发功能模块，运行tcp客户端连接，自动处理TCP收发消息。
            require "tcp_client_main"
            -- 调用发送心跳信息功能函数。
            send_tcp_heartbeat_func()
        end
    else
        -- 如果不开启WIFI连接，就直接进入低功耗模式。
        pm.power(pm.WORK_MODE, 1)
    end
end

-- 定义一个发送心跳信息功能函数。
function send_tcp_heartbeat_func()
    -- 通过网卡状态判断WIFI是否连接成功，WIFI连接成功后再运行消息发送。
    while not socket.adapter(socket.LWIP_STA) do
        -- 在此处阻塞等待WIFI连接成功的消息"IP_READY"，避免联网过快，丢失了"IP_READY"信息而导致一直被卡住。
        -- 或者等待30秒超时退出阻塞等待状态
        log.warn("tcp_client_main_task_func", "wait IP_READY")
        sys.waitUntil("IP_READY", 30000)
    end
    -- 起一个循环定时器，根据预设时间循环定时发送一次消息到TCP服务器。
    while true do
        sys.publish("SEND_DATA_REQ", "timer", heart_data)
        sys.wait(tcp_heartbeat * 60 * 1000)
    end
end

sys.taskInit(low_power_func)
