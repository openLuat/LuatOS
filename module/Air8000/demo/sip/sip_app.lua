--[[
@module  sip_app
@summary SIP/VoIP 电话功能模块
@version 1.0
@date    2026.04.15
@usage
本模块包含SIP/VoIP电话的所有功能实现：
- SIP配置
- 事件回调处理
- 主业务逻辑

本模块被 require 时自动执行初始化
]]

local exsip = require "exsip"
local audio_drv = require "audio_drv"

local sip_app = {}

local g_sip_started = false
local g_network_ready = false
local g_net_switch_debounce_timer = nil

local SIP_CONFIG = {
    sip_server_addr = "180.152.6.34",
    sip_server_port = 8910,
    sip_domain = "180.152.6.34",
    sip_username = "100001",
    sip_password = "Mm123..",
    -- sip_transport = exsip.TRANSPORT_TCP,
    sip_transport = exsip.TRANSPORT_UDP,
    auto_answer = true,
}

local function start_sip_service()
    log.info("sip", "start_sip_service called, SIP_CONFIG type:", type(SIP_CONFIG), SIP_CONFIG)

    log.info("sip", "开始初始化 SIP...")
    if exsip.init(SIP_CONFIG) then
        log.info("sip", "配置完成，开始启动 SIP...")
        if exsip.start() then
            log.info("sip", "启动完成，等待注册...")
            -- g_sip_started 会在收到 lifecycle online 事件时设置
        else
            log.error("sip", "启动失败")
        end
    else
        log.error("sip", "初始化失败")
    end
end

local function sip_callback(event, arg1, arg2, arg3)
    if event == "register" then
        local status, data = arg1, arg2
        if status == "ok" then
            log.info("sip", "注册成功，有效期:", data.expires, "SIP响应头:", data.headers)
        elseif status == "failed" then
            log.error("sip", "注册失败")
        end
    elseif event == "ready" then
        log.info("sip", "SIP 服务已就绪")
    elseif event == "call" then
        local sub_event, data = arg1, arg2
        if sub_event == "incoming" then
            log.info("sip", "来电:", data.from,data.call_id,data.uri,data.headers,body,data.remote_sdp)
        elseif sub_event == "ringing" then
            log.info("sip", "对方响铃中")
        elseif sub_event == "connected" then
            log.info("sip", "通话已建立")
        elseif sub_event == "ended" then
            log.info("sip", "通话已结束，结束原因为：",data.reason,"通话对象：",data.dialog)
        end
    elseif event == "media" then
        local sub_event, session = arg1, arg2
        if sub_event == "ready" then
            log.info("sip", "媒体通道就绪", session.remote_ip .. ":" .. session.remote_port)
        elseif sub_event == "stop" then
            log.info("sip", "媒体通道已关闭，关闭原因：",session.reason)
        end
    elseif event == "message" then
        local sub_event, data = arg1, arg2
        if sub_event == "rx" then
            log.info("sip", "收到消息:", data.from, data.body)
        elseif sub_event == "sent" then
            log.info("sip", "消息已发送到:", data.to,"消息内容为：",data.body)
        end
    elseif event == "voip" then
        local sub_event, data = arg1, arg2
        if sub_event == "state" then
            log.info("voip", "状态:", data)
        elseif sub_event == "stats" then
            log.info("voip", "统计 - 发送:", data.tx_packets,
                "接收:", data.rx_packets,
                "丢失:", data.rx_lost)
        elseif sub_event == "error" then
            log.error("voip", "错误:", data)
        end
    elseif event == "lifecycle" then
        local sub_event, data = arg1, arg2
        log.info("sip", "lifecycle event:", sub_event)
        if sub_event == "online" then
            g_sip_started = true
            log.info("sip", "SIP 服务已在线，本地IP地址为：",data.local_ip)
        elseif sub_event == "offline" or sub_event == "stopped" then
            g_sip_started = false
            log.info("sip", "SIP 服务已离线/停止")
        end
    elseif event == "error" then
        local action, payload = arg1, arg2
        log.error("sip", "错误:", action, payload.event, payload.param)
    end
end


local function gpio_dial_callback()
    log.info("sip_app", "BOOT键被按下，尝试拨号")
    if not exsip.isRegistered() then
        log.warn("sip_app", "SIP尚未注册完成，无法拨号")
        return
    end
    local state = exsip.dial(100000)
    if state then
        log.info("exsip", "拨号成功")
    else
        log.warn("exsip", "拨号失败")
    end
end
local function gpio_hangup_callback()
    log.info("sip_app", "PWR键被按下，尝试挂断")
    local state = exsip.hangUp()
    if state then
        log.info("exsip", "挂断成功")
    else
        log.warn("exsip", "挂断失败")
    end
end

local function check_net(net_type, adapter)
    log.info("sip_app", "NETDRV_NETWORK_STATUS", net_type, adapter)
    if net_type then
        -- 有可用网卡了
        g_network_ready = true
        
        -- 如果之前有防抖定时器，先取消
        if g_net_switch_debounce_timer then
            sys.timerStop(g_net_switch_debounce_timer)
            g_net_switch_debounce_timer = nil
        end
        
        log.info("sip_app", "网络已就绪，等待网络稳定...")
        g_net_switch_debounce_timer = sys.timerStart(function()
            g_net_switch_debounce_timer = nil
            
            -- 无论SIP是否在运行，都先停止它（清除状态），然后重新启动
            sys.taskInit(function()
                log.info("sip_app", "准备重启 SIP 服务")
                
                -- 先停止当前的SIP服务
                if g_sip_started or exsip.is_started() then
                    log.info("sip_app", "正在停止 SIP 服务...")
                    exsip.stop()
                    g_sip_started = false
                end
                
                -- 等待 exsip 完全停止
                log.info("sip_app", "等待 SIP 完全停止...")
                local wait_count = 0
                while exsip.is_started() and wait_count < 200 do
                    sys.wait(10)
                    wait_count = wait_count + 1
                end
                log.info("sip_app", "SIP 已停止")
                
                -- 重新启动SIP服务
                log.info("sip_app", "开始重新初始化和启动 SIP 服务")
                start_sip_service()
            end)
        end, 3000)
    else
        -- 没网卡了
        g_network_ready = false
        -- 取消防抖定时器
        if g_net_switch_debounce_timer then
            sys.timerStop(g_net_switch_debounce_timer)
            g_net_switch_debounce_timer = nil
        end
        if g_sip_started then
            log.info("sip_app", "网络断开，停止 SIP")
            exsip.stop()
            g_sip_started = false
        end
    end
end

local function sip_init_task()

    if audio_drv.init() then
        log.info("sip_app", "音频驱动初始化成功")
    end

    if SIP_CONFIG.sip_server_addr == "xxx.xxx.xxx.xxx" then
        log.error("sip", "请先配置 SIP 服务器地址和账号密码")
        return
    end

    log.info("sip", "等待网卡稳定...")
    
    -- 订阅网络状态事件
    sys.subscribe("NETDRV_NETWORK_STATUS", check_net)

    -- 设置按键
    gpio.setup(0, gpio_dial_callback, gpio.PULLDOWN, gpio.RISING)
    gpio.setup(gpio.PWR_KEY, gpio_hangup_callback, gpio.PULLUP, gpio.FALLING)
end

function sip_app.init()
    exsip.on(sip_callback)
    sys.taskInit(sip_init_task)
end

-- 模块被 require 时自动执行初始化
sip_app.init()

return sip_app
