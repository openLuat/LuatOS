--[[
@module  sntp_app
@summary sntp时间同步应用功能模块
@version 1.0
@date    2025.07.31
@author  孟伟
@usage
本文件为sntp时间同步应用功能模块，核心业务逻辑为：
1、连接ntp服务器进行时间同步；
2、如果同步成功，1小时之后重新发起同步动作；
3、如果同步失败，10秒钟之后重新发起同步动作；

本文件没有对外接口，直接在其他应用功能模块中require "sntp_app"就可以加载运行；
]]

-- sntp时间同步的任务处理函数
local function sntp_task_func()

    while true do
        -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
        while not socket.adapter(socket.dft()) do
            log.warn("sntp_task_func", "wait IP_READY", socket.dft())
            -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
            -- 或者等待1秒超时退出阻塞等待状态;
            -- 注意：此处的1000毫秒超时不要修改的更长；
            -- 因为当使用libnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
            -- 当libnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
            -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
            sys.waitUntil("IP_READY", 1000)
        end

        -- 检测到了IP_READY消息
        log.warn("sntp_task_func", "recv IP_READY")

        -- 发起ntp时间同步动作
        socket.sntp()

        -- 等待ntp时间同步结果，30秒超时失败，通常只需要几百毫秒就能成功
        local ret = sys.waitUntil("NTP_UPDATE", 30000)

        --同步成功
        if ret then
            -- 以下是获取/打印时间的演示,注意时区问题
            log.info("sntp_task_func", "时间同步成功", "本地时间", os.date())
            log.info("sntp_task_func", "时间同步成功", "UTC时间", os.date("!%c"))
            log.info("sntp_task_func", "时间同步成功", "RTC时钟(UTC时间)", json.encode(rtc.get()))
            log.info("sntp_task_func", "时间同步成功", "本地时间戳", os.time())
            local t = os.date("*t")
            log.info("sntp_task_func", "时间同步成功", "本地时间os.date() json格式", json.encode(t))
            log.info("sntp_task_func", "时间同步成功", "本地时间os.date(os.time())", os.time(t))

            -- 正常使用, 一小时一次, 已经足够了, 甚至1天一次也可以
            sys.wait(3600000)
        --同步失败
        else
            log.info("sntp_task_func", "时间同步失败")
            -- 10秒后重新发起同步动作
            sys.wait(10000)
        end
    end
end

--创建并且启动一个task
--运行这个task的主函数sntp_task_func
sys.taskInit(sntp_task_func)

