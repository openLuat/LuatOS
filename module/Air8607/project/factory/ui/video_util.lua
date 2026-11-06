--[[
@module  video_util
@summary 媒体素材工具（容器格式嗅探 / 帧尺寸读取 / 分辨率上限 / HZV 音轨初始化 / 播放器创建）—— 播放类页面共用
@version 2.1
@date    2026.10.29
@author  江访

=== 为什么单独成模块 ===
idle_win（桌面播放器）与 video_win（全屏播放页）都要读素材帧尺寸，而 airui 播放器
**不支持缩放**：控件尺寸与素材帧尺寸不一致时会被强制改回素材尺寸
（components/airui/src/components/widgets/luat_airui_video.c 的
 "scaling is not supported yet ... force reset widget size"）。
也就是说，帧尺寸读错**不会**把画面拉伸，只会让控件溢出容器、把画面切掉一块 ——
同一份口径必须只有一处实现，否则两个页面的裁切行为会不一致。

（welcome_win 里的历史副本已随 welcome 页面删除，全工程只剩这一处实现。）

=== MP4 / HZV / MJPG 统一走 airui.video（2026-10-09 起）===
airui.video 已支持 HZV 与 MP4：MJPG / HZV 走 videoplayer 后端（控件内拉 RGB565 帧），
MP4 按 format 自动路由到 mplayer 后端（自带音频通路、硬件图层送显、组件内部
循环重播与 EOS 回调 on_complete）。桌面播放器（idle_win）与全屏播放页
（video_win）三种格式的播放全部收口到 create_player 一个入口。
MP4 的功放使能副作用也在这里收口，见「MP4 会话副作用」。

@api video_util.guess_format(path)              容器格式："hzv" | "mjpg" | "mp4"
@api video_util.read_dimensions(path)           w, h；读不到返回 nil
@api video_util.frame_size(path, def_w, def_h)  w, h；读不到时用调用方给的兜底值
@api video_util.max_frame_size(fmt)             该格式的源分辨率上限 w, h
@api video_util.check_frame(path)               ok, w, h, fmt, reason；超上限时 ok=false 且 reason 说明原因
@api video_util.audio_ensure()                  幂等初始化配套音频框架（MJPG 的同名 MP3 用，
                                                HZV 不走 exaudio），返回是否可用
@api video_util.create_player(path, o)          按格式创建**嵌入式**播放器（airui.video，
                                                HZV/MJPG/MP4 统一；o.on_complete=单次播完回调）
                                                创建失败按「硬解→软解→建好再起播」降级重试，
                                                全部失败返回 nil 并逐档打日志（含堆剩余）
]]

local ok_exaudio, exaudio = pcall(require, "exaudio")
if not ok_exaudio then exaudio = nil end

-- exaudio.setup 入参统一组装（必带 uart_id/audio_mode，Air1103 靠它绑到 UART6）
local audio_hw = require "audio_hw"
-- 录音/播放分路：Air1103 机型录音走语音芯片、播放走内置 DAC（其余机型原样转发 exaudio）
local audio_route = require "audio_route"
-- Air1103 的 MP4 同名 .pcm 伴音（流式 PCM 补声，见该模块头注释）
local pcm_play = require "pcm_play"

local M = {}

--[[判断素材用哪种容器解析：优先看魔数，其次看扩展名

魔数优先的原因：素材被改名（或从 SD 卡拷进来时后缀被改）后仍能正确解码。
MP4 的魔数是偏移 4 处的 "ftyp" box（前 4 字节是 box 长度，不能只读 4 字节）。]]
function M.guess_format(path)
    local f = io.open(path, "rb")
    if f then
        local magic = f:read(8)
        f:close()
        if magic then
            if magic:sub(1, 4) == "HZV1" then return "hzv" end
            if magic:sub(5, 8) == "ftyp" then return "mp4" end
        end
    end
    local ext = path and path:match("%.([^%.]+)$")
    if ext then
        ext = ext:lower()
        if ext == "hzv" then return "hzv" end
        if ext == "mp4" or ext == "m4v" then return "mp4" end
    end
    return "mjpg"
end

--[[MP4 容器盒解析拿编码宽高（纯 Lua，不碰解码器）

只为读两个整数就 open 解码器太重（会初始化 FFmpeg / 硬解并喂 SPS/PPS），
纯 Lua 解析 moov 盒足够：优先 stsd 里 avc1/hev1/hvc1/mp4v 的
VisualSampleEntry 宽高（载荷偏移 +24/+26），找不到再用 tkhd 尾部 16.16
定点显示宽高兜底。moov 超 2MB 放弃（正常素材远小于此）。
盒结构：[size(4) type(4) payload...]，size==1 时 64 位盒长跟在头后。]]
local function mp4_box_dimensions(path)
    local f = io.open(path, "rb")
    if not f then return nil end

    local function be32(s, o)
        local a, b, c, d = s:byte(o, o + 3)
        return a * 16777216 + b * 65536 + c * 256 + d
    end
    local function be16(s, o)
        local a, b = s:byte(o, o + 1)
        return a * 256 + b
    end

    -- 顶层盒遍历找 moov（只读盒头跳过 mdat 等大盒，不整文件读入）
    local moov = nil
    local fsize = io.fileSize(path) or 0
    local pos = 0
    while pos + 8 <= fsize do
        f:seek("set", pos)
        local hdr = f:read(8)
        if not hdr or #hdr < 8 then break end
        local size = be32(hdr, 1)
        if size == 1 then
            local ext = f:read(8)
            if not ext or #ext < 8 then break end
            size = be32(ext, 1) * 4294967296 + be32(ext, 5)
        elseif size == 0 then
            size = fsize - pos
        end
        if size < 8 then break end
        if hdr:sub(5, 8) == "moov" then
            local msize = size - 8
            if msize > 2 * 1024 * 1024 then break end
            f:seek("set", pos + 8)
            moov = f:read(msize)
            break
        end
        pos = pos + size
    end
    f:close()
    if not moov or #moov < 32 then return nil end

    -- VisualSampleEntry：SampleEntry 头 8 字节 + 预留 16 字节后是 width/height
    for _, tag in ipairs({ "avc1", "hvc1", "hev1", "mp4v" }) do
        local i = moov:find(tag, 1, true)
        while i do
            local p = i + 4
            if p + 27 <= #moov then
                local w, h = be16(moov, p + 24), be16(moov, p + 26)
                if w >= 16 and w <= 8192 and h >= 16 and h <= 8192 then return w, h end
            end
            i = moov:find(tag, i + 1, true)
        end
    end

    -- tkhd 兜底：显示宽高是 16.16 定点在载荷尾部（v0 载荷 84 字节宽偏移 76，v1 为 96/88）
    local i = moov:find("tkhd", 1, true)
    while i do
        local p = i + 4
        if p + 4 <= #moov then
            local woff = (moov:byte(p) == 1) and 88 or 76
            if p + woff + 8 <= #moov then
                local w = math.floor(be32(moov, p + woff) / 65536)
                local h = math.floor(be32(moov, p + woff + 4) / 65536)
                if w >= 16 and w <= 8192 and h >= 16 and h <= 8192 then return w, h end
            end
        end
        i = moov:find("tkhd", i + 1, true)
    end
    return nil
end

--[[读媒体容器头拿回 (width, height)

HZV v1: 前 4 字节为 "HZV1"，0x44 / 0x46 处各一个 uint16 宽、高
        （Lua 下标从 1 起，所以是 byte(69)/byte(70) 与 byte(71)/byte(72)）
MP4 :   纯 Lua 解析容器盒拿宽高（见 mp4_box_dimensions，不碰解码器）
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

    -- MP4（魔数 = 偏移 4 处的 "ftyp" box）：纯 Lua 解析容器盒，不碰 H.264 解码器
    if data:sub(5, 8) == "ftyp" then
        return mp4_box_dimensions(path)
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

-- ==================== 素材分辨率上限 ====================
--[[各格式的源分辨率上限（含）：超出拒绝起播，调用方按「无法播放」走提示 / 空态

mp4      : mplayer 后端（闭源 mp4_decode 解码器 + RGB565 视频层缓冲），480×320 以上解不稳
hzv/mjpg : videoplayer 后端（tjpgd 软解或平台硬解，控件内双帧缓冲），支持到 1024×600

上限**按格式分档**，不能一刀切：MP4 与 HZV 走的是两套解码器、两套帧缓冲，
MP4 那 480×320 的天花板不该把 HZV 一起限死（1024×600 的 HZV 是合法素材，
在 1024×600 屏上能整屏播）。

只拦「读到了尺寸且超限」的确定情况：尺寸读不出来时交回解码器去试，
不要因为容器头解析失败就误杀一个好素材。]]
local FRAME_MAX = {
    mp4  = { w = 480, h = 320 },
    hzv  = { w = 1024, h = 600 },
    mjpg = { w = 1024, h = 600 },
}

--[[取某格式的源分辨率上限
@param fmt string 容器格式（guess_format 的返回值）
@return number max_w, number max_h（未知格式返回 0,0 表示不设限）]]
function M.max_frame_size(fmt)
    local lim = FRAME_MAX[fmt]
    if not lim then return 0, 0 end
    return lim.w, lim.h
end

--[[按格式上限校验素材（三种格式同一套口径，两个播放页面都只调这一个）

@param path string 素材路径
@return boolean  ok     是否可播
@return number   w       帧宽（读不到时 nil）
@return number   h       帧高（读不到时 nil）
@return string   fmt     容器格式
@return string   reason  不可播原因（可播时 nil），可直接给用户看
]]
function M.check_frame(path)
    local fmt = M.guess_format(path)
    local w, h = M.read_dimensions(path)
    local max_w, max_h = M.max_frame_size(fmt)
    if w and h and max_w > 0 and (w > max_w or h > max_h) then
        return false, w, h, fmt, string.format(
            "%s 素材 %d×%d 超过该格式上限 %d×%d，无法播放",
            string.upper(fmt), w, h, max_w, max_h)
    end
    return true, w, h, fmt, nil
end

--[[配套音频框架初始化（幂等，MJPG 的同名 MP3 用）

首次真 setup，之后只 RESUME 并重新对齐 ac.play_vol（设置页「亮度和声音」会改
ac.play_vol，回到播放路径时对齐一次）。失败不阻断画面创建（只是没声音）。

HZV **不走这里**：它的音轨由 videoplayer 自己调用 luat_audio_request_play_stream，
测试工程不碰 exaudio 一切正常；而 exaudio.setup 的 DAC 收尾会 audio_v2.shutdown
关掉 codec 和功放 —— MP4 的 mplayer 刚把上一路请求标成结束、音频任务还没释放完，
紧接着 shutdown 会让下一次 play_stream 没声音（真机踩过：MP4→HZV 切换后静音）。

用全局标志 _G.__hzv_audio_ready 记账：桌面播放器与全屏播放页共用同一套音频框架，
各自 setup 一次会互相打断，标志位必须跨模块共享。]]
function M.audio_ensure()
    if not exaudio then return false end
    local ac = audio_hw.cfg()
    if not ac then return false end
    if _G.__hzv_audio_ready then
        pcall(exaudio.pm, exaudio.RESUME)
        --[[RESUME 后重新对齐一次当前音量：设置页「亮度和声音」会改 ac.play_vol，
        回到播放路径时对齐一次，保证桌面 HZV 音轨跟着用户音量走；
        也兜住增益状态在休眠中丢失的个别平台。]]
        audio_hw.vol()
        return true
    end
    --[[入参由 audio_hw 统一组装（必带 uart_id/audio_mode），
    Air1103 语音芯片靠它绑到 UART6，漏传会让整机没声音。]]
    local ok, err = audio_hw.setup()
    if ok then
        _G.__hzv_audio_ready = true
        return true
    end
    log.warn("video_util", "exaudio.setup 失败，音轨与播放时钟可能不可用", err)
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
    --[[Air1103 的下行只认 TTS(type=1) 与流式 PCM(type=2)，文件播放(type=0) 直接被拒。
    分路板把播放切到内置 DAC 后 type=0 可用，此时照常放；仍走 Air1103 下行的
    （hw.audio.play_model = "air1103"）与其静默失败不如明确跳过。]]
    if audio_hw.is_air1103() and not audio_route.enabled() then
        log.warn("video_util", "Air1103 下行不支持 MP3 文件播放，配套音已跳过", mp3_path)
        return false
    end
    if not exaudio_inited then
        pcall(exaudio.pm, exaudio.RESUME)
        exaudio_inited = true
    end
    M.audio_stop()                 -- 必须先停再记：stop 会清空 audio_mp3
    audio_mp3 = mp3_path
    local function play_loop(path)
        return audio_route.play_start({
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

-- ==================== MP4 会话副作用（功放） ====================
--[[mplayer 自己不拉 PA（功放引脚要手动使能），airui.video 的 MP4 后端内部同样走
mplayer，这个副作用原样存在 —— 在创建/销毁播放器时统一收口（见 wrap_mp4_player）；
跨格式切换丢功放由 pa_reassert 补（见 create_player）。

MP4 源分辨率上限 480×320（HZV/MJPG 到 1024×600）：按格式分档，见文件上方
FRAME_MAX 与 check_frame —— 起播前用纯 Lua 盒解析读宽高拦截，超限直接不起播。]]

-- PA 功放使能/关闭（引脚与电平读板级 hw.audio）
local function pa_set(on)
    local ac = _G.project_config and _G.project_config.hw and _G.project_config.hw.audio
    if not (ac and ac.pa_ctrl) then return end
    if on then
        pcall(gpio.setup, ac.pa_ctrl, ac.pa_on_level or 0)
    else
        pcall(gpio.setup, ac.pa_ctrl, (ac.pa_on_level == 1) and 0 or 1)
    end
end

-- 跨格式功放补枪的世代号（HZV/MJPG 路径用，与任一 MP4 会话无关）
local pa_gen = 0

-- MP4 销毁会把功放拉高；HZV 的 exaudio.setup 收尾也会 shutdown 关掉功放。
-- 切到 HZV/MJPG 后必须再打开，并在音频任务异步收尾之后补一次。
local function pa_reassert()
    pa_gen = pa_gen + 1
    local gen = pa_gen
    pa_set(true)
    sys.timerStart(function()
        if gen == pa_gen then pa_set(true) end
    end, 200)
end

-- ==================== 播放器会话释放窗口 ====================
--[[stop/destroy 到下一次 create 必须留出释放时间

mplayer 的音频会话从 stop() 到 C 侧打出 `dac_sound audio v2 request end` 实测要
400~530ms。这段窗口里再起一路新会话去 luat_audio_request_play_stream，会跟还没
释放完的旧会话抢：轻则新会话的 DAC 驱动起不来（`Movie audio` 打印了却没有
`dac_sound audio v2 driver started`），重则新会话阻塞在音频请求上、解码线程一帧
不出，连带触摸 I2C 事务被拖死。真机 100% 复现（2026.11.03：桌面↔文件管理来回、
中间切两次循环，第 5 路音频断在半路、第 6 路卡死）。

页面的「停旧 → 建新」都在同一次回调里做，中间让不出时间，所以收口到这里：
stop/destroy 打开释放窗口，窗口没关就把建播放器的动作延后到窗口结束再做。
延后用定时器而不是 sys.wait —— 起播发生在点击 / 焦点回调里，不在协程上下文。]]
local RELEASE_MS = 700          -- 释放窗口长度（实测 400~530ms，留余量）
local release_timer = nil       -- 非 nil = 释放窗口未关
local pending_create = nil      -- 窗口结束后要执行的建播放器动作

-- 打开（或顺延）释放窗口：每停一路就从头计时
local function mark_release()
    if release_timer then sys.timerStop(release_timer) end
    release_timer = sys.timerStart(function()
        release_timer = nil
        local fn = pending_create
        pending_create = nil
        if fn then fn() end
    end, RELEASE_MS)
end

---释放窗口内延后执行 fn，窗口已关则立即执行
---连点 / 连切只保留最后一次动作，不会排队建出多个播放器
function M.after_release(fn)
    if not release_timer then
        fn()
        return
    end
    log.info("video_util", "释放窗口未关，起播延后", RELEASE_MS .. "ms")
    pending_create = fn
end

---丢掉待执行的建播放器动作（页面失焦 / 销毁时调用）
---只丢动作、不关窗口：这一次销毁照样需要完整的释放时间
function M.cancel_pending()
    pending_create = nil
end

--[[包装 MP4 播放器：功放跟随播放状态开关，destroy 时统一收尾

接口面与裸 airui.video 对象一致（:play/:pause/:stop/:destroy），调用方无感；
paused 字段记录用户暂停状态（应用层循环续播据此跳过，见 create_player）；
HZV/MJPG 没有这套 PA / 伴音副作用，由 wrap_release 只补释放窗口（见下）。

pcm_path 非 nil 时（配了同名 .pcm 伴音）声音走 exaudio 流式 PCM，
play/pause/stop/destroy 同步驱动 pcm_play；没配伴音时 MP4 的 mplayer 音轨照常走
内置 DAC 出声。伴音只在同目录同名文件存在时启用，二者同开会叠成双声。

**收尾只碰自己这一路**：destroy 停自己的伴音、关功放，并翻一次全局功放世代作废
pa_reassert 尚未触发的跨格式补枪，不插手别的播放器实例（历史上桌面播放器与全屏
播放器共用会话状态，切换几次后 mplayer 的音频会话被搅坏、画面黑屏不更新）。]]
local function wrap_mp4_player(v, pcm_path)
    -- 本实例会话收尾：停伴音、关功放，并作废尚未触发的跨格式补枪。
    -- 作废要连全局功放世代一起翻（功放是全局唯一硬件资源，pa_reassert 的跨格式
    -- 补枪也操控它，收尾须全局封枪）
    local function mp4_session_end()
        if pcm_path then pcm_play.stop() end
        pa_gen = pa_gen + 1          -- 作废 pa_reassert 尚未触发的跨格式补枪
        pa_set(false)
    end

    -- auto_play 的画面自动开播，伴音在构造时跟上（暂停续播/循环重播走下面的 play）
    if pcm_path then pcm_play.play(pcm_path) end

    return {
        paused = false,
        play = function(self, ...)
            local r = v:play(...)
            self.paused = false
            pa_set(true)            -- PA_EN 跟随播放：起播开功放
            -- 伴音跟播放对齐：暂停续播接着断点放，循环重播/从头放由 pcm_play 自己判
            if pcm_path then pcm_play.play(pcm_path) end
            return r
        end,
        pause = function(self, ...)
            local r = v:pause(...)
            self.paused = true
            pa_set(false)           -- PA_EN 跟随暂停：暂停关功放
            if pcm_path then pcm_play.pause() end
            return r
        end,
        stop = function(self, ...)
            local r = v:stop(...)
            self.paused = true
            pa_set(false)           -- PA_EN 跟随停止：停止关功放
            if pcm_path then pcm_play.stop() end
            mark_release()          -- 音频会话开始释放，下一路要等
            return r
        end,
        destroy = function(_)
            pcall(function() v:destroy() end)
            mp4_session_end()
            mark_release()
        end,
    }
end

--[[给裸 airui.video 补一层会话收尾：stop/destroy 顺带打开释放窗口

HZV/MJPG 没有 MP4 那套 PA / 伴音副作用，所以不走 wrap_mp4_player；但 HZV 的
videoplayer 与 MP4 的 mplayer 音轨都从 luat_audio_request_play_stream 走，
「停旧 → 建新」同样要留释放窗口。接口面与裸对象一致（:play/:pause/:stop/:destroy）。]]
local function wrap_release(v)
    return {
        play = function(self, ...) return v:play(...) end,
        pause = function(self, ...) return v:pause(...) end,
        stop = function(self, ...)
            local r = v:stop(...)
            mark_release()
            return r
        end,
        destroy = function(_)
            pcall(function() v:destroy() end)
            mark_release()
        end,
    }
end

-- ==================== 播放器创建 ====================
--[[堆剩余快照（只在创建失败时调用）

1024×600 的 HZV 要两块 RGB565 帧缓冲（约 2.4MB），起播时还要一块解码输出（约 1.2MB），
建不出来多半是内存不够，把剩余量一起打出来才好判断。]]
local function mem_snapshot()
    if not rtos or not rtos.meminfo then return "" end
    local out = {}
    for _, pool in ipairs({ "sys", "psram" }) do
        local ok, total, used = pcall(rtos.meminfo, pool)
        if ok and type(total) == "number" and type(used) == "number" and total > used then
            out[#out + 1] = string.format("%s余%dKB", pool, math.floor((total - used) / 1024))
        end
    end
    return table.concat(out, " ")
end

--[[最大连续块实测（只在创建失败时调用）

rtos.meminfo 报的是池子「总量-已用」，报不出「最大连续块」：碎片化时总量还很富余，
1MB 级的整块照样要不出来。帧缓冲走 luat_heap_memalign / luat_heap_malloc，跟
zbuff 取的是同一批堆（都落到 luat_heap_opt_malloc），所以用 zbuff 二分实测，
直接跟素材需要的「单块 = 宽×高×2」对账。]]
local function alloc_probe()
    if not zbuff or type(zbuff.create) ~= "function" then return "无zbuff" end

    -- 每测一档就地释放：zbuff 是 userdata，要两遍 GC 才回收，不收干净会把下一档搅小
    local function try(n)
        local ok, buf = pcall(zbuff.create, n)
        local got = ok and (buf ~= nil)
        buf = nil
        collectgarbage()
        collectgarbage()
        return got
    end

    collectgarbage()
    collectgarbage()
    local step = 64 * 1024
    local lo, hi, best = step, 4 * 1024 * 1024, 0
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2 / step) * step
        if mid < step then break end
        if try(mid) then
            best = mid
            lo = mid + step
        else
            hi = mid - step
        end
    end
    return string.format("最大连续块%dKB", math.floor(best / 1024))
end

--[[起播并确认真的起来了

airui.video:play() 既不报错也不返回值（C 端把错误吞了），是否起来只能问
get_stats().playing —— 组件只在底层起播成功时才置 true。
老固件没有 get_stats，无从校验，按起来了算。]]
local function start_player(v)
    pcall(function() v:play() end)
    if type(v.get_stats) ~= "function" then return true end
    local ok, st = pcall(function() return v:get_stats() end)
    return ok and type(st) == "table" and st.playing == true
end

--[[按素材格式创建**嵌入式**播放器（唯一入口）

HZV / MJPG / MP4 都走 airui.video（父容器内的控件，随 UI 层级显示/隐藏）：
MJPG 逐帧按 interval 喂；HZV / MP4 自带帧时序（HZV 容器帧时长 / MP4 PTS），
单次播完（on_complete）由组件回调，循环控制栏代码无感 —— HZV/MJPG 循环
由组件统一处理，MP4 循环为应用层续播（走包装层 play，功放/伴音每轮都跟上，见下）。
两个播放页面（桌面播放器 / 全屏播放页）都走这里，格式差异只有一处实现。

@table o
  @userdata o.parent   airui 父容器
  @number   o.x,o.y    画面摆放位置（相对 parent）
  @number   o.w,o.h    画面尺寸（必须等于素材帧尺寸，不支持缩放）
  @boolean  o.loop     是否循环
  @function o.on_complete 单次播完（loop=false 读到 EOF）回调
@return userdata|nil 播放器对象（:play/:pause/:stop/:destroy），失败 nil
                      （素材超过该格式分辨率上限、或播放器创建失败时）
]]
function M.create_player(path, o)
    o = o or {}
    local pcm_path = nil   -- MP4 同名 .pcm 伴音（Air1103 补声，非 nil 才走）

    --[[分辨率超限拒绝起播：调用方按「无法播放」走提示 / 空态。
    三种格式各有各的上限（见 FRAME_MAX），校验收口在 check_frame ——
    页面要提前知道「能不能播 / 为什么不能播」，也调它，不要各写一套判断。]]
    local size_ok, _w, _h, fmt, reason = M.check_frame(path)
    if not size_ok then
        log.warn("video_util", reason or "素材超过格式上限，拒绝起播", path)
        return nil
    end

    if fmt == "mp4" then
        --[[停掉残留的配套/容器音频再起 mplayer：两路音频同开必打架。
        MP4 的声音走 mplayer 自带音频通路（组件内部自行初始化），不经 exaudio，
        最终落到芯片内置 DAC；分路板（play_model="dac"）正是要走这一路。
        只有仍留在 Air1103 单通路的机型，mplayer 的音轨才出不来声，
        那时靠同名 .pcm 伴音走 exaudio 流式 PCM 补声（见 app/common/pcm_play.lua）。]]
        M.audio_stop()
        if exaudio then pcall(exaudio.play_stop, { type = 0 }) end
        pa_set(true)
        if pcm_play.available() then
            pcm_path = pcm_play.find_companion(path)
            if pcm_path then
                --[[伴音走 exaudio，先把音频通路建起来。
                不碰 mplayer 的音频请求，与 HZV 那条「不能在这里 exaudio.setup」不冲突
                （那条针对 DAC 模式收尾的 audio_v2.shutdown）。]]
                M.audio_ensure()
                log.info("video_util", "MP4 走 .pcm 伴音补声", pcm_path)
            elseif audio_route.enabled() then
                -- 分路板上 mplayer 音轨本就走内置 DAC，没配伴音是常态
                log.info("video_util", "MP4 音轨走内置 DAC（未配同名 .pcm 伴音）", path)
            else
                log.warn("video_util", "Air1103 单通路 MP4 无声：缺同名 .pcm 伴音", path,
                         "转法: ffmpeg -i xx.mp4 -ac 1 -ar 16000 -f s16le xx.pcm")
            end
        end
    elseif fmt == "hzv" then
        --[[HZV 音轨由 videoplayer 自己调用 luat_audio_request_play_stream。
        不能在这里 exaudio.setup：DAC 模式收尾会 audio_v2.shutdown 关掉 codec 和功放，
        而 MP4 的 mplayer 刚把上一路请求标成结束、音频任务还没释放完。
        紧接着 shutdown，下一次 play_stream 就没有声音。
        测试工程不碰 exaudio，只保持功放开，切换是正常的。]]
        pa_reassert()
    else
        -- MJPG 配套 MP3 走 exaudio，先确保音频框架
        M.audio_ensure()
        pa_reassert()
    end

    local vcfg = {
        parent = o.parent,
        x = o.x, y = o.y, w = o.w, h = o.h,
        src = path, format = fmt,
        decode_mode = "hw",
        loop = o.loop and true or false,
        auto_play = true,
    }
    if o.on_complete then
        vcfg.on_complete = o.on_complete
    end
    if fmt == "mjpg" then
        vcfg.interval = 33   -- 30fps（调大即慢放，看着像卡住）
    elseif fmt == "hzv" then
        -- HZV 自带逐帧时长，不填 interval，显式走 videoplayer 后端；
        -- MP4 不指定 backend，组件按 format 自动路由到 mplayer 后端
        vcfg.backend = "videoplayer"
    end

    --[[MP4 的 loop 改为应用层续播（EOF 回调里 play() 从头重播）：组件内部
    循环重播走不到包装层 play，功放与伴音跟不上、paused 状态也没人维护。
    重播与组件内部循环同为「play 从头重播」路径，画面无差异；
    用户暂停中不续播（paused 状态由包装层维护）。]]
    local player_obj = nil
    if fmt == "mp4" then
        if o.loop then
            vcfg.loop = false
            vcfg.on_complete = function()
                -- 应用层续播：走包装层 play，PA 与伴音自动跟上
                if player_obj and not player_obj.paused then
                    player_obj:play()
                end
            end
        else
            -- 单次播完（EOF）：关功放、停伴音，再回调调用方（翻播放状态/刷控制栏）
            local user_complete = vcfg.on_complete
            vcfg.on_complete = function()
                pa_set(false)
                if pcm_path then pcm_play.stop() end
                if user_complete then user_complete() end
            end
        end
    end

    --[[创建失败逐档降级重试

    C 端这条路全程静默：airui.video 建不出来只返回 nil（不抛错），videoplayer 的
    硬解回退、HZV 起播时音轨请求被拒也都不打日志。分档试，每档失败都记一行原因：
      1) 硬解 → 2) 软解（tjpgd 对大分辨率更宽容）
      3) 创建时不起播、建好后单独起播 —— auto_play 路径上「起播被拒」会把整个控件
         拖没（组件建不出来），跟「建不出来」混在一起分不清；分开后靠
         get_stats().playing 就能确认起播到底成没成。
    任一档成功即返回，全部失败才返回 nil。]]
    local attempts = {
        { decode_mode = "hw", auto_play = true },
        { decode_mode = "sw", auto_play = true },
        { decode_mode = "hw", auto_play = false },
        { decode_mode = "sw", auto_play = false },
    }
    if fmt == "mp4" then
        -- MP4 走 mplayer 后端，没有硬解/软解之分，起播语义也归包装层管
        attempts = { { decode_mode = "hw", auto_play = true } }
    end

    -- 起播前先收干净垃圾：大分辨率要整块分配帧缓冲，Lua 侧能挤出来的都挤出来。
    -- 收两遍，userdata（上一个播放器的 zbuff / 临时对象）第二遍才回收
    collectgarbage()
    collectgarbage()

    local v = nil
    for i = 1, #attempts do
        local a = attempts[i]
        vcfg.decode_mode = a.decode_mode
        vcfg.auto_play = a.auto_play
        local ok, obj = pcall(airui.video, vcfg)
        if not ok then
            log.warn("video_util", "airui.video 报错", path, "decode=", a.decode_mode,
                     tostring(obj), mem_snapshot())
        elseif obj then
            if a.auto_play or start_player(obj) then
                v = obj
                break
            end
            log.warn("video_util", "起播被拒", path, "decode=", a.decode_mode, mem_snapshot())
            pcall(function() obj:stop() end)
            pcall(function() obj:destroy() end)
            mark_release()   -- 半路起播也可能占住音频请求，一并留释放窗口
        else
            log.warn("video_util", "airui.video 返回 nil", path, "fmt=", fmt,
                     "decode=", a.decode_mode, mem_snapshot())
        end
    end
    if not v then
        --[[放弃时把账算全：堆剩余 / 最大连续块 / 该素材单块需要多少。
        1024×600 单块是 1.23MB，起播峰值要 3 块（两块持久帧缓冲 + 一块解码输出），
        最大连续块够不上就是内存不够，够得上就往别处找原因。]]
        local need_kb = 0
        if type(_w) == "number" and type(_h) == "number" then
            need_kb = math.floor(_w * _h * 2 / 1024)
        end
        log.warn("video_util", "播放器创建放弃", path, "mem=", mem_snapshot(),
                 "单块需", need_kb .. "KB", alloc_probe())
        if fmt == "mp4" then
            -- 起播失败收尾：此时未 wrap，直接关功放
            pa_set(false)
        end
        mark_release()   -- 各档都试过，残留的音频请求同样要留出释放时间
        return nil
    end
    if fmt == "mp4" then
        -- 伴音在构造时起播，跟 auto_play 的画面同刻
        player_obj = wrap_mp4_player(v, pcm_path)
        return player_obj
    end
    -- 播放器打开时音频任务可能再次把功放拉高，创建成功后再拉一次
    pa_set(true)
    return wrap_release(v)
end

return M
