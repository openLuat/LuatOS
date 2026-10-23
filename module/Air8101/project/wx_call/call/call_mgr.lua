--[[
@module  call_mgr
@summary 通话状态机：呼出 / 来电 / 接听 / 拒接 / 挂断 / 计时 / 静音 / 免提 / 摄像头
@version 1.2.0
@date    2026.10.21
@usage
  call_mgr.dial("voice"|"video")
  call_mgr.answer() / call_mgr.reject() / call_mgr.hangup()
  call_mgr.toggle_mute() / toggle_speaker() / toggle_camera()

  广播：
    CALL_STATE(state, mode, peer)   state = idle/dialing/ringing/connecting/talking
    CALL_TICK(seconds)
    CALL_MEDIA(muted, speaker, camera_on)
    UI_TOAST(text)                  界面提示
]]

local cfg = require "hw_config"
local wx  = require "wx_call"
local svc = require "call_service"

local call = {
    state     = "idle",        -- idle / dialing / ringing / connecting / talking
    mode      = "voice",       -- voice / video
    peer      = cfg.call.peer,
    seconds   = 0,
    muted     = false,
    speaker   = true,
    cam_on    = true,
    call_id   = nil,
    direction = "outgoing",
}

local timer_on = false

-- 通话后端是否已就绪（tc_iot 注册成功）。未就绪时顶栏显示“未就绪”
local svc_ready = false

local function wx_idle()
    wx.set(svc_ready and "idle" or "offline", call.peer)
end

sys.subscribe("CALL_SERVICE_READY", function(backend)
    svc_ready = (backend == "tc")
    if svc_ready then
        log.info("call_mgr", "微信通话后端已就绪")
    else
        log.warn("call_mgr", "微信通话后端不可用（固件无 tc_iot / 凭证未填 / 网络未连）")
    end
    wx_idle()
end)

local function fmt(sec)
    return string.format("%02d:%02d", (sec // 60) % 100, sec % 60)
end

call.fmt = fmt

local function emit()
    sys.publish("CALL_STATE", call.state, call.mode, call.peer)
end

local function emit_media()
    sys.publish("CALL_MEDIA", call.muted, call.speaker, call.cam_on)
end

local function start_timer()
    if timer_on then return end
    timer_on = true
    sys.taskInit(function()
        while call.state == "talking" do
            sys.wait(1000)
            if call.state ~= "talking" then break end
            call.seconds = call.seconds + 1
            sys.publish("CALL_TICK", call.seconds)
        end
        timer_on = false
    end)
end

local function reset()
    call.state   = "idle"
    call.call_id = nil
    call.seconds = 0
    wx_idle()
    emit()
end

-- 本地演示：没有 tc 后端时，延时后自动"接通"，用于界面联调
local function local_demo_connect(delay)
    local id = call.call_id
    sys.taskInit(function()
        sys.wait(delay or 1200)
        if call.call_id ~= id or call.state == "idle" or call.state == "talking" then return end
        call.state   = "talking"
        call.seconds = 0
        wx.set("talking", call.peer)
        emit()
        emit_media()
        start_timer()
    end)
end

--- 发起通话
-- @param mode "voice" | "video"
function call.dial(mode)
    if call.state ~= "idle" then
        sys.publish("UI_TOAST", "请先结束当前通话")
        return false
    end

    mode = (mode == "video") and "video" or "voice"
    call.mode      = mode
    call.direction = "outgoing"
    call.seconds   = 0
    call.muted, call.speaker, call.cam_on = false, true, true
    call.call_id   = string.format("ui-%d-%d", os.time(), mcu.ticks() % 10000)
    call.state     = "dialing"

    wx.set("connecting", call.peer)
    emit()
    emit_media()

    local cid = call.call_id

    -- 拨号要发 HTTP 登记 + SDK 呼叫，必须放到协程里执行：
    -- airui 的点击回调不是协程，http.request().wait() 在那里会立刻失败
    sys.taskInit(function()
        local ok, err = svc.dial(mode, cid)

        if ok then
            -- 60 秒无应答自动挂断
            sys.wait(60000)
            if call.state == "dialing" and call.call_id == cid then
                call.hangup()
                sys.publish("UI_TOAST", "对方无应答")
            end
            return
        end

        -- 等待期间可能已被挂断/已结束，避免误伤新通话
        if call.call_id ~= cid or call.state == "idle" then return end

        if err == "local" then
            if cfg.wechat.local_demo then
                log.info("call_mgr", "本地演示通话（未真正接入微信）", mode)
                local_demo_connect(cfg.call.ring_ms or 1200)
                return
            end
            log.warn("call_mgr", "微信通话未就绪，取消呼叫")
            reset()
            sys.publish("UI_TOAST", "微信通话未就绪：检查 tc_iot 固件与 tc_iot_config")
            return
        end

        log.warn("call_mgr", "呼叫失败", err)
        local msg = "呼叫失败：" .. tostring(err)
        if err == "no_user" then
            msg = "没有已授权的微信用户"
        elseif err == "register" then
            msg = "呼叫登记失败，请检查业务后端"
        elseif err == "busy" then
            msg = "设备正在通话中"
        end
        reset()
        sys.publish("UI_TOAST", msg)
    end)

    return true
end

--- 接听来电
function call.answer()
    if call.state ~= "ringing" then return false end
    call.state = "connecting"
    wx.set("connecting", call.peer)
    emit()

    local cid = call.call_id
    sys.taskInit(function()
        local ok = svc.answer(cid)
        if not ok and call.call_id == cid and call.state == "connecting" then
            local_demo_connect(800)
        end
    end)
    return true
end

--- 拒接来电
function call.reject()
    if call.state ~= "ringing" then return false end
    local cid = call.call_id
    reset()
    sys.taskInit(function()
        svc.reject(cid)
    end)
    return true
end

--- 挂断 / 取消呼叫
function call.hangup()
    if call.state == "idle" then return false end
    if call.state == "ringing" then return call.reject() end

    reset()                       -- 先回主页，SDK 挂断在协程里完成
    sys.taskInit(function()
        svc.hangup()
    end)
    return true
end

local function toggle_media(field)
    if call.state ~= "talking" then return false end
    call[field] = not call[field]
    emit_media()
    local m, s, c = call.muted, call.speaker, call.cam_on
    sys.taskInit(function()
        svc.set_media(m, s, c)
    end)
    return true
end

function call.toggle_mute()
    return toggle_media("muted")
end

function call.toggle_speaker()
    return toggle_media("speaker")
end

function call.toggle_camera()
    if call.mode ~= "video" then return false end
    return toggle_media("cam_on")
end

function call.snapshot()
    return {
        state = call.state, mode = call.mode, peer = call.peer,
        seconds = call.seconds, muted = call.muted,
        speaker = call.speaker, camera = call.cam_on,
    }
end

-- ==================== 后端事件 ====================
sys.subscribe("CALL_SERVICE_EVENT", function(e, id, code)
    if e == "incoming" then
        if call.state ~= "idle" then
            sys.taskInit(function() svc.reject(id) end)
            sys.publish("UI_TOAST", "正在通话中，已拒接新来电")
            return
        end
        call.direction = "incoming"
        call.state     = "ringing"
        call.call_id   = id
        call.mode      = cfg.wechat.video_on_incoming and "video" or "voice"
        call.seconds   = 0
        call.muted, call.speaker, call.cam_on = false, true, true
        wx.set("ringing", call.peer)
        log.info("call_mgr", "微信来电", id)
        emit()
        emit_media()

        if cfg.wechat.auto_answer then
            sys.taskInit(function()
                sys.wait(800)
                if call.state == "ringing" then call.answer() end
            end)
        end

    elseif e == "talking" then
        if call.state == "idle" then return end
        if id and call.call_id and id ~= call.call_id then return end
        call.state   = "talking"
        call.seconds = 0
        wx.set("talking", call.peer)
        emit()
        emit_media()
        start_timer()

    elseif e == "ended" or e == "failed" then
        if call.state == "idle" then return end
        if id and call.call_id and id ~= call.call_id then return end
        if e == "failed" then
            sys.publish("UI_TOAST", "通话失败" .. (type(code) == "number" and ("：" .. code) or ""))
        end
        reset()
    end
end)

return call
