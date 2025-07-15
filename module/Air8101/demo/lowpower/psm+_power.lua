--[[
@module  psm+_power
@summary psm+超低功耗模式主应用功能模块 
@version 1.0
@date    2025.07.01
@author  陈取德
@usage
本文件为psm+超低功耗模式主应用功能模块，核心业务逻辑为：
1、进入低功耗模式
2、判断是否在低功耗模式下连接网络和发送平台心跳包
使用前请根据需要，变更功能变量。条件不同，功耗体现不同。
本文件没有对外接口，直接在main.lua中require "psm+_power"就可以加载运行；
]] --
----是否需要连接WIFI，测试连接网络状态下功耗--------------------------------------
local wifi_mode = true -- true 需要   --false 不需要
-------------------------------------------------------------------------------

-----是否需要保持服务器心跳------------------------------------------------------
local tcp_mode = true -- true 需要，设置下方心跳包。    --false 不需要，不需要设置心跳包。
local tcp_heartbeat = 5 -- PSM+模式心跳包，单位（分钟），输入 1 为 一分钟一次心跳包。
local heart_data = string.rep("1234567890", 3) -- 心跳包数据内容，可自定义。
-------------------------------------------------------------------------------

-- 定义send_result函数用于获取tcp_client_sender中的信息发送是否成功
function send_result(a1, b1)
    log.info("发送状态 :", a1, b1)
    -- 获取tcp_client_sender发送状态后推送信息解除psm_power_func()的sys.waitUntil挂起状态。并返回发送状态a1。
    sys.publish("send_success", a1, b1)
end

-- 定义一个表，将回调函数放在表中，因为tcp_client_sender处理回调函数时考虑到带参执行，所以要将函数和参数都放在表里
local send_result_func = {
    func = send_result
}

function psm_power_func()
    log.info("开始测试PSM+模式功耗。")
    -- 判断是否连接WIFI，请注意WIFI账号密码是否正确。
    if wifi_mode then
        -- 导入WIFI_app功能，自动运行连接WIFI。
        require "wifi_app"
        -- 判断是否连接TCP平台。
        if tcp_mode then
            -- 导入tcp客户端收发功能模块，运行tcp客户端连接，自动处理TCP收发消息。
            require "tcp_client_main"
            while not socket.adapter(socket.LWIP_STA) do
                log.warn("tcp_client_main_task_func", "wait IP_READY")
                -- 在此处阻塞等待WIFI连接成功的消息"IP_READY"，避免联网过快，丢失了"IP_READY"信息而导致一直被卡住。
                -- 或者等待30秒超时退出阻塞等待状态
                sys.waitUntil("IP_READY", 30000)
            end
            -- 推送"SEND_DATA_REQ"消息，该消息为tcp_client_sender的接口，带上tag和信息还有回调函数，可以实现自动发送和发送状态获取。
            sys.publish("SEND_DATA_REQ", "timer", heart_data, send_result_func)
            -- 通过变量获取回调函数在tcp_client_sender中获取的发送状态。
            -- 第一个值为sys.waitUntil的结果，是否信息唤醒。
            -- 第二个值为发送是否成功
            -- 第三个值为回调函数带的参数
            local _, a, b = sys.waitUntil("send_success")
            -- 通过发送状态判断发送是否成功，并打印变量 a 的赋值
            if a then
                log.info("发送成功！", a)
            else
                log.info("发送失败！", a)
            end
            -- 进入PSM+前需要手动断开AP链接，不然无法正常进入PSM+
            wlan.disconnect()
            -- 等待断网事件确定已经断开AP
            sys.waitUntil("IP_LOSE", 5000)
            -- 判断完有没有发送成功后都进入PSM+模式，减少功耗损耗。
            -- 配置dtimerStart唤醒定时器，根据预设时间唤醒Air8101上传心跳信息。
            pm.dtimerStart(0, tcp_heartbeat * 60 * 1000)
            -- 定完定时器即可进入PSM+，执行到这条代码后，CPU关机，后续代码不会执行。
            pm.power(pm.WORK_MODE, 3)
        else
            -- 进入PSM+前需要手动断开AP链接，不然无法正常进入PSM+
            wlan.disconnect()
            -- 等待断网事件确定已经断开AP
            sys.waitUntil("IP_LOSE", 5000)
            -- 执行到这条代码后，CPU关机，后续代码不会执行。
            pm.power(pm.WORK_MODE, 3)
        end
    else
        -- 判断不需要连WIFI，直接进入PSM+
        -- 执行到这条代码后，CPU关机，后续代码不会执行。
        pm.power(pm.WORK_MODE, 3)
    end
end

sys.taskInit(psm_power_func)
