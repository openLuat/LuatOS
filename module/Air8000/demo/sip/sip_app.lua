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
]]

local exsip = require "exsip"
local audio_drv = require "audio_drv"

local sip_app = {}

local SIP_CONFIG = {
    sip_server_addr = "180.152.6.34",
    sip_server_port = 8910,
    sip_domain = "180.152.6.34",
    sip_username = "100001",
    sip_password = "Mm123..",
    -- sip_transport = exsip.TRANSPORT_TCP,
    sip_transport = exsip.TRANSPORT_UDP,
    auto_answer = true,
    --4G
    -- adapter = nil,
    --WIFI
    -- adapter = socket.LWIP_STA,
    --以太网
    adapter = socket.LWIP_ETH,
}

local function sip_callback(event, arg1, arg2, arg3)
    if event == "register" then
        local status, data = arg1, arg2
        if status then
            log.info("sip", "注册成功，有效期:", data.expires)
        else
            log.error("sip", "注册失败")
        end
    elseif event == "ready" then
        log.info("sip", "SIP 服务已就绪")
    elseif event == "call" then
        local sub_event, data = arg1, arg2
        if sub_event == "incoming" then
            log.info("sip", "来电:", data.from)
            local call_result = exsip.get_current_call()
            if call_result then
                log.info("来电号码:", call_result.from)
            end
        elseif sub_event == "ringing" then
            log.info("sip", "对方响铃中")
        elseif sub_event == "connected" then
            log.info("sip", "通话已建立")
        elseif sub_event == "ended" then
            log.info("sip", "通话已结束")
        end
    elseif event == "media" then
        local sub_event, session = arg1, arg2
        if sub_event == "ready" then
            log.info("sip", "媒体通道就绪", session.remote_ip .. ":" .. session.remote_port)
        elseif sub_event == "stop" then
            log.info("sip", "媒体通道已关闭")
        end
    elseif event == "message" then
        local sub_event, data = arg1, arg2
        if sub_event == "rx" then
            log.info("sip", "收到消息:", data.from, data.body)
        elseif sub_event == "sent" then
            log.info("sip", "消息已发送到:", data.to)
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
    elseif event == "error" then
        local action, payload = arg1, arg2
        log.error("sip", "错误:", action, payload.event, payload.param)
    end
end

function sip_app.init()
    exsip.on(sip_callback)

    sys.taskInit(function()
        if not (rtos and rtos.bsp and rtos.bsp() and rtos.bsp():find("PC")) then
            gpio.setup(147, 1)
        end
        sys.wait(3000)

        if audio_drv.init() then
            log.info("sip_app", "音频驱动初始化成功")
        end

        if SIP_CONFIG.sip_server_addr == "xxx.xxx.xxx.xxx" then
            log.error("sip", "请先配置 SIP 服务器地址和账号密码")
            return
        end

        log.info("sip", "检查网络状态...")
        if socket.adapter(SIP_CONFIG.adapter) then
            log.info("sip", "网络已就绪（已连接）")
        else
            log.info("sip", "等待网络连接...")
            sys.waitUntil("IP_READY")
            log.info("sip", "网络已就绪")
        end

        log.info("sip", "开始初始化 SIP...")
        if exsip.init(SIP_CONFIG) then
            log.info("sip", "配置完成，开始启动 SIP...")
            if exsip.start() then
                log.info("sip", "启动完成，等待注册...")
            else
                log.error("sip", "启动失败")
            end
        else
            log.error("sip", "初始化失败")
        end

        if not (rtos and rtos.bsp and rtos.bsp() and rtos.bsp():find("PC")) then
            gpio.setup(0, function()
                local state = exsip.dial(100000)
                if state then
                    log.info("exsip", "拨号成功!!!!!!!")
                else
                    log.warn("exsip", "拨号失败")
                end
            end, gpio.PULLDOWN, gpio.RISING)
        end

    end)
end

return sip_app
