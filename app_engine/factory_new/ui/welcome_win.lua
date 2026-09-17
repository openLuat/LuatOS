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
黑色全屏背景 + 居中播放 MJPG 开机视频（从文件头读取实际尺寸），循环播放固定时长后切桌面。
]]

local theme = require "ui_theme"
local ok_exaudio, exaudio = pcall(require, "exaudio")
if not ok_exaudio then exaudio = nil end

local BOOT_VIDEO   = "/luatos_boot.mjpg"
local BOOT_VW      = 480
local BOOT_VH      = 270
local BOOT_WAIT_MS = 5400

local window_id = nil
local bg_shape
local video_obj
local welcome_audio_path = nil

--- 从 MJPG/JPEG 文件头读取第一帧的宽高（解析 SOF0 标记）
local function mjpg_read_dimensions(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read(512)
    f:close()
    if not data or #data < 4 then return nil end
    local i = 1
    while i <= #data - 1 do
        if data:byte(i) == 0xFF then
            local marker = data:byte(i + 1)
            if marker == 0xC0 or marker == 0xC2 then
                if i + 9 <= #data then
                    local h = data:byte(i + 5) * 256 + data:byte(i + 6)
                    local w = data:byte(i + 7) * 256 + data:byte(i + 8)
                    return w, h
                end
                return nil
            end
            if marker ~= 0xD8 and marker ~= 0xD9 and (marker < 0xD0 or marker > 0xD7) then
                if i + 3 <= #data then
                    local seg_len = data:byte(i + 2) * 256 + data:byte(i + 3)
                    i = i + 2 + seg_len
                else
                    break
                end
            else
                i = i + 2
            end
        else
            i = i + 1
        end
    end
    return nil
end

local function on_timeout()
    if window_id then
        log.info("welcome_win", "开机动画结束，进入桌面")
        -- 先停掉开机视频释放文件句柄和解码器资源，再通知桌面创建
        if video_obj then
            pcall(video_obj.stop, video_obj)
            pcall(video_obj.destroy, video_obj)
            video_obj = nil
        end
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

    -- 资源落点随烧录方式而变（/luadb/ 或根目录），先挑实际存在的那个
    local video_path = BOOT_VIDEO
    if not io.exists(video_path) then
        for _, p in ipairs({ "/luatos_boot.mjpg", "/luadb/luatos_boot.mjpg" }) do
            if io.exists(p) then
                video_path = p
                break
            end
        end
    end

    -- 从文件头读取实际帧尺寸，居中播放
    local vw, vh = mjpg_read_dimensions(video_path)
    if not vw or not vh then vw, vh = BOOT_VW, BOOT_VH end
    local vx = math.floor((screen_w - vw) / 2)
    local vy = math.floor((screen_h - vh) / 2)

    local ok, v = pcall(airui.video, {
        x = vx, y = vy, w = vw, h = vh,
        src = video_path,
        format = "mjpg",
        decode_mode = "hw",
        interval = 33,
        loop = true,
        auto_play = true,
    })

    if ok and v then
        video_obj = v
        log.info("welcome_win", "开机视频循环播放", video_path)
    else
        log.warn("welcome_win", "开机视频不可用", video_path)
    end

    -- 配套音频：同名 MP3 循环播放
    if exaudio and _G.project_config and _G.project_config.hw and _G.project_config.hw.audio then
        local dir = video_path:match("^(.+/)") or "/"
        local base = video_path:match("([^/]+)%.mjpg$") or video_path:match("([^/]+)%.MJPG$")
        if base then
            local mp3 = dir .. base .. ".mp3"
            if not io.exists(mp3) then mp3 = dir .. base .. ".MP3" end
            if io.exists(mp3) then
                welcome_audio_path = mp3
                pcall(exaudio.pm, exaudio.RESUME)
                pcall(exaudio.play_start, { type = 0, content = mp3,
                    cbfnc = function(event)
                        if event == exaudio.PLAY_DONE and welcome_audio_path then
                            pcall(exaudio.play_start, { type = 0, content = welcome_audio_path })
                        end
                    end
                })
                log.info("welcome_win", "开机音频播放", mp3)
            end
        end
    end

    -- 固定时长后切桌面
    sys.timerStart(on_timeout, BOOT_WAIT_MS)
end

local function on_destroy()
    welcome_audio_path = nil
    pcall(exaudio.play_stop, { type = 0 })
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
