--[[
@module  welcome_win
@summary 开机欢迎页 —— 黑色背景播放 HZV 开机动画
@version 3.1
@date    2026.09.20
@author  江访
@usage
订阅: OPEN_WELCOME_WIN  → 创建欢迎页，播放 /luatos_boot.hzv
发布: OPEN_IDLE_WIN     → 动画播完或超时后发布，触发桌面窗口

=== 视觉说明 ===
黑色全屏背景 + 居中播放 HZV 开机动画（从容器头读取实际帧尺寸）。

=== 播放策略：单次播放，谁先完成谁先入场 ===
loop = false，两条收尾路径共用同一个 finish()，先到者生效、后到者被 finished 标志挡住：

  1. on_complete —— videoplayer 解码到 EOF 时触发（素材播完）；
  2. BOOT_MAX_WAIT_MS —— 兜底上限（素材比这更长，或 on_complete 没来）。

之所以必须留超时这条路：早期 MJPG 素材走的是软件解码路径，
on_complete 未必会触发；且素材损坏、解码器起不来时，没有超时就会永久停在黑屏。

HZV 容器自带 MP3 音轨与逐帧时长，由 videoplayer 后端统一驱动，
Lua 侧不再手填 interval，也不再单独起一路「同名 MP3」。
]]

local theme = require "ui_theme"
local ok_exaudio, exaudio = pcall(require, "exaudio")
if not ok_exaudio then exaudio = nil end

local BOOT_VIDEO   = "/luatos_boot.hzv"
local BOOT_VW      = 480
local BOOT_VH      = 270
-- 兜底上限：素材比这长就按此时间入场；素材更短则由 on_complete 提前入场
local BOOT_MAX_WAIT_MS = 5400

local window_id = nil
local bg_shape
local video_obj

--[[收尾标记与定时器句柄

finished 是「只走一次」的闸门：on_complete 与超时是两条独立路径，
必须保证无论哪条先到，进入桌面这件事都只发生一次 —— 重复 publish
OPEN_IDLE_WIN 会让 exwin 重复创建桌面。
]]
local finished = false
local wait_timer = nil

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
        pcall(exaudio.vol, ac.play_vol or 100)
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

--[[收尾：进入桌面（播完 / 超时共用，只生效一次）

@param reason string 仅用于日志，标明是哪条路径先到

顺序上必须先停掉开机视频（释放文件句柄与解码器），再 publish OPEN_IDLE_WIN ——
桌面播放器要打开同一个 /luatos_boot.hzv，句柄没释放会打不开。
]]
local function finish(reason)
    if finished or not window_id then return end
    finished = true

    if wait_timer then
        sys.timerStop(wait_timer)
        wait_timer = nil
    end

    log.info("welcome_win", "开机动画结束(", reason, ")，进入桌面")
    if video_obj then
        pcall(video_obj.stop, video_obj)
        pcall(video_obj.destroy, video_obj)
        video_obj = nil
    end
    sys.publish("OPEN_IDLE_WIN")
    exwin.close(window_id)
end

local function on_timeout()
    finish("超时")
end

--[[素材播完（videoplayer 解码到 EOF，仅 loop = false 时触发）

这个回调是在 LVGL 的播放定时器里同步调进来的：此刻销毁视频控件，会把
「正在执行的那个定时器」一起删掉。所以推后一个 tick 再收尾，
让销毁发生在定时器回调之外。
]]
local function on_video_done()
    sys.timerStart(function() finish("播放完毕") end, 1)
end

local function on_create()
    finished = false
    wait_timer = nil

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
        loop = false,              -- 单次播放：播完由 on_complete 收尾
        auto_play = true,
        on_complete = on_video_done,
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
        log.info("welcome_win", "开机动画单次播放", video_path, fmt)
    else
        log.warn("welcome_win", "开机动画不可用", video_path)
    end

    -- 兜底上限：素材更长 / on_complete 没来 / 素材不可用时，都由它收尾
    wait_timer = sys.timerStart(on_timeout, BOOT_MAX_WAIT_MS)
end

local function on_destroy()
    -- 先落闸，避免 close 之后残留的 on_complete 再触发一次收尾
    finished = true
    if wait_timer then
        sys.timerStop(wait_timer)
        wait_timer = nil
    end

    -- 兜底：停掉可能还在跑的容器音轨
    -- 注意 exaudio 是容错加载的（可能为 nil），取字段必须在 pcall 之外先判空，
    -- 否则 exaudio.play_stop 本身就会抛 "attempt to index a nil value"
    if exaudio then
        pcall(exaudio.play_stop, { type = 0 })
    end
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
