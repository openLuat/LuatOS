--[[
@module  usb_cam
@summary USB(UVC) 摄像头状态检测（camera 核心库）
@version 1.0.0
@date    2026.10.21
@usage
  require "usb_cam" 后自动探测，状态通过消息通知 UI：
    sys.subscribe("USB_CAM", function(state) ... end)
  state: "online" / "offline" / "disabled" / "unsupported"
  cam.id 为 camera.init 返回的 id，视频通话可直接 camera.start(cam.id)
]]

local cfg = require "hw_config"

local cam = {
    state = "offline",
    id    = nil,
}

local function report(state)
    if cam.state == state then return end
    cam.state = state
    sys.publish("USB_CAM", state)
end

local function probe()
    if not cfg.camera.enable then
        report("disabled")
        return
    end
    if not camera then
        report("unsupported")
        return
    end

    local ok, id = pcall(camera.init, {
        id            = camera.USB,
        sensor_width  = cfg.camera.sensor_width,
        sensor_height = cfg.camera.sensor_height,
        usb_port      = cfg.camera.usb_port,
    })

    -- 注意：camera.init 失败时实测可能返回错误码（如 9）而不是 false，
    -- 所以只认 0/1 这两路合法 UVC id，避免把错误码当成"已接入"
    if ok and (id == 0 or id == 1) then
        cam.id = id
        -- 仅做状态检测，先暂停采集，避免占用带宽；通话时再 camera.start(cam.id)
        pcall(camera.stop, id)
        log.info("usb_cam", "uvc online, id =", id)
        report("online")
    else
        log.warn("usb_cam", "uvc not found")
        report("offline")
    end
end

-- 谁管理摄像头：self = 本模块探测；tc = 腾讯通话 SDK 接管（H.264 上行）
local owner, owner_decided = "self", false
sys.subscribe("CAM_OWNER", function(o)
    owner, owner_decided = o, true
    log.info("usb_cam", "camera owner ->", o)
end)

local function worker()
    sys.waitUntil("UI_READY", 8000)   -- 让 UI 先起来，避免首次探测拖慢开机画面
    sys.wait(300)

    -- 等通话后端决定摄像头归属，最多 10s（tc 库检测/配置读取很快，之后才等 WiFi）
    local waited = 0
    while not owner_decided and waited < 10000 do
        sys.wait(250)
        waited = waited + 250
    end
    if owner == "tc" then
        log.info("usb_cam", "摄像头由腾讯通话 SDK 接管，本模块停止探测")
    end

    if cfg.demo_mode then
        report("online")
        while true do
            sys.wait(10000)
        end
    end

    while true do
        if owner == "tc" then
            -- 由 call_service 轮询 tc.camera_status 并推送 USB_CAM 状态
        elseif cam.id and cam.state == "online" then
            -- 已在线只做轻量巡检；掉线后重新探测
            report("online")
        else
            probe()
        end
        sys.wait(cfg.camera.probe_interval)
    end
end

sys.taskInit(worker)

return cam
