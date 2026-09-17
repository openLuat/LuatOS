--[[
@module  welcome_win
@summary 开机欢迎页 —— 黑色背景播放 MJPG 开机动画
@version 3.0
@date    2026.09.15
@author  江访
@usage
订阅: OPEN_WELCOME_WIN  → 创建欢迎页，播放 /luatos_boot.mjpg
发布: OPEN_IDLE_WIN     → 动画结束后发布，触发桌面窗口

=== 视觉说明 ===
黑色全屏背景 + 居中播放 MJPG 开机视频（480×272），循环播放固定时长后切桌面。
]]

local theme = require "ui_theme"

local BOOT_VIDEO   = "/luatos_boot.mjpg"
local BOOT_VW      = 480
local BOOT_VH      = 272
local BOOT_WAIT_MS = 5400

local window_id = nil
local bg_shape
local video_obj

local function on_timeout()
    if window_id then
        log.info("welcome_win", "开机动画结束，进入桌面")
        sys.publish("OPEN_IDLE_WIN")
        exwin.close(window_id)
    end
end

local function on_create()
    -- 黑色全屏背景
    bg_shape = airui.shape({
        x = 0, y = 0, w = screen_w, h = screen_h,
        items = {
            { type = "rect", x = 0, y = 0, w = screen_w, h = screen_h,
              fill = true, fill_color = theme.C.black, color = theme.C.black },
        },
    })

    -- 居中播放 MJPG
    local vx = math.floor((screen_w - BOOT_VW) / 2)
    local vy = math.floor((screen_h - BOOT_VH) / 2)

    local ok, v = pcall(airui.video, {
        x = vx, y = vy, w = BOOT_VW, h = BOOT_VH,
        src = BOOT_VIDEO,
        format = "auto",
        decode_mode = "hw",
        interval = 33,
        loop = true,
        auto_play = true,
    })

    if ok and v then
        video_obj = v
        log.info("welcome_win", "开机视频循环播放", BOOT_VIDEO)
    else
        log.warn("welcome_win", "开机视频不可用", BOOT_VIDEO)
    end

    -- 固定时长后切桌面
    sys.timerStart(on_timeout, BOOT_WAIT_MS)
end

local function on_destroy()
    if video_obj then
        pcall(video_obj.stop, video_obj)
        pcall(video_obj.destroy, video_obj)
        video_obj = nil
    end
    if bg_shape then
        bg_shape:destroy()
        bg_shape = nil
    end
    window_id = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_WELCOME_WIN", open_handler)
