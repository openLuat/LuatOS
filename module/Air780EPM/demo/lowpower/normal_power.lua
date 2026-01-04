--[[
@module  normal_power
@summary 常规模式主应用功能模块 
@version 1.0
@date    2025.07.17
@author  陈取德
@usage
本文件为常规模式主应用功能模块，核心业务逻辑为：
1、进入常规模式
2、判断是否开启4G、连接TCP服务器和发送平台心跳包
使用前请根据需要，变更功能变量。条件不同，功耗体现不同。
本文件没有对外接口，直接在main.lua中require "normal_power"就可以加载运行；
]] --
----是否需要开启4G，测试连接网络状态下功耗--------------------------------------
local mobile_mode = true -- true 需要   --false 不需要
-------------------------------------------------------------------------------

-----是否需要保持服务器心跳------------------------------------------------------
local tcp_mode = true -- true 需要连接TCP服务器，设置下方心跳包。    --false 不需要连接TCP服务器，不需要设置心跳包。
local tcp_heartbeat = 5 -- 常规模式和低功耗模式心跳包，单位（分钟），输入 1 为 一分钟一次心跳包。
local heart_data = string.rep("1234567890", 3) -- 心跳包数据内容，可自定义。
-------------------------------------------------------------------------------

function normal_power_func()
    log.info("开始测试常规模式功耗。")
    -- 将电源模式调整为常规模式。
    pm.power(pm.WORK_MODE, 0)
    -- 判断是否开启4G。
    if mobile_mode then
        -- 判断是否连接TCP平台。
        if tcp_mode then
            -- 导入tcp客户端收发功能模块，运行tcp客户端连接，自动处理TCP收发消息。
            require "tcp_client_main"
            -- 调用发送心跳信息功能函数。
            send_tcp_heartbeat_func()
        end
    else
        -- 开启飞行模式，保持环境干净。
        mobile.flymode(0, true)
    end
end

-- 定义一个发送心跳信息功能函数。
function send_tcp_heartbeat_func()
    -- 通过驻网状态判断4G是否连接成功，不成功则等待成功连接后再开始发送信息。
    while not socket.adapter(socket.dft())do
        -- 在此处阻塞等待4G连接成功的消息"IP_READY"，避免联网过快，丢失了"IP_READY"信息而导致一直被卡住。
        -- 或者等待30秒超时退出阻塞等待状态
        log.warn("tcp_client_main_task_func", "wait IP_READY")
        local mobile_result = sys.waitUntil("IP_READY", 30000)
        if mobile_result then
            log.info("4G已经连接成功。")
        else
            log.info("SIM卡异常,当前状态：",mobile.status(),"。请检查SIM卡!")
            -- 30S后网络还没连接成功，开关一下飞行模式，让SIM卡软重启，重新尝试驻网。
            mobile.flymode(0, true)
            mobile.flymode(0, false)
        end
    end
    -- 4G驻网后会与基站发送保活心跳。
    log.info("4G已经连接,开始与基站发送保活心跳")
    -- 起一个循环定时器，根据预设时间循环定时发送一次消息到TCP服务器。
    while true do
        sys.publish("SEND_DATA_REQ", "timer", heart_data)
        sys.wait(tcp_heartbeat * 60 * 1000)
    end
end

sys.taskInit(normal_power_func)
