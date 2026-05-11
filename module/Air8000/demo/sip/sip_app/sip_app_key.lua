
local g_tag = "sip_app_key"
local g_sip_app_ready = false
local g_sip_incoming = false



local function ready_ind()
    log.info(g_tag, "SIP应用已初始化")
    g_sip_app_ready = true
end

local function lose_ind()
    log.info(g_tag, "SIP应用已断开")
    g_sip_app_ready = false
end



-- POWERKEY键：挂断
local function powerkey_handler()
    log.info(g_tag, "按下POWERKEY键")
    g_sip_incoming = false
    sys.publish("SIP_APP_MAIN_HANGUP_REQ", g_tag)
end

-- BOOT键：呼出/接听
local function boot_key_handler()
    log.info(g_tag, "按下BOOT键")

    if not g_sip_app_ready then
        log.warn(g_tag, "SIP应用未初始化，无法呼出/接听")
        return
    end

    if g_sip_incoming then
        log.info(g_tag, "呼入中，接听")
        sys.publish("SIP_APP_MAIN_ACCEPT_REQ", g_tag)
        g_sip_incoming = false
        return
    end

    sys.publish("SIP_APP_MAIN_DIAL_REQ", g_tag, "100000")
end

local function dial_rsp(tag, success, reason)
    if tag == g_tag then
        if not success then
            log.error(g_tag, "呼出失败，原因：", reason)
        end
    end
end

local function connected_ind()
    log.info(g_tag, "通话建立成功")
    g_sip_incoming = false
end

local function disconnected_ind()
    log.info(g_tag, "通话已断开")
    g_sip_incoming = false
end

local function incoming_ind()
    log.info(g_tag, "呼入中")
    g_sip_incoming = true
end


-- 订阅SIP_APP_MAIN_READY和SIP_APP_MAIN_LOSE消息，用于更新SIP服务可用状态
sys.subscribe("SIP_APP_MAIN_READY", ready_ind)
sys.subscribe("SIP_APP_MAIN_LOSE", lose_ind)

sys.subscribe("SIP_APP_MAIN_DIAL_RSP", dial_rsp)
sys.subscribe("SIP_APP_MAIN_CONNECTED", connected_ind)
sys.subscribe("SIP_APP_MAIN_DISCONNECTED", disconnected_ind)
sys.subscribe("SIP_APP_MAIN_INCOMING", incoming_ind)

-- 设置POWERKEY键
gpio.setup(gpio.PWR_KEY, powerkey_handler, gpio.PULLUP, gpio.FALLING)
gpio.debounce(gpio.PWR_KEY, 200, 1)

-- 设置BOOT键
gpio.setup(0, boot_key_handler, gpio.PULLDOWN, gpio.RISING)
gpio.debounce(0, 200, 1)


-- 启动SIP应用服务
sys.publish("SIP_APP_MAIN_START_REQ", g_tag)
