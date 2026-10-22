--[[
@module  call_service
@summary 通话后端适配层：优先腾讯云 IoT 微信通话（tc_iot），固件/配置不可用时降级为本地模式
@version 1.0.0
@date    2026.10.21
@usage
  call_service.start()                        -- main.lua 里调用一次
  call_service.dial("voice"|"video", call_id) -- 返回 ok, err；err=="local" 表示走本地演示
  call_service.answer(room_id)  / call_service.reject(room_id) / call_service.hangup()
  call_service.set_media(muted, speaker, camera)

  统一事件：sys.publish("CALL_SERVICE_EVENT", evt, id, code)
    evt = "incoming" / "talking" / "ended" / "failed"
  就绪状态：sys.publish("CALL_SERVICE_READY", "tc"|"local")
  摄像头：tc 模式下由本模块推送 "USB_CAM" 状态，并广播 "CAM_OWNER","tc"
]]

local cfg  = require "hw_config"
local net  = require "net_mgr"

local M = {
    backend = "local",     -- local / tc
    ready   = false,
    camera  = "unavailable",
}

local tc
local provisioning
local inited = false

-- 当前外呼登记信息（挂断时上报 ENDED 用）
local current_bid, current_user, current_video

local CAM_MAP = {
    ready       = "online",
    warming     = "warming",
    off         = "offline",
    failed      = "offline",
    stalled     = "offline",
    unavailable = "unsupported",
}

local function evt(name, id, code)
    sys.publish("CALL_SERVICE_EVENT", name, id, code)
end

local function backend_id()
    return string.format("dev-%d-%d", os.time(), mcu.ticks() % 1000000)
end

-- 设备主动外呼前必须向后端登记，小程序才会收到来电（与 demo 的 device-call 一致）
-- call_status_url 形如 http://host/api/twecall/device-status，登记地址自动换成 .../device-call
local function register_outgoing(bid, user, video, state)
    local p = provisioning
    if not p or type(p.call_status_url) ~= "string" or p.call_status_url == "" then
        return true          -- 未配置后端：直接走 SDK 呼叫
    end

    local prefix = p.call_status_url:match("^(.+)/device%-status$")
    if not prefix then
        log.warn("call_service", "call_status_url 必须以 /device-status 结尾")
        return false
    end

    local http, json = _G.http, _G.json
    if not (http and json) then
        log.warn("call_service", "固件无 http/json 库，跳过外呼登记")
        return true
    end

    local ok, code = pcall(function()
        return http.request("POST", prefix .. "/device-call",
            { ["content-type"] = "application/json" },
            json.encode({
                deviceToken = p.call_status_token,
                callId      = bid,
                openId      = user,
                roomType    = video and "video" or "voice",
                state       = state or "RINGING",
            }), { timeout = 3000 }).wait()
    end)
    if not ok then
        log.warn("call_service", "外呼登记异常:", tostring(code))
        return false
    end
    log.info("call_service", "外呼登记返回", state or "RINGING", tostring(code))
    return type(code) == "number" and code >= 200 and code < 300
end

-- 取第一个已授权微信用户（设备主动呼出时使用）
local function pick_user()
    if not (tc and tc.voip_get_user_list) then return nil end
    local ok, total, users = pcall(tc.voip_get_user_list, 0, 10)
    if not ok or type(users) ~= "table" then return nil end

    -- 指定了 call_open_id 就精确匹配
    local wanted = provisioning and provisioning.call_open_id
    if type(wanted) == "string" and #wanted > 0 then
        for _, id in ipairs(users) do
            if id == wanted then return id end
        end
        log.warn("call_service", "指定用户不在授权列表", wanted)
        return nil
    end

    if #users > 0 and type(users[1]) == "string" and #users[1] > 0 then
        if #users > 1 then
            log.warn("call_service", "存在多位微信用户，默认呼叫第一个，建议配置 call_open_id")
        end
        return users[1]
    end

    log.warn("call_service", "授权用户为空", tostring(total))
    return nil
end

local function camera_loop()
    while true do
        if M.backend == "tc" and tc and tc.camera_status then
            local ok, st = pcall(tc.camera_status)
            if ok and st then
                M.camera = st
                sys.publish("USB_CAM", CAM_MAP[st] or "offline")
            end
        end
        sys.wait(1000)
    end
end

-- tc_iot 是固件内置扩展库，不能随脚本打包。
-- 这里用动态模块名加载，避免 Luatools 静态扫描 require 时提示“缺少 tc_iot.lua”
local function load_tc_sdk()
    if type(_G.tc_iot) == "table" then
        return _G.tc_iot
    end
    local mod = "tc" .. "_iot"
    local ok, m = pcall(require, mod)
    if ok and type(m) == "table" then
        return m
    end
    return nil
end

local function connect_tc()
    local sdk = load_tc_sdk()
    if not sdk then
        log.warn("call_service", "固件未包含 tc_iot，通话使用本地模式")
        return false
    end
    tc = sdk

    local cok, c = pcall(require, "tc_iot_config")
    if not cok or type(c) ~= "table" then
        log.warn("call_service", "缺少 tc_iot_config.lua，通话使用本地模式")
        return false
    end
    for _, k in ipairs({ "product_id", "device_name", "device_secret", "model_id", "wxa_appid" }) do
        if type(c[k]) ~= "string" or c[k] == "" then
            log.warn("call_service", "tc_iot_config 缺少", k)
            return false
        end
    end
    provisioning = c

    -- 确定使用 tc 后端后，立即通知 usb_cam 让出摄像头控制权
    sys.publish("CAM_OWNER", "tc")

    -- 等 net_mgr 连上 WiFi（最多 45s）
    local wait_s = 0
    while not net.ready and wait_s < 45 do
        sys.wait(1000)
        wait_s = wait_s + 1
    end

    -- 兜底：用 tc_iot_config 里的热点再连一次（与 demo 行为一致）
    if not net.ready and type(c.wifi_ssid) == "string" and #c.wifi_ssid > 0 and wlan then
        log.warn("call_service", "net_mgr 未连上，使用 tc_iot_config 热点重连", c.wifi_ssid)
        pcall(wlan.init)
        pcall(wlan.setMode, wlan.STATION)
        pcall(wlan.connect, c.wifi_ssid, c.wifi_password or "", 1)
        wait_s = 0
        while not net.ready and wait_s < 30 do
            sys.wait(1000)
            wait_s = wait_s + 1
        end
    end

    if not net.ready then
        log.warn("call_service", "WiFi 未连接，微信通话不可用")
        return false
    end

    -- 腾讯 voip 需要正确时间（NTP 回包后可能还要再校一次）
    if socket and socket.sntp then
        sys.subscribe("NTP_UPDATE", function()
            if tc then pcall(tc.set_time, os.time()) end
        end)
        socket.sntp()
        sys.waitUntil("NTP_UPDATE", 10000)
    end
    pcall(tc.set_time, os.time())

    -- 初始化设备接入（失败带次数上限，避免死循环刷日志）
    local retry = 0
    while tc.init(c.product_id, c.device_name, c.device_secret, c.region or "china") ~= 0 do
        retry = retry + 1
        if retry >= 6 then
            log.error("call_service", "tc.init 失败，检查 product_id/device_secret")
            return false
        end
        sys.wait(5000)
    end

    while not tc.online() do sys.wait(1000) end

    retry = 0
    while tc.voip_init(c.voip_type or 1, c.data_path or "/tc_iot/voip", c.model_id, c.wxa_appid) ~= 0 do
        retry = retry + 1
        if retry >= 6 then
            log.error("call_service", "tc.voip_init 失败，检查 model_id/wxa_appid")
            return false
        end
        sys.wait(5000)
    end

    M.backend = "tc"
    M.ready   = true
    inited    = true

    -- 摄像头交给 tc 管理，usb_cam 停止自行探测
    sys.publish("CAM_OWNER", "tc")
    sys.publish("CALL_SERVICE_READY", "tc")

    if tc.camera_warmup then
        local ret = tc.camera_warmup()
        if ret ~= 0 then log.warn("call_service", "camera_warmup", ret) end
    end

    log.info("call_service", "腾讯微信通话已就绪")
    sys.taskInit(camera_loop)
    return true
end

--- 启动通话服务（异步）
function M.start()
    sys.taskInit(function()
        -- 由 main 在 UI 建好后调用，这里只让首帧先刷出来
        sys.wait(200)
        if not cfg.wechat.enable then
            log.info("call_service", "微信通话已关闭，使用本地演示")
            sys.publish("CAM_OWNER", "self")
            sys.publish("CALL_SERVICE_READY", "local")
            return
        end
        if connect_tc() then return end
        -- tc 不可用：把摄像头交还 usb_cam 自行探测
        M.backend = "local"
        sys.publish("CAM_OWNER", "self")
        sys.publish("CALL_SERVICE_READY", "local")
    end)
end

--- 发起呼叫
-- @return boolean ok, string|number err  err == "local" 表示没有 tc 后端
function M.dial(kind, call_id)
    if M.backend ~= "tc" or not M.ready or not tc then
        return false, "local"
    end
    if tc.voip_is_busy then
        local bok, busy = pcall(tc.voip_is_busy)
        if bok and busy then return false, "busy" end
    end

    local user = pick_user()
    if not user then
        return false, "no_user"
    end

    local video = (kind == "video")
    local bid = backend_id()

    -- 先登记再呼叫：小程序靠这个接口弹出"设备来电"
    if not register_outgoing(bid, user, video, "RINGING") then
        if cfg.wechat.require_register then
            log.warn("call_service", "外呼登记失败，严格模式取消呼叫")
            return false, "register"
        end
        log.warn("call_service", "外呼登记失败，继续直接呼叫（小程序可能没有来电提示）")
    end

    if tc.media_controls then
        -- 注意：C 层按布尔解析，必须传 true/false，传 0 会被当成 true
        pcall(tc.media_controls, false, true, video)
    end

    current_bid, current_user, current_video = bid, user, video

    local okc, ret = pcall(tc.voip_call, user, bid, video and 1 or 0, 0, call_id)
    if not okc then
        log.error("call_service", "voip_call 异常", ret)
        return false, "sdk_error"
    end
    if ret ~= 0 then
        return false, ret
    end
    log.info("call_service", "voip_call", kind, user)
    return true
end

--- 接听来电
function M.answer(room_id)
    if M.backend ~= "tc" or not tc then return true end
    local okj, ret = pcall(tc.voip_join, room_id, 0)
    if not okj then
        log.error("call_service", "voip_join 异常", ret)
        return false, "sdk_error"
    end
    log.info("call_service", "voip_join answer", room_id, ret)
    return ret == 0, ret
end

--- 拒接来电
function M.reject(room_id)
    if M.backend ~= "tc" or not tc then return true end
    pcall(tc.voip_join, room_id, 11)
    log.info("call_service", "voip_join reject", room_id)
    return true
end

--- 挂断
function M.hangup()
    if M.backend ~= "tc" or not tc then return end
    if tc.voip_hangup then
        pcall(tc.voip_hangup)
    end

    -- 通知后端通话结束，避免小程序侧状态残留
    local bid, user, video = current_bid, current_user, current_video
    current_bid, current_user = nil, nil
    if bid then
        sys.taskInit(function()
            register_outgoing(bid, user, video, "ENDED")
        end)
    end
end

--- 音视频控制（静音 / 免提 / 摄像头）
function M.set_media(muted, speaker, camera)
    if M.backend ~= "tc" or not tc or not tc.media_controls then return 0 end
    -- C 层按布尔解析；显式转 true/false，避免 0 被当作 true
    local ret = tc.media_controls(muted == true, speaker == true, camera == true)
    log.info("call_service", "media_controls", muted, speaker, camera, ret)
    return ret
end

function M.is_ready()
    return M.ready and M.backend == "tc"
end

-- ==================== tc_iot 事件 ====================
sys.subscribe("TC_IOT_INCOMING", function(id)
    if type(id) ~= "string" or id == "" then return end
    evt("incoming", id)
end)

sys.subscribe("TC_IOT_INCOMING_BUSY", function(id)
    if type(id) ~= "string" or id == "" or not tc then return end
    pcall(tc.voip_join, id, 9)
end)

sys.subscribe("TC_IOT_TALKING", function(id)
    evt("talking", id)
end)

sys.subscribe("TC_IOT_CALL_ENDED", function(id)
    evt("ended", id, "remote")
end)

sys.subscribe("TC_IOT_CANCELLED", function(id)
    evt("ended", id, "cancelled")
end)

sys.subscribe("TC_IOT_CALL_FAILED", function(id, code)
    evt("failed", id, code)
end)

sys.subscribe("TC_IOT_MEDIA_ERROR", function(id)
    evt("ended", id, "media_error")
end)

return M
