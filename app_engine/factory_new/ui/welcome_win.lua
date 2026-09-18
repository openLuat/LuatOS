--[[
@module  welcome_win
@summary 开机欢迎页 —— 黑色背景播放 HZV 开机动画
@version 3.0
@date    2026.09.15
@author  江访
@usage
订阅: OPEN_WELCOME_WIN  → 创建欢迎页，播放 /luatos_boot.hzv
发布: OPEN_IDLE_WIN     → 动画结束后发布，触发桌面窗口

=== 视觉说明 ===
黑色全屏背景 + 居中播放 HZV 开机动画（从容器头读取实际帧尺寸），循环播放固定时长后切桌面。
HZV 容器自带 MP3 音轨与逐帧时长，由 videoplayer 后端统一驱动，
Lua 侧不再手填 interval，也不再单独起一路「同名 MP3」。
]]

local theme = require "ui_theme"
local ok_exaudio, exaudio = pcall(require, "exaudio")
if not ok_exaudio then exaudio = nil end

local BOOT_VIDEO   = "/luatos_boot.hzv"
local BOOT_VW      = 480
local BOOT_VH      = 270
local BOOT_WAIT_MS = 5400

local window_id = nil
local bg_shape
local video_obj

--- 判断素材用哪种容器解析：优先看魔数，其次看扩展名
--- @return "hzv" | "mjpg" | "mp4"
local function media_guess_format(path)
    local f = io.open(path, "rb")
    if f then
        local magic = f:read(4)
        f:close()
        if magic == "HZV1" then return "hzv" end
    end
    local ext = path:match("%.([^%.]+)$")
    if ext then
        ext = ext:lower()
        if ext == "hzv" then return "hzv" end
        if ext == "mp4" then return "mp4" end
    end
    return "mjpg"
end

--- HZV 的音轨由 Audio V2 播放，视频时钟跟随 DAC DMA sample counter：
--- 音频框架没起来时既不响、也不会走帧，所以这里做一次幂等初始化。
--- 首次真 setup，之后只 RESUME；失败不阻断画面创建。
local function hzv_audio_ensure()
    if not exaudio then return false end
    if not (_G.project_config and _G.project_config.hw and _G.project_config.hw.audio) then
        return false
    end
    if _G.__hzv_audio_ready then
        pcall(exaudio.pm, exaudio.RESUME)
        return true
    end
    local ac = _G.project_config.hw.audio
    local ok = pcall(exaudio.setup, {
        model       = ac.model or "dac",
        pa_ctrl     = ac.pa_ctrl,
        pa_on_level = ac.pa_on_level or 0,
        dac_delay   = ac.dac_delay,
    })
    if ok then
        pcall(exaudio.vol, ac.play_vol or 70)
        _G.__hzv_audio_ready = true
        return true
    end
    log.warn("welcome_win", "hzv: exaudio.setup 失败，音轨与播放时钟可能不可用")
    return false
end

--- 读媒体容器头拿回 (width, height)
--- HZV v1: 前 4 字节为 "HZV1"，0x44 / 0x46 处各一个 uint16 宽、高
--- 其它  : 按 MJPG/JPEG 扫 SOF0/SOF2 标记
--- 取不到返回 nil，由调用方回退默认尺寸
local function media_read_dimensions(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read(512)  -- HZV 头部 0x48 以内 / JPEG 的 SOF 标记一般在 512 字节内
    f:close()
    if not data or #data < 8 then return nil end

    -- HZV 容器：帧尺寸直接写在头里（Lua 下标从 1 起，0x44 → 69）
    if data:sub(1, 4) == "HZV1" then
        local hw = data:byte(69) + data:byte(70) * 256
        local hh = data:byte(71) + data:byte(72) * 256
        if hw > 0 and hh > 0 then return hw, hh end
        return nil
    end

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
        -- .hzv 优先（真机硬解）；素材还没换成 hzv 时回落同名 .mjpg，避免开机黑屏
        for _, p in ipairs({
            "/luatos_boot.hzv", "/luadb/luatos_boot.hzv",
            "/luatos_boot.mjpg", "/luadb/luatos_boot.mjpg",
        }) do
            if io.exists(p) then
                video_path = p
                break
            end
        end
    end

    -- 从容器头读取实际帧尺寸，居中播放
    local vw, vh = media_read_dimensions(video_path)
    if not vw or not vh then vw, vh = BOOT_VW, BOOT_VH end
    local vx = math.floor((screen_w - vw) / 2)
    local vy = math.floor((screen_h - vh) / 2)

    -- HZV 的音轨由 Audio V2 播放，视频时钟跟随 DAC DMA sample counter：
    -- 音频框架没起来时画面同样不会走帧，所以先确保一次音频初始化。
    hzv_audio_ensure()

    local fmt = media_guess_format(video_path)
    local vcfg = {
        x = vx, y = vy, w = vw, h = vh,
        src = video_path,
        format = fmt,
        decode_mode = "hw",
        loop = true,
        auto_play = true,
    }
    if fmt == "hzv" then
        -- HZV 容器自带 MP3 音轨与逐帧时长，Lua 不填 interval，交给 videoplayer 后端统一驱动
        vcfg.backend = "videoplayer"
    else
        -- 兼容早期 MJPG 素材：帧间隔只能由 Lua 指定
        vcfg.interval = 33
    end

    local ok, v = pcall(airui.video, vcfg)

    if ok and v then
        video_obj = v
        log.info("welcome_win", "开机动画循环播放", video_path, fmt)
    else
        log.warn("welcome_win", "开机动画不可用", video_path)
    end

    -- 固定时长后切桌面
    sys.timerStart(on_timeout, BOOT_WAIT_MS)
end

local function on_destroy()
    pcall(exaudio.play_stop, { type = 0 })   -- 兜底：停掉可能还在跑的容器音轨
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
