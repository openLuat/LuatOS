--[[
@module  auto_dump_udp_srv
@summary 自动上报异常日志到自建udp服务器功能模块
@version 1.0
@date    2025.09.3
@author  孟伟
@usage
本功能模块演示的内容为：
自动上报异常日志到自建udp服务器功能
自动上报异常日志到自建udp服务器，如果是系统异常日志，则会在重启后自动上报，如果是用户写入调试日志，则周期性上报。
使用此功能时需要注意的是，自己的udp服务器收到上报的dump日志时，需要回复一个大写的"OK"来通知模组服务器收到消息了，不然会重复发送，并且也不会删除已发送的日志
]]


local function test_user_log()
    -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
    while not socket.adapter(socket.dft()) do
        log.warn("auto_dump_udp_srv_task_func", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        sys.waitUntil("IP_READY", 1000)
    end
    -- 下面演示自动发送异常日志到自建udp服务器，如果是系统异常日志，则会在重启后自动上报，如果是用户写入调试日志，则周期性上报。
    errDump.config(true,600,nil,nil,"112.125.89.8",47539)
    while true do
        sys.wait(15000)
        -- 上报用户调试日志
        errDump.record("测试一下用户的调试日志记录功能")
    end
end

--故意写错用来触发系统异常日志记录
local function test_error_log()
    sys.wait(60000)
    --故意写错代码死机
    lllllllllog.info("此处使用一个不存在的库文件，导致出现异常")
end

 -- 启动errdemp测试任务
sys.taskInit(test_user_log)
--启动错误函数任务
sys.taskInit(test_error_log)
