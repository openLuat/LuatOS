--[[
@module  pcm_play
@summary Air1103 流式 PCM 播放（MP4 同名 .pcm 伴音）
@version 1.0
@date    2026.10.27
@author  江访

=== 设计要点 ===

1. Air1103（model="air1103"）的下行只认两种起播方式：type=1（TTS 文本）与
   type=2（流式 PCM），type=0（文件）直接 "unsupported"。
   MP4 的音轨由 mplayer 解到 C 层音频框架（dac_sound → 内置 DAC），
   在 Air1103 机型上实测不出声，所以补一份 .pcm 伴音兜底：
   画面由 mplayer 照常放，声音由本模块流式播。

   伴音本身也经 app/common/audio_route.lua 走同一套播放通路：
   分路板（hw.audio.play_model="dac"）出内置 DAC，与 mplayer 音轨同一路；
   非分路板仍出 Air1103 下行。分路板上若某支素材的 mplayer 音轨也出了声，
   会与伴音叠成双声，删掉同名 .pcm 即可。

2. 补声素材（16kHz/16bit/单声道小端）预转（素材目录下执行，fruit.mp4 → fruit.pcm）：
       ffmpeg -i fruit.mp4 -ac 1 -ar 16000 -f s16le fruit.pcm

3. 暂停/续播：LuatOS 的文件句柄在协程间可以一直持有，断点就记在**没关掉的句柄**上，
   续播接着读下一批即可，不依赖 file:seek。同名文件 + 处于暂停态才算续播，
   其余一律从头重播（覆盖「播完循环重播」与「stop 后再播」两种情形）。

4. 喂数节奏 32B/ms（Air1103 下行 320B/10ms），每批 3200 字节 = 100ms。

=== 对外接口 ===

  pcm_play.available()             -> boolean 是否走 Air1103 流式通路
  pcm_play.find_companion(video)   -> string|nil 同名 .pcm 路径
  pcm_play.play(path)              -> ok, err  起播 / 暂停续播 / 从头重播
  pcm_play.pause()                 -> ok       暂停（记断点）
  pcm_play.stop()                  -> ok       停止（丢断点、关句柄）
  pcm_play.playing()               -> boolean  是否在放
]]

local M = {}

-- exaudio 是固件扩展库，须 require 绑定；无音频固件上取不到则为 nil
local ok_exaudio, exaudio = pcall(require, "exaudio")
if not ok_exaudio then exaudio = nil end

-- exaudio.setup 入参统一组装（判 Air1103 要读 hw.audio.model）
local audio_hw = require "audio_hw"

-- 录音/播放分路：伴音跟着主播放通路走（分路板出内置 DAC，其余出 Air1103 下行）
local audio_route = require "audio_route"

-- 每批字节数（Air1103 下行 320B/10ms，取 10 帧一批）
local CHUNK = 3200
-- 喂数节奏：Air1103 按 32KB/s 消费，每批等 #d/32 毫秒防溢出
local BYTE_PER_MS = 32

-- 播放会话状态（全局唯一一路伴音：同一时刻只有一个视频在放）
local st = {
    path = nil,      -- 当前伴音文件
    fp = nil,        -- 未关的句柄即暂停断点
    gen = 0,         -- 喂数协程代号，停止/重播时 +1 让旧协程退出
    active = false,  -- 是否正在放
    paused = false,  -- 是否停在断点上
}

--[[
@function available
@summary 是否启用 .pcm 伴音补声（非 Air1103 机型仍由 mplayer 自带音频出声）
@return boolean
]]
function M.available()
    return exaudio ~= nil
        and audio_hw.is_air1103()
        and type(exaudio.play_start) == "function"
        and type(exaudio.play_stream_write) == "function"
end

--[[
@function find_companion
@summary 在同目录下搜索与视频同名的 .pcm 伴音
@param string video_path 视频路径
@return string|nil
]]
function M.find_companion(video_path)
    if type(video_path) ~= "string" then return nil end
    local dir = video_path:match("^(.+/)") or "/"
    local base = video_path:match("([^/]+)%.[^./]+$")
    if not base then return nil end
    local p = dir .. base .. ".pcm"
    if io.exists(p) then return p end
    p = dir .. base .. ".PCM"
    if io.exists(p) then return p end
    return nil
end

-- 关掉句柄并丢弃断点
local function close_fp()
    if st.fp then
        pcall(st.fp.close, st.fp)
        st.fp = nil
    end
    st.path = nil
end

-- 打开伴音句柄（同一文件且句柄还在则复用断点）
local function open_fp(path)
    if st.fp and st.path == path then return true end
    close_fp()
    local f = io.open(path, "rb")
    if not f then return false end
    st.fp = f
    st.path = path
    return true
end

-- 喂数协程：边读边喂 Air1103，读完 exaudio.finish() 排空触发 PLAY_DONE
-- gen 是本路的代号：暂停/停止/重播后旧协程靠它认出自己已过期
local function feed_task(gen)
    local f = st.fp
    if not f then st.active = false; return end
    while st.gen == gen do
        local d = f:read(CHUNK)
        if not d or #d == 0 then break end
        -- 最后一批不足 CHUNK 补静音，保证 320B 帧对齐
        if #d < CHUNK then
            d = d .. string.rep("\0", CHUNK - #d)
        end
        pcall(exaudio.play_stream_write, d)
        sys.wait(math.max(20, math.floor(#d / BYTE_PER_MS)))
    end
    if st.gen == gen then
        pcall(exaudio.finish)
        -- 自然播完：丢断点，下一次 play 从头重播（应用层循环续播走这条路）
        st.active = false
        st.paused = false
        close_fp()
    end
end

--[[
@function play
@summary 起播伴音：同名文件停在断点则续播，其余从头重播
@param string path 伴音文件路径
@return boolean, string|nil
]]
function M.play(path)
    if not M.available() then return false, "非 Air1103 流式通路" end
    if type(path) ~= "string" or not io.exists(path) then return false, "伴音文件不存在" end

    -- 停在断点上且是同一份文件才续播，否则丢断点从头
    local resume = (st.paused and st.path == path and st.fp ~= nil)
    if not resume then
        close_fp()
        if not open_fp(path) then return false, "伴音文件打开失败" end
    end

    st.gen = st.gen + 1
    local gen = st.gen
    pcall(exaudio.play_stop, { type = 2 })
    local ok, ret = audio_route.play_start({
        type = 2,
        cbfnc = function(event)
            if event == exaudio.PLAY_DONE and gen == st.gen then st.active = false end
        end,
        priority = 1,
        sampling_rate = 16000,
        sampling_depth = 16,
        signed_or_unsigned = true,
    })
    if not ok or not ret then
        close_fp()
        st.active = false
        return false, "伴音起播失败: " .. tostring(ret)
    end
    st.active = true
    st.paused = false
    sys.taskInit(feed_task, gen)
    log.info("pcm_play", resume and "伴音续播" or "伴音起播", path)
    return true
end

--[[
@function pause
@summary 暂停伴音（断点留在未关的句柄上）
@return boolean
]]
function M.pause()
    if not st.active then return false end
    st.gen = st.gen + 1
    st.active = false
    st.paused = true
    pcall(exaudio.play_stop, { type = 2 })
    log.info("pcm_play", "伴音暂停")
    return true
end

--[[
@function stop
@summary 停止伴音（丢断点、关句柄）
@return boolean
]]
function M.stop()
    st.gen = st.gen + 1
    st.active = false
    st.paused = false
    close_fp()
    pcall(exaudio.play_stop, { type = 2 })
    return true
end

--[[
@function playing
@summary 是否正在放
@return boolean
]]
function M.playing()
    return st.active
end

return M
