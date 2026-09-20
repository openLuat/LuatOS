--[[
@module  network_watchdog
@summary 网络环境检测看门狗功能模块
@version 1.0
@date    2026.09.18
@author  孟伟
@usage
参考 Air780EPM/demo/socket/client/long_connection/network_watchdog.lua 实现。
本文件为网络环境检测看门狗功能模块，监控网络环境是否工作正常（设备和服务器双向通信正常），核心业务逻辑为：
1、启动一个网络环境检测看门狗task，等待其他socket网络应用功能模块来喂狗，如果喂狗超时，则控制软件重启；
2、喂狗超时时间确定原则：
   (1) 最小基准值T1：2分钟（网络环境准备就绪预留时间，不能小于2分钟）；
   (2) 业务相关值T2：本项目 1 分钟周期上报电压/工作状态，网络收发频率适中；
       取 T2 = 5 分钟（能接受连续 5 次发送失败的时长）；
   (3) 取 T1 和 T2 的最大值，最终喂狗超时时间 = 5 分钟（300 秒）；
3、喂狗时机（由 aircloud_app 执行）：
   (1) 设备收到服务器下发的数据时；
   (2) TCP 连接下，设备成功发送数据到服务器时；
   (3) TCP 连接成功时（不到万不得已不喂狗，避免掩盖收发数据异常）；

本文件没有对外接口，直接在main.lua中require "network_watchdog"就可以加载运行；
外部功能模块喂狗时，直接调用sys.publish("FEED_NETWORK_WATCHDOG")
]]

-- 网络环境检测看门狗task处理函数
local function network_watchdog_task_func()
    while true do
        -- 如果等待300秒没有等到"FEED_NETWORK_WATCHDOG"消息，则看门狗超时
        if not sys.waitUntil("FEED_NETWORK_WATCHDOG", 300000) then
            log.error("network_watchdog_task_func timeout")
            -- 等待3秒钟，然后软件重启
            sys.wait(3000)
            rtos.reboot()
        end
    end
end

-- 创建并且启动一个task
-- 运行这个task的处理函数network_watchdog_task_func
sys.taskInit(network_watchdog_task_func)
