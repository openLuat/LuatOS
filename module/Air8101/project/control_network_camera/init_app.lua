--[[
@module  init_app
@summary 网络摄像头控制系统初始化模块
@version 1.0
@date    2025.12.30
@author  拓毅恒
@usage
初始化网络连接和SD卡挂载
功能：自动连接指定的WiFi网络，并在联网成功后挂载SD卡，为摄像头控制功能提供基础环境。

本文件没有对外接口，直接在main.lua中require "init_app"就可以加载运行。
]]

-- 挂载SD卡
local function sdcard_mount_task()
    local mount_result
    -- gpio13为8101TF卡的供电控制引脚，在挂载前需要设置为高电平，不能省略
    gpio.setup(13, 1)
    mount_result = fatfs.mount(fatfs.SDIO, "/sd", 24 * 1000 * 1000)
    log.info("SDCARD", "挂载SD卡结果:", mount_result)
end

-- Air8101 连接网络
local function wifi_connect_task()
    -- 连接WIFI网络
    log.info("执行STA连接操作")
    -- 模组需和摄像头连接同一网络
    wlan.connect("@PHICOMM_75", "li19760705")
    -- 等待wifi_sta网络连接成功
    while not socket.adapter(socket.LWIP_STA) do
        -- 在此处阻塞等待wifi连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        sys.waitUntil("IP_READY", 1000)
    end
    -- 联网成功后发送消息
    sys.publish("WIFI_CONNECT_OK")
    -- 开始挂载SD卡
    sdcard_mount_task()
end

sys.taskInit(wifi_connect_task)