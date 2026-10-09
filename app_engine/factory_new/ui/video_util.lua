--[[
@module  video_util
@summary 媒体素材工具（容器格式嗅探 / 帧尺寸读取 / HZV 音轨初始化 / 播放器创建）—— 播放类页面共用
@version 1.5
@date    2026.10.09
@author  江访

=== 为什么单独成模块 ===
idle_win（桌面播放器）与 video_win（全屏播放页）都要读素材帧尺寸，而 airui 播放器
**不支持缩放**：控件尺寸与素材帧尺寸不一致时会被强制改回素材尺寸
（components/airui/src/components/widgets/luat_airui_video.c 的
 "scaling is not supported yet ... force reset widget size"）。
也就是说，帧尺寸读错**不会**把画面拉伸，只会让控件溢出容器、把画面切掉一块 ——
同一份口径必须只有一处实现，否则两个页面的裁切行为会不一致。

（welcome_win 里还有一份历史副本。开机路径没跟着迁移，改这里时别以为全工程都干净了。）

=== MP4 / HZV / MJPG 统一走 airui.video（2026-10-09 起）===
airui.video 已支持 HZV 与 MP4：MJPG / HZV 走 videoplayer 后端（控件内拉 RGB565 帧），
MP4 按 format 自动路由到 mplayer 后端（自带音频通路、硬件图层送显、组件内部
循环重播与 EOS 回调 on_complete）。桌面播放器（idle_win）与全屏播放页
（video_win）三种格式的播放全部收口到 create_player 一个入口。
MP4 的两个会话副作用（功放使能、触摸总线守护）也在这里收口，见「MP4 会话副作用」。

@api video_util.guess_format(path)              容器格式："hzv" | "mjpg" | "mp4"
@api video_util.read_dimensions(path)           w, h；读不到返回 nil
@api video_util.frame_size(path, def_w, def_h)  w, h；读不到时用调用方给的兜底值
@api video_util.audio_ensure()                  幂等初始化 HZV 音轨（Audio V2），返回是否可用；
                                                已就绪时 RESUME 并重新对齐 ac.play_vol 音量
@api video_util.create_player(path, o)          按格式创建**嵌入式**播放器（airui.video，
                                                HZV/MJPG/MP4 统一；o.on_complete=单次播完回调）
@api video_util.tp_bus_restore()                恢复触摸 I2C 总线配置（音频通路会重置总线）
]]

local ok_exaudio, exaudio = pcall(require, "exaudio")
if not ok_exaudio then exaudio = nil end

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
    local ac = pc.hw.audio
    if _G.__hzv_audio_ready then
        pcall(exaudio.pm, exaudio.RESUME)
        --[[RESUME 后重新对齐一次当前音量：设置页「亮度和声音」会改 ac.play_vol，
        回到播放路径时对齐一次，保证桌面 HZV 音轨跟着用户音量走；
        也兜住增益状态在休眠中丢失的个别平台。]]
        pcall(exaudio.vol, ac.play_vol or 100)
        return true
    end
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

-- ==================== 触摸总线守护 ====================
--[[恢复触摸 I2C 总线配置（音频通路会重置总线）
@return boolean 是否有可恢复的触摸驱动]]
function M.tp_bus_restore()
    if _G.tp_drv and _G.tp_drv.i2c_restore then
        pcall(_G.tp_drv.i2c_restore)
        return true
    end
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

-- ==================== MP4 会话副作用（功放 / 触摸总线守护） ====================
--[[mplayer 的音频通路启动时会把触摸 I2C 总线配置重置（真机踩过：GT911 读超时、
触摸失灵），功放引脚也要手动使能（mplayer 自己不拉 PA）。airui.video 的 MP4
后端内部同样走 mplayer，这两个副作用原样存在 —— 在创建/销毁播放器时统一收口：
起播前 PA 使能 + 500ms 触摸总线守护泵，destroy 时统一收尾（见 wrap_mp4_player）。

MP4 分辨率上限 480×320：mplayer 的 RGB 帧缓冲是静态数组，超限直接溢出
（mp4 时代的真机教训），起播前用纯 Lua 盒解析读宽高拦截。]]
local MP4_MAX_W = 480
local MP4_MAX_H = 320

local mp4_guard_timer = nil

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

local function mp4_session_begin()
    pa_set(true)
    if mp4_guard_timer then return end
    mp4_guard_timer = sys.timerLoopStart(function() M.tp_bus_restore() end, 500)
end

local function mp4_session_end()
    if mp4_guard_timer then sys.timerStop(mp4_guard_timer); mp4_guard_timer = nil end
    pa_set(false)
    M.tp_bus_restore()
end

--[[包装 MP4 播放器：destroy 时统一收掉会话副作用

接口面与裸 airui.video 对象一致（:play/:pause/:stop/:destroy），调用方无感；
HZV/MJPG 不涉及这些副作用，create_player 仍返回裸对象。]]
local function wrap_mp4_player(v)
    return {
        play = function(_, ...) return v:play(...) end,
        pause = function(_, ...) return v:pause(...) end,
        stop = function(_, ...) return v:stop(...) end,
        destroy = function(_)
            pcall(function() v:destroy() end)
            mp4_session_end()
        end,
    }
end

-- ==================== 播放器创建 ====================
--[[按素材格式创建**嵌入式**播放器（唯一入口）

HZV / MJPG / MP4 都走 airui.video（父容器内的控件，随 UI 层级显示/隐藏）：
MJPG 逐帧按 interval 喂；HZV / MP4 自带帧时序（HZV 容器帧时长 / MP4 PTS），
循环（loop）与单次播完（on_complete）由组件统一处理，控制栏代码无感。
两个播放页面（桌面播放器 / 全屏播放页）都走这里，格式差异只有一处实现。

@table o
  @userdata o.parent   airui 父容器
  @number   o.x,o.y    画面摆放位置（相对 parent）
  @number   o.w,o.h    画面尺寸（必须等于素材帧尺寸，不支持缩放）
  @boolean  o.loop     是否循环
  @function o.on_complete 单次播完（loop=false 读到 EOF）回调
@return userdata|nil 播放器对象（:play/:pause/:stop/:destroy），失败 nil
]]
function M.create_player(path, o)
    o = o or {}
    local fmt = M.guess_format(path)

    if fmt == "mp4" then
        -- 分辨率超限拒绝起播：调用方按「无法播放」走空态 UI
        local w, h = M.read_dimensions(path)
        if w and h and (w > MP4_MAX_W or h > MP4_MAX_H) then
            log.warn("video_util", "MP4 超 480×320 上限，拒绝起播", w, h, path)
            return nil
        end
        --[[停掉残留的配套/容器音频再起 mplayer：两路音频同开必打架。
        MP4 的声音走 mplayer 自带音频通路（组件内部自行初始化），
        不经 exaudio，也不需要 audio_ensure。]]
        M.audio_stop()
        if exaudio then pcall(exaudio.play_stop, { type = 0 }) end
        mp4_session_begin()
    else
        -- HZV 的播放时钟依赖音频框架、MJPG 的配套 MP3 也走它，先确保一次
        M.audio_ensure()
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

    local ok, v = pcall(airui.video, vcfg)
    if not ok or not v then
        if fmt == "mp4" then mp4_session_end() end
        return nil
    end
    if fmt == "mp4" then return wrap_mp4_player(v) end
    return v
end

return M
