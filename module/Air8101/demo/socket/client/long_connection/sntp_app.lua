--[[
@module  sntp_app
@summary sntp时间同步应用功能模块 
@version 1.0
@date    2025.07.01
@author  朱天华
@usage
本文件为sntp时间同步应用功能模块，核心业务逻辑为：
1、连接ntp服务器进行时间同步；
2、如果同步成功，1小时之后重新发起同步动作；
3、如果同步失败，10秒钟之后重新发起同步动作；

本文件没有对外接口，直接在main.lua中require "sntp_app"就可以加载运行；
]]

-- sntp时间同步的任务处理函数
local function sntp_task_func() 

    while true do
        -- 如果WIFI还没有连接成功，一直在这里循环等待
        while not socket.adapter(socket.dft()) do
            log.warn("sntp_task_func", "wait IP_READY")
            -- 在此处阻塞等待WIFI连接成功的消息"IP_READY"
            -- 或者等待30秒超时退出阻塞等待状态
            sys.waitUntil("IP_READY", 30000)
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

