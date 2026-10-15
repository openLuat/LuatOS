--[[
@module  netdrv_wifi
@summary "WIFI STA网卡"驱动模块（airlink_wifi / 外挂 Air6205 + 断网自愈）
@version 2.0
@date    2026.09.27
@author  王城钧
@usage
本文件为WIFI STA网卡驱动模块，核心业务逻辑为：
1、通过exnetif.set_priority_order配置airlink_wifi网卡；
   exnetif内部自动完成WiFi硬件初始化和airlink桥接初始化；
2、和WIFI路由器之间的连接状态发生变化时，在日志中进行打印；
3、断网自愈：详见下方 net_recover_task 的注释。

本文件没有对外接口，直接在其他功能模块中require "netdrv_wifi"就可以加载运行；
]]

local exnetif = require "exnetif"

-- ==================== 网卡参数 ====================

-- Air6205 的 EN(GPIO57)：拉低使能、拉高断电
local AIR6205_EN_PIN = 57
local WIFI_SSID = "书房"
local WIFI_PASSWORD = "12345678"

-- 网卡配置（硬复位后重新初始化要复用同一份参数）
local function build_netif_config()
    return {
        {
            airlink_wifi = {
                auto_socket_switch = false,
                airlink_type = airlink.MODE_UART,
                airlink_uart_id = 3,
                airlink_uart_baud = 2000000, -- 必须与6205模组端一致(固定2M)，不可更改
                ssid = WIFI_SSID,
                password = WIFI_PASSWORD
            }
        }
    }
end

-- ==================== 断网自愈 ====================
-- 前提：断链后底层不会自行恢复，脚本层也没有重建链路的手段，实际恢复只能靠整机重启。
--   链路特征：外挂 Air6205 走 airlink over UART3，大帧（约 1.4KB）会导致
--   uart3 err → "airlink 数据长度错误" → "airlink link timeout, set link down" → IP_LOSE。
--   脚本层无法重建链路的原因：Lua 层 airlink.stop() 为空实现；C 层 stop_uart 不关 UART、
--   不重建任务；exnetif 的 CTRL_UPDOWN 仅 CH390H 以太网实现，airlink(WHALE) 无 ctrl 回调。
--   故硬复位 6205 + 重新 set_priority_order() 后，日志仍是
--   "uart3 is opened!" / "airlink task 已经启动过了" / "UART TX/RX任务已经启动过了!!!"，
--   即 UART3 与 airlink 任务都没有重建 → MAX_HARD_RESTART 只取 1 次，恢复仍靠整机重启。
-- 策略（三层递进）：
--   ① IP_LOSE 后 30s 仍未恢复 → 硬复位 Air6205（GPIO57 断电→上电）+ 重新初始化网卡，只试 1 次；
--   ② 再等 15s 仍无网络 → 在业务空闲时（人脸识别/存取件都不忙）整机重启，最多 5 次，防重启风暴；
--   ③ 开机 90s 从未拿到 IP（约等于一直连不上）同样进入自愈流程。
--   网络恢复（IP_READY）后自动清零计数，自愈任务退出。
local LOSE_WAIT_MS = 30000           -- IP_LOSE 后等多久开始自愈
local RESTART_WAIT_MS = 15000        -- 硬复位后等多久判定仍然失败
local MAX_HARD_RESTART = 1           -- 硬复位模组次数上限
local MAX_REBOOT = 5                 -- 最多整机重启次数
local FIRST_CONNECT_WAIT_MS = 90000  -- 开机后多久仍未联网就开始自愈

local net_ready = false              -- 当前是否有 IP（由 IP_READY / IP_LOSE 维护）
local recovering = false             -- 自愈任务是否在跑（防重入）
local recover_give_up = false        -- 已达自愈上限，放弃自动恢复
local hard_restart_count = 0
local reboot_count = 0

-- 是否允许整机重启：存取件业务与人脸识别都必须空闲
local function can_reboot_now()
    local ok_biz, busy = pcall(function()
        return require("ecbusiness").is_busy()
    end)
    if ok_biz and busy then
        return false, "存取件业务进行中"
    end
    local ok_face, face_busy = pcall(function()
        return require("face_manager").is_busy()
    end)
    if ok_face and face_busy then
        return false, "人脸识别进行中"
    end
    return true
end

-- 硬复位 Air6205 并重新初始化网卡
local function airlink_6205_restart()
    hard_restart_count = hard_restart_count + 1
    log.warn("netdrv_wifi", "网络未恢复，硬复位 Air6205（第 "
             .. hard_restart_count .. "/" .. MAX_HARD_RESTART .. " 次）")
    gpio.setup(AIR6205_EN_PIN, 1)   -- 断电（高电平）
    sys.wait(300)
    gpio.setup(AIR6205_EN_PIN, 0)   -- 重新拉低使能
    sys.wait(2000)                  -- 等 6205 启动 + airlink 重新握手
    local ok, err = pcall(function()
        exnetif.set_priority_order(build_netif_config())
    end)
    log.info("netdrv_wifi", "重新初始化网卡:", tostring(ok), tostring(err))
end

-- 网络自愈任务（IP_LOSE 或开机未联网时启动）
local function net_recover_task()
    sys.wait(LOSE_WAIT_MS)
    while not net_ready do
        if hard_restart_count < MAX_HARD_RESTART then
            airlink_6205_restart()
            sys.wait(RESTART_WAIT_MS)
        elseif reboot_count < MAX_REBOOT then
            local idle, why = can_reboot_now()
            if not idle then
                log.warn("netdrv_wifi", "网络未恢复，但" .. tostring(why) .. "，等业务空闲再重启")
                sys.wait(5000)
            else
                reboot_count = reboot_count + 1
                log.warn("netdrv_wifi", "网络自愈失败，整机重启恢复（第 "
                         .. reboot_count .. "/" .. MAX_REBOOT .. " 次）")
                sys.wait(500)
                rtos.reboot()
            end
        else
            log.error("netdrv_wifi", "网络自愈已达上限（硬复位 " .. MAX_HARD_RESTART
                      .. " 次 + 整机重启 " .. MAX_REBOOT .. " 次），停止自动恢复，等待人工处理")
            recover_give_up = true
            recovering = false
            return
        end
    end
    log.info("netdrv_wifi", "网络已恢复，退出自愈任务（本次硬复位 " .. hard_restart_count .. " 次）")
    recovering = false
end

-- 启动自愈（防重入；已恢复或已放弃时不启动）
local function start_recover(reason)
    if recovering or net_ready or recover_give_up then
        return
    end
    recovering = true
    log.warn("netdrv_wifi", "启动网络自愈任务（原因：" .. tostring(reason) .. "）")
    sys.taskInit(net_recover_task)
end

-- ==================== 状态回调 ====================

-- IP就绪回调
local function ip_ready_func(ip, adapter)
    if adapter == socket.LWIP_STA then
        -- 在位置1和2设置自定义的DNS服务器ip地址：
        -- "223.5.5.5"，这个DNS服务器IP地址是阿里云提供的DNS服务器IP地址；
        -- "114.114.114.114"，这个DNS服务器IP地址是国内通用的DNS服务器IP地址；
        -- 可以加上以下两行代码，在自动获取的DNS服务器工作不稳定的情况下，这两个新增的DNS服务器会使DNS服务更加稳定可靠；
        -- 如果使用专网卡，不要使用这两行代码；
        -- 如果使用国外的网络，不要使用这两行代码；
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")

        net_ready = true
        hard_restart_count = 0    -- 网络已恢复：清零自愈计数，下次断网重新计数
        reboot_count = 0
        log.info("netdrv_wifi.ip_ready_func", "IP_READY", socket.localIP(socket.LWIP_STA))
    end
end

-- IP丢失回调
local function ip_lose_func(adapter)
    if adapter == socket.LWIP_STA then
        net_ready = false
        log.warn("netdrv_wifi.ip_lose_func", "IP_LOSE")
        start_recover("IP_LOSE")
    end
end

--WIFI联网成功（做为STATION成功连接AP，并且获取到了IP地址）后，内核固件会产生一个"IP_READY"消息
--各个功能模块可以订阅"IP_READY"消息实时处理WIFI联网成功的事件
--也可以在任何时刻调用socket.adapter(socket.LWIP_STA)来获取WIFI网络是否连接成功

--WIFI断网后，内核固件会产生一个"IP_LOSE"消息
--各个功能模块可以订阅"IP_LOSE"消息实时处理WIFI断网的事件
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)

-- WiFi STA状态事件回调
local function wifi_sta_func(evt, data)
    -- evt 可能的值有: "CONNECTED", "DISCONNECTED"
    -- 当evt=CONNECTED, data是连接的AP的ssid, 字符串类型
    -- 当evt=DISCONNECTED, data断开的原因, 整数类型
    log.info("收到STA事件", evt, data)
end
sys.subscribe("WLAN_STA_INC", wifi_sta_func)

-- 初始化WiFi网卡任务
local function netdrv_wifi_task_func()
    -- 硬件使能：Air6205的EN(GPIO57)为拉低有效，此处手动拉低使能模块
    -- 注意：不能把airlink_wifi_en_pin传给exnetif，否则库内部会拉高EN(其默认逻辑为拉高使能)，
    --       导致拉低有效的硬件上模块被禁用，airlink握手永远无响应
    gpio.setup(AIR6205_EN_PIN, 0) -- 输出低电平，使能Air6205模块
    log.info("Air6205 EN拉低使能", "pin=" .. AIR6205_EN_PIN)
    sys.wait(100) -- 等待6205模组上电稳定后再初始化airlink

    -- 配置airlink WiFi单网卡，exnetif.set_priority_order使用的网卡编号为socket.LWIP_STA
    -- ssid/password 为要连接的WiFi路由器信息（仅支持2.4G，不支持5G）
    exnetif.set_priority_order(build_netif_config())

    -- 首次联网看门狗：开机后一直连不上（从未 IP_READY）也要能自愈
    sys.taskInit(function()
        sys.wait(FIRST_CONNECT_WAIT_MS)
        if not net_ready then
            start_recover("开机 " .. (FIRST_CONNECT_WAIT_MS / 1000) .. " 秒仍未联网")
        end
    end)
end

-- 启动网卡初始化任务（exnetif.set_priority_order 需在 task 中调用）
sys.taskInit(netdrv_wifi_task_func)
