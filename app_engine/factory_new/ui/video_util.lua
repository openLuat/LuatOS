--[[
@module  video_util
@summary 媒体素材工具（容器格式嗅探 / 帧尺寸读取 / HZV 音轨初始化）—— 播放类页面共用
@version 1.0
@date    2026.09.18
@author  江访

=== 为什么单独成模块 ===
idle_win（桌面播放器）与 video_win（全屏播放页）都要读素材帧尺寸，而 airui 播放器
**不支持缩放**：控件尺寸与素材帧尺寸不一致时会被强制改回素材尺寸
（components/airui/src/components/widgets/luat_airui_video.c 的
 "scaling is not supported yet ... force reset widget size"）。
也就是说，帧尺寸读错**不会**把画面拉伸，只会让控件溢出容器、把画面切掉一块 ——
同一份口径必须只有一处实现，否则两个页面的裁切行为会不一致。

（welcome_win 里还有一份历史副本。开机路径没跟着迁移，改这里时别以为全工程都干净了。）

@api video_util.guess_format(path)              容器格式："hzv" | "mjpg" | "mp4"
@api video_util.read_dimensions(path)           w, h；读不到返回 nil
@api video_util.frame_size(path, def_w, def_h)  w, h；读不到时用调用方给的兜底值
@api video_util.audio_ensure()                  幂等初始化 HZV 音轨（Audio V2），返回是否可用
]]

local ok_exaudio, exaudio = pcall(require, "exaudio")
if not ok_exaudio then exaudio = nil end

local M = {}

--[[判断素材用哪种容器解析：优先看魔数，其次看扩展名

魔数优先的原因：素材被改名（或从 SD 卡拷进来时后缀被改）后仍能正确解码。]]
function M.guess_format(path)
    local f = io.open(path, "rb")
    if f then
        local magic = f:read(4)
        f:close()
        if magic == "HZV1" then return "hzv" end
    end
    local ext = path and path:match("%.([^%.]+)$")
    if ext then
        ext = ext:lower()
        if ext == "hzv" then return "hzv" end
        if ext == "mp4" then return "mp4" end
    end
    return "mjpg"
end

--[[读媒体容器头拿回 (width, height)

HZV v1: 前 4 字节为 "HZV1"，0x44 / 0x46 处各一个 uint16 宽、高
        （Lua 下标从 1 起，所以是 byte(69)/byte(70) 与 byte(71)/byte(72)）
其它  : 按 MJPG/JPEG 扫 SOF0/SOF2 标记

@return width, height 或 nil（调用方必须给兜底值）]]
function M.read_dimensions(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read(512)  -- HZV 头部 0x48 以内 / JPEG 的 SOF 标记一般在 512 字节内
    f:close()
    if not data or #data < 8 then return nil end

    if data:sub(1, 4) == "HZV1" then
        local hw = data:byte(69) + data:byte(70) * 256
        local hh = data:byte(71) + data:byte(72) * 256
        if hw > 0 and hh > 0 then return hw, hh end
        return nil
    end

    -- 扫描 SOI (FF D8) 之后的标记，找 SOF0 (FF C0) / SOF2 (FF C2)
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
            -- 跳过非 SOF 标记（读取段长度并跳过）
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

--[[读素材帧尺寸，读不到时回退到调用方给的兜底值

兜底值必须与该页面的**布局基准**一致：给定错了不会「拉伸画面」，
只会让控件溢出容器、把画面切掉一块。]]
function M.frame_size(path, def_w, def_h)
    local w, h = M.read_dimensions(path)
    if w and h then return w, h end
    return def_w, def_h
end

--[[HZV 音轨初始化（幂等）

HZV 的音轨由 Audio V2 播放，视频时钟跟随 DAC DMA sample counter ——
音频框架没起来时既不响、也不会走帧。所以创建 HZV 播放器前必须先确保一次；
首次真 setup，之后只 RESUME。失败不阻断画面创建（只是没声音、可能不走帧）。

用全局标志 _G.__hzv_audio_ready 记账：桌面播放器与全屏播放页共用同一套音频框架，
各自 setup 一次会互相打断，标志位必须跨模块共享。]]
function M.audio_ensure()
    if not exaudio then return false end
    local pc = _G.project_config
    if not (pc and pc.hw and pc.hw.audio) then return false end
    if _G.__hzv_audio_ready then
        pcall(exaudio.pm, exaudio.RESUME)
        return true
    end
    local ac = pc.hw.audio
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
    log.warn("video_util", "exaudio.setup 失败，音轨与播放时钟可能不可用")
    return false
end

-- ==================== 配套音频（同名 MP3） ====================
--[[只有 MJPG 素材需要：HZV 的音轨在容器内、由 videoplayer 统一驱动，无需另外一路。
两个页面（桌面播放器 / 全屏播放页）共用一份播放状态，而不是各记一份 ——
同一时刻只会有一个页面在放视频（进入全屏时桌面会先释放自己的播放器），
共用状态顺带避免了「两边同时出声」。]]

local audio_mp3 = nil       -- 当前配套音频路径（非 nil 表示这一路在放）
local audio_playing = false
local exaudio_inited = false

local function has_audio()
    return exaudio ~= nil
        and _G.project_config ~= nil and _G.project_config.hw ~= nil
        and _G.project_config.hw.audio ~= nil
end

--[[在同目录下搜索与视频同名的 .mp3 文件（只认 .mjpg 后缀，HZV 天然返回 nil）]]
function M.find_companion_mp3(mjpg_path)
    if not has_audio() or type(mjpg_path) ~= "string" then return nil end
    if not mjpg_path:lower():match("%.mjpg$") then return nil end
    local dir = mjpg_path:match("^(.+/)") or "/"
    local base = mjpg_path:match("([^/]+)%.[mM][jJ][pP][gG]$")
    if not base then return nil end
    local mp3_path = dir .. base .. ".mp3"
    if io.exists(mp3_path) then return mp3_path end
    mp3_path = dir .. base .. ".MP3"
    if io.exists(mp3_path) then return mp3_path end
    return nil
end

--[[开始播放一路配套音频

@param mp3_path string 音频文件路径
@param should_loop function|nil 一首播完后是否续播：返回 true 则重放。
       由调用方决定（要同时看「循环开关」与「是否还在播」两个状态）
@return boolean 是否起播成功
]]
function M.audio_play(mp3_path, should_loop)
    if not has_audio() or not mp3_path then return false end
    if not exaudio_inited then
        pcall(exaudio.pm, exaudio.RESUME)
        exaudio_inited = true
    end
    M.audio_stop()                 -- 必须先停再记：stop 会清空 audio_mp3
    audio_mp3 = mp3_path
    local function play_loop(path)
        return pcall(exaudio.play_start, {
            type = 0, content = path,
            cbfnc = function(event)
                if event == exaudio.PLAY_DONE then
                    if (should_loop and should_loop()) and audio_mp3 then
                        play_loop(path)
                    else
                        audio_playing = false
                    end
                end
            end
        })
    end
    audio_playing = play_loop(mp3_path)
    log.info("video_util", "companion audio start", mp3_path, "ok=", audio_playing)
    return audio_playing
end

--[[停掉配套音频（没有在放时是空操作）]]
function M.audio_stop()
    if exaudio == nil then return end
    if audio_mp3 then
        pcall(exaudio.play_stop, { type = 0 })
        audio_mp3 = nil
        audio_playing = false
    end
end

--[[播放/暂停切换配套音频（暂停后再点会从头重放：exaudio 没有 seek/续播接口）]]
function M.audio_toggle(should_loop)
    if not audio_mp3 then return end
    if audio_playing then
        pcall(exaudio.play_stop, { type = 0 })
        audio_playing = false
    else
        M.audio_play(audio_mp3, should_loop)
    end
end

return M
