--[[
@module  network_watchdog
@summary 网络环境检测看门狗功能模块
@version 1.0
@date    2026.09.28
@usage
本文件为网络环境检测看门狗功能模块，监控网络环境是否工作正常（设备和服务器双向通信正常，
或者至少单向通信正常），核心业务逻辑为：
1、启动一个网络环境检测看门狗task，等待其他网络应用功能模块来喂狗，如果喂狗超时，则控制软件重启；
2、如何确定"喂狗超时时间"，一般来说，有以下几个原则；
   (1) 先确定一个最小基准值T1，2分钟或者5分钟或者10分钟，这个取值取决于具体项目需求，
       但是不能太短，因为开机后，在网络环境不太好的地方，网络初始化可能需要比较长的时间，
       一般推荐这个值不能小于2分钟；
   (2) 再确定一个和产品业务逻辑有关的一个值T2：
       <1> 本产品的服务器不会定时下发数据给设备，但使用的是tcp长连接，设备通过 excloud 库
           的自动心跳机制，每隔5分钟发送一次心跳，然后服务器会立即回复一个心跳应答包；
       <2> 这种情况下，T2 取 5分钟的大于等于1的倍数(此处取1倍) + 一段时间(10秒钟)，
           即 T2 = 300 + 10 = 310 秒，给网络数据传输过程留够充足的时间；
   (3) 取T1(2分钟)和T2(310秒)的最大值，即为"喂狗超时时间"，本模块取 330 秒；
3、其他网络业务功能模块的喂狗时机：
   (1) 设备收到服务器下发的数据时；
   (2) tcp连接下，设备成功发送数据到服务器时；
   (3) 设备连接成功、认证成功时；
   (4) 本产品 excloud 自动心跳（5分钟一次）发送成功时；
4、本模块可以检测以下两种网络环境异常中的任意一种：
   (1) 网络环境连续超过330秒没有准备就绪；
   (2) tcp连接下，连续330秒没有成功向服务器发送数据，且没有收到服务器下发的数据。

本文件没有对外接口，直接在 main.lua 中 require "network_watchdog" 就可以加载运行；
外部功能模块喂狗时，直接调用 sys.publish("FEED_NETWORK_WATCHDOG")。
]]

-- 喂狗超时时间，单位毫秒（330秒）
local WATCHDOG_TIMEOUT_MS = 330 * 1000

-- 网络环境检测看门狗task处理函数
local function network_watchdog_task_func()
    while true do
        -- 如果等待330秒没有等到"FEED_NETWORK_WATCHDOG"消息，则看门狗超时
        if not sys.waitUntil("FEED_NETWORK_WATCHDOG", WATCHDOG_TIMEOUT_MS) then
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
